import SwiftUI

/// Read the running app's metadata, not a hardcoded release version.
struct AppVersion {
    let version: String?
    let build: String?

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        version = Self.nonempty(info["CFBundleShortVersionString"] as? String)
        build = Self.nonempty(info["CFBundleVersion"] as? String)
    }

    var displayString: String {
        switch (version, build) {
        case let (version?, build?): "Version \(version) (\(build))"
        case let (version?, nil): "Version \(version)"
        case let (nil, build?): "Build \(build)"
        case (nil, nil): "Version unavailable"
        }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AppVersionLabel: View {
    var body: some View {
        Text(AppVersion().displayString)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}
