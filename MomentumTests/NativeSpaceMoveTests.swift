import Foundation
import Testing
@testable import Momentum

@MainActor
struct NativeSpaceMoveTests {
    private func snapshot() -> [[String: Any]] {
        [
            ["Display Identifier": "other", "Spaces": [["id64": 90, "type": 0]]],
            ["Display Identifier": "main", "Spaces": [
                ["id64": 11, "type": 0],
                ["id64": 12, "type": 4], // Fullscreen is not Desktop 2.
                ["id64": 30, "type": 0],
            ]],
        ]
    }

    @Test func resolvesDesktopOrderRatherThanTreatingNumberAsSpaceID() {
        #expect(Spaces.desktopSpace(1, in: snapshot(), displayIdentifier: "main", currentSpace: 11) == 11)
        #expect(Spaces.desktopSpace(2, in: snapshot(), displayIdentifier: "main", currentSpace: 11) == 30)
        #expect(Spaces.desktopSpace(3, in: snapshot(), displayIdentifier: "main", currentSpace: 11) == nil)
        #expect(Spaces.desktopSpace(0, in: snapshot(), displayIdentifier: "main", currentSpace: 11) == nil)
        #expect(Spaces.desktopSpace(10, in: snapshot(), displayIdentifier: "main", currentSpace: 11) == nil)
    }

    @Test func sharedSpacesFallBackToDisplayContainingCurrentSpace() {
        #expect(Spaces.desktopSpace(2, in: snapshot(), displayIdentifier: "unmatched", currentSpace: 11) == 30)
        #expect(Spaces.desktopSpace(2, in: snapshot(), displayIdentifier: nil, currentSpace: 11) == 30)
        #expect(Spaces.desktopSpace(1, in: snapshot(), displayIdentifier: nil, currentSpace: 999) == nil)
    }

    @Test func malformedSnapshotsAreRejected() {
        #expect(Spaces.desktopSpace(1, in: [], displayIdentifier: "main", currentSpace: 11) == nil)
        let malformed: [[String: Any]] = [["Display Identifier": "main", "Spaces": [["id64": 0, "type": 0]]]]
        #expect(Spaces.desktopSpace(1, in: malformed, displayIdentifier: "main", currentSpace: 11) == nil)
        let missingID: [[String: Any]] = [["Display Identifier": "main", "Spaces": [["type": 0]]]]
        #expect(Spaces.desktopSpace(1, in: missingID, displayIdentifier: "main", currentSpace: 11) == nil)
    }

    @Test func sameDesktopDoesNotSubmitOrWait() async throws {
        try await SpaceMover.move(windowID: 1, toSpace: 10, request: { _, _ in
            Issue.record("Same-Desktop move must not submit an operation")
            return false
        }, membership: { _ in 10 }, wait: { Issue.record("Same-Desktop move must not wait") })
    }

    @Test func waitsUntilMembershipConfirmsMove() async throws {
        var current: SpaceID = 10
        var requests = 0
        var waits = 0
        try await SpaceMover.move(windowID: 1, toSpace: 20, request: { window, target in
            #expect(window == 1 && target == 20)
            requests += 1
            return true
        }, membership: { _ in current }, wait: {
            waits += 1
            if waits == 3 { current = 20 }
        })
        #expect(requests == 1 && waits == 3)
    }

    @Test func unavailableOperationFailsWithoutWaiting() async {
        await #expect(throws: SpaceMover.MoveError.nativeOperationUnavailable) {
            try await SpaceMover.move(windowID: 1, toSpace: 20, request: { _, _ in false },
                                      membership: { _ in 10 }, wait: { Issue.record("Unavailable operation must not wait") })
        }
    }

    @Test func submittedOperationIsNotAssumedToHaveSucceeded() async {
        var waits = 0
        await #expect(throws: SpaceMover.MoveError.timedOut) {
            try await SpaceMover.move(windowID: 1, toSpace: 20, request: { _, _ in true },
                                      membership: { _ in 10 }, wait: { waits += 1 })
        }
        #expect(waits == 100)
    }

    @Test func checksMembershipAfterFinalWait() async throws {
        var waits = 0
        try await SpaceMover.move(windowID: 1, toSpace: 20, request: { _, _ in true },
                                  membership: { _ in waits == 100 ? 20 : 10 }, wait: { waits += 1 })
        #expect(waits == 100)
    }

    @Test func closedWindowFailsBeforeSubmitting() async {
        await #expect(throws: SpaceMover.MoveError.windowUnavailable) {
            try await SpaceMover.move(windowID: 1, toSpace: 20, request: { _, _ in
                Issue.record("Closed window must not submit")
                return true
            }, membership: { _ in nil }, wait: {})
        }
    }

    @Test func windowClosingDuringMoveFails() async {
        var closed = false
        await #expect(throws: SpaceMover.MoveError.windowUnavailable) {
            try await SpaceMover.move(windowID: 1, toSpace: 20, request: { _, _ in true },
                                      membership: { _ in closed ? nil : 10 }, wait: { closed = true })
        }
    }

    @Test func cancellationIsNotSwallowed() async {
        await #expect(throws: CancellationError.self) {
            try await SpaceMover.move(windowID: 1, toSpace: 20, request: { _, _ in true },
                                      membership: { _ in 10 }, wait: { throw CancellationError() })
        }
    }
}
