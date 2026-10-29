import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case layout, floatingApps, shortcuts, keepAwake, advanced

    var id: String { rawValue }
    var title: String {
        switch self {
        case .layout: "Layout"
        case .floatingApps: "Floating Apps"
        case .shortcuts: "Keyboard Shortcuts"
        case .keepAwake: "Keep Awake"
        case .advanced: "Advanced"
        }
    }
    var icon: String {
        switch self {
        case .layout: "rectangle.split.2x2"
        case .floatingApps: "macwindow.on.rectangle"
        case .shortcuts: "keyboard"
        case .keepAwake: "cup.and.saucer"
        case .advanced: "gearshape.2"
        }
    }
    var subtitle: String {
        switch self {
        case .layout: "Adjust window spacing and motion."
        case .floatingApps: "Choose apps that should stay outside automatic tiling."
        case .shortcuts: "Customize how you navigate and arrange your workspace."
        case .keepAwake: "Choose preferences for your next Keep Awake session."
        case .advanced: "Manage permissions and the configuration file."
        }
    }
}

enum SettingsShortcutGroup: String, CaseIterable, Identifiable {
    case focus = "Focus"
    case move = "Move Windows"
    case desktops = "Desktops"
    case displays = "Displays"
    case other = "Other"

    var id: String { rawValue }
    var actions: [Action] {
        Action.allCases.filter { action in
            switch action {
            case .focus: self == .focus
            case .move: self == .move
            case .sendToDesktop, .switchToDesktop: self == .desktops
            case .sendToPreviousDisplay, .sendToNextDisplay: self == .displays
            case .toggleFloat, .retile, .toggleKeepAwake: self == .other
            }
        }
    }
}

struct SettingsView: View {
    @Bindable var configStore: ConfigStore
    let manager: TilingManager
    let controller: AppController

    @AppStorage("settings.selectedPage") private var selectedPage = SettingsPage.layout.rawValue
    @State private var newBundleID = ""
    @State private var isPickingApps = false

