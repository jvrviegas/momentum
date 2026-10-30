import AppKit
import Observation
import os

/// Names main-thread tiling work in Instruments traces.
let tilingSignposter = OSSignposter(subsystem: "com.joaoviegas.Momentum", category: "tiling")

/// Independent layouts for each logical display and native Desktop.
@Observable final class TilingManager {
    var isEnabled = true {
        didSet {
            if !isEnabled {
                moveTask?.cancel(); pointerReleaseTask?.cancel(); cancelAnimations()
                setAside.removeAll(); noRoomMessage = nil
            }
            refresh()
        }
    }
    private(set) var isTrusted = false
    /// Says which windows float because they don't fit (MD-31).
    private(set) var noRoomMessage: String?
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
    @ObservationIgnored private var isUpdatingLayout = false
    @ObservationIgnored private var deferredRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var needsReload = false
    @ObservationIgnored private(set) var actionTask: Task<Void, Never>?
    @ObservationIgnored private(set) var desktopSwitchTask: Task<Void, Never>?
    @ObservationIgnored private(set) var moveTask: Task<Void, Never>?
    @ObservationIgnored private(set) var pointerReleaseTask: Task<Void, Never>?
    @ObservationIgnored private(set) var dragTask: Task<Void, Never>?
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var isTrackingDrag = false
    @ObservationIgnored private var dragResized = false
    @ObservationIgnored private var dragSource: LayoutKey?
    @ObservationIgnored private var animations: [DisplayID: AnimationState] = [:]
    /// Sizes apps kept when Momentum asked for less (MD-22). Forgotten on Retile and when the window closes.
    @ObservationIgnored private var minimumSizes: [WindowID: CGSize] = [:]
    /// The frame Momentum last asked each window to take. A size check that no longer matches it is out of date,
    /// and a window still at its origin belongs to that frame's display (`placement`).
    @ObservationIgnored private var requested: [WindowID: CGRect] = [:]
    /// Windows each layout set aside because they don't fit. Momentum moves them to the center once.
    @ObservationIgnored private var setAside: [LayoutKey: Set<WindowID>] = [:]
    @ObservationIgnored private(set) var sizeCheckTask: Task<Void, Never>?

    /// Apps that size windows in steps (like Terminal's character grid) can end up to this much larger than
    /// asked without having a minimum size (MD-23). Terminal rounds by about 3 pt at its default font.
    private static let sizeStep: CGFloat = 8

    private struct AnimationState {
        let key: LayoutKey
        let bounds: CGRect
        var model = WindowAnimation()
        var frames: [WindowID: CGRect] = [:]
        var targets: [WindowID: CGRect] = [:]
        var link: TilingEnvironment.DisplayLink?
        /// Tells this animation's Space checks apart from those of an animation that replaced it.
        let id = UUID()
        var spaceCheck: Task<Void, Never>?
        /// Windows the last Space check found on another Space, or on none.
        var offSpace: Set<WindowID> = []
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
        observer.onEvent = { [weak self] in self?.refresh() }
        observer.onUserDrag = { [weak self] window, resized in
            self?.trackDrag(of: window.id, isResize: resized)
        }
        observer.start()
        refresh()
    }

    func configurationDidChange() { refresh() }
    func retile() { forgetMinimumSizes(); refresh() }
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

    private func refresh() {
        guard isEnabled, isTrusted, !isSuspended, !isTrackingDrag else { return }
        guard let reload = environment.reload else { reconcile(); return }
        // Reading windows waits on other apps, so it runs off the main thread; reconcile once it lands.
        // Events during a reload ask for one more, so the layout always ends on the latest windows.
        guard reloadTask == nil else { needsReload = true; return }
        reloadTask = Task { [weak self] in
            let signpost = tilingSignposter.beginInterval("reload", id: tilingSignposter.makeSignpostID())
            await reload()
            tilingSignposter.endInterval("reload", signpost)
            guard let self else { return }
            reloadTask = nil
            reconcile()
            if needsReload { needsReload = false; refresh() }
        }
    }

