import CoreGraphics
import Foundation
import Testing
@testable import Momentum

@MainActor
final class FakeTilingWindow {
    let id: WindowID
    var frame: CGRect
    var serverFrame: CGRect?
    var space: SpaceID
    var standard = true
    var bundleID: String? = "test.app"
    var appName: String?
    var writes: [CGRect] = []
    var writeFrom: [CGRect?] = []
    var resizeFlags: [(Bool, Bool)] = []
    var succeeds = true
    var refusesResize = false
    /// The app keeps the window at least this large, as an app with a minimum size does.
    var minimumSize = CGSize.zero
    var focused = 0
    var onWrite: (() -> Void)?

    init(_ id: WindowID, _ frame: CGRect, space: SpaceID) {
        self.id = id; self.frame = frame; self.space = space
        serverFrame = frame
    }
    var handle: TilingEnvironment.Window {
        .init(id: id, bundleID: bundleID, readStandard: { self.standard }, readFrame: { self.frame },
              readCurrentFrame: { self.frame }, readSettledFrame: { self.frame },
              writeFrame: { frame, previous, resize, repair in
                  self.writes.append(frame)
                  self.writeFrom.append(previous)
                  self.resizeFlags.append((resize, repair))
                  guard self.succeeds, !(self.refusesResize && resize) else { return false }
                  var frame = frame
                  frame.size.width = max(frame.width, self.minimumSize.width)
                  frame.size.height = max(frame.height, self.minimumSize.height)
                  self.frame = frame; self.serverFrame = frame
                  self.onWrite?()
                  return true
              }, focus: { self.focused += 1 }, readAppName: { self.appName })
    }
}

@MainActor
final class TilingFixture {
    let config = TemporaryConfig()
    var displayInventory: Spaces.DisplayInventory
    var windows: [FakeTilingWindow] = []
    var focusedID: WindowID?
    var enumerations = 0
    var windowListings = 0
    var moves: [(WindowID, SpaceID)] = []
    var moveFailure: Error?
    var onMove: (() -> Void)?
    var onWait: (() -> Void)?
    var switchResults: [SpaceMover.SwitchResult] = []
    var switches = 0
    var dockRestarts = 0
    var restartsDock = true
    var onDockRestart: (() -> Void)?
    var errors = 0
    var time = 0.0
    var reduceMotion = false
    var mouse = false
    var pointer: CGPoint? = nil
    var ticks: [DisplayID: () -> Bool] = [:]
    var invalidated: [DisplayID] = []
    var provideLinks = false
    var dropTargets: [DropTargets?] = []

    init(shared: Bool = false) {
        let a = DisplayTopology.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            usableFrame: CGRect(x: 0, y: 20, width: 1000, height: 780), activeSpace: .init(id: 10, kind: .normal))
        let b = DisplayTopology.Display(id: 2, frame: CGRect(x: 1000, y: 0, width: 800, height: 600),
            usableFrame: CGRect(x: 1000, y: 20, width: 800, height: 580),
            activeSpace: .init(id: shared ? 10 : 20, kind: .normal))
        displayInventory = .init(topology: .init(displays: [a, b]), desktops: [
            1: .init(identifier: "a", activeSpace: a.activeSpace, desktopSpaces: [10, 11]),
            2: .init(identifier: "b", activeSpace: b.activeSpace, desktopSpaces: shared ? [10, 11] : [20, 21])
        ])
        config.store.config.animationsEnabled = false
    }
    func cleanup() { config.cleanup() }

    var environment: TilingEnvironment {
        .init(inventory: { self.displayInventory },
              display: { id in self.displayInventory.topology.displays.first { $0.id == id } },
              windows: { self.enumerations += 1; return self.windows.map(\.handle) },
              focusedWindow: { self.windows.first { $0.id == self.focusedID }?.handle },
              space: { id in self.windows.first { $0.id == id }?.space },
              spaces: { ids in
                  Dictionary(uniqueKeysWithValues: ids.compactMap { id in self.windows.first { $0.id == id }.map { (id, $0.space) } })
              },
              existingWindowIDs: { self.windowListings += 1; return Set(self.windows.map(\.id)) },
              serverFrame: { id in self.windows.first { $0.id == id }?.serverFrame },
              moveToSpace: { id, space in
                  if let failure = self.moveFailure { throw failure }
                  self.moves.append((id, space))
                  self.windows.first { $0.id == id }?.space = space
                  self.onMove?()
              },
              switchDesktop: { _ in
                  self.switches += 1
                  return self.switchResults.isEmpty ? .completed : self.switchResults.removeFirst()
              },
              restartDock: { self.dockRestarts += 1; self.onDockRestart?(); return self.restartsDock },
              mousePressed: { self.mouse }, cursor: { self.pointer }, reduceMotion: { self.reduceMotion },
              now: { self.time },
              makeDisplayLink: { id, tick in
                  guard self.provideLinks else { return nil }
                  self.ticks[id] = tick
                  return .init(invalidate: { self.invalidated.append(id); self.ticks[id] = nil })
              },
              wait: { self.onWait?(); self.time += 0.02; await Task.yield() },
              reportError: { self.errors += 1 },
              showDropTargets: { self.dropTargets.append($0) })
    }
    func manager(trusted: Bool = true) -> TilingManager {
        TilingManager(configStore: config.store, environment: environment, initiallyTrusted: trusted)
    }
    func display(_ id: DisplayID, space: SpaceID? = nil, kind: DisplayTopology.SpaceKind = .normal) {
        let displays = displayInventory.topology.displays.map { old in
            old.id == id ? DisplayTopology.Display(id: old.id, frame: old.frame, usableFrame: old.usableFrame,
                activeSpace: space.map { .init(id: $0, kind: kind) }) : old
        }
        displayInventory = .init(topology: .init(displays: displays), desktops: displayInventory.desktops)
    }
}

