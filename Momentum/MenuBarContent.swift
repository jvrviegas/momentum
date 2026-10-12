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
    var sessionTitle: String {
        guard isActive else { return "Ready to start" }
        return minutes.map { "\($0) min remaining" } ?? "Until stopped"
    }
    var actionTitle: String { isActive ? "Stop Keep Awake" : "Start Keep Awake" }
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
    @State private var confirmsDockRestart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            keepAwakeControls
            tilingControls
            footer
        }
        .padding(16)
        .frame(width: 340)
        .alert("Restart the Dock?", isPresented: $confirmsDockRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Restart Dock", role: .destructive) {
                Task { await manager.recoverDesktopSwitching() }
            }
        } message: {
            Text("Restarting the Dock may restore minimized windows and disrupt your desktop. After it restarts, try switching desktops again.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Momentum").font(.headline)
                AppVersionLabel()
            }
            Spacer()
            Button("Settings…", systemImage: "gearshape") {
                NSApp.activate()
                openSettings()
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Open Momentum Settings")
            .accessibilityLabel("Open Momentum Settings")
            .keyboardShortcut(",")
        }
    }

    private var keepAwakeControls: some View {
        let presentation = KeepAwakePresentation(keepAwake)
        return panel {
            Label("Keep Awake", systemImage: "cup.and.saucer")
                .font(.headline)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.sessionTitle)
                    .font(presentation.isActive ? .title3.weight(.semibold) : .subheadline)
                    .monospacedDigit()
                    .foregroundStyle(presentation.isActive ? Color.primary : Color.secondary)
                    .accessibilityValue(presentation.status)
                if let mode = presentation.mode {
                    Text(mode == .system ? "System only" : "System and display")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if presentation.showsDuration {
                Picker("Duration", selection: Binding(
                    get: { configStore.config.keepAwake.duration },
                    set: { keepAwake.selectDuration($0) }
                )) {
                    ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .pickerStyle(.menu)
            }
            Picker("Keep awake", selection: Binding(
                get: { keepAwake.mode ?? configStore.config.keepAwake.mode },
                set: { keepAwake.changeMode($0) }
            )) {
                ForEach(KeepAwakeMode.allCases, id: \.self) { mode in
                    Text(mode == .system ? "System only" : "System and display").tag(mode)
                }
            }
            .pickerStyle(.menu)
            .help("System only allows display sleep. Explicit sleep, lid closure, and battery protections still apply.")
            if presentation.isActive {
                Text("Mode changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if presentation.showsExtensions {
                HStack(spacing: 6) {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button(minutes == 60 ? "+1 hour" : "+\(minutes) min") {
                            keepAwake.extend(by: Double(minutes * 60))
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Extend Keep Awake by \(minutes) minutes")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                if keepAwake.isActive { keepAwake.stop() } else { keepAwake.start() }
            } label: {
                Text(presentation.actionTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(presentation.actionTitle)

            if let error = keepAwake.error {
                errorMessage(error)
                    .accessibilityLabel("Keep Awake error: \(error)")
                Button(presentation.retryTitle) { keepAwake.retry() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var tilingControls: some View {
        panel {
            Label("Window Tiling", systemImage: "rectangle.split.2x2")
                .font(.headline)
            Toggle("Automatic tiling", isOn: $manager.isEnabled)
                .toggleStyle(.switch)
            Text("Arrange windows automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                manager.retile()
            } label: {
                Label("Retile Windows", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(!manager.isEnabled || !manager.isTrusted)

            if !manager.isTrusted {
                Text("Tiling needs Device Control and Data Access permissions. Keep Awake does not.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }

            if let error = manager.lastDesktopMoveError {
                Divider()
                errorMessage(error)
                Button("Dismiss Move Error") { manager.dismissDesktopMoveError() }
                    .buttonStyle(.borderless)
            }
            if let error = manager.lastDesktopSwitchError {
                Divider()
                errorMessage(error)
                if manager.canRecoverDesktopSwitching {
                    Button(manager.isRecoveringDock ? "Restarting Dock…" : "Restart Dock…") {
                        confirmsDockRestart = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(manager.isRecoveringDock)
                }
                Button("Dismiss Switch Error") { manager.dismissDesktopSwitchError() }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                Button {
                    NSApp.activate()
                    updaterController?.checkForUpdates(nil)
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .disabled(updaterController == nil)
                Button("Quit", systemImage: "power") {
                    NSApp.terminate(nil)
                }
                .fixedSize()
                .accessibilityLabel("Quit Momentum")
                .keyboardShortcut("q")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .font(.body)
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}
