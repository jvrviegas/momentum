import AppKit
import ApplicationServices

/// Watches apps and their windows, and calls `onEvent` whenever the window layout may need updating.
final class WindowObserver {
    var onEvent: (() -> Void)?
    /// Called when the user starts moving or resizing a window with the mouse.
    var onUserDrag: ((AXWindow) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    private var tasks: [Task<Void, Never>] = []

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
            observe(app.processIdentifier)
        }

        let center = NSWorkspace.shared.notificationCenter
        listen(center, NSWorkspace.didLaunchApplicationNotification) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            // Newly launched apps often reject AX observers until they finish starting up.
            try? await Task.sleep(for: .milliseconds(500))
            self?.observe(app.processIdentifier)
            self?.onEvent?()
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

    /// All windows of observed apps. AX only reports windows on the currently visible Spaces.
    func allWindows() -> [AXWindow] {
        observers.keys.flatMap { pid -> [AXWindow] in
            let app = AXUIElementCreateApplication(pid)
            let elements: [AXUIElement] = app.value(of: kAXWindowsAttribute) ?? []
            return elements.compactMap { element in
                watchDestruction(of: element, pid: pid)
                return AXWindow(element: element, pid: pid)
            }
        }
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

    private static func onScreenWindowIDs() -> Set<WindowID> {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(info.compactMap { window in
            // Layer 0 holds normal application windows.
            guard window[kCGWindowLayer as String] as? Int == 0 else { return nil }
            return window[kCGWindowNumber as String] as? WindowID
        })
    }

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, axCallback, &observer) == .success, let observer else { return }

        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.appNotifications {
            AXObserverAddNotification(observer, app, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func stopObserving(_ pid: pid_t) {
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
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        switch notification {
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            // Our own frame changes also send these; only mouse-driven ones matter.
            if NSEvent.pressedMouseButtons & 1 != 0, let window = AXWindow(element: element, pid: pid) {
                onUserDrag?(window)
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
    MainActor.assumeIsolated {
        windowObserver.handle(element, notification: name)
    }
}
