import Darwin
import Foundation
import Observation

struct KeepAwakeClock {
    static func now() -> Double {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}

protocol KeepAwakeScheduler {
    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> () -> Void
}

struct TaskKeepAwakeScheduler: KeepAwakeScheduler {
    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> () -> Void {
        let task = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }
}

/// Preferences are durable; this session and its sleep-inclusive deadline never are.
@Observable final class KeepAwakeService {
    private(set) var mode: KeepAwakeMode?
    private(set) var deadline: Double?
    private(set) var isSuspended = false
    private(set) var error: String?
    private(set) var retryMode: KeepAwakeMode?
    private(set) var currentTime: Double = 0

    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private let assertions: PowerAssertions
    @ObservationIgnored private let now: @MainActor () -> Double
    @ObservationIgnored private let scheduler: any KeepAwakeScheduler
    @ObservationIgnored private var cancelScheduled: (() -> Void)?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isShutdown = false
    @ObservationIgnored private var isSavingPreference = false

    init(store: ConfigStore, assertions: PowerAssertions = PowerAssertions(),
         now: @escaping @MainActor () -> Double = KeepAwakeClock.now,
         scheduler: any KeepAwakeScheduler = TaskKeepAwakeScheduler()) {
        self.store = store
        self.assertions = assertions
        self.now = now
        self.scheduler = scheduler
        currentTime = now()
    }

    var isActive: Bool { mode != nil }
    var remainingMinutes: Int? {
        guard isActive, let deadline else { return nil }
        return Self.minutesRemaining(deadline: deadline, now: currentTime)
    }

    static func minutesRemaining(deadline: Double, now: Double) -> Int {
        Int(ceil(max(0, deadline - now) / 60))
    }

    func start() {
        guard !isSavingPreference else { return }
        reevaluate()
        guard !isShutdown, !isActive else { return }
        do {
            let preferences = store.config.keepAwake
            let additions = try assertions.prepare(preferences.mode)
            assertions.commit(additions, mode: preferences.mode)
            currentTime = now()
            mode = preferences.mode
            deadline = preferences.duration.seconds.map { currentTime + $0 }
            isSuspended = false
            clearError()
            scheduleNext()
        } catch {
            self.error = error.localizedDescription
            retryMode = nil
        }
    }

    func toggle() {
        guard !isSavingPreference else { return }
        reevaluate()
        if isActive { stop() } else { start() }
    }

    func stop() {
        guard !isSavingPreference else { return }
        cancelTimer()
        assertions.releaseAll()
        mode = nil
        deadline = nil
        isSuspended = false
        retryMode = nil
        error = assertions.cleanupError
    }

    func extend(by seconds: Double) {
        guard !isSavingPreference else { return }
        reevaluate()
        guard !isShutdown, isActive, let deadline, [900.0, 1800.0, 3600.0].contains(seconds) else { return }
        self.deadline = deadline + seconds
        clearError()
        scheduleNext()
    }

    func selectDuration(_ duration: KeepAwakeDuration) {
        guard !isSavingPreference else { return }
        reevaluate()
        guard !isShutdown, !isActive else { return }
        isSavingPreference = true
        defer { isSavingPreference = false }
        var preferences = store.config.keepAwake
        preferences.duration = duration
        do {
            try store.updateKeepAwake(preferences)
            clearError()
        } catch { self.error = error.localizedDescription }
    }

    func changeMode(_ newMode: KeepAwakeMode) {
        guard !isSavingPreference else { return }
        let wasActive = isActive
        reevaluate()
        guard !isShutdown else { return }
        // An expired command must not revive or change the just-ended session.
        guard !wasActive || isActive else { return }
        if isActive, mode == newMode { return }
        isSavingPreference = true
        defer { isSavingPreference = false }
        var preferences = store.config.keepAwake
        preferences.mode = newMode
        do {
            let additions = isActive && !isSuspended ? try assertions.prepare(newMode) : [:]
            do { try store.updateKeepAwake(preferences) }
            catch {
                assertions.rollback(additions)
                throw PowerAssertionError(message: [error.localizedDescription, assertions.cleanupError].compactMap { $0 }.joined(separator: " "))
            }
            if isActive {
                if !isSuspended { assertions.commit(additions, mode: newMode) }
                mode = newMode
            }
            clearError()
        } catch {
            self.error = error.localizedDescription
            retryMode = isActive ? newMode : nil
        }
    }

    func retry() {
        guard !isSavingPreference else { return }
        let wasActive = isActive
        let attemptedMode = retryMode
        reevaluate()
        // An active-session Retry must never become Start when that session expires.
        guard !wasActive || isActive else { return }
        if let attemptedMode, isActive { changeMode(attemptedMode) }
        else if !isActive { start() }
        else {
            assertions.retryCleanup()
            error = assertions.cleanupError
        }
    }

    func willSleep() {
        guard !isSavingPreference else { return }
        reevaluate()
        guard isActive else { return }
        assertions.releaseAll()
        isSuspended = true
        if let cleanupError = assertions.cleanupError { error = cleanupError }
        cancelTimer()
    }

    func didWake() {
        guard !isSavingPreference else { return }
        reevaluate()
        guard !isShutdown, isActive, isSuspended, let mode else { return }
        do {
            assertions.commit(try assertions.prepare(mode), mode: mode)
            isSuspended = false
            clearError()
            scheduleNext()
        } catch {
            let message = error.localizedDescription
            stop()
            self.error = [message, assertions.cleanupError].compactMap { $0 }.joined(separator: " ")
        }
    }

    func shutdown() {
        guard !isSavingPreference else { return }
        isShutdown = true
        stop()
    }

    private func reevaluate() {
        currentTime = now()
        if isActive, let deadline, currentTime >= deadline { stop() }
    }

    private func clearError() {
        error = assertions.cleanupError
        retryMode = nil
    }

    private func cancelTimer() {
        generation += 1
        cancelScheduled?()
        cancelScheduled = nil
    }

    private func scheduleNext() {
        cancelTimer()
        guard isActive, !isSuspended, let deadline else { return }
        let remaining = max(0, deadline - currentTime)
        let nextBoundary = remaining - max(0, ceil(remaining / 60) - 1) * 60
        let token = generation
        cancelScheduled = scheduler.schedule(after: max(0.01, min(60, nextBoundary))) { [weak self] in
            guard let self, token == generation, !isShutdown else { return }
            reevaluate()
            scheduleNext()
        }
    }
}