@MainActor
struct MultiDisplayTilingTests {
    @Test func oneEnumerationTilesBothDisplaysIndependently() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 0, y: 30, width: 400, height: 300), space: 10),
                     FakeTilingWindow(2, CGRect(x: 1100, y: 30, width: 400, height: 300), space: 20)]
        let manager = f.manager(); manager.retile()
        #expect(f.enumerations == 1)
        #expect(f.windows[0].frame == CGRect(x: 8, y: 28, width: 984, height: 764))
        #expect(f.windows[1].frame == CGRect(x: 1008, y: 28, width: 784, height: 564))
        let other = manager.layoutState.trees[LayoutKey(displayID: 2, spaceID: 20)]
        f.windows.append(FakeTilingWindow(3, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10))
        manager.retile()
        #expect(manager.layoutState.trees[LayoutKey(displayID: 2, spaceID: 20)] == other)
    }

    @Test func refreshStartsNewWindowAnimationWithoutDebounce() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.config.store.config.animationsEnabled = true
        f.provideLinks = true
        let manager = f.manager()
        manager.retile()
        let window = FakeTilingWindow(1, CGRect(x: 0, y: 30, width: 400, height: 300), space: 10)
        f.windows.append(window)
        let initialFrame = window.frame

        manager.configurationDidChange()

        // No task yield or elapsed time is needed to discover the window and start its animation.
        #expect(f.enumerations == 2)
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.windows == [1])
        #expect(f.ticks[1] != nil)
        #expect(window.frame == initialFrame)
        f.time = WindowAnimation.duration
        _ = f.ticks[1]?()
        #expect(window.frame == CGRect(x: 8, y: 28, width: 984, height: 764))
    }

    @Test(arguments: [false, true])
    func windowChangeDuringAnimationWriteDoesNotRestoreStaleTargets(opening: Bool) async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.config.store.config.animationsEnabled = true
        f.provideLinks = true
        let survivor = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)
        let closing = FakeTilingWindow(2, CGRect(x: 500, y: 30, width: 400, height: 300), space: 10)
        let added = FakeTilingWindow(3, CGRect(x: 100, y: 50, width: 400, height: 300), space: 10)
        f.windows = [survivor, closing]
        let manager = f.manager()
        manager.retile()
        survivor.onWrite = {
            survivor.onWrite = nil
            if opening { f.windows.append(added) }
            else { f.windows.removeAll { $0.id == closing.id } }
            manager.configurationDidChange()
        }
        f.time = 0.05
        _ = f.ticks[1]?()
        // Allow any deferred event work to finish before the next display frame.
        for _ in 0..<10 { await Task.yield() }
        let writes = closing.writes.count
        f.time = 0.1
        _ = f.ticks[1]?()
        if opening { #expect(!added.writes.isEmpty) }
        else { #expect(closing.writes.count == writes) }
        // The surviving animation should be retargeted, not replaced by stale state and cancelled.
        #expect(f.invalidated.isEmpty)
        f.time = 0.3
        _ = f.ticks[1]?()
        let targets = manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?
            .layout(in: CGRect(x: 8, y: 28, width: 984, height: 764), gap: f.config.store.config.gap)
        #expect(survivor.frame == targets?[survivor.id])
    }

    @Test func sharedSpaceDoesNotMergeDisplays() {
        let f = TilingFixture(shared: true); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 0, y: 30, width: 400, height: 300), space: 10),
                     FakeTilingWindow(2, CGRect(x: 1100, y: 30, width: 400, height: 300), space: 10)]
        let manager = f.manager(); manager.retile()
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.windows == [1])
        #expect(manager.layoutState.trees[LayoutKey(displayID: 2, spaceID: 10)]?.windows == [2])
    }

    @Test func excludesFullscreenUnknownFloatingHiddenAndWrongSpace() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = (1...4).map { FakeTilingWindow(WindowID($0), CGRect(x: 10, y: 30, width: 400, height: 300), space: 10) }
        f.windows[1].standard = false
        f.windows[2].bundleID = "com.apple.systempreferences"
        f.windows[3].space = 11
        f.windows.append(FakeTilingWindow(5, CGRect(x: 1100, y: 30, width: 400, height: 300), space: 20))
        f.display(2, space: 20, kind: .fullscreen)
        let manager = f.manager(); manager.retile()
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.windows == [1])
        #expect(f.windows.dropFirst().allSatisfy { $0.writes.isEmpty })
        f.display(1, space: nil)
        manager.retile()
        #expect(f.windows[0].writes.count == 1)
    }

    @Test func desktopChangesAndDisconnectedDisplaysDropOnlyProvenState() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)]
        let manager = f.manager(); manager.retile()
        let old = manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]
        f.display(1, space: 11); manager.retile()
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)] == old)
        f.displayInventory = .init(topology: .init(displays: Array(f.displayInventory.topology.displays.suffix(1))), desktops: [:])
        manager.retile()
        #expect(manager.layoutState.trees.keys.allSatisfy { $0.displayID == 2 })
    }

    @Test func focusPrefersLocalThenCrossesTheEdgeWhileSwapStaysLocal() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10),
                     FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10),
                     FakeTilingWindow(3, CGRect(x: 1100, y: 30, width: 200, height: 100), space: 20)]
        f.focusedID = 1
        let manager = f.manager(); manager.perform(.focus(.right))
        #expect(f.windows[1].focused == 1)
        #expect(f.windows[2].focused == 0)
        f.focusedID = 2; manager.perform(.focus(.right))
        #expect(f.windows[2].focused == 1)
        let other = manager.layoutState.trees[LayoutKey(displayID: 2, spaceID: 20)]
        manager.perform(.move(.right))
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.windows == [1, 2])
        #expect(manager.layoutState.trees[LayoutKey(displayID: 2, spaceID: 20)] == other)
    }

    @Test func focusDoesNotWrapOrTargetFloatingOrFullscreenWindows() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10),
                     FakeTilingWindow(2, CGRect(x: 1100, y: 30, width: 200, height: 100), space: 20)]
        f.windows[1].bundleID = "com.apple.systempreferences"; f.focusedID = 1
        let manager = f.manager(); manager.perform(.focus(.right)); manager.perform(.focus(.left))
        #expect(f.windows.allSatisfy { $0.focused == 0 })
        f.windows[1].bundleID = "test.app"; f.display(2, space: 20, kind: .fullscreen)
        manager.perform(.focus(.right))
        #expect(f.windows[1].focused == 0)
    }

    @Test func displayTransferConfirmsThenFocusesAndRetilesBothLayouts() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10),
                     FakeTilingWindow(2, CGRect(x: 1100, y: 30, width: 200, height: 100), space: 20)]
        f.focusedID = 1
        let manager = f.manager(); manager.perform(.sendToNextDisplay)
        #expect(f.windows[0].focused == 0)
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.windows == [1])
        await manager.moveTask?.value
        #expect(manager.lastDesktopMoveError == nil)
        #expect(f.windows[0].space == 20)
        #expect(f.windows[0].focused == 1)
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.isEmpty == true)
        #expect(Set(manager.layoutState.trees[LayoutKey(displayID: 2, spaceID: 20)]?.windows ?? []) == [1, 2])
        manager.perform(.sendToNextDisplay) // wrap from last to first
        await manager.moveTask?.value
        #expect(f.windows[0].space == 10)
        #expect(f.windows[0].focused == 2)
    }

    @Test func floatingAndExcludedWindowsPreserveSizeWithoutJoiningTheTree() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let window = FakeTilingWindow(1, CGRect(x: 50, y: 40, width: 420, height: 300), space: 10)
        window.bundleID = "com.apple.systempreferences"; window.refusesResize = true
        f.windows = [window]; f.focusedID = 1
        let manager = f.manager(); manager.perform(.sendToPreviousDisplay)
        await manager.moveTask?.value
        #expect(manager.lastDesktopMoveError == nil)
        #expect(window.frame == CGRect(x: 1050, y: 40, width: 420, height: 300))
        #expect(window.resizeFlags.last?.0 == false)
        #expect(manager.layoutState.trees.values.allSatisfy { $0.isEmpty })
        #expect(window.focused == 1)
    }

    @Test func singleOrFullscreenDestinationIsANoOpAndDisabledTilingBlocksTransfer() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)]; f.focusedID = 1
        f.display(2, space: 20, kind: .fullscreen)
        let manager = f.manager(); manager.perform(.sendToNextDisplay)
        #expect(manager.moveTask == nil)
        #expect(f.moves.isEmpty)
        f.display(2, space: 20); manager.isEnabled = false; manager.perform(.sendToPreviousDisplay)
        #expect(f.moves.isEmpty)
        #expect(f.windows[0].writes.isEmpty)
    }

    @Test func destinationDisappearingOrNativeFailureDoesNotFollowFocusAndReportsError() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let window = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        f.windows = [window]; f.focusedID = 1
        f.onMove = { f.displayInventory = .init(topology: .init(displays: Array(f.displayInventory.topology.displays.prefix(1))), desktops: [:]) }
        let manager = f.manager(); manager.perform(.sendToNextDisplay)
        await manager.moveTask?.value
        #expect(manager.lastDesktopMoveError != nil)
        #expect(window.focused == 0)
        #expect(f.errors == 1)
        manager.dismissDesktopMoveError()
        #expect(manager.lastDesktopMoveError == nil)
    }

    @Test func desktopMovesUseFocusedDisplayOrdinalsWithoutFocusOrDesktopSwitch() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 1100, y: 30, width: 200, height: 100), space: 20)]; f.focusedID = 1
        let manager = f.manager(); manager.retile()
        manager.perform(.sendToDesktop(1))
        #expect(manager.moveTask == nil)
        manager.perform(.sendToDesktop(2)); await manager.moveTask?.value
        #expect(f.moves.first?.1 == 21)
        #expect(f.windows[0].focused == 0)
        #expect(f.displayInventory.topology.displays.last?.activeSpace?.id == 20)
        f.windows[0].space = 20
        manager.perform(.sendToDesktop(3))
        #expect(manager.lastDesktopMoveError?.contains("this window's display") == true)
    }

    @Test func ignoredDesktopSwitchRestartsTheDockThenSwitchesAgain() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.switchResults = [.timedOut, .completed]
        let manager = f.manager()
        f.onDockRestart = {
            #expect(manager.isRecoveringDock)
            manager.perform(.switchToDesktop(3)) // Ignored while the Dock restarts.
        }
        manager.perform(.switchToDesktop(2)); await manager.desktopSwitchTask?.value
        #expect(f.dockRestarts == 1 && f.switches == 2)
        #expect(!manager.isRecoveringDock)
        #expect(manager.lastDesktopSwitchError == nil)
        #expect(!manager.canRecoverDesktopSwitching)
    }

    @Test func switchStillIgnoredAfterDockRestartOffersManualRecovery() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.switchResults = [.timedOut, .timedOut]
        let manager = f.manager()
        manager.perform(.switchToDesktop(2)); await manager.desktopSwitchTask?.value
        #expect(f.dockRestarts == 1 && f.switches == 2)
        #expect(manager.lastDesktopSwitchError?.contains("even after restarting the Dock") == true)
        #expect(manager.canRecoverDesktopSwitching)
    }

    @Test func failedDockRestartDoesntSwitchAgain() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.switchResults = [.timedOut]
        f.restartsDock = false
        let manager = f.manager()
        manager.perform(.switchToDesktop(2)); await manager.desktopSwitchTask?.value
        #expect(f.dockRestarts == 1 && f.switches == 1)
        #expect(manager.lastDesktopSwitchError?.contains("couldn't be restarted") == true)
        #expect(manager.canRecoverDesktopSwitching)
        #expect(!manager.isRecoveringDock)
    }

    @Test func onlyATimedOutSwitchRestartsTheDock() async {
        for result: SpaceMover.SwitchResult in [.completed, .unchecked, .shortcutUnavailable, .cancelled] {
            let f = TilingFixture(); defer { f.cleanup() }
            f.switchResults = [result]
            let manager = f.manager()
            manager.perform(.switchToDesktop(2)); await manager.desktopSwitchTask?.value
            #expect(f.dockRestarts == 0 && f.switches == 1)
            #expect(!manager.canRecoverDesktopSwitching)
        }
    }

    @Test func sharedSpaceTransfersNeedNoNativeMoveAndCommandsSerializeDuringSettling() async {
        let f = TilingFixture(shared: true); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)]; f.focusedID = 1
        let manager = f.manager()
        f.onWait = { manager.perform(.sendToPreviousDisplay); manager.retile() }
        manager.perform(.sendToNextDisplay)
        await manager.moveTask?.value
        #expect(f.moves.isEmpty)
        #expect(f.windows[0].frame.minX == 1008)
        #expect(f.windows[0].focused == 1)
        #expect(f.enumerations == 3) // refresh, destination planning, deferred reconciliation
    }

    @Test func crossDisplayDropReconcilesMembershipThenInsertsRatherThanSwaps() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let dragged = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        f.windows = [dragged, FakeTilingWindow(2, CGRect(x: 1100, y: 30, width: 200, height: 100), space: 20)]
        let manager = f.manager(); manager.retile()
        dragged.frame = CGRect(x: 1100, y: 30, width: 200, height: 100)
        f.mouse = true
        manager.drop(dragged.handle, source: .init(displayID: 1, spaceID: 10), resized: false)
        #expect(manager.moveTask == nil)
        f.mouse = false
        manager.drop(dragged.handle, source: .init(displayID: 1, spaceID: 10), resized: false)
        await manager.moveTask?.value
        #expect(manager.lastDesktopMoveError == nil)
        #expect(dragged.space == 20)
        #expect(dragged.focused == 0)
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.isEmpty == true)
        #expect(Set(manager.layoutState.trees[LayoutKey(displayID: 2, spaceID: 20)]?.windows ?? []) == [1, 2])
    }

    @Test func localDropSwapsButResizingSnapsBackAndFloatingDropRemainsUntiled() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let first = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        let second = FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        f.windows = [first, second]
        let manager = f.manager(); manager.retile()
        f.pointer = CGPoint(x: second.frame.midX, y: second.frame.midY)
        manager.drop(first.handle, source: .init(displayID: 1, spaceID: 10), resized: false)
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.windows == [2, 1])
        let stable = first.frame
        first.frame.size.width -= 10
        manager.drop(first.handle, source: .init(displayID: 1, spaceID: 10), resized: true)
        #expect(first.frame == stable)
        f.focusedID = 1; manager.perform(.toggleFloat)
        first.frame = CGRect(x: 1100, y: 30, width: 200, height: 100); first.space = 20
        manager.drop(first.handle, source: nil, resized: false)
        #expect(manager.layoutState.trees.values.allSatisfy { !$0.contains(1) })
        #expect(first.frame == CGRect(x: 1100, y: 30, width: 200, height: 100))
        #expect(f.moves.isEmpty)
    }

    @Test func draggingShowsWhereTheWindowCanGoThenSwapsOnRelease() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let first = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        let second = FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        f.windows = [first, second]
        let manager = f.manager(); manager.retile()
        let (left, right) = (first.frame, second.frame)
        let otherDisplay = f.displayInventory.topology.displays[1].tilingBounds(padding: f.config.store.config.outerPadding)
        f.mouse = true
        f.pointer = CGPoint(x: left.midX, y: left.minY + 10)
        var waits = 0
        f.onWait = {
            waits += 1
            if waits == 1 { f.pointer = CGPoint(x: right.midX, y: right.midY) } else { f.mouse = false }
        }
        manager.trackDrag(of: 1, isResize: false)
        await manager.dragTask?.value
        // Over its own tile nothing is filled; over the other tile, that tile is.
        #expect(f.dropTargets == [DropTargets(window: 1, places: [right, otherDisplay], landing: nil),
                                  DropTargets(window: 1, places: [right, otherDisplay], landing: right), nil])
        #expect(first.frame == right && second.frame == left)
    }

    @Test func aDragReportedOnlyAfterReleaseStillSwaps() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let first = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        let second = FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        f.windows = [first, second]
        let manager = f.manager(); manager.retile()
        let (left, right) = (first.frame, second.frame)
        first.frame = left.offsetBy(dx: 300, dy: 40)
        f.pointer = CGPoint(x: right.midX, y: right.midY)
        manager.trackDrag(of: 1, isResize: false)
        await manager.dragTask?.value
        #expect(f.dropTargets.allSatisfy { $0 == nil })
        #expect(first.frame == right && second.frame == left)
    }

    @Test func draggingToAnotherDisplayFillsTheDisplayItJoins() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let dragged = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        f.windows = [dragged, FakeTilingWindow(2, CGRect(x: 1100, y: 30, width: 200, height: 100), space: 20)]
        let manager = f.manager(); manager.retile()
        let start = dragged.frame
        let otherDisplay = f.displayInventory.topology.displays[1].tilingBounds(padding: f.config.store.config.outerPadding)
        f.mouse = true
        f.pointer = CGPoint(x: start.midX, y: start.minY + 10)
        f.onWait = {
            guard f.dropTargets.count < 2 else { f.mouse = false; return }
            // The window's center crosses onto the other display before the pointer would.
            dragged.frame = start.offsetBy(dx: 700, dy: 0)
            f.pointer = CGPoint(x: start.midX + 700, y: start.minY + 10)
        }
        manager.trackDrag(of: 1, isResize: false)
        await manager.dragTask?.value
        await manager.moveTask?.value
        #expect(f.dropTargets.dropLast().last??.landing == otherDisplay)
        #expect(dragged.space == 20)
    }

    @Test func resizesAndFloatingWindowsShowNoDropTargets() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let first = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        let second = FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        f.windows = [first, second]
        let manager = f.manager(); manager.retile()
        f.pointer = CGPoint(x: second.frame.midX, y: second.frame.midY)
        f.onWait = { f.mouse = false }
        f.mouse = true
        manager.trackDrag(of: 1, isResize: true)
        await manager.dragTask?.value
        f.focusedID = 1; manager.perform(.toggleFloat)
        f.mouse = true
        manager.trackDrag(of: 1, isResize: false)
        await manager.dragTask?.value
        #expect(f.dropTargets.allSatisfy { $0 == nil })
    }

    @Test func crossDropNativeFailureKeepsObservedStateAndDismissibleError() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let window = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)
        f.windows = [window]
        let manager = f.manager(); manager.retile()
        window.frame = CGRect(x: 1100, y: 30, width: 200, height: 100)
        f.moveFailure = SpaceMover.MoveError.nativeOperationUnavailable
        manager.drop(window.handle, source: .init(displayID: 1, spaceID: 10), resized: false)
        await manager.moveTask?.value
        #expect(manager.lastDesktopMoveError != nil)
        #expect(window.space == 10)
        #expect(window.focused == 0)
        #expect(manager.layoutState.trees[LayoutKey(displayID: 2, spaceID: 20)]?.isEmpty == true)
    }

    @Test func disablingDuringSettlingCancelsWithoutFollowingFocus() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)]; f.focusedID = 1
        let manager = f.manager()
        f.onWait = { manager.isEnabled = false }
        manager.perform(.sendToNextDisplay); await manager.moveTask?.value
        #expect(f.windows[0].focused == 0)
        #expect(manager.lastDesktopMoveError == nil)
        #expect(!manager.isEnabled)
        manager.isEnabled = true; f.onWait = nil; manager.retile()
        #expect(manager.layoutState.trees[LayoutKey(displayID: 2, spaceID: 20)]?.windows == [1])
    }

    @Test func failedNativeRequestPreservesSourceLayoutAndDoesNotFocus() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)]; f.focusedID = 1
        f.moveFailure = SpaceMover.MoveError.nativeOperationUnavailable
        let manager = f.manager(); manager.perform(.sendToNextDisplay); await manager.moveTask?.value
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.windows == [1])
        #expect(f.windows[0].space == 10)
        #expect(f.windows[0].focused == 0)
        #expect(manager.lastDesktopMoveError != nil)
    }

    @Test func failedAnimationWriteClearsCacheAndFinalResizeRepairsClamping() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.config.store.config.animationsEnabled = true; f.provideLinks = true
        let window = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)
        f.windows = [window]; window.succeeds = false
        let manager = f.manager(); manager.retile()
        f.time = 0.05; _ = f.ticks[1]?()
        window.succeeds = true
        f.time = 0.1; _ = f.ticks[1]?()
        #expect(window.writeFrom[1] == nil)
        f.time = 0.2; _ = f.ticks[1]?()
        #expect(window.resizeFlags.last?.0 == true)
        #expect(window.resizeFlags.last?.1 == true)
    }

    @Test func animationStopsTheFrameAfterItsWindowChangesSpace() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.config.store.config.animationsEnabled = true; f.provideLinks = true
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)]
        let manager = f.manager(); manager.retile()
        f.windows[0].space = 20
        // Windows' Spaces are checked off the main thread, so the frame that starts the check still writes.
        f.time = 0.05; _ = f.ticks[1]?()
        let writes = f.windows[0].writes.count
        for _ in 0..<10 { await Task.yield() }
        f.time = 0.1
        let continuing = f.ticks[1]?()
        #expect(continuing == false)
        #expect(f.windows[0].writes.count == writes)
        #expect(f.ticks.isEmpty)
    }

    @Test func fullscreenDropAndDisabledDropNeverSubmitNativeMoves() {
        let f = TilingFixture(); defer { f.cleanup() }
        let window = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)
        f.windows = [window]; let manager = f.manager(); manager.retile()
        f.display(2, space: 20, kind: .fullscreen)
        window.frame = CGRect(x: 1100, y: 30, width: 400, height: 300)
        manager.drop(window.handle, source: .init(displayID: 1, spaceID: 10), resized: false)
        #expect(f.moves.isEmpty)
        #expect(manager.moveTask == nil)
        manager.isEnabled = false; f.display(2, space: 20)
        manager.drop(window.handle, source: .init(displayID: 1, spaceID: 10), resized: false)
        #expect(f.moves.isEmpty)
    }

    @Test func refreshDefersAllProgrammaticWritesUntilPointerRelease() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)]
        f.mouse = true
        let manager = f.manager(); manager.retile()
        #expect(f.windows[0].writes.isEmpty)
        f.mouse = false
        await manager.pointerReleaseTask?.value
        #expect(f.windows[0].writes.count == 1)
    }

    @Test func animationsUseIndependentDisplayLinksAndRetargets() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.config.store.config.animationsEnabled = true; f.provideLinks = true
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10),
                     FakeTilingWindow(2, CGRect(x: 1100, y: 30, width: 400, height: 300), space: 20)]
        let manager = f.manager(); manager.retile()
        #expect(Set(f.ticks.keys) == [1, 2])
        #expect(f.windows.allSatisfy { $0.writes.isEmpty })
        f.time = 0.1
        _ = f.ticks[1]?()
        #expect(f.windows[0].writes.count == 1)
        #expect(f.windows[1].writes.isEmpty)
        f.windows.append(FakeTilingWindow(3, CGRect(x: 10, y: 30, width: 100, height: 100), space: 10))
        manager.retile()
        #expect(f.invalidated.isEmpty)
        f.time = 0.2
        _ = f.ticks[2]?()
        #expect(f.windows[1].frame == CGRect(x: 1008, y: 28, width: 784, height: 564))
        #expect(f.invalidated == [2])
    }

    @Test func animationTicksStopWhenSpaceOrDisplayChanges() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.config.store.config.animationsEnabled = true; f.provideLinks = true
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)]
        let manager = f.manager(); manager.retile()
        let stale = f.ticks[1]
        f.display(1, space: 11)
        let continuing = stale?()
        #expect(continuing == false)
        #expect(f.windows[0].writes.isEmpty)
        #expect(f.invalidated == [1])
    }

    @Test func animationPausesDuringMousePressAndReduceMotionFinishesImmediately() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.config.store.config.animationsEnabled = true; f.provideLinks = true
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)]
        let manager = f.manager(); manager.retile()
        f.mouse = true; f.time = 0.1
        _ = f.ticks[1]?()
        #expect(f.windows[0].writes.isEmpty)
        f.mouse = false; f.reduceMotion = true
        _ = f.ticks[1]?()
        #expect(f.windows[0].frame == CGRect(x: 8, y: 28, width: 984, height: 764))
        #expect(f.ticks.isEmpty)
    }

    @Test func disablingTilingInvalidatesLinksAndFailedWritesDoNotTrustCaches() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.config.store.config.animationsEnabled = true; f.provideLinks = true
        let window = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)
        window.succeeds = false; f.windows = [window]
        let manager = f.manager(); manager.retile()
        f.time = 0.1; _ = f.ticks[1]?()
        #expect(window.writes.count == 1)
        manager.isEnabled = false
        #expect(f.ticks.isEmpty)
        #expect(f.invalidated == [1])
    }

    @Test func reloadingEnvironmentReconcilesAfterTheReadAndRereadsOnceForEventsDuringIt() async {
        let f = TilingFixture(); defer { f.cleanup() }
        let window = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)
        f.windows = [window]
        var environment = f.environment
        var reloads = 0
        var release: CheckedContinuation<Void, Never>?
        environment.reload = { reloads += 1; await withCheckedContinuation { release = $0 } }
        let manager = TilingManager(configStore: f.config.store, environment: environment, initiallyTrusted: true)
        manager.retile()
        await waitUntil { release != nil }
        manager.retile(); manager.retile()
        #expect(window.writes.isEmpty)
        #expect(reloads == 1)
        release?.resume(); release = nil
        await waitUntil { release != nil }
        #expect(window.writes.count == 1)
        #expect(reloads == 2)
        release?.resume(); release = nil
        for _ in 0..<20 { await Task.yield() }
        #expect(reloads == 2)
    }

    @Test func shortcutsWaitForAFreshReadEach() async {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10),
                     FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 200, height: 100), space: 10)]
        f.focusedID = 1
        var environment = f.environment
        var reloads = 0
        environment.reload = { reloads += 1; await Task.yield() }
        let manager = TilingManager(configStore: f.config.store, environment: environment, initiallyTrusted: true)
        manager.perform(.focus(.right))
        manager.perform(.focus(.left))
        #expect(f.windows.allSatisfy { $0.focused == 0 })
        await manager.actionTask?.value
        #expect(reloads == 2)
        #expect(f.windows[1].focused == 1)
        #expect(f.windows[0].focused == 0)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }

    @Test func listsEveryWindowOnlyWhenAWindowHasNoSpace() {
        let f = TilingFixture(); defer { f.cleanup() }
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10),
                     FakeTilingWindow(2, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)]
        let manager = f.manager(); manager.retile()
        #expect(f.windowListings == 0)
        f.windows.removeLast()
        manager.retile()
        #expect(f.windowListings == 1)
        #expect(manager.layoutState.trees[LayoutKey(displayID: 1, spaceID: 10)]?.windows == [1])
    }

    @Test func trustDisableAndDuplicateIDsDoNotCauseExtraWrites() {
        let f = TilingFixture(); defer { f.cleanup() }
        let window = FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)
        f.windows = [window, window]
        let denied = f.manager(trusted: false); denied.retile()
        #expect(f.enumerations == 0)
        let manager = f.manager(); manager.isEnabled = false; manager.retile()
        #expect(f.enumerations == 0)
        manager.isEnabled = true; manager.retile()
        #expect(window.writes.count == 1)
    }
}
