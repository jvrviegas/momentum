import CoreGraphics

/// Pure animation state; the tiling manager supplies monotonic time and applies the resulting frames.
struct WindowAnimation {
    static let duration = 0.2

    private struct Velocity {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private struct Transition {
        let start: CGRect
        let target: CGRect
        let startedAt: Double
        let initialVelocity: Velocity
        var lastSampledAt: Double?

        var resizes: Bool {
            start.size != target.size || initialVelocity.width != 0 || initialVelocity.height != 0
        }

        func progress(at time: Double) -> Double {
            min(max((time - startedAt) / WindowAnimation.duration, 0), 1)
        }

        func frame(at time: Double) -> CGRect {
            let t = progress(at: time)
            // Allow for floating-point rounding at the deadline; always write the exact final frame.
            guard t < 1 - 1e-9 else { return target }
            // Cubic Hermite: inherited starting velocity and zero final velocity. A fresh
            // transition starts with 3 * displacement / duration, matching the original ease-out.
            let blend = t * t * (3 - 2 * t)
            let tangent = t * (1 - t) * (1 - t) * WindowAnimation.duration
            func interpolate(_ from: CGFloat, _ to: CGFloat, _ velocity: CGFloat) -> CGFloat {
                from + (to - from) * blend + velocity * tangent
            }
            return CGRect(x: interpolate(start.minX, target.minX, initialVelocity.x),
                          y: interpolate(start.minY, target.minY, initialVelocity.y),
                          width: max(1, interpolate(start.width, target.width, initialVelocity.width)),
                          height: max(1, interpolate(start.height, target.height, initialVelocity.height)))
        }

        func velocity(at time: Double, actual: CGRect) -> Velocity {
            let t = progress(at: time)
            let predicted = frame(at: time)
            let blendDerivative = 6 * t * (1 - t) / WindowAnimation.duration
            let tangentDerivative = 3 * t * t - 4 * t + 1
            func component(_ from: CGFloat, _ to: CGFloat, _ initial: CGFloat,
                           _ observed: CGFloat, _ expected: CGFloat) -> CGFloat {
                // Native minimum sizes and edge clamps can reject the model's frame. Don't
                // carry imaginary momentum on that axis; allow ordinary pixel rounding.
                guard abs(observed - expected) <= 2 else { return 0 }
                return (to - from) * blendDerivative + initial * tangentDerivative
            }
            return Velocity(x: component(start.minX, target.minX, initialVelocity.x, actual.minX, predicted.minX),
                            y: component(start.minY, target.minY, initialVelocity.y, actual.minY, predicted.minY),
                            width: component(start.width, target.width, initialVelocity.width, actual.width, predicted.width),
                            height: component(start.height, target.height, initialVelocity.height, actual.height, predicted.height))
        }
    }

    private var transitions: [WindowID: Transition] = [:]
    var isActive: Bool { !transitions.isEmpty }
    var resizingWindows: Set<WindowID> { Set(transitions.filter { $0.value.resizes }.keys) }
    func isAnimating(_ id: WindowID) -> Bool { transitions[id] != nil }

    mutating func retarget(to targets: [WindowID: CGRect], currentFrames: [WindowID: CGRect], at time: Double) {
        transitions = transitions.filter { targets[$0.key] != nil && currentFrames[$0.key] != nil }
        for (id, target) in targets {
            guard let current = currentFrames[id] else { continue }
            if current == target {
                transitions[id] = nil
            } else if transitions[id]?.target != target {
                let velocity: Velocity
                if let previous = transitions[id] {
                    velocity = previous.velocity(at: previous.lastSampledAt ?? time, actual: current)
                } else {
                    let scale = 3 / Self.duration
                    velocity = Velocity(x: (target.minX - current.minX) * scale,
                                        y: (target.minY - current.minY) * scale,
                                        width: (target.width - current.width) * scale,
                                        height: (target.height - current.height) * scale)
                }
                transitions[id] = Transition(start: current, target: target, startedAt: time, initialVelocity: velocity)
            }
        }
    }

    mutating func frames(at time: Double) -> [WindowID: CGRect] {
        var frames: [WindowID: CGRect] = [:]
        for (id, transition) in transitions {
            let frame = transition.frame(at: time)
            frames[id] = frame
            if transition.progress(at: time) >= 1 - 1e-9 {
                transitions[id] = nil
            } else {
                transitions[id]?.lastSampledAt = time
            }
        }
        return frames
    }

    mutating func cancel() {
        transitions.removeAll()
    }
}
