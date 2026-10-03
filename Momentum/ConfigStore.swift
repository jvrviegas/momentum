import Foundation
import Observation

/// Loads and saves `~/.config/momentum/tiling.json`, and reloads it live when it's edited by hand.
@Observable final class ConfigStore {
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/momentum/tiling.json")

    var config = Config() {
        didSet {
            guard config != oldValue else { return }
            if !isReloading { save() }
            onChange?(config)
        }
    }

    /// Set when the file on disk can't be parsed; the previous config stays in effect.
    private(set) var lastError: String?

    @ObservationIgnored var onChange: ((Config) -> Void)?
    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    init() {
        if FileManager.default.fileExists(atPath: Self.fileURL.path) {
            reload()
        } else {
            save()
        }
        startWatching()
    }

    private func reload() {
        do {
            let data = try Data(contentsOf: Self.fileURL)
            let decoded = try JSONDecoder().decode(Config.self, from: data)
            lastError = nil
            isReloading = true
            config = decoded
            isReloading = false
        } catch {
            lastError = "Couldn't read \(Self.fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: Self.fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "Couldn't save \(Self.fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func startWatching() {
        watcher?.cancel()
        // While the file is missing (deleted, or an editor is slow to replace it), watch its folder for it to come back.
        let isFilePresent = FileManager.default.fileExists(atPath: Self.fileURL.path)
        let watchedURL = isFilePresent ? Self.fileURL : Self.fileURL.deletingLastPathComponent()
        let descriptor = open(watchedURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            let event = source.data
            MainActor.assumeIsolated {
                if isFilePresent {
                    self?.fileChanged(event)
                } else if FileManager.default.fileExists(atPath: Self.fileURL.path) {
                    self?.reload()
                    self?.startWatching()
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func fileChanged(_ event: DispatchSource.FileSystemEvent) {
        if event.contains(.delete) || event.contains(.rename) {
            // Editors and atomic writes replace the file, so watch the new one once it exists.
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                reload()
                startWatching()
            }
        } else {
            reload()
        }
    }
}
