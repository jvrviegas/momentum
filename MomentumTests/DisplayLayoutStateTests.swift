import CoreGraphics
import Testing
@testable import Momentum

@MainActor
struct DisplayLayoutStateTests {
    private let a = LayoutKey(displayID: 1, spaceID: 10)
    private let b = LayoutKey(displayID: 2, spaceID: 20)
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func visible(_ windows: [WindowID], x: CGFloat = 0) -> DisplayLayoutState.VisibleLayout {
        .init(bounds: CGRect(x: x, y: 0, width: bounds.width, height: bounds.height), windows: windows)
    }

    @Test func sharedSpaceKeepsIndependentTreesAndChangesStayLocal() {
        let sharedB = LayoutKey(displayID: 2, spaceID: a.spaceID)
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1, 2]), sharedB: visible([3, 4], x: 1000)],
                        connectedDisplays: [1, 2], focused: 3)
        let untouched = state.trees[sharedB]
        state.reconcile(visible: [a: visible([1, 2, 5]), sharedB: visible([3, 4], x: 1000)],
                        connectedDisplays: [1, 2], focused: 5)
        #expect(state.trees[a]?.windows == [1, 2, 5])
        #expect(state.trees[sharedB] == untouched)
        #expect(state.lastFocused[a] == 5)
        #expect(state.lastFocused[sharedB] == 3)
    }

    @Test func invisibleDesktopRetainsTreeAndFocusUntilEvidenceChanges() {
        let next = LayoutKey(displayID: 1, spaceID: 11)
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1, 2]), b: visible([3])], connectedDisplays: [1, 2], focused: 1)
        let previous = state.trees[a]
        state.reconcile(visible: [next: visible([4]), b: visible([3])], connectedDisplays: [1, 2])
        #expect(state.trees[a] == previous)
        #expect(state.lastFocused[a] == 1)
        state.reconcile(visible: [next: visible([4])], connectedDisplays: [1, 2],
                        membership: [1: .closed, 2: .space(99)])
        #expect(state.trees[a] == nil)
        #expect(state.lastFocused[a] == nil)
        #expect(state.trees[b]?.windows == [3])
    }

    @Test func inactiveSharedSpaceOwnershipIsReconciledOnVisibility() {
        let sharedB = LayoutKey(displayID: 2, spaceID: 10)
        let nextA = LayoutKey(displayID: 1, spaceID: 11)
        let nextB = LayoutKey(displayID: 2, spaceID: 11)
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1]), sharedB: visible([2])], connectedDisplays: [1, 2])
        state.reconcile(visible: [nextA: visible([3]), nextB: visible([4])], connectedDisplays: [1, 2],
                        membership: [1: .space(10), 2: .space(10)])
        #expect(state.trees[a]?.windows == [1])
        #expect(state.trees[sharedB]?.windows == [2])
        state.reconcile(visible: [a: visible([]), sharedB: visible([2, 1])], connectedDisplays: [1, 2])
        #expect(state.trees[a]?.isEmpty == true)
        #expect(state.trees[sharedB]?.windows == [2, 1])
    }

    @Test func transferCollapsesSourceAndInsertsAtDestinationRememberedFocus() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1, 2]), b: visible([3, 4], x: 1000)],
                        connectedDisplays: [1, 2], focused: 3)
        var expected = state.trees[b]!
        expected.insert(2, at: 3, bounds: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        state.reconcile(visible: [a: visible([1]), b: visible([3, 4, 2], x: 1000)],
                        connectedDisplays: [1, 2], focused: 2)
        #expect(state.trees[a]?.windows == [1])
        #expect(state.trees[b] == expected)
        #expect(state.lastFocused[b] == 2)
    }

    @Test func visibleTransferRemovesStaleInactiveOwnerWithoutGuessingGeometry() {
        let hidden = LayoutKey(displayID: 1, spaceID: 11)
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1, 2])], connectedDisplays: [1, 2])
        state.reconcile(visible: [hidden: visible([3]), b: visible([2])], connectedDisplays: [1, 2])
        #expect(state.trees[a]?.windows == [1])
        #expect(state.trees[b]?.windows == [2])
    }

    @Test func disconnectDropsRuntimeStateAndReconnectDoesNotRestoreIt() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1]), b: visible([2])], connectedDisplays: [1, 2], focused: 2)
        state.reconcile(visible: [a: visible([1, 2])], connectedDisplays: [1])
        #expect(state.trees[b] == nil)
        #expect(state.lastFocused[b] == nil)
        let remaining = state.trees[a]
        state.reconcile(visible: [a: visible([1, 2]), b: visible([])], connectedDisplays: [1, 2])
        #expect(state.trees[a] == remaining)
        #expect(state.trees[b]?.isEmpty == true)
    }

    @Test func duplicateAndInvalidWindowsHaveOneOwnerAndKnownMembershipWins() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([0, 1, 1, 2, 3]), b: visible([1, 2])],
                        connectedDisplays: [1, 2], membership: [2: .space(20), 3: .closed])
        #expect(state.trees[a]?.windows == [1])
        #expect(state.trees[b]?.windows == [2])
    }

    @Test func swappingNeverCrossesDisplayOrDesktopBoundary() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1, 2]), b: visible([3, 4], x: 1000)], connectedDisplays: [1, 2])
        let other = state.trees[b]
        let swapped = state.swap(1, direction: .right, in: a, bounds: bounds)
        #expect(swapped)
        #expect(state.trees[a]?.windows == [2, 1])
        #expect(state.trees[b] == other)
        let foreignSwap = state.swap(3, direction: .left, in: a, bounds: bounds)
        let edgeSwap = state.swap(1, direction: .right, in: a, bounds: bounds)
        #expect(!foreignSwap)
        #expect(!edgeSwap)
        #expect(state.trees[b] == other)
    }

    @Test func invalidLayoutInputDoesNotEraseInactiveState() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1])], connectedDisplays: [1])
        let old = state.trees[a]
        state.reconcile(visible: [a: .init(bounds: .zero, windows: [])], connectedDisplays: [1])
        #expect(state.trees[a] == old)
        let zeroSpace = LayoutKey(displayID: 1, spaceID: 0)
        state.reconcile(visible: [zeroSpace: visible([2]), b: visible([3])], connectedDisplays: [1])
        #expect(state.trees[zeroSpace] == nil)
        #expect(state.trees[b] == nil)
        #expect(state.trees[a] == old)
    }

    @Test func focusIsPerKeyAndClearedWhenFocusedWindowLeaves() {
        var state = DisplayLayoutState()
        state.reconcile(visible: [a: visible([1, 2]), b: visible([3])], connectedDisplays: [1, 2], focused: 1)
        state.reconcile(visible: [a: visible([1, 2]), b: visible([3])], connectedDisplays: [1, 2], focused: 3)
        #expect(state.lastFocused[a] == 1)
        #expect(state.lastFocused[b] == 3)
        state.reconcile(visible: [a: visible([2]), b: visible([3])], connectedDisplays: [1, 2])
        #expect(state.lastFocused[a] == nil)
        #expect(state.lastFocused[b] == 3)
    }
}
