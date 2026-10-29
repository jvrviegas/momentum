import AppKit
import Foundation
import Testing
@testable import Momentum

@MainActor
final class FakeFlowNotifier: FlowNotifier {
    var currentStatus: FlowNotificationStatus = .notDetermined
    var grant: FlowNotificationStatus = .allowed
    var requests = 0
    var posted: [FlowEvent] = []

    func status() async -> FlowNotificationStatus { currentStatus }

    func requestAuthorization() async -> FlowNotificationStatus {
        requests += 1
        currentStatus = grant
        return currentStatus
    }

    func post(_ event: FlowEvent) { posted.append(event) }
}

@MainActor
final class FlowFixture {
    let awake = KeepAwakeFixture()
    let scheduler = FakeKeepAwakeScheduler()
    let notifier = FakeFlowNotifier()
    var store: ConfigStore { awake.config.store }
    var keepAwake: KeepAwakeService { awake.service }
    lazy var flow = FlowService(store: store, keepAwake: keepAwake, notifier: notifier,
        now: { [unowned self] in self.awake.time }, scheduler: scheduler)

    var time: Double {
        get { awake.time }
        set { awake.time = newValue }
    }

    func setFlow(_ change: (inout FlowPreferences) -> Void) throws {
        var preferences = store.config.flow
        change(&preferences)
        try store.updateFlow(preferences)
    }

    func cleanup() {
        flow.shutdown()
        awake.cleanup()
    }
}

@MainActor
struct FlowServiceTests {
    @Test func startPauseResumeAndEndWithoutBreakOrNotification() {
        let f = FlowFixture()
        defer { f.cleanup() }
        #expect(!f.flow.isActive)
        f.flow.start()
        #expect(f.flow.phase == .session)
        #expect(f.flow.deadline == 1600)
        #expect(f.flow.remainingMinutes == 25)
        f.time += 100
        f.flow.pause()
        #expect(f.flow.isPaused && f.flow.deadline == nil)
        #expect(f.flow.pausedRemaining == 1400)
        #expect(f.scheduler.liveCount == 0)
        f.time += 5000
        f.flow.didWake()
        #expect(f.flow.isPaused && f.flow.pausedRemaining == 1400)
        f.flow.resume()
        #expect(f.flow.deadline == f.time + 1400)
        #expect(f.scheduler.liveCount == 1)
        f.flow.endSession()
        #expect(!f.flow.isActive)
        #expect(f.notifier.posted.isEmpty)
        #expect(f.scheduler.liveCount == 0)
    }

    @Test func completedSessionStartsBreakAndBothEndsNotify() {
        let f = FlowFixture()
        defer { f.cleanup() }
        f.flow.start()
        f.time = 1599.9
        f.scheduler.fireLatest()
        #expect(f.flow.phase == .session && f.flow.remainingMinutes == 1)
        f.time = 1600
        f.scheduler.fireLatest()
        #expect(f.flow.phase == .break)
        #expect(f.flow.deadline == 1900)
        #expect(f.notifier.posted == [.sessionComplete(breakMinutes: 5)])
        f.time = 1900
        f.scheduler.fireLatest()
        #expect(!f.flow.isActive)
        #expect(f.notifier.posted == [.sessionComplete(breakMinutes: 5), .breakOver])
        #expect(FlowEvent.sessionComplete(breakMinutes: 5).body == "Time for a 5-minute break.")
        #expect(FlowEvent.breakOver.title == "Break's over")
    }

    @Test func breaksOffEndsAtZeroAndSkipBreakIsSilent() throws {
        let f = FlowFixture()
        defer { f.cleanup() }
        try f.setFlow { $0.breaksEnabled = false; $0.duration = .fifteenMinutes }
        f.flow.start()
        f.time += 900
        f.scheduler.fireLatest()
        #expect(!f.flow.isActive)
        #expect(f.notifier.posted == [.sessionComplete(breakMinutes: nil)])
        #expect(FlowEvent.sessionComplete(breakMinutes: nil).body == "Start another session when you're ready.")
        try f.setFlow { $0.breaksEnabled = true; $0.breakDuration = .tenMinutes }
        f.flow.start()
        f.time += 900
        f.scheduler.fireLatest()
        #expect(f.flow.phase == .break && f.flow.deadline == f.time + 600)
        f.flow.skipBreak()
        #expect(!f.flow.isActive)
        #expect(f.notifier.posted.count == 2)
    }

