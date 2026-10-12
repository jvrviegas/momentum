import AppKit
import Observation

/// Independent layouts for each logical display and native Desktop.
@Observable final class TilingManager {
    var isEnabled = true {
        didSet {
            if !isEnabled { moveTask?.cancel(); pointerReleaseTask?.cancel(); cancelAnimations() }
            scheduleRefresh()
        }
    }
    private(set) var isTrusted = false
    private(set) var lastDesktopMoveError: String?
    private(set) var lastDesktopSwitchError: String?
    private(set) var isRecoveringDock = false
    private(set) var canRecoverDesktopSwitching = false

    @ObservationIgnored private let configStore: ConfigStore
    @ObservationIgnored private let observer = WindowObserver()
    @ObservationIgnored private let environment: TilingEnvironment
    @ObservationIgnored private let usesNativeEnvironment: Bool
    @ObservationIgnored private(set) var layoutState = DisplayLayoutState()
    @ObservationIgnored private var inventory = Spaces.DisplayInventory(topology: DisplayTopology(displays: []), desktops: [:])
    @ObservationIgnored private var windows: [WindowID: TilingEnvironment.Window] = [:]
    @ObservationIgnored private var floating: Set<WindowID> = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var desktopSwitchTask: Task<Void, Never>?
    @ObservationIgnored private(set) var moveTask: Task<Void, Never>?
    @ObservationIgnored private(set) var pointerReleaseTask: Task<Void, Never>?
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var isTrackingDrag = false
    @ObservationIgnored private var dragResized = false
    @ObservationIgnored private var dragSource: LayoutKey?
    @ObservationIgnored private var animations: [DisplayID: AnimationState] = [:]

    private struct AnimationState {
        let key: LayoutKey
        let bounds: CGRect
        var model = WindowAnimation()
        var frames: [WindowID: CGRect] = [:]
        var targets: [WindowID: CGRect] = [:]
        var link: TilingEnvironment.DisplayLink?
    }

    init(configStore: ConfigStore, environment: TilingEnvironment? = nil, initiallyTrusted: Bool = false) {
        self.configStore = configStore
        self.environment = environment ?? .native(observer: observer)
        usesNativeEnvironment = environment == nil
        // Only injected environments can bypass the independent production Accessibility wait.
        isTrusted = environment != nil && initiallyTrusted
    }

    private var config: Config { configStore.config }

    func start() async {
        if !usesNativeEnvironment { refresh(); return }
        await Permissions.waitForAccessibility()
        isTrusted = true
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
        observer.onEvent = { [weak self] in self?.scheduleRefresh() }
        observer.onUserDrag = { [weak self] window, resized in
            self?.trackDrag(of: .native(window), isResize: resized)
        }
        observer.start()
        refresh()
    }

    func configurationDidChange() { scheduleRefresh() }
    func retile() { refresh() }
    func dismissDesktopMoveError() { lastDesktopMoveError = nil }
    func dismissDesktopSwitchError() {
        lastDesktopSwitchError = nil
        canRecoverDesktopSwitching = false
    }

