import CoreGraphics

/// Moves a window to another native Desktop without private APIs: it holds the window by its
/// title bar and triggers the system "Switch to Desktop N" shortcut (Ctrl+N), so macOS carries the
/// window along. Requires those shortcuts to be enabled in System Settings › Keyboard › Keyboard Shortcuts › Mission Control.
enum SpaceMover {
    static func move(_ window: AXWindow, toDesktop number: Int) async {
        guard (1...9).contains(number),
              let point = window.titleBarGrabPoint,
              let keyCode = KeyCombo(key: "\(number)", modifiers: []).keyCode else { return }

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

        postDesktopShortcut(keyCode, source: source)

        // Keep holding the window while the Desktop switch animation runs.
        try? await Task.sleep(for: .milliseconds(400))
        postMouse(.leftMouseUp, at: dragPoint, source: source)

        if let originalCursor {
            CGWarpMouseCursorPosition(originalCursor)
        }
    }

    /// Switches to Desktop `number` by triggering the system "Switch to Desktop N" shortcut.
    static func switchTo(desktop number: Int) async {
        guard (1...9).contains(number),
              let keyCode = KeyCombo(key: "\(number)", modifiers: []).keyCode else { return }
        // A private event source isn't combined with the keys the user is still holding,
        // so this can fire immediately without waiting for the hotkey's modifiers to be released.
        postDesktopShortcut(keyCode, source: CGEventSource(stateID: .privateState))
    }

    /// Posts Ctrl+`keyCode`. Explicit flags so modifiers still held from our hotkey don't leak in.
    private static func postDesktopShortcut(_ keyCode: UInt32, source: CGEventSource?) {
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
            event?.flags = .maskControl
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
