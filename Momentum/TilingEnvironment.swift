import AppKit
import QuartzCore

/// Narrow native boundary. Tests supply windows, topology, writes and clocks without starting AX observers.
struct TilingEnvironment {
    struct Window {
        let id: WindowID
        let bundleID: String?
        let readStandard: () -> Bool
        let readFrame: () -> CGRect?
        /// Asks the app now, where `readFrame` may report the last read.
        let readCurrentFrame: () async -> CGRect?
        let writeFrame: (CGRect, CGRect?, Bool, Bool) -> Bool
        let focus: () -> Void

        var isStandard: Bool { readStandard() }
        var frame: CGRect? { readFrame() }

        /// Reports the window as last read. Writes and focus run on the app's own queue;
        /// a write reports success once submitted.
        static func native(_ state: WindowObserver.WindowState, queues: AXQueues) -> Self {
            let window = state.window
            return Self(id: window.id, bundleID: state.bundleID,
                 readStandard: { state.isStandard }, readFrame: { state.frame },
                 readCurrentFrame: { await queues.run(window.pid) { window.frame } },
                 writeFrame: {
                     queues.writeFrame(window, $0, from: $1, forceResize: $2, repairClamping: $3)
                     return true
                 },
                 focus: { queues.focus(window) })
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
    /// Rereads windows, which `windows` and `focusedWindow` then report. Nil when they're always current.
    var reload: (() async -> Void)? = nil

    static func native(observer: WindowObserver) -> Self {
        Self(inventory: { Spaces.displayInventory() },
             windows: { observer.windows.map { .native($0, queues: observer.queues) } },
             focusedWindow: {
                 guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                       let window = observer.focusedWindow(in: pid) else { return nil }
                 return .native(window, queues: observer.queues)
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
             reportError: { NSSound.beep() },
             reload: { await observer.reload() })
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
