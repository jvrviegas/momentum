import AppKit
import Observation

/// Keeps one BSP tree per native Space and tiles the main display's windows.
@Observable final class TilingManager {
    var isEnabled = true {
        didSet {
            if !isEnabled { cancelAnimation() }
            scheduleRefresh()
        }
    }
    private(set) var isTrusted = false
    /// Actions whose hotkey couldn't be registered (bound twice, or refused by the system).
    private(set) var failedHotKeys: Set<Action> = []

    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let observer = WindowObserver()
    @ObservationIgnored private let hotKeys = HotKeyManager()

    @ObservationIgnored private var trees: [SpaceID: BSPTree] = [:]
    /// Windows on the main display's current Space, from the latest refresh.
    @ObservationIgnored private var windows: [WindowID: AXWindow] = [:]
    @ObservationIgnored private var floating: Set<WindowID> = []
    @ObservationIgnored private var lastFocused: WindowID?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var animation = WindowAnimation()
    @ObservationIgnored private var animationTask: Task<Void, Never>?
    @ObservationIgnored private var animationSpace: SpaceID?
    /// Set while a window is being dragged to another Desktop, so the layout isn't applied mid-drag.
    @ObservationIgnored private var isSuspended = false
    /// Set while the user drags or resizes a window, so the layout doesn't fight the mouse.
    @ObservationIgnored private var isTrackingDrag = false
    /// Set when the tracked drag resized the window rather than only moving it.
    @ObservationIgnored private var dragResized = false

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    private var config: Config { configStore.config }

    func start() async {
        hotKeys.onAction = { [weak self] action in self?.perform(action) }
        failedHotKeys = hotKeys.register(config.bindings)
        configStore.onChange = { [weak self] config in
            guard let self else { return }
            failedHotKeys = hotKeys.register(config.bindings)
            scheduleRefresh()
        }

        await Permissions.waitForAccessibility()
        isTrusted = true
        // AX calls wait for the target app to answer; don't let a hung app freeze Momentum for the default ~6 s.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
        observer.onEvent = { [weak self] in self?.scheduleRefresh() }
        observer.onUserDrag = { [weak self] window, isResize in self?.trackDrag(of: window, isResize: isResize) }
        observer.start()
        refresh()
    }

    func retile() {
        refresh()
    }

    // MARK: - Layout

    /// Coalesces bursts of window events into a single refresh.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    /// Syncs the current Space's tree with the actual windows and applies the layout.
    private func refresh() {
        guard isEnabled, isTrusted, !isSuspended, !isTrackingDrag, let screen = mainScreenFrame else { return }
        let space = Spaces.mainDisplaySpace

        let current = observer.allWindows().filter { window in
            guard window.isStandard, let frame = window.frame else { return false }
            return screen.contains(CGPoint(x: frame.midX, y: frame.midY)) && Spaces.space(for: window.id) == space
        }
        windows = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var tree = trees[space] ?? BSPTree()
        tree.sync(with: current.filter { !isFloating($0) }.map(\.id), focused: lastFocused, bounds: tilingBounds)
        trees[space] = tree
        apply(tree)
        pruneState(except: space)

        if let focused = focusedWindow?.id, windows[focused] != nil {
            lastFocused = focused
        }
    }

    /// Forgets windows that closed or moved away while their Space wasn't visible, Spaces left with no windows,
    /// and closed floating windows. Minimized and hidden windows still belong to their Space, so they're kept.
    private func pruneState(except current: SpaceID) {
        for (space, var tree) in trees where space != current {
            for id in tree.windows where Spaces.space(for: id) != space {
                tree.remove(id)
            }
            trees[space] = tree.isEmpty ? nil : tree
        }
        floating = floating.filter { Spaces.space(for: $0) != nil }
    }

