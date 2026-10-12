# Feature Spec: Multi-display tiling

*Layer 1 proposal; not a description of currently implemented behavior. On delivery, transfer verified rules to the living spec.*

| | |
|---|---|
| **Status** | Implemented on branch — approved 2026-10-08; native integration implemented; 2026-10-12 code review/targeted native checks passed, full manual acceptance pending |
| **Owner** | João |
| **Tech reviewer** | Same-agent native review recorded; no independent external sign-off |
| **Client sign-off / Linear project** | N/A — personal project; follows this repository's local planning convention |
| **Merged into** | Draft MD rules implemented in `docs/spec/multi-display-tiling.md`; not accepted/shipped or archived until T14 |

## Problem

Momentum currently tiles only the primary display. Windows on a second display do not participate in its automatic layout or keyboard navigation, leaving a multi-monitor workspace partly unmanaged.

## Goal

Extend existing tiling to all normal Desktop displays, with independent layouts and predictable cross-display navigation and transfers.

## Behaviors (acceptance criteria)

- **MD-01.** When normal Desktops are visible on multiple displays, Momentum maintains an independent BSP layout for each display/Desktop pair.
- **MD-02.** When one display's windows change, another display's layout order remains unchanged unless its own windows or usable area change.
- **MD-03.** When separate Spaces are enabled, layouts follow each display's active Desktop; when disabled, displays share the active Desktop but retain separate layouts.
- **MD-04.** When tiling runs, each layout uses its display's usable area and the shared gap, padding, animation and Reduce Motion settings, including mixed scaling and refresh rates.
- **MD-05.** When directional focus has no local tiled neighbor, it can focus the nearest eligible tiled window on another display in that direction; it does not wrap directionally.
- **MD-06.** When a directional swap runs, it swaps only within the focused window's display/Desktop layout.
- **MD-07.** When previous/next-display transfer succeeds for a tiled window, it joins the destination's active normal Desktop layout, both affected displays retile, and focus follows it.
- **MD-08.** When previous/next-display transfer runs, eligible displays are ordered by center left-to-right, then top-to-bottom for equal horizontal centers, and transfers wrap. With no other eligible display, the command is a no-op.
- **MD-09.** When a tiled window is dragged across displays and released, its center selects the destination and it joins that layout; floating windows remain floating.
- **MD-10.** When a floating or excluded-app window is sent to another display, it stays untiled, preserves its size where possible, is positioned inside the destination's usable area, and retains focus.
- **MD-11.** When a display disconnects, Momentum tiles displaced windows wherever macOS relocates them. Reconnecting does not make Momentum actively move windows back.
- **MD-12.** When Send to Desktop N runs, N selects the Nth normal Desktop in Mission Control order on the focused window's display, without moving it to another display or switching Desktops. Shared-Spaces mode uses the shared Desktop order.
- **MD-13.** When a display shows a fullscreen Space, it is excluded from cross-display focus/transfer destinations; native fullscreen windows are untouched. Commands do not automatically switch Desktops or exit fullscreen.
- **MD-14.** When an existing config loads, existing bindings remain unchanged and the two new transfer actions are unbound. Users can bind or clear them through Settings or JSON.

### Edge cases and errors

- **MD-15.** When Desktop N does not exist on the selected display, Momentum reports an error without moving the window.
- **MD-16.** When a native transfer fails or its destination disappears, Momentum does not publish an unverified successful transfer; it reconciles actual geometry/membership and reports failure. It never requires disabling SIP or automatically restarts the Dock.

## Out of scope

Per-display settings; persistent layout/monitor restoration; new Desktop creation; display-local Desktop switching (existing macOS shortcut behavior is retained and tested); direct numbered-display shortcuts; fullscreen management; release/signing changes; focus timer work. Mirroring-specific layouts are not introduced: mirrored outputs must not cause duplicate tiling of one logical desktop.

## Open questions

| # | Question | Owner | Resolved |
|---|---|---|---|
| 1 | Native cross-display transfer, display membership and shared-Spaces snapshot behavior on supported macOS with fully enabled SIP | Engineering | Partial — authorized 2026-10-10 probes passed in separate-Spaces/custom-SIP mode; shared live validation is owner-skipped (support remains planned/unverified); fullscreen checks passed in this environment; fully enabled SIP remains unverified; João explicitly authorized integration with that validation gap on 2026-10-10. Mirroring-specific behavior remains an untested conditional hardware case |
| 2 | Written technical details and error policy acceptable? | João / reviewer | Yes — João approved the written spec and implementation plan in chat on 2026-10-08; independent implementation review remains pending |

## Changelog

| Date | Change | Agreed with |
|---|---|---|
| 2026-10-08 | Captured one-at-a-time behavior decisions; two mixed-scaling/refresh-rate displays available for horizontal/vertical testing and both Spaces settings | João, in chat |
| 2026-10-08 | Approved written spec and implementation plan; native feasibility remains a blocking implementation gate | João, in chat |
| 2026-10-08 | Approved foundation-first sequencing with co-located automated/mocked tests; T1 live feasibility deferred but still blocks native integration, full manual acceptance remains last; behavior scope unchanged | João, in chat |
| 2026-10-08 | Implemented T2/T3/T4/T8 in a dedicated worktree; 133 automated tests passed. Native MD acceptance remains unverified; pending action titles/gate explicitly prevent an implemented-feature claim | João authorized foundation implementation in chat |
| 2026-10-10 | Authorized live T1 helpers verified current separate-Spaces/custom-SIP transfer/snapshot feasibility. Full native gate remains incomplete; no product behavior/scope change or acceptance claim | João authorized live probes in chat |
| 2026-10-10 | Skipped shared-Spaces live tests at owner's request; no shared-mode pass/support claim or removal of planned support; other native checks remain unresolved | João, in chat |
| 2026-10-10 | Secondary fullscreen probe and captured parser replay passed; original Desktop restored. Full SIP remains unverified and overall gate remains partial | João explicitly authorized brief fullscreen coverage in chat |
| 2026-10-10 | Authorized and implemented native integration with full-SIP compatibility pending. Final automated gate: 179 tests; real two-display product QA/review still pending. Behavior scope unchanged | João authorized native integration in chat |
