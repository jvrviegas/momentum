import AppKit

typealias SpaceID = UInt64

// Read-only private SkyLight/CoreGraphics symbols. There is no public API that identifies
// which native Space (Desktop) is visible or which Space a window belongs to.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ connection: Int32) -> UInt64

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func CGSManagedDisplayGetCurrentSpace(_ connection: Int32, _ displayUUID: CFString) -> UInt64

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windowIDs: CFArray) -> CFArray

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
