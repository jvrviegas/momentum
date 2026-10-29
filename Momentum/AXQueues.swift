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
    private var writing: Set<WindowID> = []
    /// The newest frame submitted while the window's previous write was still running.
    private var pending: [WindowID: FrameRequest] = [:]
    /// What the app did with the last write of the current burst: the accepted frame, or nil after a refusal.
    /// Cleared when the burst ends, because the user or the app can change the frame before the next one.
    private var accepted: [WindowID: CGRect?] = [:]

    /// Writes run in order per app. A frame submitted while an earlier one is still being written replaces
    /// any frame already waiting, so a slow app skips animation frames instead of falling behind.
    func writeFrame(_ window: AXWindow, _ frame: CGRect, from previous: CGRect?,
                    forceResize: Bool, repairClamping: Bool) {
        let request = FrameRequest(window: window, frame: frame, previous: previous,
                                   forceResize: forceResize, repairClamping: repairClamping)
        if writing.contains(window.id) { pending[window.id] = request } else { start(request) }
    }

    func focus(_ window: AXWindow) {
        Task {
            await run(window.pid) { window.raise() }
            NSRunningApplication(processIdentifier: window.pid)?.activate()
        }
    }

    func forget(_ pid: pid_t) {
        queues[pid] = nil
    }

    private func start(_ request: FrameRequest) {
        let id = request.window.id
        writing.insert(id)
        // Within a burst, what the app accepted is more accurate than the caller's guess.
        let previous = accepted[id] ?? request.previous
        Task {
            let succeeded = await run(request.window.pid) {
                request.window.setFrame(request.frame, from: previous, forceResize: request.forceResize,
                                        repairClamping: request.repairClamping)
            }
            writing.remove(id)
            if let next = pending.removeValue(forKey: id) {
                accepted[id] = .some(succeeded ? request.frame : nil)
                start(next)
            } else {
                accepted[id] = nil
            }
        }
    }

    func run<T: Sendable>(_ pid: pid_t, _ work: @escaping @Sendable () -> T) async -> T {
        let queue = queues[pid] ?? DispatchQueue(label: "com.joaoviegas.Momentum.ax.\(pid)")
        queues[pid] = queue
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
