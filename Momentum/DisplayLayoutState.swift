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

    private(set) var trees: [LayoutKey: BSPTree] = [:]
    private(set) var lastFocused: [LayoutKey: WindowID] = [:]

    mutating func reconcile(visible: [LayoutKey: VisibleLayout], connectedDisplays: Set<DisplayID>,
                            membership: [WindowID: Membership] = [:], focused: WindowID? = nil) {
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
            if let remembered = lastFocused[key], !tree.contains(remembered) { lastFocused[key] = nil }
        }

        for key in keys {
            guard let layout = visible[key], let windows = current[key] else { continue }
            var tree = trees[key] ?? BSPTree()
            tree.sync(with: windows, focused: lastFocused[key], bounds: layout.bounds)
            trees[key] = tree
            if let focused, tree.contains(focused) {
                lastFocused[key] = focused
            } else if let remembered = lastFocused[key], !tree.contains(remembered) {
                lastFocused[key] = nil
            }
        }
    }

    /// A swap is confined to this explicit display/Desktop key, even when bounds touch another display.
    @discardableResult
    mutating func swap(_ window: WindowID, direction: Direction, in key: LayoutKey, bounds: CGRect) -> Bool {
        guard var tree = trees[key],
              let neighbor = tree.neighbor(of: window, direction: direction, bounds: bounds) else { return false }
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