    @Test func shortcutsStartPauseResumeEndAndSkipIntoNextSession() {
        let f = FlowFixture()
        defer { f.cleanup() }
        f.flow.toggle()
        #expect(f.flow.phase == .session && !f.flow.isPaused)
        f.flow.toggle()
        #expect(f.flow.isPaused)
        f.flow.toggle()
        #expect(!f.flow.isPaused)
        f.flow.end()
        #expect(!f.flow.isActive)
        f.flow.start()
        f.time += 1500
        f.scheduler.fireLatest()
        #expect(f.flow.phase == .break)
        f.time += 60
        f.flow.toggle()
        #expect(f.flow.phase == .session && f.flow.deadline == f.time + 1500)
        f.time += 1500
        f.scheduler.fireLatest()
        f.flow.end()
        #expect(!f.flow.isActive)
        #expect(f.notifier.posted.count == 2)
    }

    @Test func keepAwakeIsStartedHeldThroughPauseAndReleasedOnlyWhenFlowOwnsIt() throws {
        let f = FlowFixture()
        defer { f.cleanup() }
        try f.setFlow { $0.keepAwake = true }
        f.flow.start()
        #expect(f.keepAwake.isActive && f.keepAwake.deadline == nil)
        #expect(f.store.config.keepAwake.duration == .thirtyMinutes)
        #expect(f.flow.holdsKeepAwake)
        f.flow.pause()
        #expect(f.keepAwake.isActive)
        f.flow.resume()
        f.time += 1500
        f.scheduler.fireLatest()
        #expect(f.flow.phase == .break && !f.keepAwake.isActive)

        // Already on: Flow leaves it exactly as it was.
        f.flow.skipBreak()
        f.keepAwake.start()
        let deadline = f.keepAwake.deadline
        f.flow.start()
        #expect(!f.flow.holdsKeepAwake)
        f.flow.endSession()
        #expect(f.keepAwake.isActive && f.keepAwake.deadline == deadline)
        f.keepAwake.stop()

        // Changed by hand during the session: Flow lets go.
        f.flow.start()
        f.keepAwake.changeMode(.systemAndDisplay)
        #expect(!f.flow.holdsKeepAwake)
        f.flow.endSession()
        #expect(f.keepAwake.isActive)
        f.keepAwake.stop()

        // Stopped and restarted by hand: the new session is not Flow's.
        f.flow.start()
        f.keepAwake.stop()
        f.keepAwake.start()
        f.flow.endSession()
        #expect(f.keepAwake.isActive)
        f.keepAwake.stop()

        // Quit releases what Flow started.
        f.flow.start()
        #expect(f.flow.holdsKeepAwake)
        f.flow.shutdown()
        #expect(!f.keepAwake.isActive)
        #expect(f.awake.client.live.isEmpty)
    }

    @Test func wakeCatchesUpAndAnnouncesOnlyTheLatestEvent() throws {
        let f = FlowFixture()
        defer { f.cleanup() }
        try f.setFlow { $0.keepAwake = true }
        f.flow.start()
        f.keepAwake.willSleep()
        f.time += 1500 + 300 + 10
        f.flow.didWake()
        f.keepAwake.didWake()
        #expect(!f.flow.isActive)
        #expect(f.notifier.posted == [.breakOver])
        #expect(!f.keepAwake.isActive)
        #expect(f.awake.client.live.isEmpty)
        f.flow.start()
        f.time += 1500 + 30
        f.flow.didWake()
        #expect(f.flow.phase == .break && f.flow.deadline == f.time - 30 + 300)
        #expect(f.notifier.posted.last == .sessionComplete(breakMinutes: 5))
        #expect(f.scheduler.liveCount == 1)
    }

    @Test func notificationPermissionIsRequestedOnceOnFirstStart() async {
        let f = FlowFixture()
        defer { f.cleanup() }
        await f.flow.refreshNotificationStatus()
        #expect(f.flow.notificationStatus == .notDetermined && f.notifier.requests == 0)
        f.flow.start()
        await f.flow.notificationTask?.value
        #expect(f.notifier.requests == 1)
        #expect(f.flow.notificationStatus == .allowed)
        f.flow.endSession()
        f.flow.start()
        await f.flow.notificationTask?.value
        #expect(f.notifier.requests == 1)
    }

