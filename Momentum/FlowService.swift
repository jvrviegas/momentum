import Foundation
import Observation
import UserNotifications

enum FlowPhase: Equatable {
    case session
    case `break`
}

enum FlowNotificationStatus: Equatable {
    case notDetermined, allowed, denied
}

/// What Flow tells people when a countdown ends (FL-05, FL-07).
enum FlowEvent: Equatable {
    /// `breakMinutes` is nil when breaks are off.
    case sessionComplete(breakMinutes: Int?)
    case breakOver

    var title: String {
        switch self {
        case .sessionComplete: "Flow session complete"
        case .breakOver: "Break's over"
        }
    }

    var body: String {
        switch self {
        case .sessionComplete(let minutes?): "Time for a \(minutes)-minute break."
        case .sessionComplete(nil): "Start another session when you're ready."
        case .breakOver: "Start your next Flow session when you're ready."
        }
    }
}

protocol FlowNotifier {
    func status() async -> FlowNotificationStatus
    func requestAuthorization() async -> FlowNotificationStatus
    func post(_ event: FlowEvent)
}

/// Delivers Flow's notifications through macOS, as banners even while the popover is open (FL-10).
final class SystemFlowNotifier: NSObject, FlowNotifier, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func status() async -> FlowNotificationStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed
        }
    }

    func requestAuthorization() async -> FlowNotificationStatus {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await status()
    }

    func post(_ event: FlowEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        // One identifier, so a newer Flow notification replaces the previous one. Failures stay silent (FL-22).
        let request = UNNotificationRequest(identifier: "flow", content: content, trigger: nil)
        Task { try? await center.add(request) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// For the unit-test host and previews: never asks macOS and never posts.
struct SilentFlowNotifier: FlowNotifier {
    var fixedStatus: FlowNotificationStatus = .notDetermined

    func status() async -> FlowNotificationStatus { fixedStatus }
    func requestAuthorization() async -> FlowNotificationStatus { fixedStatus }
    func post(_ event: FlowEvent) {}
}

/// Times Flow sessions and breaks. Preferences are durable; sessions, breaks, and deadlines never are (FL-19).
@Observable final class FlowService {
    private(set) var phase: FlowPhase?
    /// The sleep-inclusive end of the running session or break; nil while paused.
    private(set) var deadline: Double?
    private(set) var pausedRemaining: Double?
    private(set) var currentTime: Double = 0
    private(set) var notificationStatus: FlowNotificationStatus = .notDetermined
    /// The Keep Awake revision Flow started, while it may still stop it (FL-15, FL-16).
    private(set) var keepAwakeRevision: Int?

    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private let keepAwake: KeepAwakeService
    @ObservationIgnored private let notifier: any FlowNotifier
    @ObservationIgnored private let now: @MainActor () -> Double
    @ObservationIgnored private let scheduler: any KeepAwakeScheduler
    @ObservationIgnored private var cancelScheduled: (() -> Void)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored private(set) var notificationTask: Task<Void, Never>?

    init(store: ConfigStore, keepAwake: KeepAwakeService, notifier: any FlowNotifier,
         now: @escaping @MainActor () -> Double = KeepAwakeClock.now,
         scheduler: any KeepAwakeScheduler = TaskKeepAwakeScheduler()) {
        self.store = store
        self.keepAwake = keepAwake
        self.notifier = notifier
        self.now = now
        self.scheduler = scheduler
        currentTime = now()
    }

    var isActive: Bool { phase != nil }
    var isPaused: Bool { pausedRemaining != nil }

    var holdsKeepAwake: Bool {
        keepAwakeRevision != nil && keepAwake.isActive && keepAwake.revision == keepAwakeRevision
    }

    /// Whole minutes left, rounded up, as of the last minute boundary; for the menu-bar label.
    var remainingMinutes: Int? {
        if let pausedRemaining { return Int(ceil(pausedRemaining / 60)) }
        guard let deadline else { return nil }
        return KeepAwakeService.minutesRemaining(deadline: deadline, now: currentTime)
    }

    /// Seconds left right now. Reads the clock, so a view that redraws every second stays exact.
    func liveRemaining() -> Double? {
        if let pausedRemaining { return pausedRemaining }
        guard let deadline else { return nil }
        return max(0, deadline - now())
    }

    func start() {
        reevaluate()
        guard !isShutdown, !isActive else { return }
        let preferences = store.config.flow
        phase = .session
        deadline = currentTime + preferences.duration.seconds
        pausedRemaining = nil
        if preferences.keepAwake, !keepAwake.isActive {
            keepAwake.start(duration: .untilStopped)
            // A failed start shows Keep Awake's own error; the session runs anyway (FL-21).
            keepAwakeRevision = keepAwake.isActive ? keepAwake.revision : nil
        }
        scheduleNext()
        prepareNotifications()
    }

    func pause() {
        reevaluate()
        guard phase == .session, let deadline else { return }
        pausedRemaining = max(0, deadline - currentTime)
        self.deadline = nil
        cancelTimer()
    }

    func resume() {
        reevaluate()
        guard phase == .session, let pausedRemaining else { return }
        deadline = currentTime + pausedRemaining
        self.pausedRemaining = nil
        scheduleNext()
    }

    /// End Flow: stops a session early with no break and no notification (FL-04).
    func endSession() {
        reevaluate()
        guard phase == .session else { return }
        finish()
    }

    func skipBreak() {
        reevaluate()
        guard phase == .break else { return }
        finish()
    }

    /// The `end-flow` shortcut: ends a session or skips a break (FL-13).
    func end() {
        reevaluate()
        switch phase {
        case .session: endSession()
        case .break: skipBreak()
        case nil: break
        }
    }

    /// The `toggle-flow` shortcut: start, pause, or resume; during a break, start the next session (FL-13).
    func toggle() {
        reevaluate()
        switch phase {
        case nil: start()
        case .session: isPaused ? resume() : pause()
        case .break:
            finish()
            start()
        }
    }

    func selectDuration(_ duration: FlowDuration) {
        var preferences = store.config.flow
        preferences.duration = duration
        // ConfigStore reports a failed save in Settings and keeps the previous value.
        try? store.updateFlow(preferences)
    }

    func refreshNotificationStatus() async {
        notificationStatus = await notifier.status()
    }

    /// Catches up on what happened during sleep (FL-18). Call before Keep Awake's own wake handling,
    /// so a session that ended while asleep releases its Keep Awake instead of resuming it.
    func didWake() {
        reevaluate()
        scheduleNext()
    }

    func shutdown() {
        isShutdown = true
        finish()
        notificationTask?.cancel()
    }

    private func finish() {
        cancelTimer()
        releaseKeepAwake()
        phase = nil
        deadline = nil
        pausedRemaining = nil
    }

    private func releaseKeepAwake() {
        if holdsKeepAwake { keepAwake.stop() }
        keepAwakeRevision = nil
    }

    /// Asks once, the first time someone starts Flow, never at launch (FL-09).
    private func prepareNotifications() {
        notificationTask = Task { [weak self, notifier] in
            var status = await notifier.status()
            if status == .notDetermined { status = await notifier.requestAuthorization() }
            self?.notificationStatus = status
        }
    }

    /// Moves past every end the clock has reached. A long sleep can end both a session and its break;
    /// only the latest event is announced (FL-18).
    private func reevaluate() {
        currentTime = now()
        var latest: FlowEvent?
        while let end = deadline, currentTime >= end {
            switch phase {
            case .session:
                releaseKeepAwake()
                let preferences = store.config.flow
                if preferences.breaksEnabled {
                    phase = .break
                    deadline = end + preferences.breakDuration.seconds
                    latest = .sessionComplete(breakMinutes: preferences.breakDuration.minutes)
                } else {
                    phase = nil
                    deadline = nil
                    latest = .sessionComplete(breakMinutes: nil)
                }
            case .break:
                phase = nil
                deadline = nil
                latest = .breakOver
            case nil:
                deadline = nil
            }
        }
        if let latest, !isShutdown { notifier.post(latest) }
        if !isActive { cancelTimer() }
    }

    private func cancelTimer() {
        generation += 1
        cancelScheduled?()
        cancelScheduled = nil
    }

    /// Wakes at each whole-minute change for the menu-bar label, and at the end of the countdown.
    private func scheduleNext() {
        cancelTimer()
        guard !isShutdown, let deadline else { return }
        let remaining = max(0, deadline - currentTime)
        let nextBoundary = remaining - max(0, ceil(remaining / 60) - 1) * 60
        let token = generation
        cancelScheduled = scheduler.schedule(after: max(0.01, min(60, nextBoundary))) { [weak self] in
            guard let self, token == generation, !isShutdown else { return }
            reevaluate()
            scheduleNext()
        }
    }

    #if DEBUG
    /// Puts Flow into one state for snapshots: `-MomentumFlowPreview running|paused|break`.
    /// `ending` leaves 5 seconds, to check a real end-of-session notification by hand.
    func preview(_ state: String) {
        currentTime = now()
        switch state {
        case "running":
            phase = .session
            deadline = currentTime + 24 * 60 + 13
        case "ending":
            phase = .session
            deadline = currentTime + 5
        case "paused":
            phase = .session
            pausedRemaining = 18 * 60 + 2
        case "break":
            phase = .break
            deadline = currentTime + 4 * 60 + 12
        default: return
        }
        scheduleNext()
    }
    #endif
}
