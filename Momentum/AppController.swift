import AppKit
import Observation

protocol HotKeyRegistration: AnyObject {
    var onAction: ((Action) -> Void)? { get set }
    func register(_ bindings: [Action: KeyCombo?]) -> Set<Action>
    func shutdown()
}

/// App actions are available before the independent tiling Accessibility wait completes.
@Observable final class AppController {
    private(set) var failedHotKeys: Set<Action> = []
    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private let keepAwake: KeepAwakeService
    @ObservationIgnored private let performTiling: (Action) -> Void
    @ObservationIgnored private let refreshTiling: () -> Void
    @ObservationIgnored private var hotKeys: (any HotKeyRegistration)?
    @ObservationIgnored private var listeners: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var isShutdown = false

    init(store: ConfigStore, keepAwake: KeepAwakeService,
         hotKeys: (any HotKeyRegistration)? = nil,
         performTiling: @escaping (Action) -> Void, refreshTiling: @escaping () -> Void) {
        self.store = store
        self.keepAwake = keepAwake
        self.hotKeys = hotKeys
        self.performTiling = performTiling
        self.refreshTiling = refreshTiling
    }

    func start(listening: Bool = true) {
        guard !started, !isShutdown else { return }
        started = true
        if hotKeys == nil { hotKeys = HotKeyManager() }
        hotKeys?.onAction = { [weak self] in self?.perform($0) }
        failedHotKeys = hotKeys?.register(store.config.bindings) ?? []
        store.onChange = { [weak self] config in
            guard let self, !isShutdown else { return }
            failedHotKeys = hotKeys?.register(config.bindings) ?? []
            refreshTiling()
        }
        if listening {
            let workspace = NSWorkspace.shared.notificationCenter
            listen(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.keepAwake.willSleep() }
            listen(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.keepAwake.didWake() }
            listen(.default, NSApplication.willTerminateNotification) { [weak self] in self?.shutdown() }
        }
    }

    func perform(_ action: Action) {
        guard !isShutdown else { return }
        if action == .toggleKeepAwake { keepAwake.toggle() }
        else { performTiling(action) }
    }

    func shutdown() {
        guard !isShutdown else { return }
        isShutdown = true
        for (center, token) in listeners { center.removeObserver(token) }
        listeners.removeAll()
        hotKeys?.shutdown()
        hotKeys = nil
        keepAwake.shutdown()
        store.shutdown()
    }

    private func listen(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        }
        listeners.append((center, token))
    }
}

/// Evaluated before constructing ConfigStore or any native startup service.
enum AppEnvironment {
    static var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    static func makeConfigStore(testing: Bool) -> ConfigStore {
        guard testing else { return ConfigStore() }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "momentum-test-host-\(UUID())/tiling.json")
        return ConfigStore(fileURL: url, watching: false)
    }
}