    /// `prioritizing` joins its layout ahead of the other windows, so it's the last one set aside (MD-29).
    private func reconcile(prioritizing: WindowID? = nil) {
        guard isEnabled, isTrusted, !isSuspended, !isTrackingDrag else { return }
        // A synchronous frame write (as in tests) can deliver another event while an update is in flight.
        // Finish that update before reconciling again; no timed debounce is needed.
        guard !isUpdatingLayout else { deferRefresh(); return }
        isUpdatingLayout = true
        let signpost = tilingSignposter.beginInterval("refresh")
        defer { isUpdatingLayout = false; tilingSignposter.endInterval("refresh", signpost) }
        inventory = environment.inventory()
        for (id, state) in animations where bounds(for: state.key, in: inventory) != state.bounds {
            cancelAnimation(on: id)
        }
        let current = environment.windows()
        // Listing every window is slow, and only a window without a Space needs it.
        lazy var existing = environment.existingWindowIDs()
        var memberships: [WindowID: DisplayLayoutState.Membership] = [:]
        let remembered = Set(layoutState.trees.values.flatMap(\.windows)).union(floating).union(current.map(\.id))
        for id in remembered {
            if let space = environment.space(id) { memberships[id] = .space(space) }
            else if existing?.contains(id) == false { memberships[id] = .closed }
        }
        floating = floating.filter { memberships[$0] != .closed }
        minimumSizes = minimumSizes.filter { memberships[$0.key] != .closed }
        requested = requested.filter { memberships[$0.key] != .closed }

        var visible: [LayoutKey: DisplayLayoutState.VisibleLayout] = [:]
        var ids: [LayoutKey: [WindowID]] = [:]
        for display in inventory.topology.eligibleDisplays {
            guard let space = display.activeSpace?.id else { continue }
            ids[LayoutKey(displayID: display.id, spaceID: space)] = []
        }
        windows.removeAll(keepingCapacity: true)
        for window in current {
            guard window.isStandard, windows[window.id] == nil, let frame = window.frame,
                  let display = inventory.topology.owner(of: placement(of: window.id, at: frame)), display.isEligible,
                  let space = display.activeSpace?.id, memberships[window.id] == .space(space) else { continue }
            windows[window.id] = window
            if !isFloating(window) { ids[LayoutKey(displayID: display.id, spaceID: space), default: []].append(window.id) }
        }
        for (key, list) in ids {
            guard let display = inventory.topology.displays.first(where: { $0.id == key.displayID }) else { continue }
            visible[key] = .init(bounds: display.tilingBounds(padding: config.outerPadding), windows: list)
        }
        layoutState.reconcile(visible: visible, connectedDisplays: Set(inventory.topology.displays.map(\.id)),
                              membership: memberships, focused: environment.focusedWindow()?.id,
                              prioritized: prioritizing)
        for key in visible.keys { apply(key) }
        setAside = setAside.filter { layoutState.trees[$0.key] != nil }
        updateNoRoomMessage(on: visible.keys)
    }

    private func deferRefresh() {
        guard deferredRefreshTask == nil else { return }
        deferredRefreshTask = Task { [weak self] in
            guard let self else { return }
            deferredRefreshTask = nil
            refresh()
        }
    }

    private func apply(_ key: LayoutKey) {
        guard let bounds = bounds(for: key, in: inventory),
              let arrangement = arrangement(for: key, bounds: bounds) else { return }
        let targets = arrangement.frames
        let current = Dictionary(uniqueKeysWithValues: targets.keys.compactMap { id in
            windows[id]?.frame.map { (id, $0) }
        })
        // Programmatic AX writes while the button is held look like user drags to the observer.
        if environment.mousePressed() { refreshAfterPointerRelease(); return }
        placeAside(arrangement.setAside, in: key, bounds: bounds)
        for (id, frame) in targets { requested[id] = frame }
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
        var written: [WindowID: CGRect] = [:]
        for (id, frame) in targets {
            guard let window = windows[id], let current = window.frame, current != frame else { continue }
            _ = window.writeFrame(frame, current, current.size != frame.size, true)
            written[id] = frame
        }
        checkSizes(written)
    }

