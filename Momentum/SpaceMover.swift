import AppKit

/// Sends windows directly through SkyLight; only Desktop switching uses system shortcuts.
enum SpaceMover {
    typealias Shortcut = (keyCode: CGKeyCode, flags: CGEventFlags)

    enum MoveError: LocalizedError, Equatable {
        case desktopUnavailable(Int)
        case nativeOperationUnavailable
        case windowUnavailable
        case timedOut

        var errorDescription: String? {
            switch self {
            case .desktopUnavailable(let number): "Desktop \(number) isn't available on this window's display."
            case .nativeOperationUnavailable: "Native Desktop moves aren't available on this macOS build."
            case .windowUnavailable: "The window is no longer available."
            case .timedOut: "macOS didn't confirm the Desktop move. Try again."
            }
        }
    }

    static func move(_ window: AXWindow, toDesktop number: Int) async throws {
        guard let target = Spaces.desktopSpace(number) else { throw MoveError.desktopUnavailable(number) }
        try await move(windowID: window.id, toSpace: target)
    }

    /// The asynchronous private operation has no documented success result. Verify membership
    /// before the caller changes layout state. Dependencies allow tests without moving real windows.
    static func move(
        windowID: WindowID, toSpace target: SpaceID,
        request: (WindowID, SpaceID) -> Bool = { MomentumRequestNativeSpaceMove($0, $1) },
        membership: (WindowID) -> SpaceID? = { Spaces.space(for: $0) },
        wait: () async throws -> Void = { try await Task.sleep(for: .milliseconds(20)) }
    ) async throws {
        try Task.checkCancellation()
        guard let source = membership(windowID) else { throw MoveError.windowUnavailable }
        guard source != target else { return }
        guard request(windowID, target) else { throw MoveError.nativeOperationUnavailable }
        for _ in 0..<100 {
            try Task.checkCancellation()
            guard let current = membership(windowID) else { throw MoveError.windowUnavailable }
            if current == target { return }
            try await wait()
        }
        // Check once more after the final wait, before reporting a timeout.
        try Task.checkCancellation()
        if membership(windowID) == target { return }
        throw MoveError.timedOut
    }

    enum SwitchResult: Equatable {
        case completed
        case unchecked
        case shortcutUnavailable
        case timedOut
        case cancelled
    }

    /// Switches using the system shortcut. Recovery must never silently restart the Dock:
    /// terminating it restores minimized windows on some macOS builds.
    static func switchTo(desktop number: Int) async -> SwitchResult {
        guard let shortcut = desktopShortcut(number) else { return .shortcutUnavailable }
        // A private event source isn't combined with the keys the user is still holding,
        // so this can fire immediately without waiting for the hotkey's modifiers to be released.
        let source = CGEventSource(stateID: .privateState)
        return await switchTo(Spaces.desktopSpace(number), send: { post(shortcut, source: source) })
    }

    /// Dependencies allow tests without switching real Desktops.
    static func switchTo(
        _ target: SpaceID?,
        send: () -> Void,
        currentSpaces: () -> Set<SpaceID> = { Spaces.currentSpaces },
        wait: () async -> Void = { try? await Task.sleep(for: .milliseconds(50)) }
    ) async -> SwitchResult {
        guard !Task.isCancelled else { return .cancelled }
        let before = currentSpaces()
        send()
        // Unknown membership cannot prove failure; don't retry or report a false timeout.
        guard let target else { return .unchecked }
        guard !before.contains(target) else { return .completed }
        // Bounded, non-destructive retries. Any display changing counts because Mission Control
        // may number Desktops across displays. Stop if the user switches elsewhere too.
        for attempt in 0..<3 {
            if attempt > 0 {
                guard !Task.isCancelled else { return .cancelled }
                if currentSpaces() != before { return .completed }
                send()
            }
            for _ in 0..<20 {
                await wait()
                guard !Task.isCancelled else { return .cancelled }
                if currentSpaces() != before { return .completed }
            }
        }
        return .timedOut
    }

    /// Explicit user-confirmed recovery only. Restores minimized windows on some macOS builds.
    /// Quits the Dock, as `killall Dock` does, and waits until launchd's relaunch has finished launching.
    static func restartDock() async -> Bool {
        let bundleID = "com.apple.dock"
        guard let old = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier,
              kill(old, SIGTERM) == 0 else { return false }
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .contains(where: { $0.processIdentifier != old && $0.isFinishedLaunching }) {
                // It can report this before loading Desktops, which took up to ~350 ms when measured.
                try? await Task.sleep(for: .milliseconds(500))
                return true
            }
        }
        return false
    }

    /// The user's "Switch to Desktop `number`" shortcut, or nil if it's turned off. When the user has never
    /// changed these shortcuts, the settings have no entry and the default ⌃`number` is used.
    static func desktopShortcut(
        _ number: Int,
        symbolicHotKeys: [String: Any]? = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
    ) -> Shortcut? {
        guard (1...9).contains(number) else { return nil }
        // Entries 118–126 are "Switch to Desktop 1–9".
        guard let entry = symbolicHotKeys?[String(117 + number)] as? [String: Any] else {
            return KeyCombo(key: "\(number)", modifiers: []).keyCode.map { (CGKeyCode($0), .maskControl) }
        }
        // Parameters are (character, key code, modifier flags); the flags use the same bits as CGEventFlags.
        guard entry["enabled"] as? Bool == true,
              let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int],
              parameters.count == 3 else { return nil }
        return (CGKeyCode(parameters[1]), CGEventFlags(rawValue: UInt64(parameters[2])))
    }

    /// Posts `shortcut` with explicit flags so modifiers still held from our hotkey don't leak in.
    private static func post(_ shortcut: Shortcut, source: CGEventSource?) {
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: keyDown)
            event?.flags = shortcut.flags
            event?.post(tap: .cghidEventTap)
        }
    }
}
