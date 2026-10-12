import Testing
@testable import Momentum

@MainActor
struct AppVersionTests {
    @Test func includesVersionAndBuild() {
        let version = AppVersion(info: ["CFBundleShortVersionString": "0.5.0", "CFBundleVersion": "7"])
        #expect(version.displayString == "Version 0.5.0 (7)")
    }

    @Test func handlesMissingMetadataWithoutInventingAVersion() {
        #expect(AppVersion(info: [:]).displayString == "Version unavailable")
        #expect(AppVersion(info: ["CFBundleShortVersionString": "0.5.0"]).displayString == "Version 0.5.0")
        #expect(AppVersion(info: ["CFBundleVersion": "7"]).displayString == "Build 7")
        #expect(AppVersion(info: ["CFBundleShortVersionString": " ", "CFBundleVersion": ""]).displayString == "Version unavailable")
    }

    @Test func readsTheRunningAppBundle() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(AppVersion().version == info["CFBundleShortVersionString"] as? String)
        #expect(AppVersion().build == info["CFBundleVersion"] as? String)
    }
}
