import CoreGraphics

typealias DisplayID = UInt32

/// Normalized inputs only. Live screen/managed-Space mapping is gated on native feasibility.
struct DisplayTopology {
    enum SpaceKind: Equatable {
        case normal, fullscreen, unknown
    }

    struct ActiveSpace: Equatable {
        let id: SpaceID
        let kind: SpaceKind
    }

    struct Display: Equatable {
        let id: DisplayID
        /// Global top-left coordinates in logical points, matching AX and BSPTree.
        let frame: CGRect
        let usableFrame: CGRect
        let activeSpace: ActiveSpace?

        var isEligible: Bool {
            activeSpace?.kind == .normal && activeSpace?.id != 0
        }

        func tilingBounds(padding: CGFloat) -> CGRect {
            let requested = padding.isFinite ? max(0, padding) : 0
            // Leave positive bounds even on a tiny display.
            let dx = min(requested, max(0, (usableFrame.width - 1) / 2))
            let dy = min(requested, max(0, (usableFrame.height - 1) / 2))
            return usableFrame.insetBy(dx: dx, dy: dy)
        }
    }

    enum Step {
        case previous, next
    }

    let displays: [Display]

    init(displays: [Display]) {
        // Inputs represent logical screens. Exact duplicate frames (mirrors) get one owner.
        var ids: Set<DisplayID> = []
        var frames: [CGRect] = []
        self.displays = displays.sorted { $0.id < $1.id }.filter { display in
            guard Self.isValid(display.frame), Self.isValid(display.usableFrame),
                  display.frame.contains(display.usableFrame),
                  !ids.contains(display.id), !frames.contains(display.frame) else { return false }
            ids.insert(display.id)
            frames.append(display.frame)
            return true
        }
    }

    /// Flip every screen with the same primary reference. Backing scale never enters this conversion.
    static func axFrame(fromAppKit frame: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: primaryFrame.maxY - frame.maxY,
               width: frame.width, height: frame.height)
    }

    var eligibleDisplays: [Display] {
        displays.filter(\.isEligible).sorted {
            if $0.frame.midX != $1.frame.midX { return $0.frame.midX < $1.frame.midX }
            if $0.frame.midY != $1.frame.midY { return $0.frame.midY < $1.frame.midY }
            return $0.id < $1.id
        }
    }

    func destination(from source: DisplayID, step: Step) -> Display? {
        let eligible = eligibleDisplays
        guard eligible.count > 1, let index = eligible.firstIndex(where: { $0.id == source }) else { return nil }
        let offset = step == .next ? 1 : -1
        return eligible[(index + offset + eligible.count) % eligible.count]
    }

    /// Ownership includes fullscreen/unknown displays: never force their windows onto a normal screen.
    func owner(of frame: CGRect) -> Display? {
        guard Self.isValid(frame) else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let containing = displays.first(where: { $0.frame.contains(center) }) { return containing }
        return displays.min { lhs, rhs in
            let lArea = Self.intersectionArea(frame, lhs.frame)
            let rArea = Self.intersectionArea(frame, rhs.frame)
            if lArea != rArea { return lArea > rArea }
            let lDistance = Self.distanceSquared(center, to: lhs.frame)
            let rDistance = Self.distanceSquared(center, to: rhs.frame)
            return lDistance != rDistance ? lDistance < rDistance : lhs.id < rhs.id
        }
    }

    /// Called only after local BSP navigation has no neighbor. Frames contain tiled windows only.
    func crossDisplayNeighbor(of window: WindowID, direction: Direction,
                              frames: [WindowID: CGRect], owners: [WindowID: DisplayID]) -> WindowID? {
        guard let origin = frames[window], let source = owners[window],
              eligibleDisplays.contains(where: { $0.id == source }) else { return nil }
        let eligible = Set(eligibleDisplays.map(\.id))
        let candidates = frames.filter { id, frame in
            guard id != window, let owner = owners[id], owner != source, eligible.contains(owner) else { return false }
            switch direction {
            case .left: return frame.midX < origin.midX
            case .right: return frame.midX > origin.midX
            case .up: return frame.midY < origin.midY
            case .down: return frame.midY > origin.midY
            }
        }
        func score(_ frame: CGRect) -> (CGFloat, CGFloat) {
            switch direction {
            case .left: return (max(0, origin.minX - frame.maxX), abs(origin.midY - frame.midY))
            case .right: return (max(0, frame.minX - origin.maxX), abs(origin.midY - frame.midY))
            case .up: return (max(0, origin.minY - frame.maxY), abs(origin.midX - frame.midX))
            case .down: return (max(0, frame.minY - origin.maxY), abs(origin.midX - frame.midX))
            }
        }
        return candidates.min {
            let lhs = score($0.value), rhs = score($1.value)
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return $0.key < $1.key
        }?.key
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy(\.isFinite)
            && frame.width > 0 && frame.height > 0
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func distanceSquared(_ point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }
}
