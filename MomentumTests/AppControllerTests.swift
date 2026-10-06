import AppKit
import Foundation
import Testing
@testable import Momentum

@MainActor
final class FakeHotKeys: HotKeyRegistration {
    var onAction: ((Action) -> Void)?
    var registrations: [[Action: KeyCombo?]] = []
    var failed: Set<Action> = []
    var shutdownCount = 0

    func register(_ bindings: [Action: KeyCombo?]) -> Set<Action> {
        registrations.append(bindings)
        return failed
    }

    func shutdown() {
        shutdownCount += 1
        onAction = nil
    }
}

@MainActor
struct AppControllerTests {
    @Test func appRoutingAndConfigurationAreIndependentOfTiling() throws {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        let hotKeys = FakeHotKeys()
        hotKeys.failed = [.toggleKeepAwake]
        var tilingActions: [Action] = []
        var refreshes = 0
        let controller = AppController(store: f.config.store, keepAwake: f.service, hotKeys: hotKeys,
            performTiling: { tilingActions.append($0) }, refreshTiling: { refreshes += 1 })
        controller.start(listening: false)
        controller.start(listening: false)
        #expect(hotKeys.registrations.count == 1)
        #expect(controller.failedHotKeys == [.toggleKeepAwake])
        hotKeys.onAction?(.toggleKeepAwake)
        #expect(f.service.isActive)
        #expect(tilingActions.isEmpty)
        let deadline = f.service.deadline
        controller.perform(.focus(.left))
        controller.perform(.sendToDesktop(1))
        #expect(tilingActions == [.focus(.left), .sendToDesktop(1)])
        try f.config.store.updateKeepAwake(.init(duration: .untilStopped, mode: .systemAndDisplay))
        #expect(refreshes == 1)
        #expect(hotKeys.registrations.count == 2)
        #expect(f.service.mode == .system)
        #expect(f.service.deadline == deadline)
        f.config.store.config.bindings[.toggleKeepAwake] = .some(nil)
        #expect(refreshes == 2)
        #expect(hotKeys.registrations.last?[.toggleKeepAwake] == .some(nil))
        controller.shutdown()
        controller.shutdown()
        #expect(hotKeys.shutdownCount == 1)
        #expect(f.client.live.isEmpty)
        #expect(f.scheduler.liveCount == 0)
        #expect(f.config.store.onChange == nil)
        controller.perform(.toggleKeepAwake)
        #expect(!f.service.isActive)
    }

    @Test func lifecycleNotificationsResumeAndTerminationDisposesListeners() {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        let hotKeys = FakeHotKeys()
        let controller = AppController(store: f.config.store, keepAwake: f.service, hotKeys: hotKeys,
            performTiling: { _ in }, refreshTiling: {})
        controller.start()
        controller.perform(.toggleKeepAwake)
        let deadline = f.service.deadline
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(f.service.isSuspended)
        #expect(f.client.live.isEmpty)
        f.time += 30
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(f.service.isActive && !f.service.isSuspended)
        #expect(f.service.deadline == deadline)
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        #expect(hotKeys.shutdownCount == 1)
        #expect(f.client.live.isEmpty)
        let creates = f.client.creates.count
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(f.client.creates.count == creates)
        #expect(f.config.store.onChange == nil)
    }

    @Test func constructionDoesNotRegisterOrStartAndHostConfigIsTemporary() {
        let store = AppEnvironment.makeConfigStore(testing: true)
        defer {
            store.shutdown()
            try? FileManager.default.removeItem(at: store.location.deletingLastPathComponent())
        }
        #expect(store.location != ConfigStore.fileURL)
        let client = FakePowerClient()
        let service = KeepAwakeService(store: store, assertions: PowerAssertions(client: client))
        let hotKeys = FakeHotKeys()
        let controller = AppController(store: store, keepAwake: service, hotKeys: hotKeys,
            performTiling: { _ in Issue.record("Unexpected tiling dispatch") }, refreshTiling: {})
        #expect(hotKeys.registrations.isEmpty)
        #expect(client.creates.isEmpty)
        #expect(store.onChange == nil)
        controller.shutdown()
    }

    @Test func liveAtomicEditFansOutWithoutChangingActiveSession() async throws {
        let fixture = TemporaryConfig(watching: true)
        defer { fixture.cleanup() }
        let client = FakePowerClient()
        let service = KeepAwakeService(store: fixture.store, assertions: PowerAssertions(client: client))
        let keys = FakeHotKeys()
        var refreshes = 0
        let controller = AppController(store: fixture.store, keepAwake: service, hotKeys: keys,
            performTiling: { _ in }, refreshTiling: { refreshes += 1 })
        controller.start(listening: false)
        defer { controller.shutdown() }
        service.start()
        let deadline = service.deadline
        try Data(#"{"keepAwake":{"duration":"8h","mode":"system-and-display"},"bindings":{"toggle-keep-awake":"ctrl+alt+a"}}"#.utf8)
            .write(to: fixture.store.location, options: .atomic)
        for _ in 0..<50 {
            if refreshes > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(refreshes == 1)
        #expect(keys.registrations.count == 2)
        #expect(service.mode == .system)
        #expect(service.deadline == deadline)
        #expect(client.creates == [.system])
        #expect(fixture.store.config.keepAwake.mode == .systemAndDisplay)
        #expect(keys.registrations.last?[.toggleKeepAwake] == KeyCombo(string: "ctrl+alt+a"))
    }

    @Test func untrustedDisabledTilingRetainsExistingGuards() {
        let f = KeepAwakeFixture()
        defer { f.cleanup() }
        let tiling = TilingManager(configStore: f.config.store)
        tiling.isEnabled = false
        #expect(!tiling.isTrusted)
        let controller = AppController(store: f.config.store, keepAwake: f.service,
            performTiling: { tiling.perform($0) }, refreshTiling: {})
        controller.perform(.toggleKeepAwake)
        #expect(f.service.isActive)
        for action in Action.allCases where action != .toggleKeepAwake { controller.perform(action) }
        #expect(!tiling.isTrusted)
        #expect(f.service.isActive)
        controller.shutdown()
    }
}
