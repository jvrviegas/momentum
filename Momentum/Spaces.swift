import AppKit

typealias SpaceID = UInt64

/// Reads native Space membership and Desktop order through the private bridge.
enum Spaces {
    private nonisolated static let allSpacesMask: Int32 = 0x7

    /// The Space currently shown on the main display.
    static var mainDisplaySpace: SpaceID {
        let connection = CGSMainConnectionID()
        if let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue(),
           let uuidString = CFUUIDCreateString(nil, uuid) {
            let space = CGSManagedDisplayGetCurrentSpace(connection, uuidString)
            if space != 0 { return space }
        }
        // Falls back when "Displays have separate Spaces" is off.
        return CGSGetActiveSpace(connection)
    }

    /// The Space currently shown on each display.
    static var currentSpaces: Set<SpaceID> {
        let managed = MomentumCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? []
        return Set(managed.compactMap { (($0["Current Space"] as? [String: Any])?["id64"] as? NSNumber)?.uint64Value })
    }

    /// Desktop numbers follow Mission Control order, excluding fullscreen Spaces.
    static func desktopSpace(_ number: Int) -> SpaceID? {
        guard let managed = MomentumCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] else { return nil }
        var identifier: String?
        if let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue() {
            identifier = CFUUIDCreateString(nil, uuid) as String?
        }
        return desktopSpace(number, in: managed, displayIdentifier: identifier, currentSpace: mainDisplaySpace)
    }

    /// Pure snapshot parsing, also handles "Displays have separate Spaces" being off.
    static func desktopSpace(_ number: Int, in managed: [[String: Any]],
                             displayIdentifier: String?, currentSpace: SpaceID) -> SpaceID? {
        guard (1...9).contains(number) else { return nil }
        let display = managed.first {
            guard let displayIdentifier else { return false }
            return ($0["Display Identifier"] as? String) == displayIdentifier
        }
            ?? managed.first { entry in
                (entry["Spaces"] as? [[String: Any]])?.contains {
                    ($0["id64"] as? NSNumber)?.uint64Value == currentSpace
                } == true
            }
        guard let spaces = display?["Spaces"] as? [[String: Any]] else { return nil }
        let desktops = spaces.filter { ($0["type"] as? NSNumber)?.intValue == 0 }
        guard desktops.indices.contains(number - 1),
              let id = desktops[number - 1]["id64"] as? NSNumber, id.uint64Value != 0 else { return nil }
        return id.uint64Value
    }

    /// Parsed fixture contract, not a live mapping guarantee. Native callers remain unchanged until T1.
    struct DisplaySnapshot: Equatable {
        let identifier: String
        let activeSpace: DisplayTopology.ActiveSpace?
        let desktopSpaces: [SpaceID]
    }

    /// Strict display-local parsing: unlike the legacy main-display resolver, never falls back
    /// to a different display. Shared mode must explicitly provide a normalized shared snapshot.
    static func displaySnapshot(for identifier: String, in managed: [[String: Any]]) -> DisplaySnapshot? {
        guard !identifier.isEmpty else { return nil }
        let matches = managed.filter { ($0["Display Identifier"] as? String) == identifier }
        guard matches.count == 1, let entry = matches.first,
              let spaces = entry["Spaces"] as? [[String: Any]] else { return nil }
        var kinds: [SpaceID: DisplayTopology.SpaceKind] = [:]
        var types: [SpaceID: Int] = [:]
        var desktops: [SpaceID] = []
        for space in spaces {
            guard let id = snapshotSpaceID(space["id64"]), kinds[id] == nil,
                  let type = snapshotSpaceType(space["type"]) else { return nil }
            types[id] = type
            let kind: DisplayTopology.SpaceKind
            switch type {
            case 0: kind = .normal
            case 4: kind = .fullscreen
            default: kind = .unknown
            }
            kinds[id] = kind
            if kind == .normal { desktops.append(id) }
        }
        var active: DisplayTopology.ActiveSpace?
        if let current = entry["Current Space"] as? [String: Any],
           let id = snapshotSpaceID(current["id64"]), let kind = kinds[id] {
            // Missing type is compatible with existing fixtures. A supplied type must be valid
            // and agree exactly; an inconsistent snapshot must never make a display eligible.
            if current["type"] == nil || snapshotSpaceType(current["type"]) == types[id] {
                active = .init(id: id, kind: kind)
            }
        }
        return DisplaySnapshot(identifier: identifier, activeSpace: active, desktopSpaces: desktops)
    }

    /// Explicit normalized input also supports shared Spaces without guessing its private snapshot schema.
    static func desktopSpace(_ number: Int, in display: DisplaySnapshot) -> SpaceID? {
        guard (1...9).contains(number), display.desktopSpaces.indices.contains(number - 1) else { return nil }
        let id = display.desktopSpaces[number - 1]
        return id == 0 ? nil : id
    }

    private static func snapshotSpaceType(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number == NSNumber(value: number.intValue) else { return nil }
        return number.intValue
    }

    private static func snapshotSpaceID(_ value: Any?) -> SpaceID? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let id = number.uint64Value
        guard id != 0, number == NSNumber(value: id) else { return nil }
        return id
    }

    struct ScreenInput {
        let id: DisplayID
        let identifier: String
        let frame: CGRect
        let visibleFrame: CGRect
    }

    struct DisplayInventory {
        let topology: DisplayTopology
        let desktops: [DisplayID: DisplaySnapshot]
    }

    /// One consistent set of screen geometry and managed-Space records per refresh/command.
    static func displayInventory() -> DisplayInventory {
        let screens = NSScreen.screens
        guard let primary = screens.first else {
            return DisplayInventory(topology: DisplayTopology(displays: []), desktops: [:])
        }
        let inputs = screens.compactMap { screen -> ScreenInput? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
            return ScreenInput(id: number.uint32Value, identifier: CFUUIDCreateString(nil, uuid) as String,
                               frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
        let managed = MomentumCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? []
        return inventory(screens: inputs, primaryFrame: primary.frame, managed: managed,
                         separateSpaces: NSScreen.screensHaveSeparateSpaces, sharedSpace: CGSGetActiveSpace(CGSMainConnectionID()))
    }

    /// One display's geometry and the Space it shows now. Unlike `displayInventory` it doesn't read every
    /// Desktop, so it's cheap enough for every animation frame. The Space's kind is reported as unknown.
    static func display(_ id: DisplayID) -> DisplayTopology.Display? {
        let screens = NSScreen.screens
        guard let primary = screens.first, let screen = screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }) else { return nil }
        let connection = CGSMainConnectionID()
        var space = CGSGetActiveSpace(connection)
        if NSScreen.screensHaveSeparateSpaces {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
                  let identifier = CFUUIDCreateString(nil, uuid) else { return nil }
            space = CGSManagedDisplayGetCurrentSpace(connection, identifier)
        }
        return .init(id: id, frame: DisplayTopology.axFrame(fromAppKit: screen.frame, primaryFrame: primary.frame),
                     usableFrame: DisplayTopology.axFrame(fromAppKit: screen.visibleFrame, primaryFrame: primary.frame),
                     activeSpace: space == 0 ? nil : .init(id: space, kind: .unknown))
    }

    /// Shared mode reuses the legacy active-Space matching strategy, but accepts only an
    /// unambiguous normalized snapshot. Its live OS shape remains unvalidated, not guessed.
    static func inventory(screens: [ScreenInput], primaryFrame: CGRect, managed: [[String: Any]],
                          separateSpaces: Bool, sharedSpace: SpaceID) -> DisplayInventory {
        let parsed = managed.compactMap { entry -> DisplaySnapshot? in
            guard let identifier = entry["Display Identifier"] as? String else { return nil }
            return displaySnapshot(for: identifier, in: managed)
        }
        let sharedCandidates = parsed.filter { $0.activeSpace?.id == sharedSpace }
        let shared = sharedCandidates.first.flatMap { first in
            sharedCandidates.allSatisfy {
                $0.activeSpace == first.activeSpace && $0.desktopSpaces == first.desktopSpaces
            } ? first : nil
        }
        var desktops: [DisplayID: DisplaySnapshot] = [:]
        let displays = screens.map { screen -> DisplayTopology.Display in
            let snapshot = separateSpaces ? displaySnapshot(for: screen.identifier, in: managed) : shared
            desktops[screen.id] = snapshot
            return .init(id: screen.id, frame: DisplayTopology.axFrame(fromAppKit: screen.frame, primaryFrame: primaryFrame),
                         usableFrame: DisplayTopology.axFrame(fromAppKit: screen.visibleFrame, primaryFrame: primaryFrame),
                         activeSpace: snapshot?.activeSpace)
        }
        let topology = DisplayTopology(displays: displays)
        desktops = desktops.filter { entry in topology.displays.contains { $0.id == entry.key } }
        return DisplayInventory(topology: topology, desktops: desktops)
    }

    /// The Space that `window` lives on.
    nonisolated static func space(for window: WindowID) -> SpaceID? {
        let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), allSpacesMask, [window] as CFArray) as? [NSNumber]
        return spaces?.first?.uint64Value
    }

    /// Each window's Space, read off the main thread: while windows resize, WindowServer can take
    /// milliseconds to answer.
    @concurrent nonisolated static func spaces(for windows: [WindowID]) async -> [WindowID: SpaceID] {
        var spaces: [WindowID: SpaceID] = [:]
        for window in windows { spaces[window] = space(for: window) }
        return spaces
    }
}
