import CoreGraphics

struct LayoutKey: Hashable {
    let displayID: DisplayID
    let spaceID: SpaceID
}

/// Pure reconciliation seam. No AX reads, native moves, animations or persistent monitor restoration.
struct DisplayLayoutState {
    struct VisibleLayout {
        let bounds: CGRect
        /// Already filtered to standard, nonfloating windows by the caller.
        let windows: [WindowID]
    }

    enum Membership: Equatable {
        case space(SpaceID)
        /// Explicit evidence of closure; omitted membership means unknown, not closed.
        case closed
    }

    /// A layout's tiles, and the windows set aside because they don't fit at their minimum sizes.
    struct Arrangement {
        let frames: [WindowID: CGRect]
        let setAside: Set<WindowID>
    }

    private(set) var trees: [LayoutKey: BSPTree] = [:]
    private(set) var lastFocused: [LayoutKey: WindowID] = [:]
    /// Each layout's windows in the order they joined it, oldest first; the oldest fit first.
    private(set) var joinOrder: [LayoutKey: [WindowID]] = [:]

    /// `prioritized` moves to the front of its layout's join order, so it's the last window set aside.
    mutating func reconcile(visible: [LayoutKey: VisibleLayout], connectedDisplays: Set<DisplayID>,
                            membership: [WindowID: Membership] = [:], focused: WindowID? = nil,
                            prioritized: WindowID? = nil) {
        let keys = visible.keys.filter { key in
            guard connectedDisplays.contains(key.displayID), key.spaceID != 0,
                  let bounds = visible[key]?.bounds else { return false }
            return bounds.width > 0 && bounds.height > 0
                && [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite)
        }.sorted(by: Self.ordered)
        var owners: [WindowID: LayoutKey] = [:]
        var current: [LayoutKey: [WindowID]] = [:]
        // Defensive deduplication gives even malformed synthetic inputs one deterministic owner.
        for key in keys {
            current[key] = (visible[key]?.windows ?? []).filter { id in
                guard id != 0, owners[id] == nil else { return false }
                if let known = membership[id], known != .space(key.spaceID) { return false }
                owners[id] = key
                return true
            }
        }

        for key in Array(trees.keys) {
            guard connectedDisplays.contains(key.displayID) else {
                trees[key] = nil
                lastFocused[key] = nil
                joinOrder[key] = nil
                continue
            }
            guard current[key] == nil, var tree = trees[key] else { continue }
            for id in tree.windows {
                if let owner = owners[id], owner != key {
                    tree.remove(id)
                } else if let known = membership[id], known != .space(key.spaceID) {
                    tree.remove(id)
                }
            }
            trees[key] = tree.isEmpty ? nil : tree
            joinOrder[key] = tree.isEmpty ? nil : joinOrder[key]?.filter(tree.contains)
            if let remembered = lastFocused[key], !tree.contains(remembered) { lastFocused[key] = nil }
        }

        for key in keys {
            guard let layout = visible[key], let windows = current[key] else { continue }
            var tree = trees[key] ?? BSPTree()
            tree.sync(with: windows, focused: lastFocused[key], bounds: layout.bounds)
            trees[key] = tree
            var order = (joinOrder[key] ?? []).filter(tree.contains)
            order += windows.filter { !order.contains($0) }
            if let prioritized, let index = order.firstIndex(of: prioritized) {
                order.insert(order.remove(at: index), at: 0)
            }
            joinOrder[key] = order
            if let focused, tree.contains(focused) {
                lastFocused[key] = focused
            } else if let remembered = lastFocused[key], !tree.contains(remembered) {
                lastFocused[key] = nil
            }
        }
    }

    /// Tiles the layout's windows in join order at their minimum sizes, setting aside each one that doesn't fit.
    func arrangement(for key: LayoutKey, bounds: CGRect, gap: CGFloat,
                     minimums: [WindowID: CGSize] = [:]) -> Arrangement? {
        guard var tree = trees[key] else { return nil }
        // Without minimum sizes of its own, a layout splits evenly as it always has.
        let minimums = minimums.filter { tree.contains($0.key) }
        let setAside = tree.windowsThatDontFit(in: bounds, gap: gap, minimums: minimums, order: joinOrder[key] ?? [])
        for id in setAside { tree.remove(id) }
        return Arrangement(frames: tree.layout(in: bounds, gap: gap, minimums: minimums), setAside: setAside)
    }

    /// A swap is confined to this explicit display/Desktop key, even when bounds touch another display.
    @discardableResult
    mutating func swap(_ window: WindowID, direction: Direction, in key: LayoutKey, bounds: CGRect,
                       gap: CGFloat = 0, minimums: [WindowID: CGSize] = [:]) -> Bool {
        guard var tree = trees[key],
              let frames = arrangement(for: key, bounds: bounds, gap: gap, minimums: minimums)?.frames,
              let neighbor = BSPTree.neighbor(of: window, direction: direction, in: frames) else { return false }
        tree.swap(window, neighbor)
        trees[key] = tree
        return true
    }

    @discardableResult
    mutating func swap(_ first: WindowID, with second: WindowID, in key: LayoutKey) -> Bool {
        guard var tree = trees[key], tree.contains(first), tree.contains(second), first != second else { return false }
        tree.swap(first, second)
        trees[key] = tree
        return true
    }

    private static func ordered(_ lhs: LayoutKey, _ rhs: LayoutKey) -> Bool {
        lhs.displayID != rhs.displayID ? lhs.displayID < rhs.displayID : lhs.spaceID < rhs.spaceID
    }
}