    @Test func runtimeStateIsNeverSavedAndDurationSavesWhileInactive() throws {
        let f = FlowFixture()
        defer { f.cleanup() }
        f.flow.selectDuration(.fiftyMinutes)
        #expect(f.store.config.flow.duration == .fiftyMinutes)
        f.flow.start()
        #expect(f.flow.deadline == f.time + 3000)
        let json = String(decoding: try JSONEncoder().encode(f.store.config), as: UTF8.self)
        for runtimeKey in ["deadline", "phase", "pausedRemaining", "revision"] { #expect(!json.contains(runtimeKey)) }
        let next = FlowService(store: f.store, keepAwake: f.keepAwake, notifier: SilentFlowNotifier())
        #expect(!next.isActive)
    }

    @Test func preferencesDecodeStrictlyAndActionsAppendLast() throws {
        for json in ["{}", #"{"flow":{}}"#] {
            let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
            #expect(config.flow == FlowPreferences())
            #expect(config.bindings[.toggleFlow] == nil && config.bindings[.endFlow] == nil)
        }
        for duration in FlowDuration.allCases {
            for breakDuration in FlowBreakDuration.allCases {
                var config = Config()
                config.flow = .init(duration: duration, breakDuration: breakDuration, breaksEnabled: false, keepAwake: true)
                #expect(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config)) == config)
            }
        }
        for value in ["null", #"{"duration":null}"#, #"{"duration":"20m"}"#, #"{"breakDuration":"1h"}"#,
                      #"{"breaksEnabled":"yes"}"#, #"{"keepAwake":null}"#] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(Config.self, from: Data("{\"flow\":\(value)}".utf8))
            }
        }
        #expect(FlowDuration.allCases.map(\.minutes) == [15, 25, 30, 45, 50, 60, 90])
        #expect(FlowBreakDuration.allCases.map(\.minutes) == [5, 10, 15, 20])
        #expect(Array(Action.allCases.suffix(2)) == [.toggleFlow, .endFlow])
        #expect(Action(rawValue: "toggle-flow") == .toggleFlow && Action(rawValue: "end-flow") == .endFlow)
        #expect(Action.toggleFlow.title == "Start or pause Flow" && Action.endFlow.title == "End Flow")
    }

    @Test func presentationWordsAndClock() {
        let f = FlowFixture()
        defer { f.cleanup() }
        #expect(FlowPresentation.clock(1500) == "25:00")
        #expect(FlowPresentation.clock(1452.2) == "24:13")
        #expect(FlowPresentation.clock(59.1) == "1:00")
        #expect(FlowPresentation.clock(0) == "0:00")
        #expect(FlowPresentation.clock(3600) == "1:00:00")
        #expect(FlowPresentation.clock(5399) == "1:29:59")
        let preferences = f.store.config.flow
        let inactive = FlowPresentation(f.flow, preferences: preferences)
        #expect(inactive.menuSymbol == nil && inactive.countdown == nil && inactive.spokenStatus == nil)
        #expect(inactive.breakHint == "Then a 5-minute break.")
        #expect(FlowPresentation(f.flow, preferences: .init(breaksEnabled: false)).breakHint == nil)
        f.flow.start()
        let running = FlowPresentation(f.flow, preferences: preferences)
        #expect(running.menuSymbol == "timer" && running.countdown == "25m")
        #expect(running.spokenStatus == "Flow session, 25 minutes left")
        #expect(running.caption(endingAt: .now).hasPrefix("Flow session · ends at "))
        f.time += 1440
        f.flow.pause()
        let paused = FlowPresentation(f.flow, preferences: preferences)
        #expect(paused.menuSymbol == "pause.fill" && paused.countdown == "1m")
        #expect(paused.minutesLeft == "1 minute left")
        #expect(paused.caption(endingAt: .now) == "Paused")
        f.flow.resume()
        f.time += 60
        f.scheduler.fireLatest()
        let resting = FlowPresentation(f.flow, preferences: preferences)
        #expect(resting.menuSymbol == "figure.walk" && resting.title == "Break")
        #expect(resting.caption(endingAt: .now).hasPrefix("Break · ends at "))
    }

    @Test func controllerRoutesShortcutsAndWakesFlowBeforeKeepAwake() throws {
        let f = FlowFixture()
        defer { f.cleanup() }
        try f.setFlow { $0.keepAwake = true }
        let hotKeys = FakeHotKeys()
        var tilingActions: [Action] = []
        let controller = AppController(store: f.store, keepAwake: f.keepAwake, flow: f.flow, hotKeys: hotKeys,
            performTiling: { tilingActions.append($0) }, refreshTiling: {})
        controller.start()
        hotKeys.onAction?(.toggleFlow)
        #expect(f.flow.phase == .session && f.keepAwake.isActive)
        hotKeys.onAction?(.toggleFlow)
        #expect(f.flow.isPaused)
        hotKeys.onAction?(.endFlow)
        #expect(!f.flow.isActive && !f.keepAwake.isActive)
        #expect(tilingActions.isEmpty)

        // A session that ended during sleep must not have its Keep Awake resumed on wake.
        controller.perform(.toggleFlow)
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        f.time += 1500
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(f.flow.phase == .break)
        #expect(!f.keepAwake.isActive && f.awake.client.live.isEmpty)
        controller.shutdown()
        #expect(!f.flow.isActive)
    }
}
