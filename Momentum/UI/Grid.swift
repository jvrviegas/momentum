import SwiftUI

/// The spacing scale. Every padding and spacing sits on a 4 pt grid.
enum Space {
    /// A title and the caption under it.
    static let xs: CGFloat = 4
    /// Buttons side by side, and short stacks of text.
    static let sm: CGFloat = 8
    /// Items in a panel, and panels in the popover.
    static let md: CGFloat = 12
    /// The popover's margin.
    static let lg: CGFloat = 16
    /// The Settings page header.
    static let xl: CGFloat = 24
}
