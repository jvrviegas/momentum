# Window minimum sizes validation

Rules: MD-22 to MD-31 in [the living spec](../spec/multi-display-tiling.md). Feature spec: [window minimum sizes](../plans/window-minimum-sizes-feature-spec.md).

## Environment and safety

- Branch `feat/window-minimum-sizes` (base `65058f7`); macOS 27.2 (26B123), Xcode 27.1 (27A9275).
- One display: LG HDR 4K, 2560 × 1440 pt. The owner's config: gap 8, padding 8, animations on.
- Checks ran on the owner's normal profile. The installed app was quit, the Release build ran directly (same team signature, so the Accessibility grant held), and the installed app was restarted afterwards. Test windows were closed, and Terminal and Xcode, which weren't running before, were quit. The owner's Slack window was part of the layout and returned to full screen.
- Evidence came from WindowServer frames (`CGWindowListCopyWindowInfo`, no titles) and the `size` signpost, which logs every write an app didn't take exactly (`log stream --signpost`, subsystem `com.joaoviegas.Momentum`). A temporary trace of each layout's targets was used to find the two bugs below, then removed.
- A probe app (a plain AppKit window with `minSize` 1800 × 900) stood in for a window too large to fit. System Settings wasn't used: it's in the owner's Floating Apps.

## Automated quality gate (2026-10-30)

- `xcodebuild test` (Debug): 221 tests passed, 0 failed, 16 of them for this feature. Eight earlier runs of the suite were all green, so the new async tests aren't flaky.
- Clean Debug build and Release build: zero warnings. `scripts/grid-lint.sh`: PASS.

## Matrix

| Case | Status | Evidence |
|---|---|---|
| V1 Learning (MD-22) | Passed — agent verified | Slack asked 630 × 693, kept 668 × 693, then 668 × 342 → 668 × 400. Chrome asked 100 × 400, kept 626 × 469. Xcode asked 668 × 100 → 668 × 350 and 100 × 469 → 400 × 469. Terminal asked 100 × 508 → 177 × 511. Each was learned and the display laid out again |
| V2 Size steps (MD-23) | Passed — agent verified, after a change | Terminal rounds to its grid by about 3 pt either way (776 → 779, 508 → 511, 277 → 273). The first build's 20 pt step hid Terminal's real 119 pt minimum height when it was asked for 100 pt, leaving a 19 pt overlap. The step is now 8 pt |
| V3 Making room and flipping (MD-25, MD-26) | Passed — agent verified, after two fixes | Six windows, then ten (Slack, Chrome, Xcode, six Terminal windows), settled with every window at or above its minimum size and no overlaps between tiles. The first build asked a Terminal window for 0 pt; MD-25 now has a 100 pt smallest tile |
| V4 Window stays on its display (MD-22) | Passed — agent verified, after a fix | The 0 pt request also made the window's requested frame empty, so it matched no display and dropped out of tiling. The requested frame now counts only when it has an area |
| V5 Doesn't fit (MD-27) | Passed — agent verified | The probe window was asked 100 × 400, kept 1800 × 900, didn't fit, and moved to the center of the tiling area (center 1280, 735). Moving it by hand isn't undone |
| V6 Rejoin (MD-28) | Passed — agent verified | After the probe floated by choice, the two Terminal windows set aside for it returned to their exact earlier frames |
| V7 Toggle floating priority (MD-29) | Passed — agent verified | ⌥⇧Space on the probe tiled it at 1800 × 900; the two newest Terminal windows floated at the center instead. The beep case is unit-tested only |
| V8 Retile (MD-24) | Passed — agent verified | ⌥⇧R forgot the learned sizes, measured again (11 size events), and settled on the same layout with no overlaps |
| V9 Panel caption (MD-31) | Passed — agent verified | Dark: "MinSizeProbe floats until there's room to tile it." Light: "Slack floats until there's room to tile it." Secondary caption style below Retile Windows, one line |
| V10 Transfer (MD-30) | Unit-tested only | One display; `transferMakesRoomAtTheDestination` covers making room at the destination |
| V11 Ghostty, iTerm2 | Not checked | Ghostty's windows were on the owner's other Desktops; iTerm2 isn't installed |

## Findings that stay open

- Learning takes a few passes, so a crowd of new windows visibly moves several times before it settles (11 size events for the ten-window Retile).
- When Momentum starts, every window joins at once in the order macOS lists them, so the window that floats isn't necessarily the newest. In the light-mode check, Slack floated and the probe tiled.
- A floating window keeps the size of its last tile, which can be tall and narrow (a 177 × 1393 Terminal in V7).
