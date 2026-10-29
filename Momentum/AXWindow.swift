import AppKit
import ApplicationServices

/// Thin wrapper over an Accessibility window element. Frames use top-left origin global coordinates.
/// Not tied to the main actor: calls wait on the other app, so they run on that app's queue (`AXQueues`).
/// Unchecked: an element is an immutable reference, and Accessibility calls on it are thread-safe.
nonisolated struct AXWindow: @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t
    let id: WindowID

    init?(element: AXUIElement, pid: pid_t) {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &windowID) == .success, windowID != 0 else { return nil }
        self.element = element
        self.pid = pid
        self.id = windowID
    }

    /// Everything the layout needs, in one round trip to the app; nil if the app didn't answer in time.
    /// Standard means a normal document-style window: not a dialog, sheet, minimized or fullscreen window.
    /// Hidden apps still list their windows, so the caller checks that separately.
    func readState() -> (isStandard: Bool, frame: CGRect?)? {
        let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute, "AXFullScreen",
                          kAXPositionAttribute, kAXSizeAttribute] as CFArray
        var values: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(), &values)
        guard result != .cannotComplete else { return nil }
        // Attributes the window lacks come back as error values, which read as nil below.
        guard let values = values as? [AnyObject], values.count == 6 else { return (false, nil) }
        let isStandard = values[0] as? String == kAXWindowRole
            && values[1] as? String == kAXStandardWindowSubrole
            && values[2] as? Bool != true
            && values[3] as? Bool != true
        guard let position: CGPoint = decodeAXValue(values[4], type: .cgPoint),
              let size: CGSize = decodeAXValue(values[5], type: .cgSize) else { return (isStandard, nil) }
        return (isStandard, CGRect(origin: position, size: size))
    }

    var frame: CGRect? {
        guard let position: CGPoint = element.axValue(of: kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = element.axValue(of: kAXSizeAttribute, type: .cgSize) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// WindowServer geometry is sampled independently when verifying an asynchronous native transfer.
    static func serverFrame(for id: WindowID) -> CGRect? {
        guard let entries = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let entry = entries.first(where: { ($0[kCGWindowNumber as String] as? WindowID) == id }),
              let bounds = entry[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    enum FrameChange: Equatable {
        case position(CGPoint)
        case size(CGSize)
    }

    /// A known previous frame avoids redundant AX writes. The final resize always repairs edge clamping.
    static func frameChanges(to frame: CGRect, from previous: CGRect?, forceResize: Bool = false,
                             repairClamping: Bool = true) -> [FrameChange] {
        let resize = forceResize || previous?.size != frame.size
        let move = previous?.origin != frame.origin
        if forceResize || previous == nil || (resize && move && repairClamping) {
            // Size first so the move isn't clamped by the screen edge, then size again
            // in case the original size prevented the window from fitting at the new position.
            return [.size(frame.size), .position(frame.origin), .size(frame.size)]
        }
        if resize && move { return [.size(frame.size), .position(frame.origin)] }
        if resize { return [.size(frame.size)] }
        if move { return [.position(frame.origin)] }
        return []
    }

    @discardableResult
    func setFrame(_ frame: CGRect, from previous: CGRect? = nil, forceResize: Bool = false,
                  repairClamping: Bool = true) -> Bool {
        var succeeded = true
        for change in Self.frameChanges(to: frame, from: previous, forceResize: forceResize, repairClamping: repairClamping) {
            let written: Bool
            switch change {
            case .position(let position):
                written = element.setAXValue(position, of: kAXPositionAttribute, type: .cgPoint)
            case .size(let size):
                written = element.setAXValue(size, of: kAXSizeAttribute, type: .cgSize)
            }
            if !written { succeeded = false }
        }
        return succeeded
    }

    /// Brings the window to the front of its app; activating the app is left to the caller.
    func raise() {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

}

private nonisolated func decodeAXValue<T>(_ value: CFTypeRef, type: AXValueType) -> T? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { pointer.deallocate() }
    // The cast is safe: the type ID was checked above.
    guard AXValueGetValue(value as! AXValue, type, pointer) else { return nil }
    return pointer.pointee
}

nonisolated extension AXUIElement {
    func value<T>(of attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    func axValue<T>(of attribute: String, type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success,
              let value else { return nil }
        return decodeAXValue(value, type: type)
    }

    func setAXValue<T: BitwiseCopyable>(_ value: T, of attribute: String, type: AXValueType) -> Bool {
        var value = value
        guard let axValue = AXValueCreate(type, &value) else { return false }
        return AXUIElementSetAttributeValue(self, attribute as CFString, axValue) == .success
    }
}
