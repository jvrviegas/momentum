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

    /// Save before native completion, but publish only after both succeed. A failed
    /// completion restores the previous file without exposing the candidate to observers.
    func updateKeepAwake(_ preferences: KeepAwakePreferences, committing: () throws -> Void = {}) throws {
        let previous = config
        var candidate = previous
        candidate.keepAwake = preferences
        let changed = candidate != previous
        do {
            if changed { try write(candidate) }
            do { try committing() }
            catch {
                let completionError = error
                if changed {
                    do { try write(previous) }
                    catch {
                        throw NSError(domain: "Momentum.ConfigStore", code: 1, userInfo: [NSLocalizedDescriptionKey:
                            "\(completionError.localizedDescription) Couldn't restore \(location.lastPathComponent): \(error.localizedDescription)"])
                    }
                }
                throw completionError
            }
            lastError = nil
            isReloading = true
            config = candidate
            isReloading = false
        } catch {
            lastError = "Couldn't update Keep Awake in \(location.lastPathComponent): \(error.localizedDescription)"
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
                guard let self, !self.isShutdown, let event = self.watcher?.data else { return }
                if isFilePresent {
                    self.fileChanged(event)
                } else if FileManager.default.fileExists(atPath: self.location.path) {
                    self.reload()
                    self.startWatching()
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
