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
| `sm` | 8 | Related controls (items in a panel); buttons side by side; the footer |
| `md` | 12 | Panels in the popover |
| `lg` | 16 | Padding inside a card; the popover's margin; the sidebar footer |
| `margin` | 20 | Window and page margins (the Settings page header) |

- Every padding and spacing comes from `Space`. Raw numbers are 0, 1, 2, or a multiple
  of 4. `.padding()` with no value is fine: it is the system's default.
- One leading edge per column. The Settings header sits on the grouped Form's box
  edge (20 pt); let `Form`, `LabeledContent`, and `Label` align everything else.
- The popover is a compact surface, not a page: 16 pt margin and 12 pt between
  panels, because filled cards need less space between them than plain groups.

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
- Fixed sizes sit on the 4 pt grid. Sheets are 360, 480, or 640 wide. Controls take
  their height from `.controlSize`, never a fixed height.

## Components.swift

- `Panel { … }`: one feature in the popover (Keep Awake, Window Tiling, and the
  upcoming Focus timer). It pads 16 and spaces its items 8. A headline `Label` with
  an SF Symbol comes first.
- `.noInitialFocus()` (`WindowBehavior.swift`) on every window and sheet: it opens
  with nothing focused, no ring and no selected text. Only a window whose one job is
  typing focuses its field.
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

`scripts/grid-lint.sh` prints PASS. Then no hits outside `Momentum/UI/`:

```bash
grep -rnE 'cornerRadius: [0-9]{1,2}\b|duration: [0-9]|\.spring\(response|\.snappy\b|\.easeInOut|\.easeOut\(|Color\(hex:|Color\(red:|\.foregroundStyle\(\.(red|orange|yellow)\)|Color\.(red|orange|yellow)' Momentum/ \
  | grep -v '^Momentum/UI/'
```
