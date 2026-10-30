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

    /// What a window needs, in a layout that makes room for minimum sizes, before its own minimum is known.
    /// Without it, a side could be left 0 pt wide.
    static let smallestTile = CGSize(width: 100, height: 100)

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

    /// Matches the tree to `current`: removes windows that are gone, then inserts new ones in order by splitting `focused`.
    mutating func sync(with current: [WindowID], focused: WindowID?, bounds: CGRect) {
        let keep = Set(current)
        for id in windows where !keep.contains(id) {
            remove(id)
        }
        for id in current where !contains(id) {
            insert(id, at: focused, bounds: bounds)
        }
    }

    /// The window whose tile contains `point`, ignoring `excluded`.
    static func window(at point: CGPoint, excluding excluded: WindowID, in frames: [WindowID: CGRect]) -> WindowID? {
        frames.first { $0.key != excluded && $0.value.contains(point) }?.key
    }

    /// Computes a frame for every window. `gap` is the spacing between sibling windows.
    /// A split gives a side its windows' `minimums` when half isn't enough, and lays out the other way
    /// while its own direction doesn't fit. Splits whose windows fit stay equal.
    func layout(in rect: CGRect, gap: CGFloat, minimums: [WindowID: CGSize] = [:]) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        if let root { Self.layout(root, in: rect, gap: gap, minimums: minimums, into: &result) }
        return result
    }

    /// Whether every window fits in `rect` at its minimum size.
    func fits(in rect: CGRect, gap: CGFloat, minimums: [WindowID: CGSize]) -> Bool {
        guard let root, !minimums.isEmpty else { return true }
        return Self.minimumSizes(of: root, gap: gap, minimums: minimums)
            .contains { $0.width <= rect.width && $0.height <= rect.height }
    }

    /// The windows to set aside so the rest fit: windows are tiled in `order` (oldest first), and each one that
    /// doesn't fit with the windows before it is set aside. Windows missing from `order` come last.
    func windowsThatDontFit(in rect: CGRect, gap: CGFloat, minimums: [WindowID: CGSize],
                            order: [WindowID]) -> Set<WindowID> {
        guard !fits(in: rect, gap: gap, minimums: minimums) else { return [] }
        let all = windows
        let ordered = order.filter(all.contains) + all.filter { !order.contains($0) }
        var setAside: Set<WindowID> = []
        var tiled = BSPTree()
        for id in ordered {
            var trial = self
            for other in all where other != id && !tiled.contains(other) { trial.remove(other) }
            if trial.fits(in: rect, gap: gap, minimums: minimums) { tiled = trial } else { setAside.insert(id) }
        }
        return setAside
    }

    /// The nearest window in `direction` from `window`, based on computed frames.
    static func neighbor(of window: WindowID, direction: Direction, in frames: [WindowID: CGRect]) -> WindowID? {
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

    private static func overlaps(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> Bool {
        a.lowerBound < b.upperBound - 1 && b.lowerBound < a.upperBound - 1
    }

    private static func score(_ frame: CGRect, from origin: CGRect, direction: Direction) -> (distance: CGFloat, alignment: CGFloat) {
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

    private static func layout(_ node: Node, in rect: CGRect, gap: CGFloat, minimums: [WindowID: CGSize],
                               into result: inout [WindowID: CGRect]) {
        switch node {
        case .leaf(let id):
            result[id] = rect.integral
        case .split(let axis, let a, let b):
            let first: CGRect
            let second: CGRect
            let (axis, length) = split(rect, axis: axis, a, b, gap: gap, minimums: minimums)
            // The second child takes the remainder, so the gap stays exact.
            switch axis {
            case .horizontal:
                first = CGRect(x: rect.minX, y: rect.minY, width: length, height: rect.height)
                second = CGRect(x: rect.minX + length + gap, y: rect.minY, width: rect.width - length - gap, height: rect.height)
            case .vertical:
                first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: length)
                second = CGRect(x: rect.minX, y: rect.minY + length + gap, width: rect.width, height: rect.height - length - gap)
            }
            layout(a, in: first, gap: gap, minimums: minimums, into: &result)
            layout(b, in: second, gap: gap, minimums: minimums, into: &result)
        }
    }

    /// A split's direction and its first child's length: half on a whole point, unless a side needs more for
    /// its windows' minimum sizes. The other direction is used only while the split's own doesn't fit.
    private static func split(_ rect: CGRect, axis: Axis, _ a: Node, _ b: Node, gap: CGFloat,
                              minimums: [WindowID: CGSize]) -> (Axis, CGFloat) {
        func half(_ axis: Axis) -> CGFloat {
            (((axis == .horizontal ? rect.width : rect.height) - gap) / 2).rounded(.down)
        }
        guard !minimums.isEmpty else { return (axis, half(axis)) }
        let sizesA = minimumSizes(of: a, gap: gap, minimums: minimums)
        let sizesB = minimumSizes(of: b, gap: gap, minimums: minimums)
        for candidate in [axis, axis.flipped] {
            let length = candidate == .horizontal ? rect.width : rect.height
            let across = candidate == .horizontal ? rect.height : rect.width
            guard let needA = extent(of: sizesA, along: candidate, within: across),
                  let needB = extent(of: sizesB, along: candidate, within: across),
                  needA + gap + needB <= length else { continue }
            return (candidate, min(max(half(candidate), needA), length - gap - needB))
        }
        return (axis, half(axis))
    }

    /// The least length along `axis` that one of `sizes` needs while fitting in `across` the other way.
    private static func extent(of sizes: [CGSize], along axis: Axis, within across: CGFloat) -> CGFloat? {
        sizes.filter { (axis == .horizontal ? $0.height : $0.width) <= across }
            .map { axis == .horizontal ? $0.width : $0.height }
            .min()
    }

    /// The smallest sizes `node` can take with its splits in either direction: each one beats every other
    /// in width or in height.
    private static func minimumSizes(of node: Node, gap: CGFloat, minimums: [WindowID: CGSize]) -> [CGSize] {
        switch node {
        case .leaf(let id):
            let minimum = minimums[id] ?? .zero
            return [CGSize(width: max(minimum.width, smallestTile.width), height: max(minimum.height, smallestTile.height))]
        case .split(_, let a, let b):
            let sizesB = minimumSizes(of: b, gap: gap, minimums: minimums)
            var sizes: [CGSize] = []
            for x in minimumSizes(of: a, gap: gap, minimums: minimums) {
                for y in sizesB {
                    sizes.append(CGSize(width: x.width + gap + y.width, height: max(x.height, y.height)))
                    sizes.append(CGSize(width: max(x.width, y.width), height: x.height + gap + y.height))
                }
            }
            var smallest: [CGSize] = []
            for size in sizes where !smallest.contains(size)
                && !sizes.contains(where: { $0 != size && $0.width <= size.width && $0.height <= size.height }) {
                smallest.append(size)
            }
            return smallest
        }
    }
}

private extension BSPTree.Axis {
    var flipped: Self { self == .horizontal ? .vertical : .horizontal }
}
