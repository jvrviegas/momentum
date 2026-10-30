# Feature Spec: Window minimum sizes

*Layer 1 — proposed behavior, not a claim of shipping functionality. Merge rules into `docs/spec/multi-display-tiling.md` when implemented. Terms follow `docs/GLOSSARY.md`.*

| | |
|---|---|
| **Status** | Implemented on `feat/window-minimum-sizes`; 221 tests pass; agent-verified with real apps (see validation record); owner acceptance pending |
| **Owner** | João |
| **Tech reviewer** | Same-agent implementation; independent review pending |
| **Client sign-off / Linear project** | N/A — personal Momentum project; repository-local spec |
| **Merged into** | `docs/spec/multi-display-tiling.md` (2026-10-29, draft branch behavior) |

## Problem

Window Tiling splits every tile exactly in half and doesn't know that apps can refuse to shrink. When a window's **minimum size** is larger than its tile (Xcode needs about 900 pt, Chrome about 500 pt), the app keeps the larger size at the tile's top-left corner. The window covers part of its neighbor or runs past the edge of the display. Momentum then animates it toward the size it refused on every refresh. The more windows share a display, the more often this happens.

macOS doesn't tell other apps a window's minimum size: the Accessibility API has no attribute for it (checked in the macOS 27 SDK). Momentum has to learn it from how the app answers a resize.

## Goal

Windows on a display never overlap because an app can't shrink. A window that needs more room gets it from its neighbors. When windows can't all fit, the newest one floats until there's room. No setting is needed.

## Behaviors (acceptance criteria)

Rule IDs continue `docs/spec/multi-display-tiling.md`.

### Learning minimum sizes

- **MD-22.** When Momentum resizes a window and the app keeps it larger than asked, Momentum remembers that width or height as the window's minimum size and lays the display out again. It doesn't keep animating a window toward a size its app refuses. While the window's top-left corner stays where Momentum put it, the window belongs to that display, even if its larger size reaches into another one.
- **MD-23.** When a window ends at most 8 pt larger than asked, as apps that size in steps do (Terminal rounds by about 3 pt at its default font), Momentum doesn't treat that as a minimum size.
- **MD-24.** When Retile runs, from the menu or the shortcut, Momentum forgets every remembered minimum size and measures again. Minimum sizes are also forgotten when the window closes or Momentum quits. They are never saved.

### Making room

- **MD-25.** When one side of a split needs more than half the space for its windows' minimum sizes, that side gets what it needs and the other side gets the rest. Splits whose windows fit stay equal. Once a layout makes room, a window whose minimum size isn't known yet counts as needing 100 × 100 pt, so no tile shrinks to nothing. Focus, swaps, and drops use these tiles.
- **MD-26.** When the two sides of a split can't fit side by side at their minimum sizes but fit stacked, or the reverse, that split is laid out the other way. It returns to its own direction as soon as that fits again. The stored layout doesn't change.

### When windows don't fit

- **MD-27.** When windows on a display still don't fit, Momentum tiles them in the order they joined that display's layout, and each window that doesn't fit with the windows before it floats. Usually that's the newest window. A window that floats this way keeps its size and moves to the center of the display's tiling area, or to its top or left edge where the window is larger than the area. After that it stays wherever people move it. Momentum doesn't change focus or window order.
- **MD-28.** When there's room again (a window closes or floats, the display grows, gaps change, or Retile measures smaller minimum sizes), windows that float because they didn't fit rejoin their place in the layout, oldest first.
- **MD-29.** When Toggle floating tiles a window, including one that floats because it didn't fit, that window takes priority: the newest other windows that don't fit float instead. If the window doesn't fit on its display even alone, it stays floating and Momentum beeps.
- **MD-30.** When a window is sent or dragged to a display where it doesn't fit, it moves to the center of that display's tiling area (MD-27) and floats there until there's room. A window larger than the destination's usable area can't be sent, and Momentum shows the move error (MD-16).
- **MD-31.** While any window floats because it doesn't fit, the Window Tiling panel says so (see UX). The message disappears when they rejoin.

## UX

- **Flow:** a window opens, or a display gets smaller → Momentum tiles it → the app keeps the window larger than its tile → Momentum remembers the minimum size and lays out again: neighbors make room, a split that doesn't fit flips, and the newest window that still doesn't fit floats at the center → a window closes or the display grows → the floating window rejoins its place. Ways back: Toggle floating tiles a floating window at once (others float instead), Retile measures minimum sizes again, and closing or floating any window makes room.
- **Surface:** no new surface. The layout itself is the feedback. One caption goes in the existing Window Tiling panel of the menu-bar popover ("information that needs no action goes inline"). No alert, notification, or setting.
- **States:**

  | State | What people see |
  | --- | --- |
  | Everything fits | Equal tiles, as today |
  | A window needs more room | Its tile grows to its minimum size; the other side of the split shrinks; nothing overlaps |
  | A split fits only the other way | That pair stacks (or sits side by side) until there's room again |
  | Windows don't fit | The newest window floats at the center of the display; the panel caption appears |
  | Room again | The window animates back into its place; the caption disappears |
  | First tiling of a window with a minimum size | The window moves toward its tile, stops at its minimum size, then the layout adjusts once |

