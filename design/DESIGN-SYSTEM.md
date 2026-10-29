# Momentum design system

Momentum keeps Apple's look. Tokens live in `Momentum/UI/` and cover only what the
system does not. Views use tokens, never raw numbers or colors. Add a token when a
view first needs it, not before.

## Accent

- No `Theme.swift`: Momentum follows the accent people set for their Mac.
- Accent reaches views through `.tint`, `.borderedProminent`, switches, and selection.
  Never hard-code an accent hex. The violet brand color belongs to the icon and the
  landing page only.

## Grid.swift — `Space`

| Token | Value | Use for |
| --- | --- | --- |
| `xs` | 4 | A title and the caption under it; an icon and its count in the menu bar |
| `sm` | 8 | Buttons side by side; short stacks of text; the footer |
| `md` | 12 | Items in a panel; panel padding; panels in the popover |
| `lg` | 16 | The popover's margin; the sidebar footer's side padding |
| `xl` | 24 | The Settings page header |

- Every padding and spacing comes from `Space`. `.padding()` with no value is fine:
  it is the system's default.

## Surfaces.swift — `Palette`

- `surface`: the fill behind a popover panel. It stays translucent so the popover's
  glass shows through. Use it only through `Panel`.
- `warning`: the one status color (system orange). It colors the warning **symbol**,
  never a whole sentence: orange text is hard to read on a light background.
- Never copy or redefine a semantic color (`.secondary`, `.separator`). Every new
  custom color needs light, dark, and Increase Contrast values.

## Radius.swift — `Radius`

- `md` 12: cards (popover panels).
- Inner corners are concentric: inner radius = outer radius − inset.

## Layout.swift — `Layout`

- `popoverWidth` 340: every popover panel fills this width minus `Space.lg` margins.
- `settingsMinSize`, `settingsIdealSize`, `sidebar*Width`: the Settings window.
- `appPickerSize`, `rowIcon`, `shortcutMinWidth`: the app picker and Settings rows.
- Fixed sizes sit on the 4 pt grid.

## Components.swift

- `Panel { … }`: one feature in the popover (Keep Awake, Window Tiling, and the
  upcoming Focus timer). A headline `Label` with an SF Symbol comes first.
- `WarningLabel(message)`: every error or "needs attention" message, in the popover
  (`.font(.caption)`) and in Settings (`.textSelection(.enabled)`).
- One `.borderedProminent` button per panel: its main action.
- Style controls with `ButtonStyle` and `ToggleStyle`. Never rebuild a control from
  shapes: it loses the keyboard, focus, and VoiceOver.

## Motion

- No SwiftUI animation exists yet, so there is no `Motion.swift`. Add it with the
  first one (likely the Focus timer countdown) and route every animation through it,
  so Reduce Motion applies everywhere.
- Window tiling motion is a separate engine (`WindowAnimation.swift`, 200 ms ease-out,
  with its own setting and Reduce Motion override). It does not go through `Motion`.
- Units never animate, only the number (`.contentTransition(.numericText())`).
- Never animate a view's first layout. Hover never moves a selection.

## Check

No hits outside `Momentum/UI/`:

```bash
grep -rnE 'cornerRadius: [0-9]{1,2}\b|duration: [0-9]|\.spring\(response|\.snappy\b|\.easeInOut|\.easeOut\(|Color\(hex:|Color\(red:|\.foregroundStyle\(\.(red|orange|yellow)\)|Color\.(red|orange|yellow)' Momentum/ \
  | grep -v '^Momentum/UI/'
```
