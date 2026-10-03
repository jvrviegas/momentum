import CoreGraphics

/// CGWindowID of a managed window.
typealias WindowID = UInt32

enum Direction: String, Codable, CaseIterable {
    case left, right, up, down
}

/// Binary space partitioning tree used for dwindle-style tiling.
/// All geometry uses top-left origin coordinates (y grows downward), matching the Accessibility API.
struct BSPTree: Equatable {
    enum Axis: Equatable {
        /// Children placed side by side.
        case horizontal
        /// Children stacked top and bottom.
        case vertical
    }

    indirect enum Node: Equatable {
        case leaf(WindowID)
        case split(Axis, Node, Node)
    }

    private(set) var root: Node?

    /// Windows in traversal order (left/top first).
    var windows: [WindowID] {
        guard let root else { return [] }
        return Self.leaves(of: root)
    }

    var isEmpty: Bool { root == nil }

    func contains(_ window: WindowID) -> Bool {
        windows.contains(window)
    }

    /// Inserts `window` by splitting the `focused` leaf (or the last leaf when `focused` isn't in the tree)
    /// along its longer side. The new window takes the right/bottom half.
    mutating func insert(_ window: WindowID, at focused: WindowID?, bounds: CGRect) {
        guard !contains(window) else { return }
        guard let root else {
            self.root = .leaf(window)
            return
        }
        guard let target = focused.flatMap({ contains($0) ? $0 : nil }) ?? windows.last else { return }
        let frame = layout(in: bounds, gap: 0)[target] ?? bounds
        let axis: Axis = frame.width >= frame.height ? .horizontal : .vertical
        self.root = Self.replacing(target, in: root, with: .split(axis, .leaf(target), .leaf(window)))
    }

    /// Removes `window`; its sibling takes over the parent's space.
    mutating func remove(_ window: WindowID) {
        guard let root else { return }
        self.root = Self.removing(window, from: root)
    }

    /// Exchanges the positions of two windows.
    mutating func swap(_ a: WindowID, _ b: WindowID) {
        guard let root, a != b, contains(a), contains(b) else { return }
        self.root = Self.mapLeaves(root) { $0 == a ? b : ($0 == b ? a : $0) }
    }

    /// Computes a frame for every window. `gap` is the spacing between sibling windows.
    func layout(in rect: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        if let root { Self.layout(root, in: rect, gap: gap, into: &result) }
        return result
    }

    /// The nearest window in `direction` from `window`, based on computed frames.
    func neighbor(of window: WindowID, direction: Direction, bounds: CGRect) -> WindowID? {
        let frames = layout(in: bounds, gap: 0)
        guard let origin = frames[window] else { return nil }
        let epsilon: CGFloat = 1

        let candidates = frames.filter { id, frame in
            guard id != window else { return false }
            switch direction {
            case .left:  return frame.maxX <= origin.minX + epsilon && overlaps(frame.minY...frame.maxY, origin.minY...origin.maxY)
            case .right: return frame.minX >= origin.maxX - epsilon && overlaps(frame.minY...frame.maxY, origin.minY...origin.maxY)
            case .up:    return frame.maxY <= origin.minY + epsilon && overlaps(frame.minX...frame.maxX, origin.minX...origin.maxX)
            case .down:  return frame.minY >= origin.maxY - epsilon && overlaps(frame.minX...frame.maxX, origin.minX...origin.maxX)
            }
        }

        // Prefer the closest edge, then the best-aligned center on the perpendicular axis.
        return candidates.min { lhs, rhs in
            let l = score(lhs.value, from: origin, direction: direction)
            let r = score(rhs.value, from: origin, direction: direction)
            return l.distance != r.distance ? l.distance < r.distance : l.alignment < r.alignment
        }?.key
    }

    // MARK: - Helpers

    private func overlaps(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> Bool {
        a.lowerBound < b.upperBound - 1 && b.lowerBound < a.upperBound - 1
    }

    private func score(_ frame: CGRect, from origin: CGRect, direction: Direction) -> (distance: CGFloat, alignment: CGFloat) {
        switch direction {
        case .left:  return (origin.minX - frame.maxX, abs(frame.midY - origin.midY))
        case .right: return (frame.minX - origin.maxX, abs(frame.midY - origin.midY))
        case .up:    return (origin.minY - frame.maxY, abs(frame.midX - origin.midX))
        case .down:  return (frame.minY - origin.maxY, abs(frame.midX - origin.midX))
        }
    }

    private static func leaves(of node: Node) -> [WindowID] {
        switch node {
        case .leaf(let id): return [id]
        case .split(_, let a, let b): return leaves(of: a) + leaves(of: b)
        }
    }

    private static func replacing(_ target: WindowID, in node: Node, with replacement: Node) -> Node {
        switch node {
        case .leaf(let id): return id == target ? replacement : node
        case .split(let axis, let a, let b):
            return .split(axis, replacing(target, in: a, with: replacement), replacing(target, in: b, with: replacement))
        }
    }

    private static func removing(_ target: WindowID, from node: Node) -> Node? {
        switch node {
        case .leaf(let id): return id == target ? nil : node
        case .split(let axis, let a, let b):
            let newA = removing(target, from: a)
            let newB = removing(target, from: b)
            switch (newA, newB) {
            case let (a?, b?): return .split(axis, a, b)
            case let (a?, nil): return a
            case let (nil, b?): return b
            case (nil, nil): return nil
            }
        }
    }

    private static func mapLeaves(_ node: Node, _ transform: (WindowID) -> WindowID) -> Node {
        switch node {
        case .leaf(let id): return .leaf(transform(id))
        case .split(let axis, let a, let b): return .split(axis, mapLeaves(a, transform), mapLeaves(b, transform))
        }
    }

    private static func layout(_ node: Node, in rect: CGRect, gap: CGFloat, into result: inout [WindowID: CGRect]) {
        switch node {
        case .leaf(let id):
            result[id] = rect.integral
        case .split(let axis, let a, let b):
            let first: CGRect
            let second: CGRect
            switch axis {
            case .horizontal:
                let width = (rect.width - gap) / 2
                first = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
                second = CGRect(x: rect.minX + width + gap, y: rect.minY, width: width, height: rect.height)
            case .vertical:
                let height = (rect.height - gap) / 2
                first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
                second = CGRect(x: rect.minX, y: rect.minY + height + gap, width: rect.width, height: height)
            }
            layout(a, in: first, gap: gap, into: &result)
            layout(b, in: second, gap: gap, into: &result)
        }
    }
}
