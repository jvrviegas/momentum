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
        MenuBarExtra("Momentum", image: "MenuBarIcon") {
            MenuContent(manager: manager, updaterController: updaterController)
        }
        Settings {
            SettingsView(configStore: configStore, manager: manager, controller: controller)
        }
    }
}

private struct MenuContent: View {
    @Bindable var manager: TilingManager
    let updaterController: SPUStandardUpdaterController?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Toggle("Tiling Enabled", isOn: $manager.isEnabled)
        Button("Retile") { manager.retile() }
        if let error = manager.lastDesktopMoveError {
            Text(error)
            Button("Dismiss Move Error") { manager.dismissDesktopMoveError() }
        }
        Divider()
        Button("Settings…") {
            // Menu-bar-only apps aren't active, so the Settings window would open behind other apps.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Check for Updates…") {
            NSApp.activate()
            updaterController?.checkForUpdates(nil)
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