    private func arrangement(for key: LayoutKey, bounds: CGRect) -> DisplayLayoutState.Arrangement? {
        layoutState.arrangement(for: key, bounds: bounds, gap: config.gap, minimums: minimumSizes)
    }

    /// Moves windows that no longer fit to the center of the display (MD-27). After that they float
    /// wherever people put them.
    private func placeAside(_ ids: Set<WindowID>, in key: LayoutKey, bounds: CGRect) {
        let placed = setAside[key] ?? []
        setAside[key] = ids
        for id in ids.subtracting(placed) {
            guard let window = windows[id], let current = window.frame else { continue }
            let frame = Self.centered(current.size, in: bounds)
            requested[id] = frame
            if frame != current { _ = window.writeFrame(frame, current, false, true) }
        }
    }

    /// Where Momentum put the window. An app that kept it larger than asked doesn't move it to another display.
    private func placement(of id: WindowID, at frame: CGRect) -> CGRect {
        guard let asked = requested[id], asked.width > 0, asked.height > 0,
              abs(frame.minX - asked.minX) <= 1, abs(frame.minY - asked.minY) <= 1 else { return frame }
        return asked
    }

    /// Centered in `bounds`, or at its top or left edge where `size` is larger.
    static func centered(_ size: CGSize, in bounds: CGRect) -> CGRect {
        func origin(_ start: CGFloat, _ available: CGFloat, _ length: CGFloat) -> CGFloat {
            length > available ? start : (start + (available - length) / 2).rounded(.down)
        }
        return CGRect(x: origin(bounds.minX, bounds.width, size.width), y: origin(bounds.minY, bounds.height, size.height),
                      width: size.width, height: size.height)
    }

    private func isSetAside(_ id: WindowID) -> Bool {
        setAside.values.contains { $0.contains(id) }
    }

    /// Learns minimum sizes from the sizes apps kept after Momentum's last write to each window (MD-22).
    private func checkSizes(_ frames: [WindowID: CGRect]) {
        var checks: [Task<Void, Never>] = []
        for (id, frame) in frames {
            guard let window = windows[id] else { continue }
            checks.append(Task { [weak self] in
                let size = await window.readSettledFrame()?.size
                guard let self, learnMinimumSize(of: id, requested: frame, kept: size) else { return }
                refresh()
            })
        }
        guard !checks.isEmpty else { return }
        // Waits for earlier checks too, so awaiting the latest one waits for every check still running.
        let earlier = sizeCheckTask
        sizeCheckTask = Task {
            await earlier?.value
            for check in checks { await check.value }
        }
    }

    private func learnMinimumSize(of id: WindowID, requested frame: CGRect, kept size: CGSize?) -> Bool {
        // A newer layout or the user's drag makes the answer out of date.
        guard let size, requested[id] == frame, !environment.mousePressed() else { return false }
        if abs(size.width - frame.width) > 2 || abs(size.height - frame.height) > 2 {
            let app = windows[id]?.bundleID ?? "?"
            tilingSignposter.emitEvent("size", """
                \(app, privacy: .public) asked \(Int(frame.width))x\(Int(frame.height)) \
                kept \(Int(size.width))x\(Int(size.height))
                """)
        }
        let known = minimumSizes[id] ?? .zero
        var minimum = known
        if size.width > frame.width + Self.sizeStep { minimum.width = max(known.width, size.width.rounded(.up)) }
        if size.height > frame.height + Self.sizeStep { minimum.height = max(known.height, size.height.rounded(.up)) }
        guard minimum != known else { return false }
        minimumSizes[id] = minimum
        return true
    }

    /// Retile measures minimum sizes again (MD-24).
    private func forgetMinimumSizes() {
        minimumSizes.removeAll()
    }

