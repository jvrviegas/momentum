import CoreGraphics
import Testing
@testable import Momentum

@MainActor
struct MinimumSizeLayoutTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    /// 1 on the left half, 2 on the right.
    func pair() -> BSPTree {
        var tree = BSPTree()
        tree.insert(1, at: nil, bounds: bounds)
        tree.insert(2, at: 1, bounds: bounds)
        return tree
    }

    /// 1 on the left half, 2 top-right, 3 bottom-right.
    func threeWindowTree() -> BSPTree {
        var tree = pair()
        tree.insert(3, at: 2, bounds: bounds)
        return tree
    }

    @Test func windowThatNeedsMoreThanHalfTakesItFromTheOtherSide() {
        let frames = threeWindowTree().layout(in: bounds, gap: 10, minimums: [1: CGSize(width: 700, height: 0)])
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 700, height: 600))
        // The other side's own split stays equal.
        #expect(frames[2] == CGRect(x: 710, y: 0, width: 290, height: 295))
        #expect(frames[3] == CGRect(x: 710, y: 305, width: 290, height: 295))
    }

    @Test func secondSideCanTakeMoreThanHalf() {
        let frames = pair().layout(in: bounds, gap: 0, minimums: [2: CGSize(width: 800, height: 0)])
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 200, height: 600))
        #expect(frames[2] == CGRect(x: 200, y: 0, width: 800, height: 600))
    }

    @Test func splitStacksOnlyWhileSideBySideDoesntFit() {
        let minimums: [WindowID: CGSize] = [1: CGSize(width: 600, height: 200), 2: CGSize(width: 600, height: 200)]
        let stacked = pair().layout(in: bounds, gap: 0, minimums: minimums)
        #expect(stacked[1] == CGRect(x: 0, y: 0, width: 1000, height: 300))
        #expect(stacked[2] == CGRect(x: 0, y: 300, width: 1000, height: 300))
        let wide = pair().layout(in: CGRect(x: 0, y: 0, width: 1400, height: 600), gap: 0, minimums: minimums)
        #expect(wide[1] == CGRect(x: 0, y: 0, width: 700, height: 600))
        #expect(wide[2] == CGRect(x: 700, y: 0, width: 700, height: 600))
    }

    @Test func windowWithoutAKnownMinimumStillGetsTheSmallestTile() {
        // 950 pt leaves 2 only 50 pt side by side, so the pair stacks instead.
        let frames = pair().layout(in: bounds, gap: 0, minimums: [1: CGSize(width: 950, height: 0)])
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 1000, height: 300))
        #expect(frames[2] == CGRect(x: 0, y: 300, width: 1000, height: 300))
    }

    @Test func windowsAreTiledInJoinOrderAndTheFirstThatDoesntFitIsSetAside() {
        let tree = threeWindowTree()
        let minimums: [WindowID: CGSize] = [1: CGSize(width: 600, height: 300), 2: CGSize(width: 600, height: 300),
                                            3: CGSize(width: 600, height: 300)]
        #expect(!tree.fits(in: bounds, gap: 0, minimums: minimums))
        #expect(tree.windowsThatDontFit(in: bounds, gap: 0, minimums: minimums, order: [1, 2, 3]) == [3])
        #expect(tree.windowsThatDontFit(in: bounds, gap: 0, minimums: minimums, order: [3, 1, 2]) == [2])
    }

    @Test func windowTooLargeForTheDisplayIsSetAsideAndTheRestStay() {
        let minimums: [WindowID: CGSize] = [1: CGSize(width: 1200, height: 0)]
        #expect(threeWindowTree().windowsThatDontFit(in: bounds, gap: 0, minimums: minimums, order: [1, 2, 3]) == [1])
    }

    @Test func withoutMinimumSizesEverythingFits() {
        #expect(threeWindowTree().fits(in: bounds, gap: 10, minimums: [:]))
        #expect(threeWindowTree().windowsThatDontFit(in: bounds, gap: 10, minimums: [:], order: []).isEmpty)
    }
}

@MainActor
struct MinimumSizeStateTests {
    private let a = LayoutKey(displayID: 1, spaceID: 10)
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func visible(_ windows: [WindowID]) -> DisplayLayoutState.VisibleLayout {
        .init(bounds: bounds, windows: windows)
    }

