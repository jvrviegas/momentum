import Carbon.HIToolbox

/// Registers system-wide hotkeys through Carbon's `RegisterEventHotKey`.
final class HotKeyManager: HotKeyRegistration {
    var onAction: ((Action) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: Action] = [:]
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4D_54_4C_52 // 'MTLR'

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Replaces all registered hotkeys. Returns the actions whose combo wasn't registered, because an
    /// earlier action (in `Action.allCases` order) already uses it or the system refused it.
    @discardableResult
    func register(_ bindings: [Action: KeyCombo?]) -> Set<Action> {
        unregisterAll()
        var failed: Set<Action> = []
        var used: Set<KeyCombo> = []
        for (index, action) in Action.allCases.enumerated() {
            guard let combo = bindings[action] ?? nil, let keyCode = combo.keyCode else { continue }
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            var ref: EventHotKeyRef?
            if used.insert(combo).inserted,
               RegisterEventHotKey(keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                hotKeyRefs.append(ref)
                actions[UInt32(index)] = action
            } else {
                failed.insert(action)
            }
        }
        return failed
    }

    func unregisterAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }

    func shutdown() {
        unregisterAll()
        onAction = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    fileprivate func handle(_ id: UInt32) {
        if let action = actions[id] { onAction?(action) }
    }
}

/// Carbon delivers hotkey events on the main thread.
private nonisolated func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        manager.handle(id)
    }
    return noErr
}
