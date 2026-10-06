import Foundation
import Testing
@testable import Momentum

@MainActor
final class FakeKeepAwakeScheduler: KeepAwakeScheduler {
    struct Entry {
        let delay: Double
        let action: @MainActor () -> Void
        var cancelled = false
    }
    var entries: [Entry] = []
    var liveCount: Int { entries.filter { !$0.cancelled }.count }

    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let index = entries.count
        entries.append(Entry(delay: seconds, action: action))
        return { self.entries[index].cancelled = true }
    }

    func fireLatest() {
        let index = entries.count - 1
        entries[index].cancelled = true
        entries[index].action()
    }
}

@MainActor
final class KeepAwakeFixture {
    let config = TemporaryConfig()
    let client = FakePowerClient()
    let scheduler = FakeKeepAwakeScheduler()
    var time: Double = 100
    lazy var service = KeepAwakeService(store: config.store, assertions: PowerAssertions(client: client),
        now: { [unowned self] in self.time }, scheduler: scheduler)

    func cleanup() {
        service.shutdown()
        config.cleanup()
    }
}

@MainActor
struct KeepAwakeServiceTests {
    @Test func startStopToggleAndRelaunch() throws {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        #expect(!f.service.isActive)
        f.service.start()
        #expect(f.service.mode == .system)
        #expect(f.service.deadline == 1900)
        f.time += 50
        f.service.start()
        #expect(f.service.deadline == 1900)
        #expect(f.client.creates.count == 1)
        #expect(f.scheduler.liveCount == 1)
        f.service.toggle()
        #expect(!f.service.isActive)
        #expect(f.client.live.isEmpty)
        #expect(f.scheduler.liveCount == 0)
        f.service.stop()
        #expect(f.client.releases.count == 1)
        f.service.toggle()
        #expect(f.service.deadline == 1950)
        let next = KeepAwakeService(store: f.config.store, assertions: PowerAssertions(client: FakePowerClient()))
        #expect(!next.isActive)
        let json = String(decoding: try JSONEncoder().encode(f.config.store.config), as: UTF8.self)
        for runtimeKey in ["deadline", "isActive", "assertion", "currentTime"] { #expect(!json.contains(runtimeKey)) }
    }

    @Test func exactExpiryAndStaleCallbackCannotAffectNewSession() {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        f.service.start()
        let stale = f.scheduler.entries[0].action
        f.time = 1899.9
        f.scheduler.fireLatest()
        #expect(f.service.remainingMinutes == 1)
        f.time = 1900
        f.scheduler.fireLatest()
        #expect(!f.service.isActive)
        #expect(f.service.error == nil)
        #expect(f.client.live.isEmpty)
        #expect(f.scheduler.liveCount == 0)
        f.service.start()
        let deadline = f.service.deadline
        stale()
        #expect(f.service.deadline == deadline)
        #expect(f.service.isActive)
        f.service.shutdown()
        #expect(f.scheduler.liveCount == 0)
        f.service.start()
        #expect(!f.service.isActive)
    }

    @Test func extensionsUseExistingDeadlineAndNeverPersistOrRevive() throws {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        f.service.extend(by: 900)
        #expect(!f.service.isActive)
        try f.config.store.updateKeepAwake(.init(duration: .eightHours))
        f.service.start()
        let original = try #require(f.service.deadline)
        f.time += 100
        for seconds in [900.0, 1800.0, 3600.0] { f.service.extend(by: seconds) }
        #expect(f.service.deadline == original + 6300)
        #expect(f.config.store.config.keepAwake.duration == .eightHours)
        f.time = original + 6300
        f.service.extend(by: 900)
        #expect(!f.service.isActive)
        #expect(f.client.live.isEmpty)
        try f.config.store.updateKeepAwake(.init(duration: .untilStopped))
        f.service.start()
        f.time += 100_000
        f.service.extend(by: 900)
        #expect(f.service.isActive)
        #expect(f.service.deadline == nil)
        #expect(f.service.remainingMinutes == nil)
        #expect(f.scheduler.liveCount == 0)
    }

    @Test func modeTransactionPreservesDeadlineAndRollsBackFailures() throws {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        f.service.start()
        let deadline = f.service.deadline
        f.client.failCreateAt = 2
        f.service.changeMode(.systemAndDisplay)
        #expect(f.service.mode == .system)
        #expect(f.service.deadline == deadline)
        #expect(f.config.store.config.keepAwake.mode == .system)
        #expect(f.client.live == [1])
        #expect(f.service.retryMode == .systemAndDisplay)
        f.client.failCreateAt = nil
        f.service.retry()
        #expect(f.service.mode == .systemAndDisplay)
        #expect(f.service.deadline == deadline)
        #expect(f.config.store.config.keepAwake.mode == .systemAndDisplay)
        #expect(f.service.error == nil)
        let createCount = f.client.creates.count
        f.service.changeMode(.systemAndDisplay)
        #expect(f.client.creates.count == createCount)
        f.service.changeMode(.system)
        #expect(f.client.live == [1])
        try FileManager.default.removeItem(at: f.config.directory)
        try Data().write(to: f.config.directory)
        f.service.changeMode(.systemAndDisplay)
        #expect(f.service.mode == .system)
        #expect(f.service.deadline == deadline)
        #expect(f.config.store.config.keepAwake.mode == .system)
        #expect(f.client.live == [1])
        #expect(f.service.error != nil)
    }

    @Test func sleepWakeUsesOriginalDeadlineAndExpiresBeforeAcquisition() throws {
        for duration in [KeepAwakeDuration.thirtyMinutes, .untilStopped] {
            let f = KeepAwakeFixture()
            defer { f.cleanup() }
            try f.config.store.updateKeepAwake(.init(duration: duration, mode: .systemAndDisplay))
            f.service.start()
            let deadline = f.service.deadline
            f.service.willSleep()
            #expect(f.service.isActive && f.service.isSuspended)
            #expect(f.client.live.isEmpty)
            #expect(f.scheduler.liveCount == 0)
            f.time += 100
            f.service.didWake()
            #expect(f.service.isActive && !f.service.isSuspended)
            #expect(f.service.deadline == deadline)
            #expect(f.client.live.count == 2)
            f.service.willSleep()
            f.time = 1900
            let creates = f.client.creates.count
            f.service.didWake()
            if duration == .thirtyMinutes {
                #expect(!f.service.isActive)
                #expect(f.client.creates.count == creates)
            } else { #expect(f.service.isActive) }
        }
    }

    @Test func failedWakeEndsSessionAndRetryStartsRememberedConfiguration() {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        f.service.start()
        f.service.willSleep()
        f.time += 100
        f.client.failCreateAt = 2
        f.service.didWake()
        #expect(!f.service.isActive)
        #expect(f.service.error != nil)
        #expect(f.client.live.isEmpty)
        #expect(f.scheduler.liveCount == 0)
        f.client.failCreateAt = nil
        f.service.retry()
        #expect(f.service.deadline == f.time + 1800)
        #expect(f.service.error == nil)
    }

    @Test func failedActivationAndSecondAssertionDoNotPublishActive() throws {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        try f.config.store.updateKeepAwake(.init(mode: .systemAndDisplay))
        f.client.failCreateAt = 2
        f.service.start()
        #expect(!f.service.isActive)
        #expect(f.service.error != nil)
        #expect(f.client.live.isEmpty)
        #expect(f.scheduler.liveCount == 0)
        f.service.retry()
        #expect(f.service.isActive)
        #expect(f.service.error == nil)
    }

    @Test func inactiveSelectionsAndExternalEditsDoNotMutateSession() throws {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        f.service.selectDuration(.oneHour)
        f.service.changeMode(.systemAndDisplay)
        #expect(f.client.creates.isEmpty)
        #expect(f.config.store.config.keepAwake == .init(duration: .oneHour, mode: .systemAndDisplay))
        f.service.start()
        let deadline = f.service.deadline
        try Data(#"{"keepAwake":{"duration":"15m","mode":"system"}}"#.utf8).write(to: f.config.store.location, options: .atomic)
        f.config.store.reload()
        #expect(f.service.mode == .systemAndDisplay)
        #expect(f.service.deadline == deadline)
        f.service.selectDuration(.eightHours)
        #expect(f.config.store.config.keepAwake.duration == .fifteenMinutes)
        f.service.stop()
        f.service.start()
        #expect(f.service.mode == .system)
        #expect(f.service.deadline == f.time + 900)
    }

    @Test func expiredModeCommandDoesNotChangeDefaultsAndSuspendedToggleStops() {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        f.service.start()
        f.time = 1900
        f.service.changeMode(.systemAndDisplay)
        #expect(!f.service.isActive)
        #expect(f.config.store.config.keepAwake.mode == .system)
        f.service.start()
        f.service.willSleep()
        f.service.toggle()
        #expect(!f.service.isActive)
        #expect(f.client.live.isEmpty)
    }
}
