import Sparkle
import SwiftUI

@main struct MomentumApp: App {
    private let configStore: ConfigStore
    private let manager: TilingManager
    private let keepAwake: KeepAwakeService
    private let controller: AppController
    /// Sparkle updater; checks the GitHub Releases appcast (`SUFeedURL` in Info.plist).
    private let updaterController: SPUStandardUpdaterController?

    init() {
        let testing = AppEnvironment.isTesting
        configStore = AppEnvironment.makeConfigStore(testing: testing)
        manager = TilingManager(configStore: configStore)
        keepAwake = KeepAwakeService(store: configStore)
        controller = AppController(store: configStore, keepAwake: keepAwake,
            performTiling: { [manager] in manager.perform($0) },
            refreshTiling: { [manager] in manager.configurationDidChange() })
        // Don't take over windows or check for updates when the app is only hosting unit tests.
        if !testing {
            controller.start()
            updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            Task { [manager] in await manager.start() }
        } else {
            updaterController = nil
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(manager: manager, configStore: configStore, keepAwake: keepAwake,
                updaterController: updaterController)
        } label: {
            KeepAwakeMenuLabel(service: keepAwake)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(configStore: configStore, manager: manager, controller: controller)
        }
    }
}
