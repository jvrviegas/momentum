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

    let location: URL
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var isShutdown = false

    init(fileURL: URL = ConfigStore.fileURL, watching: Bool = true) {
        location = fileURL
        if FileManager.default.fileExists(atPath: location.path) {
            reload()
        } else {
            save()
        }
        if watching { startWatching() }
    }

    func shutdown() {
        isShutdown = true
        reloadTask?.cancel()
        reloadTask = nil
        watcher?.cancel()
        watcher = nil
        onChange = nil
    }

    /// Keep Awake controls publish only after the candidate has been atomically saved.
    func updateKeepAwake(_ preferences: KeepAwakePreferences) throws {
        var candidate = config
        candidate.keepAwake = preferences
        guard candidate != config else { return }
        do {
            try write(candidate)
            lastError = nil
            isReloading = true
            config = candidate
            isReloading = false
        } catch {
            lastError = "Couldn't save \(location.lastPathComponent): \(error.localizedDescription)"
            throw error
        }
    }

    func reload() {
        do {
            let data = try Data(contentsOf: location)
            let decoded = try JSONDecoder().decode(Config.self, from: data)
            lastError = nil
            isReloading = true
            config = decoded
            isReloading = false
        } catch {
            lastError = "Couldn't read \(location.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try write(config)
            lastError = nil
        } catch {
            lastError = "Couldn't save \(location.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func write(_ candidate: Config) throws {
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(candidate).write(to: location, options: .atomic)
    }

    private func startWatching() {
        guard !isShutdown else { return }
        watcher?.cancel()
        // While the file is missing (deleted, or an editor is slow to replace it), watch its folder for it to come back.
        let isFilePresent = FileManager.default.fileExists(atPath: location.path)
        let watchedURL = isFilePresent ? location : location.deletingLastPathComponent()
        let descriptor = open(watchedURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !isShutdown, let event = watcher?.data else { return }
                if isFilePresent {
                    fileChanged(event)
                } else if FileManager.default.fileExists(atPath: location.path) {
                    reload()
                    startWatching()
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
            reloadTask?.cancel()
            reloadTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, !isShutdown else { return }
                reload()
                startWatching()
            }
        } else {
            reload()
        }
    }
}
