import Testing
@testable import Momentum

@MainActor
struct KeepAwakePresentationTests {
    @Test func countdownRoundsUpAtExactBoundaries() {
        #expect(KeepAwakeService.minutesRemaining(deadline: 60.1, now: 0) == 2)
        #expect(KeepAwakeService.minutesRemaining(deadline: 60, now: 0) == 1)
        #expect(KeepAwakeService.minutesRemaining(deadline: 0.1, now: 0) == 1)
        #expect(KeepAwakeService.minutesRemaining(deadline: 0, now: 0) == 0)
        #expect(KeepAwakeService.minutesRemaining(deadline: 0, now: 1) == 0)
    }

    @Test func inactiveTimedAndIndefinitePresentationMatchesSession() throws {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        let inactive = KeepAwakePresentation(f.service)
        #expect(inactive.iconName == "MenuBarIcon")
        #expect(inactive.countdown == nil)
        #expect(inactive.showsDuration && !inactive.showsExtensions)
        #expect(inactive.status == "Inactive")
        f.service.start()
        let timed = KeepAwakePresentation(f.service)
        #expect(timed.iconName == "MenuBarAwakeIcon")
        #expect(timed.countdown == "30m")
        #expect(!timed.showsDuration && timed.showsExtensions)
        #expect(timed.status.contains("30 min remaining"))
        f.time = 1900
        f.scheduler.fireLatest()
        #expect(KeepAwakePresentation(f.service).iconName == "MenuBarIcon")
        try f.config.store.updateKeepAwake(.init(duration: .untilStopped))
        f.service.start()
        let indefinite = KeepAwakePresentation(f.service)
        #expect(indefinite.iconName == "MenuBarAwakeIcon")
        #expect(indefinite.countdown == nil)
        #expect(!indefinite.showsDuration && !indefinite.showsExtensions)
        #expect(indefinite.status.contains("Until stopped"))
    }

    @Test func retryReflectsFailedStartOrActiveModeChange() {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        f.client.failCreateAt = 1
        f.service.start()
        #expect(KeepAwakePresentation(f.service).iconName == "MenuBarIcon")
        #expect(KeepAwakePresentation(f.service).retryTitle == "Retry Start")
        f.service.retry()
        f.client.failCreateAt = 3
        let deadline = f.service.deadline
        f.service.changeMode(.systemAndDisplay)
        #expect(KeepAwakePresentation(f.service).retryTitle == "Retry mode change")
        #expect(KeepAwakePresentation(f.service).mode == .system)
        f.service.retry()
        #expect(f.service.deadline == deadline)
        #expect(f.service.mode == .systemAndDisplay)
    }
}
