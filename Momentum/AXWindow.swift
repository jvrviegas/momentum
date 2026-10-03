import AppKit
import ApplicationServices

// Private but stable HIServices function that maps an AX window element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

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

    /// Normal, visible document-style windows; excludes dialogs, sheets, minimized and fullscreen windows.
    var isStandard: Bool {
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

    func setFrame(_ frame: CGRect) {
        // Size first so the move isn't clamped by the screen edge, then size again
        // in case the original size prevented the window from fitting at the new position.
        element.setAXValue(frame.size, of: kAXSizeAttribute, type: .cgSize)
        element.setAXValue(frame.origin, of: kAXPositionAttribute, type: .cgPoint)
        element.setAXValue(frame.size, of: kAXSizeAttribute, type: .cgSize)
    }

    func focus() {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// A point near the top of the window that can be grabbed to drag it. Each candidate is hit-tested
    /// so we don't press a tab, button or text field (e.g. browser tab strips start right after the traffic lights).
    var titleBarGrabPoint: CGPoint? {
        guard let frame else { return nil }
        var startX = frame.minX + 80
        if let zoomButton: AXUIElement = element.value(of: kAXZoomButtonAttribute),
           let position: CGPoint = zoomButton.axValue(of: kAXPositionAttribute, type: .cgPoint),
           let size: CGSize = zoomButton.axValue(of: kAXSizeAttribute, type: .cgSize) {
            startX = position.x + size.width + 8
        }

        let systemWide = AXUIElementCreateSystemWide()
        let draggableRoles: Set<String> = [kAXWindowRole, kAXToolbarRole, kAXGroupRole, kAXStaticTextRole]
        for yOffset in [6.0, 12, 20] {
            for x in stride(from: startX, to: frame.maxX - 20, by: 30) {
                let point = CGPoint(x: x, y: frame.minY + yOffset)
                var hit: AXUIElement?
                guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
                      let hit else { continue }
                var hitPID: pid_t = 0
                AXUIElementGetPid(hit, &hitPID)
                if hitPID == pid, let role: String = hit.value(of: kAXRoleAttribute), draggableRoles.contains(role) {
                    return point
                }
            }
        }
        return CGPoint(x: startX, y: frame.minY + 12)
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

    func setAXValue<T: BitwiseCopyable>(_ value: T, of attribute: String, type: AXValueType) {
        var value = value
        guard let axValue = AXValueCreate(type, &value) else { return }
        AXUIElementSetAttributeValue(self, attribute as CFString, axValue)
    }
}
