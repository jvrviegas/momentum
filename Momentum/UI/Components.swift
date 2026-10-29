import SwiftUI

/// Groups one feature's controls in the menu-bar popover.
struct Panel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.lg)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}

/// A failure or something that needs attention. Only the symbol takes the warning color,
/// so the message keeps full text contrast.
struct WarningLabel: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
