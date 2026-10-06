import AppKit

typealias SpaceID = UInt64

/// Reads native Space membership and Desktop order through the private bridge.
enum Spaces {
    private static let allSpacesMask: Int32 = 0x7

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

    /// The Space that `window` lives on.
    static func space(for window: WindowID) -> SpaceID? {
        let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), allSpacesMask, [window] as CFArray) as? [NSNumber]
        return spaces?.first?.uint64Value
    }
}