    func recoverDesktopSwitching() async {
        guard canRecoverDesktopSwitching, !isRecoveringDock, !isSuspended else { return }
        desktopSwitchTask?.cancel()
        isRecoveringDock = true
        defer { isRecoveringDock = false }
        if await environment.restartDock() { dismissDesktopSwitchError() }
        else { lastDesktopSwitchError = "The Dock couldn't be restarted. Try again or restart it manually." }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func refresh() {
        guard isEnabled, isTrusted, !isSuspended, !isTrackingDrag else { return }
        inventory = environment.inventory()
        for (id, state) in animations where bounds(for: state.key, in: inventory) != state.bounds {
            cancelAnimation(on: id)
        }
        let current = environment.windows()
        let existing = environment.existingWindowIDs()
        var memberships: [WindowID: DisplayLayoutState.Membership] = [:]
        let remembered = Set(layoutState.trees.values.flatMap(\.windows)).union(floating).union(current.map(\.id))
        for id in remembered {
            if let space = environment.space(id) { memberships[id] = .space(space) }
            else if existing?.contains(id) == false { memberships[id] = .closed }
        }
        floating = floating.filter { memberships[$0] != .closed }

        var visible: [LayoutKey: DisplayLayoutState.VisibleLayout] = [:]
        var ids: [LayoutKey: [WindowID]] = [:]
        for display in inventory.topology.eligibleDisplays {
            guard let space = display.activeSpace?.id else { continue }
            ids[LayoutKey(displayID: display.id, spaceID: space)] = []
        }
        windows.removeAll(keepingCapacity: true)
        for window in current {
            guard window.isStandard, windows[window.id] == nil, let frame = window.frame,
                  let display = inventory.topology.owner(of: frame), display.isEligible,
                  let space = display.activeSpace?.id, memberships[window.id] == .space(space) else { continue }
            windows[window.id] = window
            if !isFloating(window) { ids[LayoutKey(displayID: display.id, spaceID: space), default: []].append(window.id) }
        }
        for (key, list) in ids {
            guard let display = inventory.topology.displays.first(where: { $0.id == key.displayID }) else { continue }
            visible[key] = .init(bounds: display.tilingBounds(padding: config.outerPadding), windows: list)
        }
        layoutState.reconcile(visible: visible, connectedDisplays: Set(inventory.topology.displays.map(\.id)),
                              membership: memberships, focused: environment.focusedWindow()?.id)
        for key in visible.keys { apply(key) }
    }

    private func apply(_ key: LayoutKey) {
        guard let tree = layoutState.trees[key], let bounds = bounds(for: key, in: inventory) else { return }
        let targets = tree.layout(in: bounds, gap: config.gap)
        let current = Dictionary(uniqueKeysWithValues: targets.keys.compactMap { id in
            windows[id]?.frame.map { (id, $0) }
        })
        // Programmatic AX writes while the button is held look like user drags to the observer.
        if environment.mousePressed() { refreshAfterPointerRelease(); return }
        guard config.shouldAnimate(reduceMotion: environment.reduceMotion()) else {
            cancelAnimation(on: key.displayID)
            writeImmediately(targets)
            return
        }
        if let previous = animations[key.displayID], previous.key != key || previous.bounds != bounds {
            cancelAnimation(on: key.displayID)
        }
        var state = animations[key.displayID] ?? AnimationState(key: key, bounds: bounds)
        state.model.retarget(to: targets, currentFrames: current, at: environment.now())
        guard state.model.isActive else { cancelAnimation(on: key.displayID); return }
        state.frames = current
        state.targets = targets
        if state.link == nil {
            state.link = environment.makeDisplayLink(key.displayID) { [weak self] in
                guard let self else { return false }
                return animateFrame(on: key.displayID)
            }
        }
        guard state.link != nil else {
            cancelAnimation(on: key.displayID)
            writeImmediately(targets)
            return
        }
        animations[key.displayID] = state
    }

    private func refreshAfterPointerRelease() {
        guard pointerReleaseTask == nil else { return }
        pointerReleaseTask = Task { [weak self] in
            guard let self else { return }
            defer { pointerReleaseTask = nil }
            do {
                while environment.mousePressed() {
                    try Task.checkCancellation()
                    try await environment.wait()
                }
                try Task.checkCancellation()
                refresh()
            } catch { } // Disabled/cancelled work must not write frames.
        }
    }

    private func writeImmediately(_ targets: [WindowID: CGRect]) {
        for (id, frame) in targets {
            guard let window = windows[id], let current = window.frame, current != frame else { continue }
            _ = window.writeFrame(frame, current, current.size != frame.size, true)
        }
    }

    private func animateFrame(on display: DisplayID) -> Bool {
        guard var state = animations[display] else { return false }
        let live = environment.inventory()
        guard isEnabled, isTrusted, !isSuspended, !isTrackingDrag,
              bounds(for: state.key, in: live) == state.bounds,
              state.targets.keys.allSatisfy({ environment.space($0) == state.key.spaceID }) else {
            cancelAnimation(on: display)
            scheduleRefresh()
            return false
        }
        if environment.mousePressed() { return true }
        if !config.shouldAnimate(reduceMotion: environment.reduceMotion()) {
            writeImmediately(state.targets)
            cancelAnimation(on: display)
            return false
        }
        let resizing = state.model.resizingWindows
        for (id, frame) in state.model.frames(at: environment.now()) {
            guard let window = windows[id] else { continue }
            let finalResize = resizing.contains(id) && !state.model.isAnimating(id)
            let succeeded = window.writeFrame(frame, state.frames[id], finalResize, finalResize)
            state.frames[id] = succeeded ? frame : nil
        }
        animations[display] = state
        if !state.model.isActive { cancelAnimation(on: display); return false }
        return true
    }

    private func cancelAnimation(on display: DisplayID) {
        animations[display]?.link?.invalidate()
        animations[display] = nil
    }

    private func cancelAnimations() {
        for id in Array(animations.keys) { cancelAnimation(on: id) }
    }

    private func bounds(for key: LayoutKey, in snapshot: Spaces.DisplayInventory) -> CGRect? {
        guard let display = snapshot.topology.displays.first(where: { $0.id == key.displayID }),
              display.isEligible, display.activeSpace?.id == key.spaceID else { return nil }
        return display.tilingBounds(padding: config.outerPadding)
    }

    private func key(for window: TilingEnvironment.Window, in snapshot: Spaces.DisplayInventory) -> LayoutKey? {
        guard window.isStandard, let frame = window.frame,
              let display = snapshot.topology.owner(of: frame), display.isEligible,
              let space = display.activeSpace?.id, environment.space(window.id) == space else { return nil }
        return LayoutKey(displayID: display.id, spaceID: space)
    }

    private func isFloating(_ window: TilingEnvironment.Window) -> Bool {
        floating.contains(window.id) || window.bundleID.map(config.floatingBundleIDs.contains) == true
    }

    func perform(_ action: Action) {
        guard isTrusted, !isSuspended, !isRecoveringDock, !isTrackingDrag else { return }
        switch action {
        case .sendToDesktop(let number): sendToDesktop(number)
        case .switchToDesktop(let number):
            cancelAnimations()
            desktopSwitchTask?.cancel()
            dismissDesktopSwitchError()
            desktopSwitchTask = Task { [weak self] in
                guard let self else { return }
                let result = await environment.switchDesktop(number)
                guard !Task.isCancelled else { return }
                switch result {
                case .timedOut:
                    canRecoverDesktopSwitching = true
                    lastDesktopSwitchError = "Desktop switching didn't respond after three attempts. You can restart the Dock manually to recover it."
                case .shortcutUnavailable:
                    lastDesktopSwitchError = "Enable the Switch to Desktop \(number) shortcut in System Settings → Keyboard → Keyboard Shortcuts → Mission Control."
                case .completed, .unchecked, .cancelled: break
                }
            }
        case _ where !isEnabled: break
        case .focus(let direction): focus(direction)
        case .move(let direction): swap(direction)
        case .toggleFloat:
            guard let window = environment.focusedWindow(), window.isStandard else { return }
            if floating.remove(window.id) == nil { floating.insert(window.id) }
            refresh()
        case .retile: refresh()
        case .toggleKeepAwake: break
        case .sendToPreviousDisplay: sendToDisplay(.previous)
        case .sendToNextDisplay: sendToDisplay(.next)
        }
    }

    private func focus(_ direction: Direction) {
        refresh()
        guard let window = environment.focusedWindow(), let key = key(for: window, in: inventory),
              let bounds = bounds(for: key, in: inventory), let tree = layoutState.trees[key],
              tree.contains(window.id) else { return }
        if let local = tree.neighbor(of: window.id, direction: direction, bounds: bounds) {
            windows[local]?.focus()
            return
        }
        var frames: [WindowID: CGRect] = [:]
        var owners: [WindowID: DisplayID] = [:]
        for (candidate, tree) in layoutState.trees {
            guard let bounds = self.bounds(for: candidate, in: inventory) else { continue }
            for (id, frame) in tree.layout(in: bounds, gap: config.gap) where windows[id] != nil {
                frames[id] = frame
                owners[id] = candidate.displayID
            }
        }
        if let neighbor = inventory.topology.crossDisplayNeighbor(of: window.id, direction: direction,
                                                                  frames: frames, owners: owners) {
            windows[neighbor]?.focus()
        }
    }

    private func swap(_ direction: Direction) {
        refresh()
        guard let window = environment.focusedWindow(), let key = key(for: window, in: inventory),
              let bounds = bounds(for: key, in: inventory) else { return }
        if layoutState.swap(window.id, direction: direction, in: key, bounds: bounds) { apply(key) }
    }

    private func sendToDesktop(_ number: Int) {
        let snapshot = environment.inventory()
        guard let window = environment.focusedWindow(), let key = key(for: window, in: snapshot),
              let desktops = snapshot.desktops[key.displayID] else { return }
        guard let target = Spaces.desktopSpace(number, in: desktops) else {
            lastDesktopMoveError = SpaceMover.MoveError.desktopUnavailable(number).localizedDescription
            environment.reportError()
            return
        }
        lastDesktopMoveError = nil
        guard environment.space(window.id) != target else { return }
        startMove { [environment] in
            try await environment.moveToSpace(window.id, target)
            try Task.checkCancellation()
            let live = environment.inventory()
            guard live.topology.displays.contains(where: { $0.id == key.displayID }),
                  live.desktops[key.displayID]?.desktopSpaces.contains(target) == true else {
                throw DisplayMover.MoveError.destinationChanged
            }
            guard environment.space(window.id) == target else { throw SpaceMover.MoveError.timedOut }
            // Remain on the source Desktop; no focus or cursor change.
        }
    }

    private func sendToDisplay(_ step: DisplayTopology.Step) {
        let snapshot = environment.inventory()
        guard let window = environment.focusedWindow(), let source = key(for: window, in: snapshot),
              let destination = snapshot.topology.destination(from: source.displayID, step: step) else { return }
        // A single eligible display is a true no-op, including layout/frame writes.
        refresh()
        transfer(window, to: destination, in: snapshot)
    }

    private func transfer(_ window: TilingEnvironment.Window, to destination: DisplayTopology.Display,
                          in snapshot: Spaces.DisplayInventory, followFocus: Bool = true) {
        guard window.isStandard, let current = window.frame, let space = destination.activeSpace?.id,
              let source = snapshot.topology.owner(of: current) else { return }
        let target: CGRect
        if isFloating(window) {
            target = DisplayMover.floatingFrame(current, from: source.usableFrame, to: destination.usableFrame)
        } else {
            let destinationKey = LayoutKey(displayID: destination.id, spaceID: space)
            let bounds = destination.tilingBounds(padding: config.outerPadding)
            var tree = layoutState.trees[destinationKey] ?? BSPTree()
            var ids = environment.windows().filter {
                $0.id != window.id && $0.isStandard && !isFloating($0) && environment.space($0.id) == space
                    && $0.frame.flatMap { snapshot.topology.owner(of: $0)?.id } == destination.id
            }.map(\.id)
            ids.append(window.id)
            tree.sync(with: ids, focused: layoutState.lastFocused[destinationKey], bounds: bounds)
            guard let placement = tree.layout(in: bounds, gap: config.gap)[window.id] else { return }
            target = placement
        }
        let client = DisplayMover.Client(topology: { self.environment.inventory().topology },
            membership: { self.environment.space(window.id) }, frame: { window.frame },
            serverFrame: { self.environment.serverFrame(window.id) },
            moveSpace: { try await self.environment.moveToSpace(window.id, $0) },
            writeFrame: { target in
                let previous = window.frame
                return window.writeFrame(target, previous, previous?.size != target.size, true)
            }, wait: environment.wait)
        startMove {
            try await DisplayMover.move(to: destination, frame: target, client: client)
            try Task.checkCancellation()
            if followFocus && window.isStandard { window.focus() }
        }
    }

    private func startMove(_ operation: @escaping () async throws -> Void) {
        desktopSwitchTask?.cancel()
        refreshTask?.cancel()
        lastDesktopMoveError = nil
        cancelAnimations()
        isSuspended = true
        moveTask = Task { [weak self] in
            guard let self else { return }
            defer { isSuspended = false; refresh() }
            do { try await operation() }
            catch is CancellationError { }
            catch { lastDesktopMoveError = error.localizedDescription; environment.reportError() }
        }
    }

    private func trackDrag(of window: TilingEnvironment.Window, isResize: Bool) {
        guard isEnabled, !isSuspended, window.isStandard else { return }
        guard !isTrackingDrag else { if isResize { dragResized = true }; return }
        cancelAnimations()
        isTrackingDrag = true
        dragResized = isResize
        dragSource = layoutState.trees.first(where: { $0.value.contains(window.id) })?.key
        Task { [weak self] in
            guard let self else { return }
            while environment.mousePressed() { try? await environment.wait() }
            isTrackingDrag = false
            drop(window, source: dragSource, resized: dragResized)
        }
    }

    /// Internal event seam for injected coordinator tests; only native observer callbacks call this live.
    func drop(_ window: TilingEnvironment.Window, source: LayoutKey?, resized: Bool) {
        guard isEnabled, isTrusted, !isSuspended, !isRecoveringDock, !environment.mousePressed(), window.isStandard else { return }
        let snapshot = environment.inventory()
        if let source, source.displayID != window.frame.flatMap({ snapshot.topology.owner(of: $0)?.id }),
           layoutState.trees[source]?.contains(window.id) == true, !isFloating(window),
           let frame = window.frame, let destination = snapshot.topology.owner(of: frame), destination.isEligible {
            // Cross-display drop inserts rather than swapping. OS may already have moved Space membership.
            transfer(window, to: destination, in: snapshot, followFocus: false)
            return
        }
        if !resized, let source, key(for: window, in: snapshot) == source,
           let tree = layoutState.trees[source], tree.contains(window.id),
           let cursor = environment.cursor(), let bounds = bounds(for: source, in: snapshot),
           let target = tree.window(at: cursor, excluding: window.id, in: bounds, gap: config.gap) {
            layoutState.swap(window.id, with: target, in: source)
        }
        refresh()
    }
}
