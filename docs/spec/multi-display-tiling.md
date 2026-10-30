# Functional Spec: Multi-display tiling

> Layer 2 — **draft branch behavior**, implemented but not accepted for release/merge. Automated/fake integration and isolated native-driver checks are not final two-display product QA. Update this file with any behavior change.

| | |
|---|---|
| **Area owner** | João |
| **Verification** | 2026-10-10: native integration tests; separate-Spaces/custom-SIP helper feasibility and fullscreen snapshot replay; 2026-10-12: 179 tests, 16 native coordinator checks and 19 owner-observed guarded-preview manual passes; unrestricted/compatibility limits remain; 2026-10-29: 205 tests and Release-build traces with a main-thread probe across animation, shortcut and unresponsive-app scenarios (MD-17 to MD-20); 2026-10-30: 221 tests including minimum-size layout, learning, set-aside and transfer cases (MD-22 to MD-31), and an agent-run live check with Slack, Terminal, Chrome, Xcode and a probe app on one display; owner acceptance pending |

## Overview

This worktree tiles normal windows on each logical display's visible Desktop independently. Keyboard focus can cross display edges, swaps remain local, and optional shortcuts transfer windows between displays. Desktop sending uses per-display ordinal order while Desktop switching continues to use macOS's global system shortcuts. Settings remain shared across displays; no monitor-specific persistence or automatic window move-back is introduced.

## Concepts

| Term | Meaning |
|---|---|
| Display/Desktop layout | One BSP tree and remembered focus for a logical display plus native Space ID |
| Eligible display | A connected logical display whose active Space is unambiguously mapped and normal, not fullscreen |
| Display order | Center x ascending, then center y ascending in global top-left coordinates; identity breaks exact ties |
| Confirmed transfer | Destination still exists and membership, AX geometry and WindowServer geometry agree for five consecutive samples |
| Shared Spaces | One active Space normalized across logical displays; live validation owner-skipped |

## Behaviors

### Layouts and motion

- **MD-01.** When multiple normal Desktop displays are mapped, Momentum maintains a separate layout for every display/Desktop pair, including two displays sharing the same Space ID.
- **MD-02.** When one layout's windows change, other layouts retain their tree order unless their own window membership or usable bounds change.
- **MD-03.** When separate Spaces are enabled, layouts use each display's active Desktop. With shared Spaces, a consistent shared snapshot is normalized onto every display; missing or conflicting mapping is left unmanaged rather than treated as the primary Desktop.
- **MD-04.** When layouts apply, each uses its own usable bounds with common point-based gap/padding settings, animation policy and Reduce Motion override. Each animated display owns its own native display link. A tick on a display that has switched Desktops or changed bounds is cancelled before it writes. A window that moves to another Space mid-animation stops receiving frames from the next tick: windows' Spaces are checked off the main thread, one frame behind. Programmatic layout writes are deferred while the left mouse button is held.

### Focus, swaps and transfers

- **MD-05.** When directional focus has no local tiled neighbor, it selects a tiled window on another eligible display in that direction by edge distance, perpendicular alignment and stable ID. Directional focus does not wrap or target floating windows.
- **MD-06.** When a directional swap runs, it swaps only within the focused window's display/Desktop layout.
- **MD-07.** When a tiled previous/next-display transfer is confirmed, the window joins the destination's active layout, both affected displays reconcile, and focus follows. Layout state is not changed optimistically before verification.
- **MD-08.** When a display transfer runs, it wraps through eligible displays in physical center order. Empty normal Desktops are valid destinations; no other eligible display means no native request or frame/layout write.
- **MD-09.** When a tiled drag ends across displays, its center-based owner selects the destination; Momentum verifies membership/placement and inserts it rather than swapping across displays. Same-layout moved drops retain cursor-based swapping; same-layout resizes snap back. Floating drops remain untiled and do not receive Momentum-driven focus changes.
- **MD-10.** When a floating/excluded-app window is sent with a display shortcut, it stays untiled; logical size and relative offset are preserved where possible, otherwise clamped/shrunk to destination usable bounds. Focus follows only after confirmation.
- **MD-11.** When a display disconnects, its runtime layout/animation state is discarded and windows reconcile wherever macOS relocates them. Reconnect does not actively return windows to their former monitor.
- **MD-12.** When Send to Desktop N runs, N resolves the Nth normal Desktop on the focused window's display, excluding fullscreen entries. It does not switch Desktops, warp the cursor or follow focus into an inactive Desktop. System-shortcut Desktop switching retains macOS's global behavior.
- **MD-13.** When a display shows fullscreen or uncertain Space mapping, it is not a transfer/focus destination. Fullscreen, minimized, hidden and nonstandard source windows are not manipulated. Commands never automatically exit fullscreen or create/switch Desktops.
- **MD-14.** When an old configuration loads, both new display actions are unbound and old action registration priority remains unchanged. Settings/JSON can bind or explicitly clear `send-to-previous-display` and `send-to-next-display`; omitted defaults remain unbound.

