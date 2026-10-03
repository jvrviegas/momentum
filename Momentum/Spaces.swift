import AppKit

typealias SpaceID = UInt64

/// Uses the read-only private SkyLight functions declared in `Momentum-Bridging-Header.h`.
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

    /// The Space that `window` lives on.
    static func space(for window: WindowID) -> SpaceID? {
        let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), allSpacesMask, [window] as CFArray) as? [NSNumber]
        return spaces?.first?.uint64Value
    }
}
