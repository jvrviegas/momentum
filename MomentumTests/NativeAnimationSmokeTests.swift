import AppKit
import QuartzCore
import Testing
@testable import Momentum

/// Native driver/lifecycle smoke with virtual windows only: no real AX writes, observers or hotkeys.
@MainActor
struct NativeAnimationSmokeTests {
    @Test func injectedStartupDrivesARealDisplayLinkWithoutTouchingUserWindows() async throws {
        let actualScreen = try #require(NSScreen.screens.first)
        let actualID = try #require(actualScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).uint32Value
        let f = TilingFixture()
        defer { f.cleanup() }
        f.config.store.config.animationsEnabled = true
        f.windows = [FakeTilingWindow(1, CGRect(x: 10, y: 30, width: 400, height: 300), space: 10)]
        var environment = f.environment
        let nativeDriver = TilingEnvironment.native(observer: WindowObserver()).makeDisplayLink
        environment.now = { CACurrentMediaTime() }
        environment.makeDisplayLink = { _, tick in nativeDriver(actualID, tick) }
        let manager = TilingManager(configStore: f.config.store, environment: environment, initiallyTrusted: true)
        defer { manager.isEnabled = false }
        await manager.start() // Injected startup must not request AX or attach real observers.
        for _ in 0..<100 {
            if f.windows[0].frame == CGRect(x: 8, y: 28, width: 984, height: 764) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!f.windows[0].writes.isEmpty)
        #expect(f.windows[0].frame == CGRect(x: 8, y: 28, width: 984, height: 764))
        #expect(f.moves.isEmpty)
        #expect(f.windows[0].focused == 0)
    }
}
