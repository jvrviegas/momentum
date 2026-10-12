import AppKit
import QuartzCore

/// Narrow native boundary. Tests supply windows, topology, writes and clocks without starting AX observers.
struct TilingEnvironment {
    struct Window {
        let id: WindowID
        let bundleID: String?
        let readStandard: () -> Bool
        let readFrame: () -> CGRect?
        let writeFrame: (CGRect, CGRect?, Bool, Bool) -> Bool
        let focus: () -> Void

        var isStandard: Bool { readStandard() }
        var frame: CGRect? { readFrame() }

        static func native(_ window: AXWindow) -> Self {
            Self(id: window.id, bundleID: NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier,
                 readStandard: { window.isStandard }, readFrame: { window.frame },
                 writeFrame: { window.setFrame($0, from: $1, forceResize: $2, repairClamping: $3) },
                 focus: { window.focus() })
        }
    }

    struct DisplayLink {
        let invalidate: () -> Void
    }

    var inventory: () -> Spaces.DisplayInventory
    var windows: () -> [Window]
    var focusedWindow: () -> Window?
    var space: (WindowID) -> SpaceID?
    var existingWindowIDs: () -> Set<WindowID>?
    var serverFrame: (WindowID) -> CGRect?
    var moveToSpace: (WindowID, SpaceID) async throws -> Void
    var switchDesktop: (Int) async -> SpaceMover.SwitchResult
    var restartDock: () async -> Bool
    var mousePressed: () -> Bool
    var cursor: () -> CGPoint?
    var reduceMotion: () -> Bool
    var now: () -> Double
    var makeDisplayLink: (DisplayID, @escaping () -> Bool) -> DisplayLink?
    var wait: () async throws -> Void
    var reportError: () -> Void

    static func native(observer: WindowObserver) -> Self {
        Self(inventory: { Spaces.displayInventory() },
             windows: { observer.allWindows().map(Window.native) },
             focusedWindow: {
                 guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                       let window = AXWindow.focused(in: pid) else { return nil }
                 return Window.native(window)
             },
             space: { Spaces.space(for: $0) },
             existingWindowIDs: {
                 guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                     as? [[String: Any]] else { return nil }
                 return Set(list.compactMap { $0[kCGWindowNumber as String] as? WindowID })
             },
             serverFrame: { AXWindow.serverFrame(for: $0) },
             moveToSpace: { try await SpaceMover.move(windowID: $0, toSpace: $1) },
             switchDesktop: { await SpaceMover.switchTo(desktop: $0) },
             restartDock: { await SpaceMover.restartDock() },
             mousePressed: { NSEvent.pressedMouseButtons & 1 != 0 },
             cursor: { CGEvent(source: nil)?.location },
             reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
             now: { CACurrentMediaTime() },
             makeDisplayLink: { id, tick in
                 guard let screen = NSScreen.screens.first(where: {
                     ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
                 }) else { return nil }
                 let proxy = TilingDisplayLinkTarget(tick: tick)
                 let link = screen.displayLink(target: proxy, selector: #selector(TilingDisplayLinkTarget.tick(_:)))
                 link.add(to: .main, forMode: .common)
                 return DisplayLink(invalidate: { link.invalidate() })
             },
             wait: { try await Task.sleep(for: .milliseconds(20)) },
             reportError: { NSSound.beep() })
    }
}

/// Link retains this proxy, never the manager. An abandoned weak tick owner invalidates its link.
private final class TilingDisplayLinkTarget: NSObject {
    private let onTick: () -> Bool
    init(tick: @escaping () -> Bool) { onTick = tick }
    @objc func tick(_ link: CADisplayLink) {
        if !onTick() { link.invalidate() }
    }
}