### Minimum sizes

- **MD-22.** When Momentum resizes a window and the app keeps it larger than asked, Momentum remembers that width or height as the window's minimum size and lays the display out again. It doesn't keep animating a window toward a size its app refuses. While the window's top-left corner stays where Momentum put it, the window belongs to that display, even if its larger size reaches into another one.
- **MD-23.** When a window ends at most 8 pt larger than asked, as apps that size in steps do (Terminal rounds by about 3 pt at its default font), Momentum doesn't treat that as a minimum size.
- **MD-24.** When Retile runs, from the menu or the shortcut, Momentum forgets every remembered minimum size and measures again. Minimum sizes are also forgotten when the window closes or Momentum quits. They are never saved.
- **MD-25.** When one side of a split needs more than half the space for its windows' minimum sizes, that side gets what it needs and the other side gets the rest. Splits whose windows fit stay equal. Once a layout makes room, a window whose minimum size isn't known yet counts as needing 100 × 100 pt, so no tile shrinks to nothing. Focus, swaps, and drops use these tiles.
- **MD-26.** When the two sides of a split can't fit side by side at their minimum sizes but fit stacked, or the reverse, that split is laid out the other way. It returns to its own direction as soon as that fits again. The stored layout doesn't change.
- **MD-27.** When windows on a display still don't fit, Momentum tiles them in the order they joined that display's layout, and each window that doesn't fit with the windows before it floats. Usually that's the newest window. A window that floats this way keeps its size and moves to the center of the display's tiling area, or to its top or left edge where the window is larger than the area. After that it stays wherever people move it. Momentum doesn't change focus or window order.
- **MD-28.** When there's room again (a window closes or floats, the display grows, gaps change, or Retile measures smaller minimum sizes), windows that float because they didn't fit rejoin their place in the layout, oldest first.
- **MD-29.** When Toggle floating tiles a window, including one that floats because it didn't fit, that window takes priority: the newest other windows that don't fit float instead. If the window doesn't fit on its display even alone, it stays floating and Momentum beeps.
- **MD-30.** When a window is sent or dragged to a display where it doesn't fit, it moves to the center of that display's tiling area (MD-27) and floats there until there's room. A window larger than the destination's usable area can't be sent, and Momentum shows the move error (MD-16).
- **MD-31.** While any window on a visible Desktop floats because it doesn't fit, the Window Tiling panel says "Xcode floats until there's room to tile it." (the app's name) or "2 windows float until there's room to tile them." The message disappears when they rejoin.

### Errors and limits

- **MD-15.** When Desktop N is unavailable on the selected display, Momentum reports an error without sending the window. A same-Desktop command is a no-op.
- **MD-16.** When a request, frame write, closure, timeout or destination change prevents confirmation, Momentum reconciles actual state and shows a dismissible move error; it does not follow focus or assert successful transfer. Partial native changes cannot be promised to roll back atomically. No SIP change, synthetic drag or automatic Dock restart is performed.

### Responsiveness

