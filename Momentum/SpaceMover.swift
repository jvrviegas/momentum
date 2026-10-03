import CoreGraphics
import Foundation

/// Moves a window to another native Desktop without private APIs: it holds the window by its
/// title bar and triggers the system "Switch to Desktop N" shortcut, so macOS carries the window along.
/// Requires those shortcuts to be turned on in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.
enum SpaceMover {
    typealias Shortcut = (keyCode: CGKeyCode, flags: CGEventFlags)

    static func move(_ window: AXWindow, toDesktop number: Int) async {
        guard let shortcut = desktopShortcut(number), let point = window.titleBarGrabPoint else { return }

        await waitForModifierRelease()

        let source = CGEventSource(stateID: .hidSystemState)
        let originalCursor = CGEvent(source: nil)?.location
        let dragPoint = CGPoint(x: point.x, y: point.y + 2)

        // A press alone is a click; macOS only carries the window across Desktops once it's being dragged.
        postMouse(.mouseMoved, at: point, source: source)
        postMouse(.leftMouseDown, at: point, source: source)
        try? await Task.sleep(for: .milliseconds(50))
        postMouse(.leftMouseDragged, at: dragPoint, source: source)
        try? await Task.sleep(for: .milliseconds(50))

        post(shortcut, source: source)

        // Keep holding the window while the Desktop switch animation runs.
        try? await Task.sleep(for: .milliseconds(400))
        postMouse(.leftMouseUp, at: dragPoint, source: source)

        if let originalCursor {
            CGWarpMouseCursorPosition(originalCursor)
        }
    }

    /// Switches to Desktop `number` by triggering the system "Switch to Desktop N" shortcut.
    static func switchTo(desktop number: Int) async {
        guard let shortcut = desktopShortcut(number) else { return }
        // A private event source isn't combined with the keys the user is still holding,
        // so this can fire immediately without waiting for the hotkey's modifiers to be released.
        post(shortcut, source: CGEventSource(stateID: .privateState))
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

    /// The hotkey that triggered the move is usually still held; its modifiers would turn the
    /// synthetic click and Ctrl+N into different shortcuts. Waits up to a second for them to be released.
    private static func waitForModifierRelease() async {
        let modifiers: CGEventFlags = [.maskAlternate, .maskShift, .maskCommand, .maskControl]
        for _ in 0..<50 {
            if CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func postMouse(_ type: CGEventType, at point: CGPoint, source: CGEventSource?) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.flags = []
        event?.post(tap: .cghidEventTap)
    }
}
