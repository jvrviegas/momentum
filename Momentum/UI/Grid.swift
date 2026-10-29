import SwiftUI

/// The spacing scale. Every padding and spacing sits on a 4 pt grid (scripts/grid-lint.sh).
enum Space {
    /// A title and the caption under it.
    static let xs: CGFloat = 4
    /// Related controls, buttons side by side, and short stacks of text.
    static let sm: CGFloat = 8
    /// Panels in the popover.
    static let md: CGFloat = 12
    /// The popover's margin, and the padding inside a card.
    static let lg: CGFloat = 16
    /// Window and page margins.
    static let margin: CGFloat = 20
}