    @Test func joinOrderKeepsTheOldestFirstAndPrioritizedWindowsMoveToTheFront() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1, 2])], connectedDisplays: [1])
        state.reconcile(visible: [a: visible([2, 3, 1])], connectedDisplays: [1])
        #expect(state.joinOrder[a] == [1, 2, 3])
        state.reconcile(visible: [a: visible([2, 3])], connectedDisplays: [1], prioritized: 3)
        #expect(state.joinOrder[a] == [3, 2])
    }

    @Test func arrangementKeepsTheSetAsideWindowsPlaceAndSwapsUseTheRealTiles() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1, 2, 3])], connectedDisplays: [1])
        let minimums: [WindowID: CGSize] = [1: CGSize(width: 600, height: 400), 2: CGSize(width: 600, height: 400),
                                            3: CGSize(width: 600, height: 400)]
        let arrangement = state.arrangement(for: a, bounds: bounds, gap: 0, minimums: minimums)
        #expect(arrangement?.setAside == [3])
        // 1 and 2 don't fit side by side, so they stack.
        #expect(arrangement?.frames == [1: CGRect(x: 0, y: 0, width: 1000, height: 400),
                                        2: CGRect(x: 0, y: 400, width: 1000, height: 400)])
        #expect(state.trees[a]?.windows == [1, 2, 3])
        let swapped = state.swap(1, direction: .down, in: a, bounds: bounds, gap: 0, minimums: minimums)
        #expect(swapped)
        #expect(state.trees[a]?.windows == [2, 1, 3])
    }
}

@MainActor
struct MinimumSizeTilingTests {
    /// Display 1's tiling area in `TilingFixture`.
    private let bounds = CGRect(x: 8, y: 28, width: 984, height: 764)

    /// Lets size checks, and the layouts they cause, run until nothing new is learned.
    private func settle(_ manager: TilingManager) async {
        var checked: Task<Void, Never>?
        while let latest = manager.sizeCheckTask, latest != checked {
            checked = latest
            await latest.value
        }
    }

    /// Three windows that each need 400 × 500 pt: any two fit on display 1, three don't.
    private func crowded(_ f: TilingFixture) -> [FakeTilingWindow] {
        let windows = (1...3).map { FakeTilingWindow(WindowID($0), CGRect(x: 10, y: 30, width: 400, height: 300), space: 10) }
        for window in windows { window.minimumSize = CGSize(width: 400, height: 500) }
        windows[2].appName = "Xcode"
        f.windows = windows
        return windows
    }

