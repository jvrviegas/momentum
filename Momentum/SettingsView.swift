import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var configStore: ConfigStore
    let manager: TilingManager

    @State private var newBundleID = ""
    @State private var isPickingApps = false

    var body: some View {
        Form {
            if !manager.isTrusted {
                Section {
                    Label("Grant Accessibility access in System Settings › Privacy & Security › Accessibility.",
                          systemImage: "exclamationmark.triangle")
                }
            }
            if let error = configStore.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Layout") {
                TextField("Gap between windows", value: $configStore.config.gap, format: .number)
                TextField("Screen padding", value: $configStore.config.outerPadding, format: .number)
            }

            Section("Floating apps") {
                ForEach(configStore.config.floatingBundleIDs, id: \.self) { bundleID in
                    let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                    HStack {
                        AppIcon(url: appURL)
                        VStack(alignment: .leading) {
                            Text(appURL.map(InstalledApp.displayName) ?? bundleID)
                            Text(bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") {
                            configStore.config.floatingBundleIDs.removeAll { $0 == bundleID }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Bundle identifier", text: $newBundleID, prompt: Text("com.example.app"))
                    Button("Add") {
                        configStore.config.floatingBundleIDs.append(newBundleID)
                        newBundleID = ""
                    }
                    .disabled(newBundleID.isEmpty || configStore.config.floatingBundleIDs.contains(newBundleID))
                }
                Button("Choose Apps…") { isPickingApps = true }
            }
            .sheet(isPresented: $isPickingApps) {
                AppPickerSheet(selection: $configStore.config.floatingBundleIDs)
            }

            Section {
                ForEach(Action.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        HotKeyRecorder(combo: Binding(
                            get: { configStore.config.bindings[action] ?? nil },
                            // Store nil explicitly so a cleared hotkey isn't replaced by its default on reload.
                            set: { configStore.config.bindings[action] = .some($0) }
                        ))
                    }
                }
            } header: {
                Text("Hotkeys")
            } footer: {
                Text("Sending windows to a Desktop requires the \"Switch to Desktop N\" shortcuts (⌃1–⌃9) to be enabled in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.")
            }

            Section {
                HStack {
                    Text(ConfigStore.fileURL.path)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button("Open") { NSWorkspace.shared.open(ConfigStore.fileURL) }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.fileURL]) }
                }
            } header: {
                Text("Config file")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 600)
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
            .frame(width: 20, height: 20)
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
        .frame(width: 420, height: 520)
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
        .frame(minWidth: 100)
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