    private func updateNoRoomMessage(on keys: some Collection<LayoutKey>) {
        let ids = keys.flatMap { setAside[$0] ?? [] }
        let message: String? = switch ids.count {
        case 0: nil
        case 1: "\(windows[ids[0]]?.readAppName() ?? "A window") floats until there's room to tile it."
        default: "\(ids.count) windows float until there's room to tile them."
        }
        if message != noRoomMessage { noRoomMessage = message }
    }

    private func animateFrame(on display: DisplayID) -> Bool {
        guard var state = animations[display] else { return false }
        guard !isUpdatingLayout else { return true }
        isUpdatingLayout = true
        let signpost = tilingSignposter.beginInterval("tick")
        defer { isUpdatingLayout = false; tilingSignposter.endInterval("tick", signpost) }
        // Still showing the animation's Space also means the display is still eligible: a Space's kind never changes.
        guard isEnabled, isTrusted, !isSuspended, !isTrackingDrag,
              let live = environment.display(display), live.activeSpace?.id == state.key.spaceID,
              live.tilingBounds(padding: config.outerPadding) == state.bounds,
              state.offSpace.isDisjoint(with: state.targets.keys) else {
            cancelAnimation(on: display)
            refresh()
            return false
        }
        if state.spaceCheck == nil { state.spaceCheck = checkSpaces(of: state, on: display) }
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
            let write = tilingSignposter.beginInterval("write", "\(window.bundleID ?? "?", privacy: .public)")
            let succeeded = window.writeFrame(frame, state.frames[id], finalResize, finalResize)
            tilingSignposter.endInterval("write", write)
            state.frames[id] = succeeded ? frame : nil
        }
        animations[display] = state
        if !state.model.isActive {
            checkSizes(state.targets)
            cancelAnimation(on: display)
            return false
        }
        return true
    }

    /// Windows' Spaces are read off the main thread, because WindowServer can take milliseconds to answer
    /// while windows resize; a window that left the animation's Space stops it on the next frame.
    private func checkSpaces(of state: AnimationState, on display: DisplayID) -> Task<Void, Never> {
        let windows = Array(state.targets.keys), animation = state.id, space = state.key.spaceID
        return Task { [weak self, environment] in
            let spaces = await environment.spaces(windows)
            guard let self, animations[display]?.id == animation else { return }
            animations[display]?.spaceCheck = nil
            // The next frame compares these with its targets, so a window the animation stopped moving doesn't count.
            animations[display]?.offSpace = Set(windows.filter { spaces[$0] != space })
        }
    }

    private func cancelAnimation(on display: DisplayID) {
        animations[display]?.spaceCheck?.cancel()
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
              let display = snapshot.topology.owner(of: placement(of: window.id, at: frame)), display.isEligible,
              let space = display.activeSpace?.id, environment.space(window.id) == space else { return nil }
        return LayoutKey(displayID: display.id, spaceID: space)
    }

    private func isFloating(_ window: TilingEnvironment.Window) -> Bool {
        floating.contains(window.id) || window.bundleID.map(config.floatingBundleIDs.contains) == true
    }

    func perform(_ action: Action) {
        guard isTrusted, !isSuspended, !isRecoveringDock, !isTrackingDrag else { return }
        switch action {
        case .switchToDesktop, .toggleKeepAwake, .toggleFlow, .endFlow: break
        default:
            guard let reload = environment.reload else { break }
            // Act on the windows as they are now, in the order the shortcuts were pressed.
            let signpost = tilingSignposter.beginInterval("action", id: tilingSignposter.makeSignpostID())
            let previous = actionTask
            actionTask = Task { [weak self] in
                await previous?.value
                await reload()
                self?.performNow(action)
                tilingSignposter.endInterval("action", signpost)
            }
            return
        }
        performNow(action)
    }

    private func performNow(_ action: Action) {
        guard isTrusted, !isSuspended, !isRecoveringDock, !isTrackingDrag else { return }
        switch action {
        case .sendToDesktop(let number): sendToDesktop(number)
        case .switchToDesktop(let number):
            cancelAnimations()
            desktopSwitchTask?.cancel()
            dismissDesktopSwitchError()
            desktopSwitchTask = Task { [weak self] in
                guard let self else { return }
                var result = await environment.switchDesktop(number)
                // After a wake or display change the Dock can ignore Desktop shortcuts until it restarts.
                // Restarting it restores minimized windows on some macOS builds, so it's the last resort.
                if result == .timedOut, !Task.isCancelled {
                    isRecoveringDock = true
                    let restarted = await environment.restartDock()
                    isRecoveringDock = false
                    guard restarted else {
                        canRecoverDesktopSwitching = true
                        lastDesktopSwitchError = "The Dock couldn't be restarted. Try again or restart it manually."
                        return
                    }
                    result = await environment.switchDesktop(number)
                }
                guard !Task.isCancelled else { return }
                switch result {
                case .timedOut:
                    canRecoverDesktopSwitching = true
                    lastDesktopSwitchError = "Desktop switching didn't respond, even after restarting the Dock. You can restart it again manually."
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
            // Floating by choice or for lack of room, the window joins tiling ahead of the others (MD-29).
            if floating.remove(window.id) != nil || isSetAside(window.id) {
                reconcile(prioritizing: window.id)
                if isSetAside(window.id) { environment.reportError() }
            } else {
                floating.insert(window.id)
                reconcile()
            }
        case .retile:
            forgetMinimumSizes()
            reconcile()
        case .toggleKeepAwake, .toggleFlow, .endFlow: break
        case .sendToPreviousDisplay: sendToDisplay(.previous)
        case .sendToNextDisplay: sendToDisplay(.next)
        }
    }

    private func focus(_ direction: Direction) {
        reconcile()
        guard let window = environment.focusedWindow(), let key = key(for: window, in: inventory),
              let bounds = bounds(for: key, in: inventory), let local = arrangement(for: key, bounds: bounds)?.frames,
              local[window.id] != nil else { return }
        if let neighbor = BSPTree.neighbor(of: window.id, direction: direction, in: local) {
            windows[neighbor]?.focus()
            return
        }
        var frames: [WindowID: CGRect] = [:]
        var owners: [WindowID: DisplayID] = [:]
        for candidate in layoutState.trees.keys {
            guard let bounds = self.bounds(for: candidate, in: inventory),
                  let arrangement = arrangement(for: candidate, bounds: bounds) else { continue }
            for (id, frame) in arrangement.frames where windows[id] != nil {
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
        reconcile()
        guard let window = environment.focusedWindow(), let key = key(for: window, in: inventory),
              let bounds = bounds(for: key, in: inventory) else { return }
        if layoutState.swap(window.id, direction: direction, in: key, bounds: bounds, gap: config.gap,
                            minimums: minimumSizes) { apply(key) }
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
        reconcile()
        transfer(window, to: destination, in: snapshot)
    }

    private func transfer(_ window: TilingEnvironment.Window, to destination: DisplayTopology.Display,
                          in snapshot: Spaces.DisplayInventory, followFocus: Bool = true) {
        guard window.isStandard, let current = window.frame, let space = destination.activeSpace?.id,
              let source = snapshot.topology.owner(of: placement(of: window.id, at: current)) else { return }
        let target: CGRect
        if isFloating(window) {
            target = DisplayMover.floatingFrame(current, from: source.usableFrame, to: destination.usableFrame)
        } else {
            let destinationKey = LayoutKey(displayID: destination.id, spaceID: space)
            let bounds = destination.tilingBounds(padding: config.outerPadding)
            var tree = layoutState.trees[destinationKey] ?? BSPTree()
            var ids = environment.windows().filter { other in
                other.id != window.id && other.isStandard && !isFloating(other) && environment.space(other.id) == space
                    && other.frame.flatMap { snapshot.topology.owner(of: placement(of: other.id, at: $0))?.id }
                        == destination.id
            }.map(\.id)
            ids.append(window.id)
            tree.sync(with: ids, focused: layoutState.lastFocused[destinationKey], bounds: bounds)
            let order = (layoutState.joinOrder[destinationKey] ?? []).filter { $0 != window.id } + [window.id]
            let setAside = tree.windowsThatDontFit(in: bounds, gap: config.gap, minimums: minimumSizes, order: order)
            if setAside.contains(window.id) {
                // It floats at the center until there's room (MD-30).
                target = Self.centered(current.size, in: bounds)
            } else {
                for id in setAside { tree.remove(id) }
                guard let placement = tree.layout(in: bounds, gap: config.gap, minimums: minimumSizes)[window.id]
                else { return }
                target = placement
            }
        }
        let client = DisplayMover.Client(topology: { self.environment.inventory().topology },
            membership: { self.environment.space(window.id) }, frame: window.readCurrentFrame,
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

    /// Internal event seam for injected coordinator tests; only native observer callbacks call this live.
    /// Called after release too: macOS reports a quick drag only once it ends.
    func trackDrag(of id: WindowID, isResize: Bool) {
        guard isEnabled, !isSuspended, environment.windows().first(where: { $0.id == id })?.isStandard == true else { return }
        guard !isTrackingDrag else { if isResize { dragResized = true }; return }
        cancelAnimations()
        isTrackingDrag = true
        dragResized = isResize
        dragSource = layoutState.trees.first(where: { $0.value.contains(id) })?.key
        // The window follows the pointer, so its frame now and the pointer tell where it is later.
        let grab = environment.mousePressed()
            ? environment.serverFrame(id).flatMap { frame in environment.cursor().map { (frame: frame, pointer: $0) } }
            : nil
        dragTask = Task { [weak self] in
            guard let self else { return }
            while environment.mousePressed() {
                environment.showDropTargets(dropTargets(for: id, grab: grab))
                try? await environment.wait()
            }
            environment.showDropTargets(nil)
            // The drop needs where the drag left the window.
            await environment.reload?()
            isTrackingDrag = false
            guard let window = environment.windows().first(where: { $0.id == id }) else { return }
            drop(window, source: dragSource, resized: dragResized)
        }
    }

    /// Where the dragged tiled window can go, and where it goes if released now, as `drop` decides (MD-32).
    private func dropTargets(for id: WindowID, grab: (frame: CGRect, pointer: CGPoint)?) -> DropTargets? {
        guard isEnabled, !dragResized, let source = dragSource, let bounds = bounds(for: source, in: inventory),
              let tiles = arrangement(for: source, bounds: bounds)?.frames, tiles[id] != nil else { return nil }
        let padding = config.outerPadding
        let displays = inventory.topology.eligibleDisplays.filter { $0.id != source.displayID }
        let places = tiles.filter { $0.key != id }.sorted { $0.key < $1.key }.map(\.value)
            + displays.map { $0.tilingBounds(padding: padding) }
        let pointer = environment.cursor()
        var landing: CGRect?
        if let grab, let pointer,
           let owner = inventory.topology.owner(of: grab.frame.offsetBy(dx: pointer.x - grab.pointer.x,
                                                                        dy: pointer.y - grab.pointer.y)),
           owner.id != source.displayID {
            // Across displays, the window's center picks the display.
            landing = owner.isEligible ? owner.tilingBounds(padding: padding) : nil
        } else if let pointer, let target = BSPTree.window(at: pointer, excluding: id, in: tiles) {
            landing = tiles[target]
        }
        return DropTargets(window: id, places: places, landing: landing)
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
           let cursor = environment.cursor(), let bounds = bounds(for: source, in: snapshot),
           let frames = arrangement(for: source, bounds: bounds)?.frames, frames[window.id] != nil,
           let target = BSPTree.window(at: cursor, excluding: window.id, in: frames) {
            layoutState.swap(window.id, with: target, in: source)
        }
        reconcile()
    }
}
