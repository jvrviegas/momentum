import CoreGraphics
import Testing
@testable import Momentum

@MainActor
struct DisplayTopologyTests {
    private func display(_ id: DisplayID, _ frame: CGRect,
                         kind: DisplayTopology.SpaceKind = .normal, space: SpaceID = 10) -> DisplayTopology.Display {
        .init(id: id, frame: frame, usableFrame: frame, activeSpace: .init(id: space, kind: kind))
    }

    @Test func flipsAllScreensAgainstPrimaryNotTheirOwnHeight() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(DisplayTopology.axFrame(fromAppKit: primary, primaryFrame: primary) == primary)
        #expect(DisplayTopology.axFrame(fromAppKit: CGRect(x: -1920, y: 100, width: 1920, height: 1080),
                                        primaryFrame: primary) == CGRect(x: -1920, y: -280, width: 1920, height: 1080))
        #expect(DisplayTopology.axFrame(fromAppKit: CGRect(x: 0, y: 900, width: 1440, height: 900),
                                        primaryFrame: primary).minY == -900)
        #expect(DisplayTopology.axFrame(fromAppKit: CGRect(x: 0, y: -900, width: 1440, height: 900),
                                        primaryFrame: primary).minY == 900)
    }

    @Test func usableFrameAndPaddingStayInLogicalPoints() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let full = CGRect(x: 1440, y: -180, width: 2560, height: 1440)
        let visible = CGRect(x: 1440, y: -130, width: 2560, height: 1365)
        let screen = DisplayTopology.Display(id: 2,
            frame: DisplayTopology.axFrame(fromAppKit: full, primaryFrame: primary),
            usableFrame: DisplayTopology.axFrame(fromAppKit: visible, primaryFrame: primary),
            activeSpace: .init(id: 20, kind: .normal))
        #expect(screen.tilingBounds(padding: 8) == CGRect(x: 1448, y: -327, width: 2544, height: 1349))
    }

    @Test func paddingNeverCreatesNegativeBounds() {
        let screen = display(1, CGRect(x: 0, y: 0, width: 10, height: 4))
        #expect(screen.tilingBounds(padding: 100) == CGRect(x: 4.5, y: 1.5, width: 1, height: 1))
        #expect(screen.tilingBounds(padding: -8) == screen.frame)
        #expect(screen.tilingBounds(padding: .infinity) == screen.frame)
    }

    @Test func orderingWrapsAndHandlesVerticalTies() {
        let left = display(3, CGRect(x: -100, y: 0, width: 100, height: 100))
        let top = display(2, CGRect(x: 0, y: -100, width: 100, height: 100))
        let bottom = display(1, CGRect(x: 0, y: 0, width: 100, height: 100))
        let topology = DisplayTopology(displays: [bottom, top, left])
        #expect(topology.eligibleDisplays.map(\.id) == [3, 2, 1])
        #expect(topology.destination(from: 1, step: .next)?.id == 3)
        #expect(topology.destination(from: 3, step: .previous)?.id == 1)
        #expect(topology.destination(from: 2, step: .next)?.id == 1)
    }

    @Test func equalCentersUseStableIdentity() {
        let a = display(2, CGRect(x: 0, y: 0, width: 100, height: 100))
        let b = display(1, CGRect(x: 25, y: 25, width: 50, height: 50))
        #expect(DisplayTopology(displays: [a, b]).eligibleDisplays.map(\.id) == [1, 2])
    }

    @Test func destinationsSkipFullscreenUnknownAndZeroSpace() {
        let normal = display(1, CGRect(x: 0, y: 0, width: 100, height: 100))
        let full = display(2, CGRect(x: 100, y: 0, width: 100, height: 100), kind: .fullscreen)
        let unknown = display(3, CGRect(x: 200, y: 0, width: 100, height: 100), kind: .unknown)
        let zero = display(4, CGRect(x: 300, y: 0, width: 100, height: 100), space: 0)
        let unmapped = DisplayTopology.Display(id: 5, frame: CGRect(x: 400, y: 0, width: 100, height: 100),
                                               usableFrame: CGRect(x: 400, y: 0, width: 100, height: 100), activeSpace: nil)
        let topology = DisplayTopology(displays: [normal, full, unknown, zero, unmapped])
        #expect(topology.eligibleDisplays.map(\.id) == [1])
        #expect(topology.destination(from: 1, step: .next) == nil)
        #expect(topology.destination(from: 2, step: .previous) == nil)
        #expect(topology.owner(of: CGRect(x: 110, y: 10, width: 20, height: 20))?.id == 2)
    }

    @Test func centerWinsOverIntersectionAndSharedEdgeHasOneOwner() {
        let a = display(1, CGRect(x: 0, y: 0, width: 100, height: 100))
        let b = display(2, CGRect(x: 100, y: 0, width: 200, height: 100))
        let topology = DisplayTopology(displays: [a, b])
        #expect(topology.owner(of: CGRect(x: 80, y: 0, width: 80, height: 100))?.id == 2)
        #expect(topology.owner(of: CGRect(x: 90, y: 10, width: 20, height: 20))?.id == 2)
    }

    @Test func gapOwnershipUsesIntersectionThenNearestThenIdentity() {
        let a = display(1, CGRect(x: 0, y: 0, width: 100, height: 100))
        let b = display(2, CGRect(x: 200, y: 0, width: 100, height: 100))
        let topology = DisplayTopology(displays: [b, a])
        #expect(topology.owner(of: CGRect(x: 70, y: 0, width: 100, height: 100))?.id == 1)
        #expect(topology.owner(of: CGRect(x: 165, y: 0, width: 10, height: 10))?.id == 2)
        #expect(topology.owner(of: CGRect(x: 145, y: 0, width: 10, height: 10))?.id == 1)
        #expect(topology.owner(of: CGRect(x: -300, y: 0, width: 10, height: 10))?.id == 1)
    }

    @Test func logicalMirrorsAndDuplicateIDsDoNotCreateDuplicateOwners() {
        let a = display(1, CGRect(x: 0, y: 0, width: 100, height: 100))
        let mirror = display(2, a.frame)
        #expect(DisplayTopology(displays: [mirror, a, a]).displays == [a])
    }

    @Test func directionalCandidatesHandleVerticalOffsetOverlapAndTies() {
        let a = display(1, CGRect(x: 0, y: 0, width: 100, height: 100))
        let b = display(2, CGRect(x: 50, y: -100, width: 100, height: 100))
        let c = display(3, CGRect(x: 0, y: 100, width: 100, height: 100))
        let topology = DisplayTopology(displays: [a, b, c])
        let frames: [WindowID: CGRect] = [1: CGRect(x: 10, y: 10, width: 80, height: 80),
            2: CGRect(x: 50, y: -90, width: 40, height: 80),
            3: CGRect(x: 50, y: -90, width: 40, height: 80),
            4: CGRect(x: 10, y: 110, width: 80, height: 80)]
        let owners: [WindowID: DisplayID] = [1: 1, 2: 2, 3: 2, 4: 3]
        #expect(topology.crossDisplayNeighbor(of: 1, direction: .up, frames: frames, owners: owners) == 2)
        #expect(topology.crossDisplayNeighbor(of: 1, direction: .down, frames: frames, owners: owners) == 4)
        #expect(topology.crossDisplayNeighbor(of: 1, direction: .left, frames: frames, owners: owners) == nil)
        #expect(topology.crossDisplayNeighbor(of: 99, direction: .up, frames: frames, owners: owners) == nil)
    }

    @Test func invalidFramesAndEmptyInventoriesAreSafe() {
        let zero = display(1, .zero)
        let invalid = display(2, CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100))
        let outside = DisplayTopology.Display(id: 3, frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            usableFrame: CGRect(x: 0, y: 0, width: 200, height: 100), activeSpace: nil)
        let topology = DisplayTopology(displays: [zero, invalid, outside])
        #expect(topology.displays.isEmpty)
        #expect(topology.owner(of: CGRect(x: 0, y: 0, width: 10, height: 10)) == nil)
        #expect(topology.destination(from: 1, step: .next) == nil)
        #expect(DisplayTopology(displays: [display(4, CGRect(x: 0, y: 0, width: 100, height: 100))])
            .owner(of: .zero) == nil)
    }
}