- **MD-17.** When an app doesn't answer Accessibility, Momentum's main thread doesn't wait on it: each app's window reads, frame writes and focus run on that app's own queue, and registering for its notifications gives up after 40 ms and retries for about 10 seconds.
- **MD-18.** When an app doesn't answer a window read within 100 ms, the layout updates without waiting for it: its windows keep their last known place instead of being removed and reinserted, and windows it reports once it answers are tiled then. An app is read at most once at a time.
- **MD-19.** When an app applies frame writes slower than an animation runs, its windows skip intermediate frames and still receive the final frame; other windows' animations are unaffected.
- **MD-20.** When a window shortcut is pressed, it acts on windows read after the key press, in the order the shortcuts were pressed.
- **MD-21.** When Momentum writes window frames to an app whose enhanced Accessibility mode (`AXEnhancedUserInterface`, turned on by some assistive apps) is on, it turns the mode off for those writes and back on once the app's last write finishes. With the mode on, Chrome and other Chromium apps animate each write themselves, about 250 ms behind.

## Permissions

| Action | Requirements | Notes |
|---|---|---|
| Window/layout/focus commands | Existing Accessibility trust | Native startup waits for permission; injected test startup never starts observers |
| Display transfer | Accessibility, tiling enabled, mapped normal destination | Serialized against pending native moves and active drags |
| Send to Desktop | Accessibility and existing Desktop | Retains existing availability while automatic tiling is disabled |
| Keep Awake | Independent existing permission-free routing | Not changed by display commands |

## Integrations and side effects

- `WindowObserver` already supplies window, active-Space and screen-parameter events. Each refresh reconciles one snapshot of every observed app's windows, read off the main thread on a serial queue per app (`AXQueues`), which frame writes and focus share.
- Display links target their own screens. Invalidated/abandoned link proxies do not retain the manager.
- Native transfer reuses the unsupported bridged Space operation, then AX frame writes and independent WindowServer reads. Verification samples every 20 ms with a bounded timeout; small logical rounding is tolerated, not a different minimum size.
- Native move errors reuse the existing menu/Settings surface. New shortcuts have no defaults; no extra global hotkeys are registered automatically.

## Known gaps and quirks

- **T14 acceptance remains incomplete.** A same-agent code review and 16 targeted native coordinator checks passed on 2026-10-12; a subsequent 19-step owner-observed guarded-preview suite passed actual mouse/hotkey/UI/observer and physical-display checks. Unrestricted regular-app discovery/startup and the app-driven movement path remain unverified. Native CADisplayLink lifecycle was smoke-tested with virtual windows only, not live tiling of the owner's apps.
- Fully enabled SIP compatibility is unverified; owner approved implementation with that explicit gap. Do not ask users to disable SIP.
- Shared-Spaces live tests were skipped at owner's request, not passed. Conservative fixture-based shared normalization may leave unfamiliar native snapshots unmanaged.
- Mirroring-specific runtime inventory and final mixed-scale/refresh animation smoothness are unverified. Pure exact-frame mirror deduplication is not full mirroring QA.
- Applications can refuse resizing; a transfer that cannot settle to its requested usable placement reports failure rather than pretending it fit. Frame writes report success once submitted, so an app refusing a transfer's write surfaces as the confirmation timeout, not a refused-write error. A minimum size Momentum hasn't learned yet can still make a transfer time out.
- A window's first tiling can show a few moves, because a minimum size is only known after Momentum resizes the window once (MD-22).
- When Momentum starts, every window joins its display's layout at once, in the order macOS lists them, so the window that floats for lack of room (MD-27) isn't necessarily the newest.
- An app that lowers a window's minimum size while it's open keeps the larger tile until Retile or the window closes. Fixed-size windows that can't grow keep their size at the tile's top-left corner, leaving a gap; maximum sizes aren't handled.
- Inactive membership queries that lack evidence of closure retain layout entries; actual visible ownership reconciles on refresh.
- If Momentum quits while an app's frame writes are running, that app's enhanced Accessibility mode stays off until the app or the assistive app that enabled it turns it on again (MD-21).
- Prior MDF foundation-only unavailable/inert rules were superseded by this native integration. The proposal remains unarchived until acceptance.

Evidence: [validation record](../qa/multi-display-tiling-validation.md). Scope/decisions: [implementation plan](../plans/multi-display-tiling-implementation-plan.md); minimum sizes: [feature spec](../plans/window-minimum-sizes-feature-spec.md).
