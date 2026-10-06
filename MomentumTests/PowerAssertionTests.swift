import Foundation
import IOKit.pwr_mgt
import Testing
@testable import Momentum

@MainActor
final class FakePowerClient: PowerAssertionClient {
    var creates: [PowerAssertionKind] = []
    var releases: [IOPMAssertionID] = []
    var live: Set<IOPMAssertionID> = []
    var failCreateAt: Int?
    var releaseFailures = 0
    var returnZero = false

    func create(_ kind: PowerAssertionKind) throws -> IOPMAssertionID {
        creates.append(kind)
        if creates.count == failCreateAt { throw PowerAssertionError(message: "Injected create failure") }
        if returnZero { return 0 }
        let id = IOPMAssertionID(creates.count)
        live.insert(id)
        return id
    }

    func release(_ id: IOPMAssertionID) throws {
        releases.append(id)
        if releaseFailures > 0 {
            releaseFailures -= 1
            throw PowerAssertionError(message: "Injected release failure")
        }
        live.remove(id)
    }
}

@MainActor
struct PowerAssertionTests {
    @Test func modesAreTransactionalAndStopIsIdempotent() throws {
        let client = FakePowerClient()
        client.live.insert(99) // An unrelated request must never be released.
        let owner = PowerAssertions(client: client)
        try owner.commit(try owner.prepare(.system), mode: .system)
        #expect(client.creates == [.system])
        let old = owner.owned
        client.failCreateAt = 2
        #expect(throws: PowerAssertionError.self) { try owner.prepare(.systemAndDisplay) }
        #expect(owner.owned == old)
        #expect(client.live == [1, 99])
        client.failCreateAt = nil
        let additions = try owner.prepare(.systemAndDisplay)
        #expect(owner.owned == old)
        try owner.commit(additions, mode: .systemAndDisplay)
        #expect(client.live == [1, 3, 99])
        try owner.commit(try owner.prepare(.systemAndDisplay), mode: .systemAndDisplay)
        #expect(client.creates.count == 3)
        try owner.commit(try owner.prepare(.system), mode: .system)
        #expect(client.releases == [3])
        owner.releaseAll()
        owner.releaseAll()
        #expect(client.releases == [3, 1])
        #expect(client.live == [99])
    }

    @Test func failedDowngradeRetainsWorkingDisplayOwnershipUntilRetryOrStop() throws {
        let client = FakePowerClient()
        let owner = PowerAssertions(client: client)
        try owner.commit(try owner.prepare(.systemAndDisplay), mode: .systemAndDisplay)
        let previous = owner.owned
        client.releaseFailures = 2
        #expect(throws: PowerAssertionError.self) {
            try owner.commit(try owner.prepare(.system), mode: .system)
        }
        #expect(owner.owned == previous)
        #expect(owner.pendingCleanup.isEmpty)
        #expect(client.live == [1, 2])
        #expect(client.releases == [2, 2])
        owner.retryCleanup() // The working display ID is not orphaned cleanup.
        #expect(client.releases == [2, 2])
        #expect(try owner.prepare(.systemAndDisplay).isEmpty)
        try owner.commit(try owner.prepare(.system), mode: .system)
        #expect(owner.owned == [.system: 1])
        #expect(client.live == [1])
        #expect(client.releases == [2, 2, 2])
        owner.releaseAll()
        #expect(client.live.isEmpty)
    }

    @Test func failedFirstOrSecondCreationRollsBack() {
        for failure in [1, 2] {
            let client = FakePowerClient()
            client.failCreateAt = failure
            let owner = PowerAssertions(client: client)
            #expect(throws: PowerAssertionError.self) { try owner.prepare(.systemAndDisplay) }
            #expect(owner.owned.isEmpty)
            #expect(client.live.isEmpty)
            #expect(client.releases.count == failure - 1)
            owner.releaseAll()
            #expect(client.releases.count == failure - 1)
        }
        let client = FakePowerClient()
        client.returnZero = true
        #expect(throws: PowerAssertionError.self) { try PowerAssertions(client: client).prepare(.system) }
    }

    @Test func failedReleaseRetainsOwnershipWithBoundedRetry() throws {
        let client = FakePowerClient()
        let owner = PowerAssertions(client: client)
        try owner.commit(try owner.prepare(.system), mode: .system)
        client.releaseFailures = 3
        owner.releaseAll()
        #expect(client.releases.count == 2)
        #expect(owner.pendingCleanup == [1])
        #expect(owner.cleanupError != nil)
        owner.retryCleanup()
        #expect(client.releases.count == 4)
        #expect(owner.pendingCleanup.isEmpty)
        #expect(owner.cleanupError == nil)
    }

    @Test func failedRollbackKeepsIDsAndDoesNotPublishProtection() {
        let client = FakePowerClient()
        client.failCreateAt = 2
        client.releaseFailures = 10
        let owner = PowerAssertions(client: client)
        #expect(throws: PowerAssertionError.self) { try owner.prepare(.systemAndDisplay) }
        #expect(owner.owned.isEmpty)
        #expect(owner.pendingCleanup == [1])
        #expect(owner.cleanupError != nil)
    }
}
