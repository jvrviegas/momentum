import AppKit
import Observation

/// Keeps one BSP tree per native Space and tiles the main display's windows.
@Observable final class TilingManager {
    var isEnabled = true {
        didSet { scheduleRefresh() }
    }
    private(set) var isTrusted = false

    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let observer = WindowObserver()
    @ObservationIgnored private let hotKeys = HotKeyManager()

    @ObservationIgnored private var trees: [SpaceID: BSPTree] = [:]
    /// Windows on the main display's current Space, from the latest refresh.
    @ObservationIgnored private var windows: [WindowID: AXWindow] = [:]
    @ObservationIgnored private var floating: Set<WindowID> = []
    @ObservationIgnored private var lastFocused: WindowID?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Set while a window is being dragged to another Desktop, so the layout isn't applied mid-drag.
    @ObservationIgnored private var isSuspended = false
    /// Set while the user drags or resizes a window, so the layout doesn't fight the mouse.
    @ObservationIgnored private var isTrackingDrag = false

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    private var config: Config { configStore.config }

    func start() async {
        hotKeys.onAction = { [weak self] action in self?.perform(action) }
        hotKeys.register(config.bindings)
        configStore.onChange = { [weak self] config in
            self?.hotKeys.register(config.bindings)
            self?.scheduleRefresh()
        }

        await Permissions.waitForAccessibility()
        isTrusted = true
        observer.onEvent = { [weak self] in self?.scheduleRefresh() }
        observer.onUserDrag = { [weak self] window in self?.trackDrag(of: window) }
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

        let tileable = Set(current.filter { !isFloating($0) }.map(\.id))
        var tree = trees[space] ?? BSPTree()
        for id in tree.windows where !tileable.contains(id) {
            tree.remove(id)
        }
        // Keep a stable insertion order for windows discovered together.
        for window in current where tileable.contains(window.id) && !tree.contains(window.id) {
            tree.insert(window.id, at: lastFocused, bounds: tilingBounds)
        }
        trees[space] = tree
        apply(tree)

        if let focused = focusedWindow?.id, windows[focused] != nil {
            lastFocused = focused
        }
    }

    private func apply(_ tree: BSPTree) {
        for (id, frame) in tree.layout(in: tilingBounds, gap: config.gap) {
            guard let window = windows[id], window.frame != frame else { continue }
            window.setFrame(frame)
        }
    }

    /// Waits for the mouse button to be released, then handles the drop.
    private func trackDrag(of window: AXWindow) {
        guard isEnabled, !isTrackingDrag, !isSuspended else { return }
        isTrackingDrag = true
        Task {
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(30))
            }
            isTrackingDrag = false
            drop(window)
        }
    }

    /// Dropping a tiled window onto another tiled window swaps them; any other drop snaps it back into place.
    private func drop(_ window: AXWindow) {
        let space = Spaces.mainDisplaySpace
        if var tree = trees[space], tree.contains(window.id),
           let cursor = CGEvent(source: nil)?.location,
           let target = tree.layout(in: tilingBounds, gap: config.gap)
               .first(where: { $0.key != window.id && $0.value.contains(cursor) })?.key {
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
        guard isTrusted else { return }
        switch action {
        case .focus(let direction): focus(direction)
        case .move(let direction): move(direction)
        case .sendToDesktop(let number): sendToDesktop(number)
        case .switchToDesktop(let number): Task { await SpaceMover.switchTo(desktop: number) }
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

        // Close the gap on the current Desktop right away; once we switch Desktops these windows are no longer visible to AX.
        // If the move fails, the next refresh puts the window back since it's still on this Desktop.
        let space = Spaces.mainDisplaySpace
        if var tree = trees[space] {
            tree.remove(window.id)
            trees[space] = tree
            apply(tree)
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
