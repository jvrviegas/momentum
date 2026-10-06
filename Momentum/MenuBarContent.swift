import Sparkle
import SwiftUI

/// Shared derived values keep the menu label and open popover in agreement.
struct KeepAwakePresentation {
    let isActive: Bool
    let mode: KeepAwakeMode?
    let minutes: Int?
    let retryMode: KeepAwakeMode?

    init(_ service: KeepAwakeService) {
        isActive = service.isActive
        mode = service.mode
        minutes = service.remainingMinutes
        retryMode = service.retryMode
    }

    var iconName: String { isActive ? "MenuBarAwakeIcon" : "MenuBarIcon" }
    var countdown: String? { minutes.map { "\($0)m" } }
    var showsDuration: Bool { !isActive }
    var showsExtensions: Bool { isActive && minutes != nil }
    var status: String {
        guard isActive, let mode else { return "Inactive" }
        return "\(mode.title) · \(minutes.map { "\($0) min remaining" } ?? "Until stopped")"
    }
    var retryTitle: String {
        if isActive, retryMode != nil { return "Retry mode change" }
        return isActive ? "Retry cleanup" : "Retry Start"
    }
}

struct KeepAwakeMenuLabel: View {
    let service: KeepAwakeService

    var body: some View {
        let presentation = KeepAwakePresentation(service)
        HStack(spacing: 4) {
            Image(presentation.iconName)
            if let countdown = presentation.countdown {
                Text(countdown).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Momentum Keep Awake")
        .accessibilityValue(presentation.status)
        .help(presentation.status)
    }
}

struct MenuBarContent: View {
    @Bindable var manager: TilingManager
    let configStore: ConfigStore
    let keepAwake: KeepAwakeService
    let updaterController: SPUStandardUpdaterController?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            keepAwakeControls
            Divider()
            Toggle("Tiling Enabled", isOn: $manager.isEnabled)
            Button("Retile") { manager.retile() }
            if let error = manager.lastDesktopMoveError {
                Text(error).font(.caption).foregroundStyle(.red)
                Button("Dismiss Move Error") { manager.dismissDesktopMoveError() }
            }
            Divider()
            Button("Settings…") {
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
        .padding(16)
        .frame(width: 320)
    }

    private var keepAwakeControls: some View {
        let presentation = KeepAwakePresentation(keepAwake)
        return VStack(alignment: .leading, spacing: 10) {
            Toggle("Keep Awake", isOn: Binding(
                get: { keepAwake.isActive },
                set: { _ in keepAwake.toggle() }
            ))
            .toggleStyle(.switch)
            .font(.headline)
            .accessibilityValue(presentation.status)
            Text(presentation.status)
                .font(.caption)
                .foregroundStyle(.secondary)
            if presentation.showsDuration {
                Picker("Duration", selection: Binding(
                    get: { configStore.config.keepAwake.duration },
                    set: { keepAwake.selectDuration($0) }
                )) {
                    ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
            }
            Picker("Mode", selection: Binding(
                get: { keepAwake.mode ?? configStore.config.keepAwake.mode },
                set: { keepAwake.changeMode($0) }
            )) {
                ForEach(KeepAwakeMode.allCases, id: \.self) { mode in
                    Text(mode == .system ? "System only" : "System and display").tag(mode)
                }
            }
            .help("System only allows display sleep. macOS explicit sleep, lid and battery protections still apply.")
            if presentation.showsExtensions {
                HStack {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button("+\(minutes) min") { keepAwake.extend(by: Double(minutes * 60)) }
                            .accessibilityLabel("Extend Keep Awake by \(minutes) minutes")
                    }
                }
            }
            Button(keepAwake.isActive ? "Stop" : "Start") {
                if keepAwake.isActive { keepAwake.stop() } else { keepAwake.start() }
            }
            .accessibilityLabel(keepAwake.isActive ? "Stop Keep Awake" : "Start Keep Awake")
            if let error = keepAwake.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Keep Awake error: \(error)")
                Button(presentation.retryTitle) { keepAwake.retry() }
            }
        }
    }
}