    private var page: SettingsPage { SettingsPage(rawValue: selectedPage) ?? .layout }
    private var selection: Binding<SettingsPage?> {
        Binding(
            get: { page },
            set: { if let value = $0 { selectedPage = value.rawValue } }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPage.allCases, selection: selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
                    .padding(.vertical, Space.xs)
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
                AppVersionLabel()
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.md)
            }
            .navigationSplitViewColumnWidth(min: Layout.sidebarMinWidth, ideal: Layout.sidebarIdealWidth, max: Layout.sidebarMaxWidth)
            .navigationTitle("Momentum")
            .toolbar(removing: .sidebarToggle)
            .accessibilityLabel("Settings sections")
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(page.subtitle).foregroundStyle(.secondary)
                    if let error = configStore.lastError {
                        warning(error)
                    }
                }
                .padding(Space.margin)

                Form {
                    switch page {
                    case .layout: layoutSettings
                    case .floatingApps: floatingSettings
                    case .shortcuts: shortcutSettings
                    case .keepAwake: keepAwakeSettings
                    case .advanced: advancedSettings
                    }
                }
                .formStyle(.grouped)
                .id(page)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(page.title)
        }
        .navigationSplitViewStyle(.balanced)
        .noInitialFocus()
        .frame(minWidth: Layout.settingsMinSize.width, idealWidth: Layout.settingsIdealSize.width,
               minHeight: Layout.settingsMinSize.height, idealHeight: Layout.settingsIdealSize.height)
        .sheet(isPresented: $isPickingApps) {
            AppPickerSheet(selection: $configStore.config.floatingBundleIDs)
        }
    }

    private var layoutSettings: some View {
        Group {
            if !manager.isTrusted {
                Section {
                    warning("Tiling requires Device Control and Data Access permissions. Keep Awake does not.")
                    Button("Review Permissions") { selectedPage = SettingsPage.advanced.rawValue }
                }
            }
            Section("Spacing") {
                TextField("Gap between windows (points)", value: spacing(\.gap), format: .number)
                TextField("Screen padding (points)", value: spacing(\.outerPadding), format: .number)
            }
            Section {
                Toggle("Animate tiling transitions", isOn: $configStore.config.animationsEnabled)
                Toggle("Ignore Reduce Motion for Momentum", isOn: $configStore.config.ignoreReduceMotion)
                    .disabled(!configStore.config.animationsEnabled)
            } header: {
                Text("Motion")
            } footer: {
                Text("Transitions use a 200 ms ease-out animation. Reduce Motion is respected unless you enable this Momentum-only override; your system setting stays unchanged. Smoothness varies by app.")
            }
            Section("macOS Tiling") {
                Text("Turn off “Drag windows to screen edges to tile” in System Settings › Desktop & Dock so macOS tiling does not compete with Momentum.")
                    .foregroundStyle(.secondary)
                Button("Open Desktop & Dock Settings") {
                    openSystemSettings("com.apple.Desktop-Settings.extension")
                }
            }
        }
    }

    private var floatingSettings: some View {
        Group {
            Section("Excluded Apps") {
                if configStore.config.floatingBundleIDs.isEmpty {
                    Text("No apps excluded. Choose apps below to keep their windows floating.")
                        .foregroundStyle(.secondary)
                }
                ForEach(configStore.config.floatingBundleIDs, id: \.self) { bundleID in
                    let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                    HStack {
                        AppIcon(url: appURL)
                        VStack(alignment: .leading) {
                            Text(appURL.map(InstalledApp.displayName) ?? bundleID)
                            Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") {
                            configStore.config.floatingBundleIDs.removeAll { $0 == bundleID }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Remove \(appURL.map(InstalledApp.displayName) ?? bundleID)")
                        .accessibilityLabel("Remove \(appURL.map(InstalledApp.displayName) ?? bundleID)")
                    }
                }
                Button("Choose Apps…") { isPickingApps = true }
            }
            Section {
                HStack {
                    TextField("Bundle identifier", text: $newBundleID, prompt: Text("com.example.app"))
                    Button("Add") {
                        configStore.config.floatingBundleIDs.append(trimmedBundleID)
                        newBundleID = ""
                    }
                    .disabled(trimmedBundleID.isEmpty || configStore.config.floatingBundleIDs.contains(trimmedBundleID))
                }
            } header: {
                Text("Add Manually")
            } footer: {
                Text("Use a bundle identifier for an app that is not listed in the picker.")
            }
        }
    }

    private var trimmedBundleID: String { newBundleID.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var shortcutSettings: some View {
        Group {
            if let error = manager.lastDesktopMoveError {
                Section { warning(error) }
            }
            if let error = manager.lastDesktopSwitchError {
                Section { warning(error) }
            }
            Section {
                Text("Click a shortcut, then press your keys. Include at least one modifier. Escape cancels; Delete clears.")
                    .foregroundStyle(.secondary)
            }
            ForEach(SettingsShortcutGroup.allCases) { group in
                Section(group.rawValue) {
                    ForEach(group.actions, id: \.self) { action in
                        LabeledContent(action.title) {
                            HStack {
                                if controller.failedHotKeys.contains(action) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Palette.warning)
                                        .help("This shortcut is inactive: another action already uses it, or macOS refused it.")
                                        .accessibilityLabel("Shortcut inactive: duplicate or refused by macOS")
                                }
                                HotKeyRecorder(combo: Binding(
                                    get: { configStore.config.bindings[action] ?? nil },
                                    // Explicit nil preserves a cleared shortcut across reloads.
                                    set: { configStore.config.bindings[action] = .some($0) }
                                ))
                                .accessibilityLabel("\(action.title) shortcut")
                            }
                        }
                    }
                }
            }
            Section("Guidance") {
                DisclosureGroup("Desktop behavior & limitations") {
                    Text("""
                        Send to Desktop N uses the Nth normal Desktop on the focused window’s display, without switching Desktops or moving the cursor. This per-display order may differ from macOS’s global Desktop shortcut labels.

                        Previous/next-display shortcuts are unbound by default. They wrap through normal Desktop displays in physical order and follow the moved window. Fullscreen destinations are skipped.

                        Native moves use an unsupported macOS API and may stop working after a system update. Fully enabled SIP and end-to-end multi-display behavior still await validation. Shared-Spaces live tests were skipped.

                        Only Desktop switching uses macOS’s “Switch to Desktop N” shortcuts. Enable them in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.
                        """)
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("Keyboard layouts") {
                    Text("Shortcuts follow key positions on any keyboard layout; the config file names keys by their US-layout position. On some layouts, Option combinations type characters (for example, Option-L types @ on German keyboards). Rebind any shortcuts you need for typing.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var keepAwakeSettings: some View {
        Group {
            Section {
                Picker("Preferred duration", selection: preference(\.duration)) {
                    ForEach(KeepAwakeDuration.allCases, id: \.self) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                Picker("Preferred mode", selection: preference(\.mode)) {
                    ForEach(KeepAwakeMode.allCases, id: \.self) { mode in
                        Text(mode == .system ? "System only" : "System and display").tag(mode)
                    }
                }
            } header: {
                Text("Session Preferences")
            } footer: {
                Text("Changes apply when you next start Keep Awake. A running session is not changed.")
            }
            Section("How It Works") {
                Text("System only allows the display to sleep. System and display keeps both awake. Explicit sleep, lid closure, and macOS battery protections still apply.")
                    .foregroundStyle(.secondary)
                Text("Start, stop, and extend sessions from Momentum’s menu-bar popover. Keep Awake does not require tiling permissions.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSettings: some View {
        Group {
            Section {
                if manager.isTrusted {
                    Label("Tiling permissions granted", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    WarningLabel("Tiling permissions required")
                }
                Text("Allow Momentum under System Settings › Privacy & Security › Device Control and Data Access. Keep Awake works without these permissions.")
                    .foregroundStyle(.secondary)
                Button("Open Privacy & Security Settings") {
                    openSystemSettings("com.apple.settings.PrivacySecurity.extension")
                }
            } header: {
                Text("Permissions")
            }
            Section {
                Text(configStore.location.path)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open") { NSWorkspace.shared.open(configStore.location) }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([configStore.location])
                    }
                }
            } header: {
                Text("Configuration File")
            } footer: {
                Text("Changes save immediately. Momentum also reloads this JSON file when you edit it externally.")
            }
        }
    }

    private func warning(_ message: String) -> some View {
        WarningLabel(message)
            .textSelection(.enabled)
    }

    private func openSystemSettings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<KeepAwakePreferences, Value>) -> Binding<Value> {
        Binding(
            get: { configStore.config.keepAwake[keyPath: keyPath] },
            set: { value in
                var preferences = configStore.config.keepAwake
                preferences[keyPath: keyPath] = value
                // ConfigStore publishes the error and retains old preferences on failure.
                do { try configStore.updateKeepAwake(preferences) } catch {}
            }
        )
    }

    /// Keeps typed spacing within the range the config file accepts.
    private func spacing(_ keyPath: WritableKeyPath<Config, Double>) -> Binding<Double> {
        Binding(
            get: { configStore.config[keyPath: keyPath] },
            set: { configStore.config[keyPath: keyPath] = min(max($0, Config.spacingRange.lowerBound), Config.spacingRange.upperBound) }
        )
    }
}

/// An application bundle found in the standard Applications folders.
nonisolated struct InstalledApp: Identifiable, Hashable, Sendable {
    /// Bundle identifier.
    let id: String
    let name: String
    let url: URL

    /// Scans the Applications folders (and one level of subfolders, e.g. Utilities). Slow; call off the main thread.
    static func scan() -> [InstalledApp] {
        let fileManager = FileManager.default
        let roots = [
            URL(filePath: "/Applications"),
            URL(filePath: "/System/Applications"),
            fileManager.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
        var found: [String: InstalledApp] = [:]

        func visit(_ directory: URL, depth: Int) {
            let items = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
            for item in items {
                if item.pathExtension == "app" {
                    guard let id = Bundle(url: item)?.bundleIdentifier, found[id] == nil else { continue }
                    found[id] = InstalledApp(id: id, name: displayName(at: item), url: item)
                } else if depth == 0, (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    visit(item, depth: depth + 1)
                }
            }
        }

        roots.forEach { visit($0, depth: 0) }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Localized app name without the `.app` extension.
    static func displayName(at url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

private struct AppIcon: View {
    let url: URL?

    var body: some View {
        Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application))
            .resizable()
            .frame(width: Layout.rowIcon, height: Layout.rowIcon)
    }
}

/// Lists installed apps with checkboxes; checked apps are added to `selection`.
private struct AppPickerSheet: View {
    @Binding var selection: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var apps: [InstalledApp] = []
    @State private var search = ""

    private var filteredApps: [InstalledApp] {
        guard !search.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search", text: $search, prompt: Text("Search apps"))
                .textFieldStyle(.roundedBorder)
                .padding()

            List(filteredApps) { app in
                Toggle(isOn: isSelected(app)) {
                    HStack {
                        AppIcon(url: app.url)
                        Text(app.name)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .overlay {
                if apps.isEmpty { ProgressView() }
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: Layout.appPickerSize.width, height: Layout.appPickerSize.height)
        .task {
            apps = await Task.detached { InstalledApp.scan() }.value
        }
    }

    private func isSelected(_ app: InstalledApp) -> Binding<Bool> {
        Binding(
            get: { selection.contains(app.id) },
            set: { isOn in
                if isOn {
                    selection.append(app.id)
                } else {
                    selection.removeAll { $0 == app.id }
                }
            }
        )
    }
}

/// Click to record a new shortcut. Escape cancels, Delete clears the binding.
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo?

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "Press keys…" : (combo?.displayString ?? "None")) {
            isRecording ? stopRecording() : startRecording()
        }
        .frame(minWidth: Layout.shortcutMinWidth)
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53: // Escape
                break
            case 51: // Delete
                combo = nil
            default:
                guard let recorded = KeyCombo(event: event), !recorded.modifiers.isEmpty else { return nil }
                combo = recorded
            }
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
