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

    @Test func animationDefaultsToEnabledForExistingConfigs() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{ "gap": 12 }"#.utf8))
        #expect(config.animationsEnabled)
    }

    @Test func animationsCanBeDisabledAndRoundTrip() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{ "animationsEnabled": false }"#.utf8))
        #expect(!config.animationsEnabled)
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }

    @Test func invalidAnimationSettingIsRejected() throws {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Config.self, from: Data(#"{ "animationsEnabled": "yes" }"#.utf8))
        }
    }

    @Test func reduceMotionOverrideDefaultsOffForExistingConfigs() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{ "gap": 12 }"#.utf8))
        #expect(!config.ignoreReduceMotion)
    }

    @Test func reduceMotionOverrideRoundTrips() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{ "ignoreReduceMotion": true }"#.utf8))
        #expect(config.ignoreReduceMotion)
        #expect(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config)) == config)
    }

    @Test func invalidReduceMotionOverrideIsRejected() throws {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Config.self, from: Data(#"{ "ignoreReduceMotion": "yes" }"#.utf8))
        }
    }

    @Test func animationPolicyHonorsToggleAndOptionalReduceMotionOverride() {
        for enabled in [false, true] {
            for override in [false, true] {
                for reduceMotion in [false, true] {
                    var config = Config()
                    config.animationsEnabled = enabled
                    config.ignoreReduceMotion = override
                    let expected = enabled && (override || !reduceMotion)
                    #expect(config.shouldAnimate(reduceMotion: reduceMotion) == expected)
                }
            }
        }
    }

    @Test func roundTripsThroughJSON() throws {
        var config = Config()
        config.bindings[.retile] = .some(nil)
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }

    @Test func outOfRangeSpacingIsRejected() throws {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Config.self, from: Data(#"{ "gap": -1 }"#.utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Config.self, from: Data(#"{ "outerPadding": 101 }"#.utf8)) }
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{ "gap": 0, "outerPadding": 100 }"#.utf8))
        #expect(config.gap == 0 && config.outerPadding == 100)
    }
}

@MainActor
struct HotKeyManagerTests {
    @Test func comboBoundTwiceFailsForTheLaterAction() {
        let manager = HotKeyManager()
        defer { manager.shutdown() }
        let combo = KeyCombo(key: "f12", modifiers: [.ctrl, .alt, .shift, .cmd])
        // `toggleFloat` comes before `retile` in `Action.allCases`.
        #expect(manager.register([.retile: combo, .toggleFloat: combo, .toggleKeepAwake: combo]) == [.retile, .toggleKeepAwake])
    }
}

@MainActor
struct SpaceMoverTests {
    /// Same shape as `AppleSymbolicHotKeys` in com.apple.symbolichotkeys.plist: Desktop 1 is ⌥1, Desktop 3 is off.
    let symbolicHotKeys: [String: Any] = {
        let xml = """
            <plist version="1.0"><dict>
            <key>118</key><dict><key>enabled</key><true/><key>value</key><dict>
                <key>parameters</key><array><integer>49</integer><integer>18</integer><integer>524288</integer></array>
                <key>type</key><string>standard</string></dict></dict>
            <key>120</key><dict><key>enabled</key><false/><key>value</key><dict>
                <key>parameters</key><array><integer>65535</integer><integer>20</integer><integer>262144</integer></array>
                <key>type</key><string>standard</string></dict></dict>
            </dict></plist>
            """
        return try! PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as! [String: Any]
    }()

    @Test func usesTheUsersDesktopShortcuts() {
        let desktop1 = SpaceMover.desktopShortcut(1, symbolicHotKeys: symbolicHotKeys)
        #expect(desktop1?.keyCode == 18 && desktop1?.flags == .maskAlternate)
        #expect(SpaceMover.desktopShortcut(3, symbolicHotKeys: symbolicHotKeys) == nil)
    }

    @Test func fallsBackToControlNumberWhenNeverCustomized() {
        let desktop2 = SpaceMover.desktopShortcut(2, symbolicHotKeys: symbolicHotKeys)
        #expect(desktop2?.keyCode == 19 && desktop2?.flags == .maskControl)
        #expect(SpaceMover.desktopShortcut(10, symbolicHotKeys: nil) == nil)
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

    @Test func oddSizesKeepTheGapExact() {
        let odd = CGRect(x: 0, y: 0, width: 1001, height: 600)
        var tree = BSPTree()
        tree.insert(1, at: nil, bounds: odd)
        tree.insert(2, at: 1, bounds: odd)
        let frames = tree.layout(in: odd, gap: 8)
        #expect(frames[1] == CGRect(x: 0, y: 0, width: 496, height: 600))
        #expect(frames[2] == CGRect(x: 504, y: 0, width: 497, height: 600))
    }

    @Test func syncRemovesClosedWindowsAndSplitsFocusedForNewOnes() {
        var tree = threeWindowTree()
        tree.sync(with: [1, 3, 4], focused: 3, bounds: bounds)
        let frames = tree.layout(in: bounds, gap: 0)
        #expect(tree.windows == [1, 3, 4])
        #expect(frames[3] == CGRect(x: 500, y: 0, width: 500, height: 300))
        #expect(frames[4] == CGRect(x: 500, y: 300, width: 500, height: 300))

        let unchanged = tree
        tree.sync(with: [4, 1, 3], focused: 1, bounds: bounds)
        #expect(tree == unchanged)
    }

    @Test func windowAtPointIgnoresTheDraggedWindowAndGaps() {
        let tree = threeWindowTree()
        let bottomRight = CGPoint(x: 750, y: 450)
        #expect(tree.window(at: bottomRight, excluding: 1, in: bounds, gap: 10) == 3)
        #expect(tree.window(at: bottomRight, excluding: 3, in: bounds, gap: 10) == nil)
        #expect(tree.window(at: CGPoint(x: 500, y: 100), excluding: 2, in: bounds, gap: 10) == nil)
    }
}
