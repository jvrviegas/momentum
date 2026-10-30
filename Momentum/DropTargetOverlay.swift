import AppKit
import SwiftUI

/// Where a dragged window can go (MD-32), in global top-left coordinates.
struct DropTargets: Equatable {
    /// The dragged window. The overlay sits just below it.
    let window: WindowID
    /// The tiles it can swap with, and the tiling areas of the other displays it can join.
    let places: [CGRect]
    /// Where it goes if released now; nil when it returns to its own tile.
    let landing: CGRect?
}

/// Shows drop targets in one click-through panel per screen, ordered just below the dragged window.
final class DropTargetOverlay {
    private var panels: [(panel: NSPanel, view: NSHostingView<DropTargetsView>)] = []
    private var shown: DropTargets?

    func show(_ targets: DropTargets?) {
        guard targets != shown else { return }
        shown = targets
        let screens = NSScreen.screens
        guard let targets, let primary = screens.first else {
            for (panel, _) in panels { panel.orderOut(nil) }
            return
        }
        while panels.count < screens.count { panels.append(Self.makePanel()) }
        for ((panel, view), screen) in zip(panels, screens) {
            let area = DisplayTopology.axFrame(fromAppKit: screen.frame, primaryFrame: primary.frame)
            func local(_ frame: CGRect) -> CGRect { frame.offsetBy(dx: -area.minX, dy: -area.minY) }
            let places = targets.places.filter(area.intersects).map(local)
            let landing = targets.landing.flatMap { area.intersects($0) ? local($0) : nil }
            guard !places.isEmpty || landing != nil else { panel.orderOut(nil); continue }
            panel.setFrame(screen.frame, display: false)
            view.rootView = DropTargetsView(places: places, landing: landing)
            panel.order(.below, relativeTo: Int(targets.window))
        }
        for (panel, _) in panels.dropFirst(screens.count) { panel.orderOut(nil) }
    }

    private static func makePanel() -> (panel: NSPanel, view: NSHostingView<DropTargetsView>) {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let view = NSHostingView(rootView: DropTargetsView(places: [], landing: nil))
        view.sizingOptions = []
        panel.contentView = view
        return (panel, view)
    }
}

/// Outlines every place in the accent and fills the landing place. Frames are local, top-left.
private struct DropTargetsView: View {
    let places: [CGRect]
    let landing: CGRect?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, _ in
            let increased = contrast == .increased
            for place in places {
                context.stroke(Self.shape(place), with: increased ? .style(.tint) : .style(Palette.dropPlace), lineWidth: 2)
            }
            if let landing {
                let fill = increased ? AnyShapeStyle(Palette.dropLandingIncreasedContrast) : AnyShapeStyle(Palette.dropLanding)
                context.fill(Self.shape(landing), with: .style(fill))
                context.stroke(Self.shape(landing), with: .style(.tint), lineWidth: 2)
            }
        }
        .accessibilityHidden(true)
    }

    /// Inset by half the line width, so the outline stays inside the tile.
    private static func shape(_ frame: CGRect) -> Path {
        RoundedRectangle(cornerRadius: Radius.md).path(in: frame.insetBy(dx: 1, dy: 1))
    }
}
