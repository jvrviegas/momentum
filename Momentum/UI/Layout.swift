import SwiftUI

/// Fixed widths and sizes. Everything else sizes to its content.
enum Layout {
    /// The menu-bar popover.
    static let popoverWidth: CGFloat = 340

    /// The Settings window.
    static let settingsMinSize = CGSize(width: 720, height: 540)
    static let settingsIdealSize = CGSize(width: 780, height: 600)

    /// The Settings sidebar column.
    static let sidebarMinWidth: CGFloat = 192
    static let sidebarIdealWidth: CGFloat = 200
    static let sidebarMaxWidth: CGFloat = 240

    /// The sheet that lists installed apps. Sheets are 360, 480, or 640 wide.
    static let appPickerSize = CGSize(width: 480, height: 520)
    /// App icons in list rows.
    static let rowIcon: CGFloat = 20
    /// The shortcut recorder button, so short and long shortcuts line up.
    static let shortcutMinWidth: CGFloat = 100
}
