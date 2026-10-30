import AppKit

/// Runs each app's Accessibility calls on that app's own serial queue. Every call waits for the other app
/// to answer, so off the main thread a busy app delays only its own windows, never Momentum or other apps.
final class AXQueues {
    private struct FrameRequest {
        let window: AXWindow
        let frame: CGRect
        let previous: CGRect?
        let forceResize: Bool
        let repairClamping: Bool
    }

    private var queues: [pid_t: DispatchQueue] = [:]
    /// Windows with a write running, and their app.
    private var writing: [WindowID: pid_t] = [:]
    /// The newest frame submitted while the window's previous write was still running.
    private var pending: [WindowID: FrameRequest] = [:]
    /// What the app did with the last write of the current burst: the accepted frame, or nil after a refusal.
    /// Cleared when the burst ends, because the user or the app can change the frame before the next one.
    private var accepted: [WindowID: CGRect?] = [:]
    /// Apps whose enhanced Accessibility mode is off while their windows' writes run; see `setEnhancedUI`.
    private var enhancedUIOff: Set<pid_t> = []
    /// Callers of `settledFrame` waiting for a window's writes to finish.
    private var settling: [WindowID: [CheckedContinuation<Void, Never>]] = [:]

    /// Writes run in order per app. A frame submitted while an earlier one is still being written replaces
    /// any frame already waiting, so a slow app skips animation frames instead of falling behind.
    func writeFrame(_ window: AXWindow, _ frame: CGRect, from previous: CGRect?,
                    forceResize: Bool, repairClamping: Bool) {
        let request = FrameRequest(window: window, frame: frame, previous: previous,
                                   forceResize: forceResize, repairClamping: repairClamping)
        if writing[window.id] != nil { pending[window.id] = request } else { start(request) }
    }

    /// The window's frame once the writes submitted so far have finished; nil if the app didn't answer.
    func settledFrame(of window: AXWindow) async -> CGRect? {
        if writing[window.id] != nil {
            await withCheckedContinuation { settling[window.id, default: []].append($0) }
        }
        return await run(window.pid) { window.frame }
    }

    func focus(_ window: AXWindow) {
        Task {
            await run(window.pid) { window.raise() }
            NSRunningApplication(processIdentifier: window.pid)?.activate()
        }
    }

    func forget(_ pid: pid_t) {
        queues[pid] = nil
        enhancedUIOff.remove(pid)
    }

    private func start(_ request: FrameRequest) {
        let id = request.window.id, pid = request.window.pid
        writing[id] = pid
        // Within a burst, what the app accepted is more accurate than the caller's guess.
        let previous = accepted[id] ?? request.previous
        let startsBurst = accepted.index(forKey: id) == nil && !enhancedUIOff.contains(pid)
        Task {
            let (succeeded, turnedOff) = await run(pid) {
                let turnedOff = startsBurst && Self.setEnhancedUI(of: pid, from: true, to: false)
                return (request.window.setFrame(request.frame, from: previous, forceResize: request.forceResize,
                                                repairClamping: request.repairClamping), turnedOff)
            }
            if turnedOff { enhancedUIOff.insert(pid) }
            writing[id] = nil
            if let next = pending.removeValue(forKey: id) {
                accepted[id] = .some(succeeded ? request.frame : nil)
                start(next)
            } else {
                accepted[id] = nil
                for waiter in settling.removeValue(forKey: id) ?? [] { waiter.resume() }
                if !writing.values.contains(pid), enhancedUIOff.remove(pid) != nil {
                    Task { _ = await run(pid) { Self.setEnhancedUI(of: pid, from: false, to: true) } }
                }
            }
        }
    }

    /// Assistive apps can turn on an app's enhanced Accessibility mode. Chrome and other Chromium apps then
    /// animate every frame write themselves, about 250 ms behind, so the mode is off while Momentum writes.
    /// Returns whether the mode was `from` and is now `to`.
    private nonisolated static func setEnhancedUI(of pid: pid_t, from: Bool, to: Bool) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        let attribute = "AXEnhancedUserInterface"
        guard app.value(of: attribute) as Bool? == from else { return false }
        // Chrome applies the change but reports it as not implemented, so check what it reads now.
        AXUIElementSetAttributeValue(app, attribute as CFString, to ? kCFBooleanTrue : kCFBooleanFalse)
        return app.value(of: attribute) as Bool? == to
    }

    func run<T: Sendable>(_ pid: pid_t, _ work: @escaping @Sendable () -> T) async -> T {
        let queue = queues[pid] ?? DispatchQueue(label: "com.joaoviegas.Momentum.ax.\(pid)")
        queues[pid] = queue
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