    @Test func refusedResizeIsLearnedAndTheNeighborMakesRoom() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let wide = FakeTilingWindow(1, CGRect(x: 0, y: 30, width: 400, height: 300), space: 10)
        wide.minimumSize = CGSize(width: 700, height: 0)
        let other = FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)
        f.windows = [wide, other]
        let manager = f.manager(); manager.retile()
        await settle(manager)
        #expect(wide.frame == CGRect(x: 8, y: 28, width: 700, height: 764))
        #expect(other.frame == CGRect(x: 716, y: 28, width: 276, height: 764))
        // The window isn't sent toward the size its app refuses again.
        let writes = wide.writes.count
        manager.configurationDidChange()
        #expect(wide.writes.count == writes)
        #expect(manager.noRoomMessage == nil)
    }

    @Test func sizeStepIsNotAMinimumSize() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let stepped = FakeTilingWindow(1, CGRect(x: 0, y: 30, width: 400, height: 300), space: 10)
        stepped.minimumSize = CGSize(width: 494, height: 0)
        let other = FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)
        f.windows = [stepped, other]
        let manager = f.manager(); manager.retile()
        await settle(manager)
        #expect(stepped.frame.width == 494)
        #expect(other.frame == CGRect(x: 504, y: 28, width: 488, height: 764))
    }

    @Test func newestWindowThatDoesntFitFloatsAtTheCenterAndRejoinsWhenThereIsRoom() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let windows = crowded(f)
        let manager = f.manager(); manager.retile()
        await settle(manager)
        #expect(windows[0].frame == CGRect(x: 8, y: 28, width: 488, height: 764))
        #expect(windows[1].frame == CGRect(x: 504, y: 28, width: 488, height: 764))
        #expect(abs(windows[2].frame.midX - bounds.midX) <= 1 && abs(windows[2].frame.midY - bounds.midY) <= 1)
        #expect(manager.noRoomMessage == "Xcode floats until there's room to tile it.")
        // Moving it doesn't snap it back: it floats.
        windows[2].frame.origin = CGPoint(x: 40, y: 60)
        manager.configurationDidChange()
        #expect(windows[2].frame.origin == CGPoint(x: 40, y: 60))

        f.windows.remove(at: 1)
        manager.configurationDidChange()
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.windows == [1, 3])
        #expect(windows[2].frame == CGRect(x: 504, y: 28, width: 488, height: 764))
        #expect(manager.noRoomMessage == nil)
    }

    @Test func toggleFloatingTilesAWindowAheadOfTheOthers() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let windows = crowded(f)
        let manager = f.manager(); manager.retile()
        await settle(manager)
        f.focusedID = 3; manager.perform(.toggleFloat)
        #expect(windows[2].frame == CGRect(x: 504, y: 28, width: 488, height: 764))
        #expect(windows[0].frame == CGRect(x: 8, y: 28, width: 488, height: 764))
        #expect(manager.noRoomMessage == "A window floats until there's room to tile it.")
        #expect(f.errors == 0)
    }

    @Test func windowThatDoesntFitEvenAloneStaysFloatingAndBeeps() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let huge = FakeTilingWindow(1, CGRect(x: 0, y: 30, width: 400, height: 300), space: 10)
        huge.minimumSize = CGSize(width: 1200, height: 0)
        f.windows = [FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10), huge]
        let manager = f.manager(); manager.retile()
        await settle(manager)
        #expect(f.windows[0].frame == bounds)
        f.focusedID = 1; manager.perform(.toggleFloat)
        #expect(f.errors == 1)
        #expect(f.windows[0].frame == bounds)
        #expect(manager.noRoomMessage == "A window floats until there's room to tile it.")
    }

    @Test func retileForgetsMinimumSizesAndMeasuresAgain() async {
        let f = TilingFixture(); defer { f.cleanup() }
        _ = crowded(f)
        let manager = f.manager(); manager.retile()
        await settle(manager)
        #expect(manager.noRoomMessage != nil)
        manager.retile()
        #expect(manager.noRoomMessage == nil)
        await settle(manager)
        #expect(manager.noRoomMessage == "Xcode floats until there's room to tile it.")
    }

    @Test func transferMakesRoomAtTheDestination() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let wide = FakeTilingWindow(1, CGRect(x: 0, y: 30, width: 400, height: 300), space: 10)
        wide.minimumSize = CGSize(width: 600, height: 0)
        f.windows = [wide, FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10),
                     FakeTilingWindow(3, CGRect(x: 1100, y: 30, width: 400, height: 300), space: 20)]
        let manager = f.manager(); manager.retile()
        await settle(manager)
        f.focusedID = 1; manager.perform(.sendToNextDisplay)
        await manager.moveTask?.value
        #expect(manager.lastDesktopMoveError == nil)
        // Display 2's tiling area is 784 pt wide: window 3 keeps 784 - 8 - 600.
        #expect(wide.frame == CGRect(x: 1192, y: 28, width: 600, height: 564))
        #expect(f.windows[2].frame == CGRect(x: 1008, y: 28, width: 176, height: 564))
    }

    /// After a taller display was unplugged, Chrome was learned as needing more than the whole tiling area
    /// and floated, because its size was read while Momentum was moving it again.
    @Test func sizeReadWhileMomentumMovesTheWindowAgainIsNotAMinimumSize() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.config.store.config.animationsEnabled = true
        f.provideLinks = true
        // Tiled on a taller display that went away: both are taller than display 1's 764 pt tiling area.
        let left = FakeTilingWindow(1, CGRect(x: 0, y: 20, width: 500, height: 1000), space: 10)
        let right = FakeTilingWindow(2, CGRect(x: 500, y: 20, width: 490, height: 1000), space: 10)
        f.windows = [left, right]
        // Like the native observer, windows report their frames as of the last reload.
        var lastReload: [WindowID: CGRect] = [:]
        var environment = f.environment
        environment.windows = {
            f.windows.map { fake in
                let live = fake.handle
                return .init(id: live.id, bundleID: live.bundleID, readStandard: live.readStandard,
                             readFrame: { lastReload[fake.id] ?? fake.frame }, readCurrentFrame: live.readCurrentFrame,
                             readSettledFrame: live.readSettledFrame, writeFrame: live.writeFrame, focus: live.focus)
            }
        }
        let manager = TilingManager(configStore: f.config.store, environment: environment, initiallyTrusted: true)
        manager.configurationDidChange()
        f.time = 0.1
        _ = f.ticks[1]?()
        // A reload reads the windows halfway through the animation.
        for window in f.windows { lastReload[window.id] = window.frame }
        // The animation ends and queues its size checks; the reload's layout lands first and moves the windows
        // back to where it read them, before the checks read their sizes.
        f.time = WindowAnimation.duration
        _ = f.ticks[1]?()
        manager.configurationDidChange()
        f.time += 0.01
        _ = f.ticks[1]?()
        await settle(manager)
        f.time += WindowAnimation.duration
        _ = f.ticks[1]?()
        await settle(manager)
        #expect(manager.noRoomMessage == nil)
        #expect(left.frame == CGRect(x: 8, y: 28, width: 488, height: 764))
        #expect(right.frame == CGRect(x: 504, y: 28, width: 488, height: 764))
    }
}