- **Words:**
  - Window Tiling panel caption, below Retile Windows, secondary caption style, wraps instead of truncating:
    - One window: "Xcode floats until there's room to tile it." (the app's name)
    - Several: "2 windows float until there's room to tile them."
  - No new buttons, menu items, settings, or shortcut titles. Existing names stay: **Retile Windows**, **Toggle floating**.
- **Hover help:** no new icon-only controls, so nothing needs a tooltip.
- **Access:**
  - No new controls. Toggle floating and Retile are the keyboard ways back.
  - VoiceOver reads the caption with the rest of the Window Tiling panel.
  - The caption is plain text, not color or a symbol alone.
  - Layout changes follow the existing animation setting and Reduce Motion (MD-04).

## Impact on existing specs

- **MD-04** layouts use minimum sizes when they apply (MD-25 to MD-27).
- **MD-05, MD-06, MD-09** directional focus, swaps, and drop targets use the tiles from MD-25 and MD-26, not equal halves.
- **MD-07** transfers place a window that doesn't fit at its destination by MD-30.
- **Known gaps** in `docs/spec/multi-display-tiling.md`: replace "Applications can refuse resizing or impose minimum sizes…" with the gaps below once implemented.
- **README** Window management checklist: add the item when implemented, with a link under Detailed tracking.

## Known gaps (expected after implementation)

- A window's first tiling can show a few moves, because a minimum size is only known after Momentum resizes the window once. With several new windows at once, each pass learns more.
- When Momentum starts, every window joins its display's layout at once, in the order macOS lists them. If they don't all fit, the window that floats isn't necessarily the newest; Toggle floating picks a different one.
- Momentum reads a window's size as soon as its write finishes. An app that applied a resize later than that would be taken as refusing it; no such app was seen in testing.
- An app that lowers a window's minimum size while it's open (for example by hiding a sidebar) keeps the larger tile until Retile or the window closes.
- Windows that can't grow (fixed-size windows) keep their size at the tile's top-left corner, leaving a gap. Maximum sizes are out of scope.

## Out of scope

- Maximum sizes and fixed-size windows.
- Remembering minimum sizes across launches, or per app.
- Resizing splits by hand.
- Choosing which window floats, other than Toggle floating.
- A setting to turn this off.
- Alerts or notifications about windows that don't fit.

## Implementation guidance

Learn minimum sizes from the final write only: after `writeImmediately` or an animation's last frame, read the window's size back on its app's AX queue (MD-17). Intermediate animation frames can be skipped (MD-19) and say nothing. Measure the size step of Terminal, iTerm2, and Ghostty before choosing the MD-23 tolerance.

Keep the layout math in `BSPTree` as a pure function that takes minimum sizes and returns frames plus the windows that don't fit. Use it in every place that computes tiles today: `apply`, `neighbor`, `window(at:excluding:in:gap:)`, the insert axis, and the transfer target. A greedy top-down pass is enough; it doesn't have to find the best possible arrangement. Keep windows that don't fit in the tree as set-aside leaves so they rejoin their place (MD-28). Keep join order per `LayoutKey` in `DisplayLayoutState`, separate from the user's `floating` set.

Unit-test making room, flipping, setting aside, rejoining, Toggle floating priority, and the step tolerance in `BSPTree` and `DisplayLayoutState`. Add an injected-environment test with a fake window that enforces a minimum size, and check it isn't animated again after its size is learned. Check the panel caption and the step tolerance by hand with Xcode, Chrome, System Settings, Terminal, and Ghostty on one display, with four or more windows.

## Decisions to confirm in review

The owner chose: neighbors make room, a split flips direction only while it needs to, and the newest window that doesn't fit floats and rejoins on its own. The UX pass decided the rest:
- Learn minimum sizes from refused resizes. They are never saved, and Retile forgets them.
- Ignore small overshoot from apps that size in steps.
- A window that doesn't fit keeps its size and moves to the center of the display.
- Windows rejoin their old place, oldest first.
- Toggle floating gives a window priority; Momentum beeps when it can't fit even alone.
- One caption in the Window Tiling panel; no setting, alert, or notification.
- Rules numbered MD-22 to MD-31 so they merge into the existing tiling spec.

## Changelog

| Date | Change | Agreed with |
|---|---|---|
| 2026-10-29 | UX pass: make room, flip while needed, and newest-floats-then-rejoins chosen by the owner; draft behaviors and UX written | João |
| 2026-10-29 | Spec approved as written, including the UX pass's own decisions; implementation started | João |
| 2026-10-30 | Live check with Slack, Terminal, Chrome, Xcode and a probe app ([validation record](../qa/window-minimum-sizes-validation.md)). Fixed two bugs it found: a window could be asked for 0 pt (MD-25 now has a 100 pt smallest tile), and such a window then dropped out of tiling. MD-23's step lowered from 20 to 8 pt, because 20 hid real minimum sizes | — |
| 2026-10-29 | Implemented with 15 new tests (220 pass). MD-27 now says how the window that floats is chosen (join order, which gives MD-29 its priority); MD-30 centers the window instead of using MD-10's floating placement; MD-22 keeps an oversized window on the display Momentum placed it on; MD-23 sets the step to 20 pt. Rules merged into the living spec as draft branch behavior | — |
