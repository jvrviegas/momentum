import AppKit
import Carbon.HIToolbox

/// Commands that can be bound to a hotkey.
enum Action: Hashable, CaseIterable, RawRepresentable, Codable, CodingKeyRepresentable {
    case focus(Direction)
    case move(Direction)
    case sendToDesktop(Int)
    case switchToDesktop(Int)
    case toggleFloat
    case retile

    static var allCases: [Action] {
        Direction.allCases.map(Action.focus)
            + Direction.allCases.map(Action.move)
            + (1...9).map(Action.sendToDesktop)
            + (1...9).map(Action.switchToDesktop)
            + [.toggleFloat, .retile]
    }

    init?(rawValue: String) {
        guard let action = Self.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = action
    }

    /// Identifier used as the key in the JSON config, e.g. `focus-left`.
    var rawValue: String {
        switch self {
        case .focus(let direction): "focus-\(direction.rawValue)"
        case .move(let direction): "move-\(direction.rawValue)"
        case .sendToDesktop(let number): "send-to-desktop-\(number)"
        case .switchToDesktop(let number): "switch-to-desktop-\(number)"
        case .toggleFloat: "toggle-float"
        case .retile: "retile"
        }
    }

    var title: String {
        switch self {
        case .focus(let direction): "Focus \(direction.rawValue)"
        case .move(let direction): "Move window \(direction.rawValue)"
        case .sendToDesktop(let number): "Send window to Desktop \(number)"
        case .switchToDesktop(let number): "Switch to Desktop \(number)"
        case .toggleFloat: "Toggle floating"
        case .retile: "Retile"
        }
    }
}

/// A key plus modifiers, stored in JSON as a readable string such as `alt+shift+h`.
struct KeyCombo: Hashable, Codable, CustomStringConvertible {
    enum Modifier: String, CaseIterable {
        case ctrl, alt, shift, cmd
    }

    var key: String
    var modifiers: Set<Modifier>

    init(key: String, modifiers: Set<Modifier>) {
        self.key = key
        self.modifiers = modifiers
    }

    init?(string: String) {
        let parts = string.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let key = parts.last, Self.keyCodes[key] != nil else { return nil }
        var modifiers: Set<Modifier> = []
        for part in parts.dropLast() {
            switch part {
            case "ctrl", "control": modifiers.insert(.ctrl)
            case "alt", "opt", "option": modifiers.insert(.alt)
            case "shift": modifiers.insert(.shift)
            case "cmd", "command": modifiers.insert(.cmd)
            default: return nil
            }
        }
        self.init(key: key, modifiers: modifiers)
    }

    /// Builds a combo from a key-down event, for the hotkey recorder.
    init?(event: NSEvent) {
        guard let key = Self.keyCodes.first(where: { $0.value == UInt32(event.keyCode) })?.key else { return nil }
        let flags = event.modifierFlags
        var modifiers: Set<Modifier> = []
        if flags.contains(.control) { modifiers.insert(.ctrl) }
        if flags.contains(.option) { modifiers.insert(.alt) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.cmd) }
        self.init(key: key, modifiers: modifiers)
    }

    init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let combo = KeyCombo(string: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid hotkey \"\(string)\""))
        }
        self = combo
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var description: String {
        (Modifier.allCases.filter(modifiers.contains).map(\.rawValue) + [key]).joined(separator: "+")
    }

    /// Symbolic form for display, e.g. `⌥⇧H`. `key` names a physical key by its US-layout position, so
    /// character keys show what they type on the current layout instead (e.g. `Z` on German for `y`).
    var displayString: String {
        let symbols: [Modifier: String] = [.ctrl: "⌃", .alt: "⌥", .shift: "⇧", .cmd: "⌘"]
        let label = keyCode.flatMap(Self.typedCharacter) ?? key
        return Modifier.allCases.filter(modifiers.contains).compactMap { symbols[$0] }.joined() + label.uppercased()
    }

    var keyCode: UInt32? { Self.keyCodes[key] }

    /// What `keyCode` types on the current keyboard layout without modifiers; nil for keys that don't
    /// type a visible character (space, return, arrows, function keys…), which keep their names.
    private static func typedCharacter(forKeyCode keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layout).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { bytes in
            UCKeyTranslate(bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
                           0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                           &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let typed = String(utf16CodeUnits: characters, count: length)
        let invisible = CharacterSet.controlCharacters.union(.whitespacesAndNewlines)
        return typed.unicodeScalars.contains(where: invisible.contains) ? nil : typed
    }

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.ctrl) { result |= controlKey }
        if modifiers.contains(.alt) { result |= optionKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.cmd) { result |= cmdKey }
        return UInt32(result)
    }

    static let keyCodes: [String: UInt32] = {
        let pairs: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D), ("e", kVK_ANSI_E),
            ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I), ("j", kVK_ANSI_J),
            ("k", kVK_ANSI_K), ("l", kVK_ANSI_L), ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X), ("y", kVK_ANSI_Y),
            ("z", kVK_ANSI_Z),
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3), ("4", kVK_ANSI_4),
            ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
            ("space", kVK_Space), ("return", kVK_Return), ("tab", kVK_Tab), ("escape", kVK_Escape),
            ("delete", kVK_Delete), ("left", kVK_LeftArrow), ("right", kVK_RightArrow),
            ("up", kVK_UpArrow), ("down", kVK_DownArrow),
            ("minus", kVK_ANSI_Minus), ("equal", kVK_ANSI_Equal), ("leftbracket", kVK_ANSI_LeftBracket),
            ("rightbracket", kVK_ANSI_RightBracket), ("semicolon", kVK_ANSI_Semicolon), ("quote", kVK_ANSI_Quote),
            ("comma", kVK_ANSI_Comma), ("period", kVK_ANSI_Period), ("slash", kVK_ANSI_Slash),
            ("backslash", kVK_ANSI_Backslash), ("grave", kVK_ANSI_Grave),
            ("f1", kVK_F1), ("f2", kVK_F2), ("f3", kVK_F3), ("f4", kVK_F4), ("f5", kVK_F5), ("f6", kVK_F6),
            ("f7", kVK_F7), ("f8", kVK_F8), ("f9", kVK_F9), ("f10", kVK_F10), ("f11", kVK_F11), ("f12", kVK_F12),
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, UInt32($0.1)) })
    }()
}

