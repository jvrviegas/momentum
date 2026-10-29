import AppKit
import ApplicationServices
import os

/// Watches apps and their windows, and calls `onEvent` whenever the window layout may need updating.
final class WindowObserver {
    var onEvent: (() -> Void)?
    /// Called for each step of the user moving or resizing a window with the mouse; the flag is true for resize steps.
    var onUserDrag: ((AXWindow, _ isResize: Bool) -> Void)?
    let queues = AXQueues()

    /// One window as last read from its app.
    nonisolated struct WindowState: Sendable {
        let window: AXWindow
        let bundleID: String?
        let isStandard: Bool
        let frame: CGRect?
    }

    private nonisolated struct AppWindows: Sendable {
        let windows: [WindowState]
        let focused: WindowID?
    }

    private var observers: [pid_t: AXObserver] = [:]
    private var tasks: [Task<Void, Never>] = []
    /// Each observed app's windows as of the last `reload()`.
    private var apps: [pid_t: AppWindows] = [:]
    /// The reload each app's windows came from; an older reload can finish after a newer one.
    private var appliedReload: [pid_t: Int] = [:]
    private var reloads = 0
    /// Windows registered for their destroyed notification, as of the last `reload()`.
    private var watchedWindows: Set<WindowID> = []

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    func start() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if !observe(app.processIdentifier) {
                retryObserving(app)
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        listen(center, NSWorkspace.didLaunchApplicationNotification) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            self?.retryObserving(app)
        }
        listen(center, NSWorkspace.didTerminateApplicationNotification) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.stopObserving(app.processIdentifier)
            self?.onEvent?()
        }
        listen(center, NSWorkspace.didActivateApplicationNotification) { [weak self] _ in self?.onEvent?() }
        listen(center, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] _ in self?.onEvent?() }
        listen(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in self?.onEvent?() }

        tasks.append(Task { [weak self] in await self?.pollOnScreenWindows() })
    }

    /// All windows of observed apps as of the last `reload()`. AX only reports windows on the currently visible Spaces.
    var windows: [WindowState] { apps.values.flatMap(\.windows) }

    func focusedWindow(in pid: pid_t) -> WindowState? {
        guard let app = apps[pid], let id = app.focused else { return nil }
        return app.windows.first { $0.window.id == id }
    }

    /// Rereads every observed app's windows, each on its own queue, so a busy app delays only this update,
    /// never the main thread. An app that doesn't answer in time keeps its last known windows.
    func reload() async {
        reloads += 1
        let reload = reloads, watched = watchedWindows
        let reads = observers.keys.map { pid in
            Task { (pid, await queues.run(pid) { Self.read(pid, watched: watched) }) }
        }
        for read in reads {
            let (pid, result) = await read.value
            guard let result, observers[pid] != nil, appliedReload[pid, default: 0] < reload else { continue }
            appliedReload[pid] = reload
            apps[pid] = result.app
            for window in result.unwatched { watchDestruction(of: window.element, pid: pid) }
        }
        watchedWindows = Set(windows.map(\.window.id))
    }

    // MARK: - Private

    private func listen(_ center: NotificationCenter, _ name: Notification.Name, handler: @escaping (Notification) async -> Void) {
        tasks.append(Task {
            for await notification in center.notifications(named: name) {
                await handler(notification)
            }
        })
    }

    /// macOS sends no AX notification when a window moves to another Desktop (e.g. dragged in Mission Control),
    /// so watch the set of on-screen windows and report any change.
    private func pollOnScreenWindows() async {
        var previous: Set<WindowID> = []
        while !Task.isCancelled {
            let current = Self.onScreenWindowIDs()
            if current != previous {
                previous = current
                onEvent?()
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Runs on the app's queue. Nil when the app doesn't answer in time.
    private nonisolated static func read(_ pid: pid_t, watched: Set<WindowID>) -> (app: AppWindows, unwatched: [AXWindow])? {
        let app = AXUIElementCreateApplication(pid)
        var list: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list) != .cannotComplete else { return nil }
        let running = NSRunningApplication(processIdentifier: pid)
        var windows: [WindowState] = []
        for element in list as? [AXUIElement] ?? [] {
            guard let window = AXWindow(element: element, pid: pid) else { continue }
            guard let state = window.readState() else { return nil }
            windows.append(WindowState(window: window, bundleID: running?.bundleIdentifier,
                                       isStandard: state.isStandard && running?.isHidden != true, frame: state.frame))
        }
        let focused: AXUIElement? = app.value(of: kAXFocusedWindowAttribute)
        // Each registration is a round trip to the app, so only new windows get one. It runs on the main thread,
        // so it gets its own references with a short timeout; the ones above also carry frame writes.
        var unwatched: [AXWindow] = []
        if windows.contains(where: { !watched.contains($0.window.id) }) {
            for element: AXUIElement in app.value(of: kAXWindowsAttribute) ?? [] {
                AXUIElementSetMessagingTimeout(element, 0.04)
                if let window = AXWindow(element: element, pid: pid), !watched.contains(window.id) { unwatched.append(window) }
            }
        }
        return (AppWindows(windows: windows, focused: focused.flatMap { AXWindow(element: $0, pid: pid)?.id }), unwatched)
    }

    private static func onScreenWindowIDs() -> Set<WindowID> {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(info.compactMap { window in
            // Layer 0 holds normal application windows.
            guard window[kCGWindowLayer as String] as? Int == 0 else { return nil }
            return window[kCGWindowNumber as String] as? WindowID
        })
    }

    /// Newly launched apps often reject AX notifications until they finish starting up, so keep trying for about 10 seconds.
    private func retryObserving(_ app: NSRunningApplication) {
        Task { [weak self] in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !app.isTerminated else { return }
                if self.observe(app.processIdentifier) { break }
            }
            self?.onEvent?()
        }
    }

    /// Returns false if the app isn't answering yet; calling again retries the notifications that failed.
    /// The app is tracked either way, so its windows are still tiled if it never answers.
    @discardableResult
    private func observe(_ pid: pid_t) -> Bool {
        guard pid != ProcessInfo.processInfo.processIdentifier else { return true }
        let signpost = tilingSignposter.beginInterval("observe", "\(pid)")
        defer { tilingSignposter.endInterval("observe", signpost) }
        let observer: AXObserver
        if let existing = observers[pid] {
            observer = existing
        } else {
            var created: AXObserver?
            guard AXObserverCreate(pid, axCallback, &created) == .success, let created else { return false }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            observers[pid] = created
            observer = created
        }

        let app = AXUIElementCreateApplication(pid)
        // Registration runs on the main thread, where the observer delivers its callbacks, so give up
        // quickly on an app that's still busy starting; `retryObserving` asks again shortly.
        AXUIElementSetMessagingTimeout(app, 0.04)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.appNotifications {
            // Already-registered notifications return a harmless error; a busy app returns cannotComplete.
            // Stop at the first timeout rather than waiting on each remaining notification.
            if AXObserverAddNotification(observer, app, notification as CFString, refcon) == .cannotComplete {
                return false
            }
        }
        return true
    }

    private func stopObserving(_ pid: pid_t) {
        queues.forget(pid)
        apps[pid] = nil
        appliedReload[pid] = nil
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// Registers for the window's destroyed notification. Re-registering an element is a harmless no-op.
    private func watchDestruction(of element: AXUIElement, pid: pid_t) {
        guard let observer = observers[pid] else { return }
        AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString,
                                  Unmanaged.passUnretained(self).toOpaque())
    }

    fileprivate func handle(_ element: AXUIElement, notification: String) {
        // This runs on the main thread, so don't wait long on the app behind the notification.
        AXUIElementSetMessagingTimeout(element, 0.04)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        switch notification {
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            // Our own frame changes also send these; only mouse-driven ones matter.
            if NSEvent.pressedMouseButtons & 1 != 0, let window = AXWindow(element: element, pid: pid) {
                onUserDrag?(window, notification == kAXWindowResizedNotification)
            }
            return
        case kAXWindowCreatedNotification:
            watchDestruction(of: element, pid: pid)
        default:
            break
        }
        onEvent?()
    }
}

/// C callback for AX notifications. Observers are added to the main run loop, so this runs on the main thread.
private nonisolated func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let windowObserver = Unmanaged<WindowObserver>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    // Already on the main thread, so the element doesn't actually cross threads.
    nonisolated(unsafe) let element = element
    MainActor.assumeIsolated {
        windowObserver.handle(element, notification: name)
    }
}
