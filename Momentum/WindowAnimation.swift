import CoreGraphics

/// Pure animation state; the tiling manager supplies monotonic time and applies the resulting frames.
struct WindowAnimation {
    static let duration = 0.2

    private struct Transition {
        let start: CGRect
        let target: CGRect
        let startedAt: Double

        func frame(at time: Double) -> CGRect {
            let progress = min(max((time - startedAt) / WindowAnimation.duration, 0), 1)
            // Allow for floating-point rounding at the deadline; always write the exact final frame.
            guard progress < 1 - 1e-9 else { return target }
            let eased = 1 - pow(1 - progress, 3)
            func interpolate(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
                from + (to - from) * eased
            }
            return CGRect(x: interpolate(start.minX, target.minX),
                          y: interpolate(start.minY, target.minY),
                          width: interpolate(start.width, target.width),
                          height: interpolate(start.height, target.height))
        }
    }

    private var transitions: [WindowID: Transition] = [:]
    var isActive: Bool { !transitions.isEmpty }

    mutating func retarget(to targets: [WindowID: CGRect], currentFrames: [WindowID: CGRect], at time: Double) {
        transitions = transitions.filter { targets[$0.key] != nil && currentFrames[$0.key] != nil }
        for (id, target) in targets {
            guard let current = currentFrames[id] else { continue }
            if current == target {
                transitions[id] = nil
            } else if transitions[id]?.target != target {
                // A new command replaces the old destination, starting from the window's actual position.
                transitions[id] = Transition(start: current, target: target, startedAt: time)
            }
        }
    }

    mutating func frames(at time: Double) -> [WindowID: CGRect] {
        var frames: [WindowID: CGRect] = [:]
        for (id, transition) in transitions {
            let frame = transition.frame(at: time)
            frames[id] = frame
            if frame == transition.target { transitions[id] = nil }
        }
        return frames
    }

    mutating func cancel() {
        transitions.removeAll()
    }
}
