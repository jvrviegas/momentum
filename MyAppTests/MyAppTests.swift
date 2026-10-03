import CoreGraphics
import Foundation
import Testing
@testable import Momentum

@MainActor
struct ConfigTests {
    @Test func missingBindingsGetDefaultsAndNullStaysUnbound() throws {
        let json = #"{ "bindings": { "focus-left": "ctrl+a", "retile": null } }"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.bindings[.focus(.left)] == KeyCombo(key: "a", modifiers: [.ctrl]))
        #expect(config.bindings[.retile] == .some(nil))
        #expect(config.bindings[.switchToDesktop(2)] == KeyCombo(key: "2", modifiers: [.alt]))
    }

    @Test func roundTripsThroughJSON() throws {
        var config = Config()
        config.bindings[.retile] = .some(nil)
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }
}

@MainActor
struct BSPTreeTests {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)

    /// Builds a tree: 1 on the left half, 2 top-right, 3 bottom-right.
    func threeWindowTree() -> BSPTree {
        var tree = BSPTree()
        tree.insert(1, at: nil, bounds: bounds)
        tree.insert(2, at: 1, bounds: bounds)
        tree.insert(3, at: 2, bounds: bounds)
        return tree
    }

    @Test func singleWindowFillsBounds() {
        var tree = BSPTree()
        tree.insert(1, at: nil, bounds: bounds)
        #expect(tree.layout(in: bounds, gap: 10) == [1: bounds])
    }

    @Test func secondWindowSplitsLongerSideWithGap() {
        var tree = BSPTree()
        tree.insert(1, at: nil, bounds: bounds)
        tree.insert(2, at: 1, bounds: bounds)
        let frames = tree.layout(in: bounds, gap: 10)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 495, height: 600))
        #expect(frames[2] == CGRect(x: 505, y: 0, width: 495, height: 600))
    }

    @Test func dwindleSplitsFocusedLeafVertically() {
        let frames = threeWindowTree().layout(in: bounds, gap: 0)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(frames[2] == CGRect(x: 500, y: 0, width: 500, height: 300))
        #expect(frames[3] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }

    @Test func insertWithoutFocusSplitsLastLeaf() {
        var tree = BSPTree()
        tree.insert(1, at: nil, bounds: bounds)
        tree.insert(2, at: nil, bounds: bounds)
        tree.insert(3, at: 99, bounds: bounds)
        #expect(tree == threeWindowTree())
    }

    @Test func duplicateInsertIsIgnored() {
        var tree = threeWindowTree()
        tree.insert(2, at: 1, bounds: bounds)
        #expect(tree == threeWindowTree())
    }

    @Test func removeCollapsesParent() {
        var tree = threeWindowTree()
        tree.remove(2)
        let frames = tree.layout(in: bounds, gap: 0)
        #expect(tree.windows == [1, 3])
        #expect(frames[3] == CGRect(x: 500, y: 0, width: 500, height: 600))

        tree.remove(1)
        tree.remove(3)
        #expect(tree.isEmpty)
    }

    @Test func directionalNeighbors() {
        let tree = threeWindowTree()
        #expect(tree.neighbor(of: 2, direction: .down, bounds: bounds) == 3)
        #expect(tree.neighbor(of: 3, direction: .up, bounds: bounds) == 2)
        #expect(tree.neighbor(of: 3, direction: .left, bounds: bounds) == 1)
        #expect(tree.neighbor(of: 2, direction: .left, bounds: bounds) == 1)
        #expect(tree.neighbor(of: 1, direction: .left, bounds: bounds) == nil)
        #expect(tree.neighbor(of: 1, direction: .up, bounds: bounds) == nil)
    }

    @Test func swapExchangesPositions() {
        var tree = threeWindowTree()
        tree.swap(1, 3)
        let frames = tree.layout(in: bounds, gap: 0)
        #expect(frames[3] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(frames[1] == CGRect(x: 500, y: 300, width: 500, height: 300))
    }
}
