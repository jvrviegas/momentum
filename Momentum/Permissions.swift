import ApplicationServices

enum Permissions {
    /// Prompts for Accessibility access if needed and waits until it's granted.
    static func waitForAccessibility() async {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(options) else { return }
        while !AXIsProcessTrusted() {
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
