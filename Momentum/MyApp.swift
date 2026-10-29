import Sparkle
import SwiftUI

@main struct MomentumApp: App {
    private let configStore: ConfigStore
    private let manager: TilingManager
    private let keepAwake: KeepAwakeService
    private let flow: FlowService
    private let controller: AppController
    /// Sparkle updater; checks the GitHub Releases appcast (`SUFeedURL` in Info.plist).
    private let updaterController: SPUStandardUpdaterController?

    init() {
        let testing = AppEnvironment.isTesting
        configStore = AppEnvironment.makeConfigStore(testing: testing)
        manager = TilingManager(configStore: configStore)
        keepAwake = KeepAwakeService(store: configStore)
        flow = FlowService(store: configStore, keepAwake: keepAwake, notifier: Self.makeFlowNotifier(testing: testing))
        controller = AppController(store: configStore, keepAwake: keepAwake, flow: flow,
            performTiling: { [manager] in manager.perform($0) },
            refreshTiling: { [manager] in manager.configurationDidChange() })
        // Don't take over windows or check for updates when the app is only hosting unit tests.
        if !testing {
            controller.start()
            updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            Task { [manager] in await manager.start() }
            #if DEBUG
            if let preview = UserDefaults.standard.string(forKey: "MomentumFlowPreview") { flow.preview(preview) }
            #endif
        } else {
            updaterController = nil
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(manager: manager, configStore: configStore, keepAwake: keepAwake, flow: flow,
                updaterController: updaterController)
        } label: {
            MomentumMenuLabel(keepAwake: keepAwake, flow: flow, configStore: configStore)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(configStore: configStore, manager: manager, controller: controller, flow: flow)
        }
        .windowToolbarStyle(.unifiedCompact)
    }

    /// The unit-test host never touches macOS notifications. Debug builds can fake the permission
    /// for snapshots: `-MomentumFlowNotificationPreview allowed|denied|notDetermined`.
    private static func makeFlowNotifier(testing: Bool) -> any FlowNotifier {
        if testing { return SilentFlowNotifier() }
        #if DEBUG
        let statuses: [String: FlowNotificationStatus] = ["allowed": .allowed, "denied": .denied, "notDetermined": .notDetermined]
        if let preview = UserDefaults.standard.string(forKey: "MomentumFlowNotificationPreview"), let status = statuses[preview] {
            return SilentFlowNotifier(fixedStatus: status)
        }
        #endif
        return SystemFlowNotifier()
    }
}
