import SwiftUI

/// Custom surfaces and the one status color. Each adapts to light, dark, and Increase Contrast.
/// The accent is the Mac's own: views get it through `.tint` and prominent controls, never a hex value.
enum Palette {
    /// The fill behind a popover panel. Translucent, so the popover's glass shows through.
    static let surface: some ShapeStyle = HierarchicalShapeStyle.quaternary.opacity(0.5)
    /// Symbols that flag a failure or something that needs attention.
    static let warning = Color.orange
}