    private var shouldAnimate: Bool {
        config.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func apply(_ tree: BSPTree, animated: Bool = true) {
        let targets = tree.layout(in: tilingBounds, gap: config.gap)
        let currentFrames = windows.compactMapValues(\.frame)
        let space = Spaces.mainDisplaySpace
        if animationSpace != space { cancelAnimation() }

        // Don't generate mouse-drag notifications or fight a grab while a button is held.
        guard animated, shouldAnimate, NSEvent.pressedMouseButtons & 1 == 0 else {
            cancelAnimation()
            for (id, frame) in targets where currentFrames[id] != frame {
                windows[id]?.setFrame(frame)
            }
            return
        }

        animation.retarget(to: targets, currentFrames: currentFrames, at: ProcessInfo.processInfo.systemUptime)
        guard animation.isActive else {
            cancelAnimation()
            return
        }
        animationSpace = space
        // Retarget the existing animation instead of queueing or restarting its tick loop.
        guard animationTask == nil else { return }
        animationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
                guard let self else { return }
                guard isEnabled, !isSuspended, !isTrackingDrag,
                      animationSpace == Spaces.mainDisplaySpace else {
                    cancelAnimation()
                    return
                }
                // Pause writes during a click. An actual drag cancels via trackDrag; an ordinary
                // click must still finish the layout on release rather than leave it half-tiled.
                if NSEvent.pressedMouseButtons & 1 != 0 { continue }
                // Check each tick so enabling Reduce Motion or disabling animations takes effect mid-transition.
                if !shouldAnimate {
                    if let tree = currentTree { apply(tree, animated: false) }
                    else { cancelAnimation() }
                    return
                }
                for (id, frame) in animation.frames(at: ProcessInfo.processInfo.systemUptime) {
                    windows[id]?.setFrame(frame)
                }
                if !animation.isActive {
                    animationTask = nil
                    animationSpace = nil
                    return
                }
            }
        }
    }

    private func cancelAnimation() {
        animationTask?.cancel()
        animationTask = nil
        animationSpace = nil
        animation.cancel()
    }

    /// Waits for the mouse button to be released, then handles the drop.
    private func trackDrag(of window: AXWindow, isResize: Bool) {
        guard isEnabled, !isSuspended else { return }
        guard !isTrackingDrag else {
            // Resizing from the left or top edge also moves the window, so any resize step marks the whole drag.
            if isResize { dragResized = true }
            return
        }
        cancelAnimation()
        isTrackingDrag = true
        dragResized = isResize
        Task {
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(30))
            }
            isTrackingDrag = false
            drop(window)
        }
    }

    /// Dropping a moved tiled window onto another tiled window swaps them; any other drop,
    /// including the end of a resize, snaps it back into place.
    private func drop(_ window: AXWindow) {
        let space = Spaces.mainDisplaySpace
        if !dragResized, var tree = trees[space], tree.contains(window.id),
           let cursor = CGEvent(source: nil)?.location,
           let target = tree.window(at: cursor, excluding: window.id, in: tilingBounds, gap: config.gap) {
            tree.swap(window.id, target)
            trees[space] = tree
        }
        refresh()
    }

    private func isFloating(_ window: AXWindow) -> Bool {
        if floating.contains(window.id) { return true }
        guard let bundleID = NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier else { return false }
        return config.floatingBundleIDs.contains(bundleID)
    }

    /// The primary display's frame in top-left origin (Accessibility) coordinates.
    private var mainScreenFrame: CGRect? {
        guard let screen = NSScreen.screens.first else { return nil }
        return CGRect(origin: .zero, size: screen.frame.size)
    }

    /// The primary display's usable area (excluding menu bar and Dock), inset by the outer padding.
    private var tilingBounds: CGRect {
        guard let screen = NSScreen.screens.first else { return .zero }
        let visible = screen.visibleFrame
        let flipped = CGRect(x: visible.minX, y: screen.frame.height - visible.maxY, width: visible.width, height: visible.height)
        return flipped.insetBy(dx: config.outerPadding, dy: config.outerPadding)
    }

    private var focusedWindow: AXWindow? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return AXWindow.focused(in: pid)
    }

    private var currentTree: BSPTree? {
        trees[Spaces.mainDisplaySpace]
    }

    // MARK: - Commands

    private func perform(_ action: Action) {
        // While a window is being carried to another Desktop, a second command would interfere with the synthetic drag.
        guard isTrusted, !isSuspended else { return }
        switch action {
        case .sendToDesktop(let number): sendToDesktop(number)
        case .switchToDesktop(let number):
            cancelAnimation()
            Task { await SpaceMover.switchTo(desktop: number) }
        // The other commands act on the layout, which isn't maintained while tiling is off.
        case _ where !isEnabled: break
        case .focus(let direction): focus(direction)
        case .move(let direction): move(direction)
        case .toggleFloat: toggleFloat()
        case .retile: retile()
        }
    }

    private func focus(_ direction: Direction) {
        guard let focused = focusedWindow?.id,
              let neighbor = currentTree?.neighbor(of: focused, direction: direction, bounds: tilingBounds) else { return }
        windows[neighbor]?.focus()
    }

    private func move(_ direction: Direction) {
        let space = Spaces.mainDisplaySpace
        guard var tree = trees[space], let focused = focusedWindow?.id,
              let neighbor = tree.neighbor(of: focused, direction: direction, bounds: tilingBounds) else { return }
        tree.swap(focused, neighbor)
        trees[space] = tree
        apply(tree)
    }

    private func toggleFloat() {
        guard let window = focusedWindow else { return }
        if floating.remove(window.id) == nil {
            floating.insert(window.id)
        }
        refresh()
    }

    private func sendToDesktop(_ number: Int) {
        guard let window = focusedWindow else { return }
        refreshTask?.cancel()
        cancelAnimation()

        // Close the gap on the current Desktop right away; once we switch Desktops these windows are no longer visible to AX.
        // If the move fails, the next refresh puts the window back since it's still on this Desktop.
        let space = Spaces.mainDisplaySpace
        if isEnabled, var tree = trees[space] {
            tree.remove(window.id)
            trees[space] = tree
            apply(tree, animated: false)
        }

        isSuspended = true
        Task {
            await SpaceMover.move(window, toDesktop: number)
            isSuspended = false
            // The window is now on the target Desktop, which is visible; tile it there.
            // The old Desktop's tree drops it on the next refresh after switching back.
            refresh()
        }
    }
}
