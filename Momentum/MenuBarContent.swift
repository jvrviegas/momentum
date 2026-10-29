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

struct MomentumMenuLabel: View {
    let keepAwake: KeepAwakeService
    let flow: FlowService
    let configStore: ConfigStore

    var body: some View {
        let awake = KeepAwakePresentation(keepAwake)
        let flowState = FlowPresentation(flow, preferences: configStore.config.flow)
        let status = [flowState.spokenStatus, "Keep Awake: \(awake.status)"].compactMap { $0 }.joined(separator: " · ")
        // A menu-bar item passes on only its name, so the state goes in the name for VoiceOver.
        let name = ["Momentum", flowState.spokenStatus, awake.isActive ? "Keep Awake on" : nil].compactMap { $0 }.joined(separator: ", ")
        HStack(spacing: Space.xs) {
            icon(awake.iconName, symbol: flowState.menuSymbol)
            // Flow's countdown wins the text; the Keep Awake icon still shows (FL-12).
            if let countdown = flowState.countdown ?? awake.countdown {
                Text(countdown).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .help(status)
    }

    /// A menu-bar item draws only one image, so Flow's state symbol is drawn into the icon as one template.
    private func icon(_ name: String, symbol: String?) -> Image {
        guard let symbol else { return Image(name) }
        let renderer = ImageRenderer(content: HStack(spacing: Space.xs) {
            Image(name)
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
        }
        .foregroundStyle(.black))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return Image(name) }
        image.isTemplate = true
        return Image(nsImage: image)
    }
}

struct MenuBarContent: View {
    @Bindable var manager: TilingManager
    let configStore: ConfigStore
    let keepAwake: KeepAwakeService
    let flow: FlowService
    let updaterController: SPUStandardUpdaterController?
    @Environment(\.openSettings) private var openSettings
    @State private var confirmsDockRestart = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            FlowPanel(flow: flow, configStore: configStore)
            keepAwakeControls
            tilingControls
            footer
        }
        .padding(Space.lg)
        .frame(width: Layout.popoverWidth)
        .onDisappear { confirmsDockRestart = false }
        .onChange(of: manager.canRecoverDesktopSwitching) { _, canRecover in
            if !canRecover { confirmsDockRestart = false }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.xs) {
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
        return Panel {
            Label("Keep Awake", systemImage: "cup.and.saucer")
                .font(.headline)

            VStack(alignment: .leading, spacing: Space.xs) {
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
                if flow.holdsKeepAwake {
                    Text("Ends with your Flow session.")
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
                HStack(spacing: Space.sm) {
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
        Panel {
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
                    if confirmsDockRestart {
                        dockRestartConfirmation
                    } else {
                        Button(manager.isRecoveringDock ? "Restarting Dock…" : "Restart Dock…") {
                            confirmsDockRestart = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.isRecoveringDock)
                    }
                }
                Button("Dismiss Switch Error") {
                    confirmsDockRestart = false
                    manager.dismissDesktopSwitchError()
                }
                .buttonStyle(.borderless)
                .disabled(manager.isRecoveringDock)
            }
        }
    }

    // Keep confirmation inside the MenuBarExtra window. A modal alert can cause the
    // transient popover to close before its Cancel / Restart buttons receive the click.
    private var dockRestartConfirmation: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Restart the Dock?").font(.headline)
            Text("Restarting the Dock may restore minimized windows and disrupt your desktop. After it restarts, try switching desktops again.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", role: .cancel) { confirmsDockRestart = false }
                Button("Restart Dock", role: .destructive) {
                    confirmsDockRestart = false
                    Task { await manager.recoverDesktopSwitching() }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var footer: some View {
        VStack(spacing: Space.sm) {
            Divider()
            HStack(spacing: Space.sm) {
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

    private func errorMessage(_ message: String) -> some View {
        WarningLabel(message)
            .font(.caption)
    }
}