/// User configuration, persisted as JSON. Missing keys fall back to defaults so the file can be partially edited.
struct Config: Codable, Equatable {
    var gap: Double = 8
    var outerPadding: Double = 8
    var animationsEnabled = true
    var floatingBundleIDs: [String] = ["com.apple.systempreferences"]
    /// A `nil` value means the user explicitly unbound the action (stored as `null` in JSON).
    var bindings: [Action: KeyCombo?] = Config.defaultBindings

    static let defaultBindings: [Action: KeyCombo?] = {
        let keys: [Direction: String] = [.left: "h", .down: "j", .up: "k", .right: "l"]
        var bindings: [Action: KeyCombo?] = [:]
        for (direction, key) in keys {
            bindings[.focus(direction)] = KeyCombo(key: key, modifiers: [.alt])
            bindings[.move(direction)] = KeyCombo(key: key, modifiers: [.alt, .shift])
        }
        for number in 1...9 {
            bindings[.sendToDesktop(number)] = KeyCombo(key: "\(number)", modifiers: [.alt, .shift])
            bindings[.switchToDesktop(number)] = KeyCombo(key: "\(number)", modifiers: [.alt])
        }
        bindings[.toggleFloat] = KeyCombo(key: "space", modifiers: [.alt, .shift])
        bindings[.retile] = KeyCombo(key: "r", modifiers: [.alt, .shift])
        return bindings
    }()

    /// Allowed values for `gap` and `outerPadding`, in points.
    static let spacingRange: ClosedRange<Double> = 0...100

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config()
        // Out-of-range spacing fails like an invalid hotkey, so the previous config stays in effect.
        func spacing(_ key: CodingKeys) throws -> Double? {
            guard let value = try container.decodeIfPresent(Double.self, forKey: key) else { return nil }
            guard Self.spacingRange.contains(value) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription:
                    "\"\(key.stringValue)\" must be between \(Int(Self.spacingRange.lowerBound)) and \(Int(Self.spacingRange.upperBound))")
            }
            return value
        }
        gap = try spacing(.gap) ?? defaults.gap
        outerPadding = try spacing(.outerPadding) ?? defaults.outerPadding
        animationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .animationsEnabled) ?? defaults.animationsEnabled
        floatingBundleIDs = try container.decodeIfPresent([String].self, forKey: .floatingBundleIDs) ?? defaults.floatingBundleIDs
        let decodedBindings = try container.decodeIfPresent([Action: KeyCombo?].self, forKey: .bindings) ?? [:]
        // Actions missing from the file (e.g. added in a newer version) get their default hotkey.
        bindings = defaults.bindings.merging(decodedBindings) { _, decoded in decoded }
    }
}
