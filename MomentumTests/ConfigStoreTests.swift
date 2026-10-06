import Foundation
import Testing
@testable import Momentum

@MainActor
final class TemporaryConfig {
    let directory = FileManager.default.temporaryDirectory.appending(path: "momentum-tests-\(UUID())")
    let store: ConfigStore

    init(watching: Bool = false) {
        store = ConfigStore(fileURL: directory.appending(path: "tiling.json"), watching: watching)
    }

    func cleanup() {
        store.shutdown()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
struct ConfigStoreTests {
    @Test func preferencesDecodeStrictlyAndRoundTrip() throws {
        for json in ["{}", #"{"keepAwake":{}}"#] {
            let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
            #expect(config.keepAwake == KeepAwakePreferences())
            #expect(config.bindings[.toggleKeepAwake] == nil)
        }
        for duration in KeepAwakeDuration.allCases {
            for mode in KeepAwakeMode.allCases {
                var config = Config()
                config.keepAwake = .init(duration: duration, mode: mode)
                #expect(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config)) == config)
            }
        }
        for value in ["null", "false", "3", #"{"duration":null}"#, #"{"mode":null}"#,
                      #"{"duration":"3h"}"#, #"{"mode":"invalid"}"#, #"{"duration":10}"#] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(Config.self, from: Data("{\"keepAwake\":\(value)}".utf8))
            }
        }
        #expect(Action(rawValue: "toggle-keep-awake") == .toggleKeepAwake)
        #expect(Action.allCases.last == .toggleKeepAwake)
        #expect(Action.toggleKeepAwake.title == "Toggle Keep Awake")
        let unbound = try JSONDecoder().decode(Config.self, from: Data(#"{"bindings":{"toggle-keep-awake":null}}"#.utf8))
        #expect(unbound.bindings[.toggleKeepAwake] == .some(nil))
        let bound = try JSONDecoder().decode(Config.self, from: Data(#"{"bindings":{"toggle-keep-awake":"ctrl+alt+a"}}"#.utf8))
        #expect(try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(bound)) == bound)
    }

    @Test func saveBeforePublishAndFailedReloadRetainsAllConfig() throws {
        let fixture = TemporaryConfig()
        defer { fixture.cleanup() }
        let store = fixture.store
        var changes = 0
        store.onChange = { _ in changes += 1 }
        let preferences = KeepAwakePreferences(duration: .eightHours, mode: .systemAndDisplay)
        try store.updateKeepAwake(preferences)
        #expect(changes == 1)
        let next = ConfigStore(fileURL: store.location, watching: false)
        defer { next.shutdown() }
        #expect(next.config.keepAwake == preferences)
        let before = store.config
        try Data(#"{"gap":25,"keepAwake":{"mode":null}}"#.utf8).write(to: store.location, options: .atomic)
        store.reload()
        #expect(store.config == before)
        #expect(store.lastError != nil)
        #expect(changes == 1)
        try Data(#"{"gap":25,"bindings":{"toggle-keep-awake":"bad"}}"#.utf8).write(to: store.location)
        store.reload()
        #expect(store.config == before)
        try FileManager.default.removeItem(at: fixture.directory)
        try Data().write(to: fixture.directory) // Parent is now a file: deterministic save failure.
        #expect(throws: (any Error).self) { try store.updateKeepAwake(.init()) }
        #expect(store.config == before)
        #expect(store.lastError != nil)
        #expect(changes == 1)
    }

    @Test func synchronousReloadNotifiesExistingEdits() throws {
        let fixture = TemporaryConfig()
        defer { fixture.cleanup() }
        var changes = 0
        fixture.store.onChange = { _ in changes += 1 }
        fixture.store.config.gap = 14
        #expect(changes == 1)
        try Data(#"{"gap":19,"keepAwake":{"duration":"1h"}}"#.utf8).write(to: fixture.store.location, options: .atomic)
        fixture.store.reload()
        #expect(changes == 2)
        #expect(fixture.store.config.gap == 19)
        #expect(fixture.store.config.keepAwake.duration == .oneHour)
    }

    @Test func watcherReloadsAtomicReplacementAndRejectsInvalidEdit() async throws {
        let fixture = TemporaryConfig(watching: true)
        defer { fixture.cleanup() }
        try Data(#"{"keepAwake":{"mode":"system-and-display"}}"#.utf8).write(to: fixture.store.location, options: .atomic)
        for _ in 0..<50 {
            if fixture.store.config.keepAwake.mode == .systemAndDisplay { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fixture.store.config.keepAwake.mode == .systemAndDisplay)
        let before = fixture.store.config
        try Data(#"{"keepAwake":null}"#.utf8).write(to: fixture.store.location, options: .atomic)
        for _ in 0..<50 {
            if fixture.store.lastError != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fixture.store.lastError != nil)
        #expect(fixture.store.config == before)
    }
}
