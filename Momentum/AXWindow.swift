import AppKit
import ApplicationServices

/// Thin wrapper over an Accessibility window element. Frames use top-left origin global coordinates.
struct AXWindow {
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

    /// The application's focused window.
    static func focused(in pid: pid_t) -> AXWindow? {
        let app = AXUIElementCreateApplication(pid)
        guard let element: AXUIElement = app.value(of: kAXFocusedWindowAttribute) else { return nil }
        return AXWindow(element: element, pid: pid)
    }

    /// Normal, visible document-style windows; excludes dialogs, sheets, minimized and fullscreen windows,
    /// and windows of hidden apps (AX keeps listing those).
    var isStandard: Bool {
        guard NSRunningApplication(processIdentifier: pid)?.isHidden != true else { return false }
        let role: String? = element.value(of: kAXRoleAttribute)
        let subrole: String? = element.value(of: kAXSubroleAttribute)
        let minimized: Bool? = element.value(of: kAXMinimizedAttribute)
        let fullscreen: Bool? = element.value(of: "AXFullScreen")
        return role == kAXWindowRole
            && subrole == kAXStandardWindowSubrole
            && minimized != true
            && fullscreen != true
    }

    var frame: CGRect? {
        guard let position: CGPoint = element.axValue(of: kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = element.axValue(of: kAXSizeAttribute, type: .cgSize) else { return nil }
        return CGRect(origin: position, size: size)
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

    func focus() {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

}

extension AXUIElement {
    func value<T>(of attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    func axValue<T>(of attribute: String, type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        // The cast is safe: the type ID was checked above.
        guard AXValueGetValue(value as! AXValue, type, pointer) else { return nil }
        return pointer.pointee
    }

    func setAXValue<T: BitwiseCopyable>(_ value: T, of attribute: String, type: AXValueType) -> Bool {
        var value = value
        guard let axValue = AXValueCreate(type, &value) else { return false }
        return AXUIElementSetAttributeValue(self, attribute as CFString, axValue) == .success
    }
}
