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

    @Test func strictResolverKeepsDesktopOrdinalsDisplayLocal() throws {
        let main = try #require(Spaces.displaySnapshot(for: "main", in: snapshot()))
        let other = try #require(Spaces.displaySnapshot(for: "other", in: snapshot()))
        #expect(Spaces.desktopSpace(1, in: main) == 11)
        #expect(Spaces.desktopSpace(2, in: main) == 30)
        #expect(Spaces.desktopSpace(1, in: other) == 90)
        #expect(Spaces.desktopSpace(2, in: other) == nil)
        #expect(Spaces.desktopSpace(0, in: main) == nil)
        #expect(Spaces.desktopSpace(10, in: main) == nil)
        #expect(Spaces.displaySnapshot(for: "missing-secondary", in: snapshot()) == nil)
        #expect(Spaces.displaySnapshot(for: "", in: snapshot()) == nil)
    }

    @Test func strictSnapshotClassifiesNormalFullscreenAndUnknown() throws {
        for (type, expected) in [(0, DisplayTopology.SpaceKind.normal), (4, .fullscreen), (9, .unknown)] {
            let fixture: [[String: Any]] = [["Display Identifier": "secondary",
                "Current Space": ["id64": 91], "Spaces": [["id64": 91, "type": type]]]]
            let parsed = try #require(Spaces.displaySnapshot(for: "secondary", in: fixture))
            #expect(parsed.activeSpace == .init(id: 91, kind: expected))
            #expect(parsed.desktopSpaces == (type == 0 ? [91] : []))
        }
    }

    @Test func conflictingCurrentSpaceTypesFailClosed() throws {
        for (listed, reported) in [(0, 4), (4, 0), (0, 9), (9, 0), (9, 4), (9, 99)] {
            let fixture: [[String: Any]] = [["Display Identifier": "secondary",
                "Current Space": ["id64": 91, "type": reported],
                "Spaces": [["id64": 91, "type": listed], ["id64": 92, "type": 0]]]]
            let parsed = try #require(Spaces.displaySnapshot(for: "secondary", in: fixture))
            #expect(parsed.activeSpace == nil)
            #expect(parsed.desktopSpaces == (listed == 0 ? [91, 92] : [92]))
            let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            let display = DisplayTopology.Display(id: 2, frame: frame, usableFrame: frame,
                                                   activeSpace: parsed.activeSpace)
            #expect(!display.isEligible)
        }
    }

    @Test func matchingCurrentSpaceTypesRetainTheirClassification() throws {
        for (type, expected) in [(0, DisplayTopology.SpaceKind.normal), (4, .fullscreen), (9, .unknown)] {
            let fixture: [[String: Any]] = [["Display Identifier": "secondary",
                "Current Space": ["id64": 91, "type": type], "Spaces": [["id64": 91, "type": type]]]]
            let parsed = try #require(Spaces.displaySnapshot(for: "secondary", in: fixture))
            #expect(parsed.activeSpace == .init(id: 91, kind: expected))
        }
    }

    @Test func malformedSuppliedCurrentSpaceTypesFailClosed() throws {
        for badType in [false, true, 0.5, "0", NSNull(), NSNumber(value: UInt64.max)] as [Any] {
            let fixture: [[String: Any]] = [["Display Identifier": "secondary",
                "Current Space": ["id64": 91, "type": badType], "Spaces": [["id64": 91, "type": 0]]]]
            let parsed = try #require(Spaces.displaySnapshot(for: "secondary", in: fixture))
            #expect(parsed.activeSpace == nil)
            #expect(parsed.desktopSpaces == [91])
        }
    }

    @Test func absentCurrentSpaceTypeStillUsesListClassification() throws {
        let fixture: [[String: Any]] = [["Display Identifier": "secondary",
            "Current Space": ["id64": 91], "Spaces": [["id64": 91, "type": 0]]]]
        #expect(try #require(Spaces.displaySnapshot(for: "secondary", in: fixture)).activeSpace
                == .init(id: 91, kind: .normal))
    }

    @Test func normalizedSharedSnapshotDoesNotNeedDisplayFallback() {
        let shared = Spaces.DisplaySnapshot(identifier: "explicit-shared", activeSpace: .init(id: 11, kind: .normal),
                                            desktopSpaces: [11, 30])
        #expect(Spaces.desktopSpace(2, in: shared) == 30)
        let a = DisplayTopology.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            usableFrame: CGRect(x: 0, y: 0, width: 100, height: 100), activeSpace: shared.activeSpace)
        let b = DisplayTopology.Display(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 100),
            usableFrame: CGRect(x: 100, y: 0, width: 100, height: 100), activeSpace: shared.activeSpace)
        #expect(DisplayTopology(displays: [a, b]).eligibleDisplays.count == 2)
    }

    @Test func malformedOrAmbiguousDisplaySnapshotsAreRejected() {
        let duplicate = snapshot() + [snapshot()[1]]
        #expect(Spaces.displaySnapshot(for: "main", in: duplicate) == nil)
        for badID in [0, -1, 1.5, true, "11"] as [Any] {
            let fixture: [[String: Any]] = [["Display Identifier": "main", "Spaces": [["id64": badID, "type": 0]]]]
            #expect(Spaces.displaySnapshot(for: "main", in: fixture) == nil)
        }
        for badType in [false, 0.5, "0"] as [Any] {
            let fixture: [[String: Any]] = [["Display Identifier": "main", "Spaces": [["id64": 11, "type": badType]]]]
            #expect(Spaces.displaySnapshot(for: "main", in: fixture) == nil)
        }
        #expect(Spaces.displaySnapshot(for: "main", in: [["Display Identifier": "main"]]) == nil)
        #expect(Spaces.displaySnapshot(for: "main", in: [["Display Identifier": "main", "Spaces": [["id64": 11]]]]) == nil)
        #expect(Spaces.displaySnapshot(for: "main", in: [["Display Identifier": "main",
            "Spaces": [["id64": 11, "type": 0], ["id64": 11, "type": 4]]]]) == nil)
    }

    @Test func missingOrUnlistedCurrentSpaceStaysUnknown() throws {
        var fixture = snapshot()
        fixture[1]["Current Space"] = ["id64": 999]
        #expect(try #require(Spaces.displaySnapshot(for: "main", in: fixture)).activeSpace == nil)
        fixture[1]["Current Space"] = ["id64": 0]
        #expect(try #require(Spaces.displaySnapshot(for: "main", in: fixture)).activeSpace == nil)
        #expect(try #require(Spaces.displaySnapshot(for: "main", in: snapshot())).activeSpace == nil)
    }

    @Test func emptyDesktopListAndZeroNormalizedTargetAreSafe() throws {
        let fixture: [[String: Any]] = [["Display Identifier": "main", "Spaces": []]]
        let empty = try #require(Spaces.displaySnapshot(for: "main", in: fixture))
        #expect(Spaces.desktopSpace(1, in: empty) == nil)
        let zero = Spaces.DisplaySnapshot(identifier: "shared", activeSpace: nil, desktopSpaces: [0])
        #expect(Spaces.desktopSpace(1, in: zero) == nil)
    }

    @Test func inventoryMapsOnlyExactDisplayRecordsInSeparateMode() {
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let screens = [Spaces.ScreenInput(id: 1, identifier: "main", frame: primary, visibleFrame: primary),
                       Spaces.ScreenInput(id: 2, identifier: "missing", frame: CGRect(x: -800, y: 0, width: 800, height: 600),
                                          visibleFrame: CGRect(x: -800, y: 0, width: 800, height: 600))]
        var managed = snapshot(); managed[1]["Current Space"] = ["id64": 11, "type": 0]
        let inventory = Spaces.inventory(screens: screens, primaryFrame: primary, managed: managed,
                                         separateSpaces: true, sharedSpace: 11)
        #expect(inventory.topology.eligibleDisplays.map(\.id) == [1])
        #expect(inventory.desktops[2] == nil)
        #expect(inventory.topology.displays.first { $0.id == 2 }?.frame.minY == 200)
    }

    @Test func inventoryNormalizesAnExplicitSharedSnapshotOntoEachDisplay() {
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let screens = [Spaces.ScreenInput(id: 1, identifier: "a", frame: primary, visibleFrame: primary),
                       Spaces.ScreenInput(id: 2, identifier: "b", frame: CGRect(x: 1000, y: 0, width: 800, height: 600),
                                          visibleFrame: CGRect(x: 1000, y: 0, width: 800, height: 600))]
        let managed: [[String: Any]] = [["Display Identifier": "Main", "Current Space": ["id64": 11, "type": 0],
                                        "Spaces": [["id64": 11, "type": 0], ["id64": 30, "type": 0]]]]
        let inventory = Spaces.inventory(screens: screens, primaryFrame: primary, managed: managed,
                                         separateSpaces: false, sharedSpace: 11)
        #expect(inventory.topology.eligibleDisplays.count == 2)
        #expect(inventory.desktops[1] == inventory.desktops[2])
        #expect(inventory.topology.displays.allSatisfy { $0.activeSpace?.id == 11 })
        let missing = Spaces.inventory(screens: screens, primaryFrame: primary, managed: managed,
                                       separateSpaces: false, sharedSpace: 99)
        #expect(missing.topology.eligibleDisplays.isEmpty)
    }

    @Test func ambiguousSharedSnapshotsFailClosed() {
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let screens = [Spaces.ScreenInput(id: 1, identifier: "a", frame: frame, visibleFrame: frame)]
        let managed: [[String: Any]] = [
            ["Display Identifier": "a", "Current Space": ["id64": 11], "Spaces": [["id64": 11, "type": 0]]],
            ["Display Identifier": "b", "Current Space": ["id64": 11], "Spaces": [["id64": 11, "type": 0], ["id64": 30, "type": 0]]]]
        let inventory = Spaces.inventory(screens: screens, primaryFrame: frame, managed: managed,
                                         separateSpaces: false, sharedSpace: 11)
        #expect(inventory.topology.eligibleDisplays.isEmpty)
    }

    @Test func moveErrorsExplainTheWindowDisplayRatherThanThePrimaryDisplay() {
        #expect(SpaceMover.MoveError.desktopUnavailable(3).localizedDescription
                == "Desktop 3 isn't available on this window's display.")
        #expect(DisplayMover.MoveError.destinationChanged.localizedDescription.contains("display or Desktop"))
        #expect(DisplayMover.MoveError.frameWriteFailed.localizedDescription.contains("refused"))
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
