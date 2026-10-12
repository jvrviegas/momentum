import CoreGraphics
import Foundation
import Testing
@testable import Momentum

@MainActor
struct DisplayMoverTests {
    private let destination = DisplayTopology.Display(id: 2, frame: CGRect(x: 1000, y: 0, width: 800, height: 600),
        usableFrame: CGRect(x: 1000, y: 20, width: 800, height: 580), activeSpace: .init(id: 20, kind: .normal))
    private let target = CGRect(x: 1080, y: 80, width: 400, height: 200)

    @Test func stableAXAndServerGeometryAreBothRequired() async throws {
        var space: SpaceID? = 10, ax = CGRect.zero, server = CGRect.zero, waits = 0, moves = 0
        let client = DisplayMover.Client(topology: { .init(displays: [destination]) }, membership: { space },
            frame: { ax }, serverFrame: { server },
            moveSpace: { space = $0; moves += 1 },
            writeFrame: { ax = $0; return true },
            wait: {
                waits += 1
                if waits == 2 { server = target }
                if waits == 3 { server = .zero } // disagreement resets the stable-sample count
                if waits >= 4 { server = target }
            })
        try await DisplayMover.move(to: destination, frame: target, client: client)
        #expect(moves == 1)
        #expect(waits == 8)
    }

    @Test func sharedSpaceMoveUsesGeometryWithoutNativeSpaceRequest() async throws {
        let client = DisplayMover.Client(topology: { .init(displays: [destination]) }, membership: { 20 },
            frame: { target }, serverFrame: { target },
            moveSpace: { _ in Issue.record("Same Space must not submit a native move") },
            writeFrame: { _ in true }, wait: {})
        try await DisplayMover.move(to: destination, frame: target, client: client)
    }

    @Test func topologyChangeAfterNativeMoveFailsBeforeFrameWrite() async {
        var present = true, writes = 0
        let client = DisplayMover.Client(topology: { .init(displays: present ? [destination] : []) }, membership: { 10 },
            frame: { target }, serverFrame: { target }, moveSpace: { _ in present = false },
            writeFrame: { _ in writes += 1; return true }, wait: {})
        await #expect(throws: DisplayMover.MoveError.destinationChanged) {
            try await DisplayMover.move(to: destination, frame: target, client: client)
        }
        #expect(writes == 0)
    }

    @Test func nativeFailureAndWriteFailurePropagateWithoutAssumedSuccess() async {
        let native = DisplayMover.Client(topology: { .init(displays: [destination]) }, membership: { 10 },
            frame: { target }, serverFrame: { target }, moveSpace: { _ in throw SpaceMover.MoveError.nativeOperationUnavailable },
            writeFrame: { _ in Issue.record("Native failure must not write frame"); return true }, wait: {})
        await #expect(throws: SpaceMover.MoveError.nativeOperationUnavailable) {
            try await DisplayMover.move(to: destination, frame: target, client: native)
        }
        var refused = native
        refused.membership = { 20 }; refused.writeFrame = { _ in false }
        await #expect(throws: DisplayMover.MoveError.frameWriteFailed) {
            try await DisplayMover.move(to: destination, frame: target, client: refused)
        }
    }

    @Test func clampOrMissingServerGeometryTimesOutWithBoundedWaits() async {
        var waits = 0
        var client = DisplayMover.Client(topology: { .init(displays: [destination]) }, membership: { 20 },
            frame: { target }, serverFrame: { nil }, moveSpace: { _ in }, writeFrame: { _ in true },
            wait: { waits += 1 })
        await #expect(throws: DisplayMover.MoveError.timedOut) {
            try await DisplayMover.move(to: destination, frame: target, client: client)
        }
        #expect(waits == 150)
        client.serverFrame = { CGRect(x: 1080, y: 80, width: 600, height: 200) }
        await #expect(throws: DisplayMover.MoveError.timedOut) {
            try await DisplayMover.move(to: destination, frame: target, client: client)
        }
    }

    @Test func closureInvalidGeometryAndCancellationAreNotSwallowed() async {
        let client = DisplayMover.Client(topology: { .init(displays: [destination]) }, membership: { nil },
            frame: { nil }, serverFrame: { nil }, moveSpace: { _ in }, writeFrame: { _ in true }, wait: {})
        await #expect(throws: DisplayMover.MoveError.windowUnavailable) {
            try await DisplayMover.move(to: destination, frame: target, client: client)
        }
        await #expect(throws: DisplayMover.MoveError.invalidFrame) {
            try await DisplayMover.move(to: destination, frame: .zero, client: client)
        }
        var cancelling = client
        cancelling.membership = { 20 }; cancelling.frame = { .zero }
        cancelling.wait = { throw CancellationError() }
        await #expect(throws: CancellationError.self) {
            try await DisplayMover.move(to: destination, frame: target, client: cancelling)
        }
    }

    @Test func destinationDesktopChangeDuringSettlingFailsClosed() async {
        var destinationChanged = false
        let changed = DisplayTopology.Display(id: destination.id, frame: destination.frame,
            usableFrame: destination.usableFrame, activeSpace: .init(id: 21, kind: .normal))
        let client = DisplayMover.Client(topology: { .init(displays: [destinationChanged ? changed : destination]) },
            membership: { 20 }, frame: { target }, serverFrame: { target }, moveSpace: { _ in },
            writeFrame: { _ in true }, wait: { destinationChanged = true })
        await #expect(throws: DisplayMover.MoveError.destinationChanged) {
            try await DisplayMover.move(to: destination, frame: target, client: client)
        }
    }

    @Test func closingAfterTheNativeRequestDoesNotWriteAFrame() async {
        var closed = false
        let client = DisplayMover.Client(topology: { .init(displays: [destination]) },
            membership: { closed ? nil : 10 }, frame: { target }, serverFrame: { target },
            moveSpace: { _ in closed = true },
            writeFrame: { _ in Issue.record("Closed window must not be written"); return true }, wait: {})
        await #expect(throws: DisplayMover.MoveError.windowUnavailable) {
            try await DisplayMover.move(to: destination, frame: target, client: client)
        }
    }

    @Test func nativeAcknowledgementWithoutMembershipConfirmationNeverSucceeds() async {
        let client = DisplayMover.Client(topology: { .init(displays: [destination]) },
            membership: { 10 }, frame: { target }, serverFrame: { target }, moveSpace: { _ in },
            writeFrame: { _ in true }, wait: {})
        await #expect(throws: DisplayMover.MoveError.timedOut) {
            try await DisplayMover.move(to: destination, frame: target, client: client)
        }
    }

    @Test func floatingWindowSizeAndPositionFitDifferentUsableAreas() {
        let source = CGRect(x: 0, y: 20, width: 1000, height: 780)
        let frame = CGRect(x: 700, y: 500, width: 420, height: 300)
        #expect(DisplayMover.floatingFrame(frame, from: source, to: destination.usableFrame)
            == CGRect(x: 1380, y: 300, width: 420, height: 300))
        let huge = CGRect(x: 0, y: 20, width: 1200, height: 900)
        #expect(DisplayMover.floatingFrame(huge, from: source, to: destination.usableFrame) == destination.usableFrame)
    }
}
