import ApplicationServices

enum Permissions {
    /// Prompts for Accessibility access if needed and waits until it's granted.
    static func waitForAccessibility() async {
        // The value of `kAXTrustedCheckOptionPrompt`, which Swift 6 rejects as a mutable global.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(options) else { return }
        while !AXIsProcessTrusted() {
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
