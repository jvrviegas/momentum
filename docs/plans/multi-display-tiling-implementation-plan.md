# Multi-display tiling — implementation plan

## Status and authorization

- **Plan:** approved by João in chat on 2026-10-08; sequencing revision approved; T2–T13 foundation/native code and documentation implemented and tested in the dedicated worktree; T1 compatibility evidence partial, T14 guarded manual suite passed with unrestricted/compatibility limits; implementation committed locally, release preparation pending version confirmation.
- **Spec:** [multi-display-tiling-feature-spec.md](multi-display-tiling-feature-spec.md).
- **Inspected base:** local `main`, `58d1b9f`, 2026-10-08; working tree was clean before writing these documents. No fetch or other origin operation performed.
- **Work performed:** source inspection, SDK/API research, planning and pure foundation implementation. Baseline 102 tests; final native-integration gate 179 tests passed. Authorized T1 helper probes on 2026-10-10 verified current separate-Spaces/custom-SIP feasibility, but the full native gate and product acceptance remain incomplete.
- **Next gate:** T14 full implementation review and owner-authorized product/manual QA. T1 compatibility evidence remains partial. Shared-Spaces live testing is owner-waived/skipped (planned support remains, compatibility unverified). Fullscreen mapping/enter/exit passed in the current environment. João approved continuing native integration with fully enabled SIP compatibility explicitly pending (2026-10-10). This is an implementation-gate adjustment, not a compatibility pass or release/acceptance waiver. Mirroring-specific validation remains an untested conditional hardware case. Full manual acceptance remains at T14.
- **Safety:** this planning request does not authorize moving the owner's real windows, changing Spaces settings, logging out, replacing the installed app, committing/pushing, or publishing a release. Ask before disruptive validation. Use temporary config/build paths and only one live Momentum instance.

Use `docs/plans/` rather than introducing a second roadmap or `.specs/` tree. README remains the sole high-level v1 tracker. Implementation must update a living spec in the same change, clearly marked draft until acceptance.

## Agreed decisions

| ID | Decision |
|---|---|
| D1 | Independent BSP layout per display/Desktop pair; changes on one display do not rearrange another. |
| D2 | Directional focus crosses displays at the local edge; swaps stay local. |
| D3 | Previous/next-display transfers are configurable; tiled windows join the destination and focus follows. |
| D4 | Drag/drop transfers at release using the window center; floating windows remain floating. |
| D5 | Support both separate and shared Spaces. |
| D6 | Follow macOS relocation on disconnect; do not actively restore windows on reconnect. |
| D7 | Send to Desktop N resolves the focused window's display, excluding fullscreen Spaces; missing destination reports an error. |
| D8 | Shared settings; no per-display overrides in v1. |
| D9 | Previous/next order is display center x ascending, then center y ascending in top-left coordinates; wrap; one eligible display is a no-op. |
| D10 | Floating/excluded windows can transfer and remain untiled; preserve size where possible and keep them visible. |
| D11 | Skip fullscreen destinations and leave fullscreen windows alone; no automatic Desktop switching. |
| D12 | New actions have no default bindings; preserve all existing shortcuts. |
| D13 | Owner can test two displays with different scaling/refresh rates, horizontal and vertical arrangements, and both Spaces settings. |
| D14 | Build pure components/config actions with automated and mocked tests first; defer live probes until authorized. Initial native gate subsequently adjusted by D15; full manual acceptance remains at the end. |
| D15 | 2026-10-10: native integration authorized with full-SIP compatibility pending, shared-Spaces live tests owner-skipped and mirroring untested. No full-feature acceptance, install/run-live-tiling, commit/push or release authorization implied. |

Technical details below were approved with the written plan on 2026-10-08. If feasibility requires changing D1–D15 or the approved approach, stop and ask João; do not silently narrow the feature.

## Source map and reuse

Pointers refer to the inspected base; recheck after rebasing.

| Source | Existing behavior / reuse |
|---|---|
| `Momentum/TilingManager.swift:22–39` | Single `[SpaceID: BSPTree]`, global window cache/focus and one animation/link; must become display-aware. |
| `Momentum/TilingManager.swift:101–130` | Refresh filters window centers to primary screen and primary Space; pruning only checks Space membership. |
| `Momentum/TilingManager.swift:138–204` | Existing animation retarget/cancel/native clamping logic; preserve it with per-display ownership. |
| `Momentum/TilingManager.swift:232–263` | Same-display drag swap, primary-only coordinate flip and bounds. |
| `Momentum/TilingManager.swift:271–357` | Commands select primary tree/Space; native move suspends refresh until membership confirmation. |
| `Momentum/Spaces.swift:mainDisplaySpace`, `desktopSpace(_:in:displayIdentifier:currentSpace:)` | Existing private snapshot parser already accepts a display identifier; reuse/generalize rather than invent Desktop IDs. |
| `Momentum/SpaceMover.swift:move(windowID:toSpace:request:membership:wait:)` | Confirmed native Space move with injected dependencies, timeout/cancellation and same-Space no-op. |
| `Momentum/SpaceMover.swift:switchTo` | System shortcuts; completion can be recognized when any display's Space changes. Keep this behavior. |
| `Momentum/WindowObserver.swift:start()` | Already observes active-Space and screen-parameter changes; reuse event coalescing, not a second polling loop. |
| `Momentum/WindowObserver.swift:handle()` | Mouse AX events trigger drag handling; programmatic AX move/resize events are ignored. Explicitly refresh after commanded transfers. |
| `Momentum/AXWindow.swift:isStandard`, `setFrame`, `focus` | Existing fullscreen/minimized/hidden filters, ordered AX writes and focus behavior. Frame-write success alone does not prove a cross-display transfer. |
| `Momentum/BSPTree.swift:sync`, `neighbor`, `swap`, `window(at:)` | Keep BSP independent of displays. Reuse local insertion, focus, swaps and hit-testing. |
| `Momentum/Config.swift:Action`, `Config.defaultBindings`, decoder | Extend actions; explicit `null` stays unbound and omitted bindings use defaults. |
| `Momentum/SettingsView.swift:80–102` | Hotkey UI iterates `Action.allCases`; existing main-display explanatory text needs updating. |
| `Momentum/AppController.swift:perform` | Already forwards every non-Keep-Awake action to tiling; preserve AX-independent Keep Awake. |
| `MomentumTests/NativeSpaceMoveTests.swift`, `WindowAnimationTests.swift`, `MomentumTests.swift` | Existing fake-native move tests, pure animation/BSP/config regressions. Extend, don't replace. |

## Design

### Display snapshot and coordinates

Add `Momentum/DisplayTopology.swift`: one immutable snapshot per refresh/command containing logical display identity, full/usable AX-coordinate bounds, active Space ID and Space type. Capture screens and managed Spaces consistently; never reinterpret a missing secondary-display record as the primary Desktop.

- Use `NSScreen.screens.first` as the AppKit zero-screen reference, not `NSScreen.main` (keyboard-focused display).
- Convert every AppKit frame/visibleFrame with the same primary reference: AX x = rect.minX; AX y = primary.frame.maxY − rect.maxY. Preserve negative coordinates. Work in logical points; do not multiply by backing scale.
- Apply shared outer padding to usable bounds. Do not generate negative-sized targets when usable area is too small; bound effective insets safely.
- Associate screen number/CG display identity with the managed-display UUID. Runtime identity only; no persistent monitor database.
- Identify active normal versus fullscreen Spaces from the managed snapshot. Missing/unknown mapping is not an eligible destination.
- With shared Spaces, normalize the shared Space to each logical display; T1 must establish the actual snapshot form rather than relying on guessed keys/fallbacks.
- Mirrored outputs must not produce duplicate layouts/writes; verify the logical-screen inventory during T1 and handle duplicates if present.
- Owner selection: center containment first; in gaps/outside screens use greatest intersection, then nearest display, with stable identity tie-breaking. Fullscreen/unmapped displays must not be reassigned to an unrelated normal display just to force tiling.

### Layout reconciliation

Add a small pure `Momentum/DisplayLayoutState.swift` for `LayoutKey(displayID, spaceID)`, BSP trees and last-focused window per key. This is the test seam for display/Space reconciliation, not a replacement BSP algorithm.

`TilingManager.refresh()` reads windows once, assigns every eligible window to exactly one visible key, then synchronizes each key using its own bounds/focus. Removing a transferred window collapses only its source tree; insert it through existing BSP rules at the destination's remembered focus or last leaf.

Retain inactive-Desktop layouts without querying unavailable AX frames. Remove closed/wrong-Space entries when membership proves it; on visibility, reconcile display ownership. A shared Space ID alone cannot establish display ownership. Remove disconnected display runtime/animation state; do not persist stale restoration targets. Keep existing floating/exclusion and minimized/hidden handling.

### Focus and display ordering

Try the existing local BSP neighbor first. Only when absent, rank other normal displays' tiled-window candidates in the requested directional half-plane, using global tile geometry: directional edge distance, perpendicular center alignment, then stable window ID. Clamp directional distance at zero for offset/overlapping arrangements. Do not wrap directional focus, include fullscreen windows or suddenly focus floating windows. An empty display contributes no candidate.

Previous/next transfers use the agreed center-x/center-y order of eligible normal displays with identity as the final tie-breaker. Fullscreen displays are skipped, but an empty normal Desktop is a valid transfer destination.

### Native transfers and Desktop numbering

Add `Momentum/DisplayMover.swift` with injected native membership, geometry, frame-write and wait dependencies. Reuse `SpaceMover.move(windowID:toSpace:)` where a Space change is needed; an AX reposition alone is not assumed sufficient with separate Spaces.

Resolve the destination from a fresh topology snapshot; serialize the move, cancel stale animation writes, and suspend conflicting layout refresh/commands until completion. Verify both target Space membership (where distinct) and observed frame/display ownership before committing the layout transition and following focus. Revalidate topology during waits. Bound timeouts and reconcile actual state on failures; a native partially completed move cannot be represented as an atomic rollback guarantee.

For tiled transfers, final destination BSP geometry is authoritative. For floating transfers, preserve logical size, translate relative placement and clamp to the destination usable area; shrink only where necessary and supported by the app. App minimum-size constraints can prevent a perfect fit: report/reconcile actual geometry rather than retry forever.

Desktop N means the Nth **normal** Space in that display's snapshot order, not Space ID N. It is a per-display ordinal, which may differ from macOS's globally named shortcut labels. Generalize the existing parser with explicit source-display context. Do not change system-shortcut Desktop switching into a private display-local switch.

Keep new transfers under existing tiling command trust/enabled/suspension guards. Share the existing user-visible move-error surface, with display-aware messages and dismissal; preserve no automatic Dock restart and no cursor warping.

### Drag and animation

At drop, compare window-center owner with its source key before same-layout swap hit-testing. Cross-display drops insert into the destination, not cross-display swaps. Same-display move drops retain existing cursor-based swap behavior; same-display resizes retain existing snap-back. A geometry/Space mismatch after a cross-display drop must reconcile safely rather than reinsert into an assumed destination.

Maintain independent `WindowAnimation` state, requested-frame caches and screen-specific `CADisplayLink` per active display. One display's animation must not overwrite/cancel another's by retargeting a global animation. Never animate one window from two owners. Cancel affected state on Space/topology changes, transfer, drag, disable or invalidation; preserve Reduce Motion and native clamping repair. Do not promise identical frame timing across different refresh rates.

### API evidence and limits

Installed SDK headers confirm `NSScreen.screensHaveSeparateSpaces` and `displayLink(target:selector:)` in `AppKit.framework/Headers/NSScreen.h`. Existing AX wrapper and BSP explicitly use global top-left coordinates. Official Apple search references checked during planning:

- https://developer.apple.com/documentation/appkit/nsscreen/screens
- https://developer.apple.com/documentation/appkit/nsscreen/visibleframe
- https://developer.apple.com/documentation/appkit/nsscreen/screenshaveseparatespaces
- https://developer.apple.com/documentation/appkit/nsscreen/displaylink(target:selector:)

Public API signatures do not document the private managed-Spaces snapshot or bridged cross-display move. T1 live evidence is required. Fully enabled SIP compatibility remains unproven by this planning session.

## Execution and progress tracker

Execution is sequential, but task IDs remain unchanged for traceability. Revised order: **T2 → T3 → T4 → T8 → T1 → T5 → T6 → T7 → T9 → T10 → T11 → T12 → T13 → T14**. Pause after T8 until the owner authorizes T1. No parallel flags or separate deferred automated-test tasks. Each code task includes its own tests and a full-suite gate before its commit. Commit examples are suggestions, not authorization to commit.

Before T1, model normalized display/Space inputs and use explicit fixtures; do not claim fixture snapshots prove live private-API schemas. Keep native readers/movers and TilingManager integration out of these foundation tasks. Record assumptions for confirmation in T1; revise pure components if evidence differs.

| Task | Single deliverable | Depends on / execution predecessor | Status |
|---|---|---|---|
| T2 | Pure display topology component | None | Complete — 112-test gate; native mapping unverified |
| T3 | Display-aware Spaces resolver | T2 | Complete — fixture gate 118; native inventory wired in T5 |
| T4 | Pure layout-state component | T3 | Complete — fixture gate 128; coordinator integration in T5 |
| T8 | Configurable display action definitions | T4 | Complete — definition gate 133; activated by T10, still unbound by default |
| T1 | Native feasibility evidence | T8 (execution order) | Partial — separate Spaces/fullscreen/custom SIP passed; shared live tests owner-skipped; full SIP unverified |
| T5 | Multi-display refresh integration | T1, T4 | Code complete — 145-test gate; manual QA pending |
| T6 | Per-display animation ownership | T5 | Code complete — 149-test gate; native-driver smoke passed, mixed-rate QA pending |
| T7 | Cross-display focus selection | T6 | Code complete — 152-test gate; manual QA pending |
| T9 | Verified display-move component | T7, T8, T1 | Code complete — 159-test gate; 5-sample AX/CG/membership settling |
| T10 | Transfer-command integration | T9 | Code complete — 165-test gate; end-to-end native QA pending |
| T11 | Cross-display drag integration | T10 | Code complete — 168-test gate; real drag QA pending |
| T12 | User-facing copy/error presentation | T11 | Code complete — 170-test gate; native UI/keyboard QA pending |
| T13 | Behavior documentation | T12 | Complete — draft living rules, README, landing copy; final gate 179 |
| T14 | Manual acceptance record and review | T13 | Guarded suite complete — code review, 16 native checks, 19 owner manual passes; unrestricted/compatibility limits remain |

The table is the task dependency contract; the revised order above is a valid sequential execution map. T1 follows T8 for scheduling, not because config actions prove native feasibility. T5 and T9 explicitly retain the native gate and their component prerequisites; every listed prerequisite occurs earlier in the execution order. No separate diagram to drift.

### T1 — Prove native feasibility before native-dependent integration

**Where:** disposable isolated probe; record results in `docs/qa/multi-display-tiling-validation.md`. **Requirements:** MD-03, MD-07, MD-12, MD-13, MD-16.

- [x] With owner approval, capture display/Space snapshot mapping and coordinate frames, including fullscreen. Separate-Spaces normal/fullscreen captures and production-parser replays passed. Shared-Spaces live capture was explicitly skipped by João on 2026-10-10 (not passed); planned support is unchanged.
- [x] Move a throwaway standard window to the other display's active normal Desktop without switching Desktops/cursor or exiting fullscreen; capture actual AX geometry and Space membership. Verified only in current separate-Spaces/custom-SIP environment; T1 overall remains incomplete.
- [ ] Verify secondary-display Desktop resolution/order and actual move with fully enabled SIP. Record OS/build, SIP status and probe source.
- [ ] Check mirrored logical-screen inventory if available; otherwise record the untested limitation.
- [x] Restore probe window/config state and stop probes. Current-environment normal/fullscreen children terminated and original per-probe Desktops restored; no config edits were made. If the bridge cannot meet the contract on remaining supported configurations, stop for a scope/technical decision before T5/T9.

**Tests/gate:** native smoke evidence, not unit-test substitution. No production change. Suggested commit: `docs(tiling): record multi-display feasibility`.

### T2 — Display topology

**Where:** new `Momentum/DisplayTopology.swift`, `MomentumTests/DisplayTopologyTests.swift`. **Requirements:** MD-03, MD-04, MD-08, MD-09, MD-13.

- [x] Implement pure normalized snapshot/geometry/ownership/order rules using synthetic inputs and public-coordinate contracts, without live private readers. List unverified mapping assumptions for T1; do not hard-code a speculative shared-Spaces schema.
- [x] Unit fixtures cover negative origins, above/below/left/right layouts, unequal scale/size, usable insets, tiny bounds, center ties, gaps, empty inventories and unknown/fullscreen mapping.
- [x] Mixed backing scale does not alter point geometry; mirrored logical displays are not duplicated.

**Tests/gate:** unit + full suite. Suggested commit: `feat(tiling): model display topology`.

### T3 — Display-aware Spaces

**Where:** `Momentum/Spaces.swift`, `MomentumTests/NativeSpaceMoveTests.swift`. **Requirements:** MD-01, MD-03, MD-12, MD-13, MD-15.

- [x] Add fixture-tested active Space/type and Desktop ordinal parsing with explicit display identity. Do not switch production native readers/callers to the new resolver before T1; retain existing system-shortcut switching behavior.
- [x] Unit fixtures cover two display records, shared Spaces, missing record/UUID, malformed data, fullscreen exclusion, invalid ordinals and unrelated Space IDs.
- [x] Missing secondary mapping never silently resolves a primary-display target.

**Tests/gate:** unit + full suite. Suggested commit: `feat(spaces): resolve desktops by display`.

### T4 — Pure display-layout state

**Where:** new `Momentum/DisplayLayoutState.swift`, `MomentumTests/DisplayLayoutStateTests.swift`. **Requirements:** MD-01, MD-02, MD-03, MD-06, MD-11.

- [x] Implement keyed tree/focus state and reconciliation without AX calls.
- [x] Unit tests prove shared Space IDs do not merge displays, changing one key preserves the other's tree, inactive Desktop retention, one-owner transfer removal/insertion and disconnected-key cleanup without move-back intent.

**Tests/gate:** unit + full suite. Suggested commit: `feat(tiling): isolate per-display layout state`.

### T5 — Refresh all visible layouts

**Where:** `Momentum/TilingManager.swift:refresh/pruneState`, new `MomentumTests/MultiDisplayTilingTests.swift`. **Requirements:** MD-01–MD-04, MD-11, MD-13.

- [x] Replace primary-screen filtering with one-window-enumeration topology partitioning; use the pure state and per-key bounds.
- [x] Add narrow injected readers/writers as needed to run coordinator tests without observing/moving real windows. Do not start live observers in unit tests.
- [x] Fake integration tests verify frame targets for two visible keys, floating/exclusion/fullscreen filters, active-Space changes, config changes, no duplicates and screen removal/reappearance.
- [x] Keep Keep Awake startup/action behavior untouched.

**Tests/gate:** unit/fake integration + full suite. Suggested commit: `feat(tiling): refresh layouts across displays`.

### T6 — Per-display animation ownership

**Where:** `Momentum/TilingManager.swift:apply/animateFrame/cancelAnimation`, animation coordinator cases in `MultiDisplayTilingTests.swift`; retain `WindowAnimationTests.swift`. **Requirements:** MD-02, MD-04, MD-11.

- [x] Own animation/link/frame caches per display and bind each native link to its screen.
- [x] Fake driver tests cover simultaneous retargets, display/Space invalidation, stale ticks, unique window writer, disabled animations, Reduce Motion, drag cancellation and native clamp repair.
- [ ] Verify mixed-refresh-rate smoothness manually in T14; unit timing tests are not refresh-rate evidence.

**Tests/gate:** unit/fake integration + full suite. Suggested commit: `feat(tiling): animate each display independently`.

### T7 — Cross-display focus

**Where:** `DisplayTopology.swift` candidate helper and `TilingManager.swift:focus/move`, their tests. **Requirements:** MD-05, MD-06, MD-13.

- [x] Preserve local BSP-first navigation and local-only swapping; select the focused window's key, never the primary key by default.
- [x] Unit/fake integration cases cover left/right/up/down, offset and vertical displays, ties, empty destinations, fullscreen exclusion, no local neighbor, no directional candidate and no eligible focused window.

**Tests/gate:** unit/fake integration + full suite. Suggested commit: `feat(tiling): focus windows across display edges`.

### T8 — Unbound display actions

**Where:** `Momentum/Config.swift`, `MomentumTests/MomentumTests.swift`, `AppControllerTests.swift`. **Requirements:** MD-08, MD-14.

- [x] Add previous/next-display actions, titles and JSON identifiers (`send-to-previous-display`, `send-to-next-display`); include in `allCases`, no assigned default shortcuts. If exhaustiveness requires a dispatcher case, make it an explicitly temporary inert scaffold until T10, with a test; no native move or completed-feature claim.
- [x] Tests cover raw-value/title discovery, old config loading, JSON binding/null roundtrip, registration order/collision behavior and forwarding to tiling rather than Keep Awake.

**Tests/gate:** unit + full suite. Suggested commit: `feat(config): add optional display transfer shortcuts`.

### T9 — Verified native display move

**Where:** new `Momentum/DisplayMover.swift`, `MomentumTests/DisplayMoverTests.swift`; reuse `SpaceMover` and `AXWindow`. **Requirements:** MD-07, MD-10, MD-13, MD-16.

- [x] Implement the T1-proven transfer sequence with injected dependencies and bounded verification.
- [x] Unit tests cover separate/shared Space targets, AX failure/clamping, minimum-size limits, timeout, cancellation, closed window, disconnected target and successful geometry plus membership confirmation.
- [x] Success cannot be reported from native request return value or requested frame alone; failed partial moves return actual-state information for reconciliation. T1 observed transient AX/WindowServer geometry disagreement: use bounded stable geometry/membership verification before declaring completion, not one immediate AX read.

**Tests/gate:** unit + full suite. Suggested commit: `feat(tiling): verify native cross-display moves`.

### T10 — Transfer command integration

**Where:** `Momentum/TilingManager.swift:perform/sendToDesktop` and new display-transfer handler, `MultiDisplayTilingTests.swift`. **Requirements:** MD-07, MD-08, MD-10, MD-12–MD-16.

- [x] Route both new actions through fresh topology and DisplayMover; resolve Send to Desktop N on source display.
- [x] Fake integration tests prove wrapping, single/no-other-normal-display no-op, empty destination, floating retention, guards, refresh suspension, destination disappearing, reconcile-on-failure and focus-after-confirmation only.
- [x] Send to Desktop preserves same-Desktop no-op and source Desktop visibility; existing system-shortcut switching behavior stays unchanged.

**Tests/gate:** unit/fake integration + full suite. Suggested commit: `feat(tiling): integrate display-aware window transfers`.

### T11 — Cross-display drops

**Where:** `Momentum/TilingManager.swift:trackDrag/drop`, `MultiDisplayTilingTests.swift`. **Requirements:** MD-09, MD-10, MD-13, MD-16.

- [x] Determine center-based ownership on release before local hit-testing; reconcile actual Space/display membership before insertion.
- [x] Fake tests cover release-only transfer, source/destination tree changes, same-display swap/resize snap-back, floating/excluded windows, center over a gap, unknown/fullscreen destination and disconnect during drag.

**Tests/gate:** unit/fake integration + full suite. Suggested commit: `feat(tiling): reconcile cross-display drag drops`.

### T12 — Accurate UI and errors

**Where:** `SpaceMover.swift:MoveError`, `SettingsView.swift` and `MenuBarContent.swift` move feedback; tests in `NativeSpaceMoveTests.swift`/`MultiDisplayTilingTests.swift`. **Requirements:** MD-12, MD-14–MD-16.

- [x] Remove primary-only claims; explain per-display Desktop ordinals versus macOS shortcut switching, optional bindings and native API limitations.
- [x] Show/dismiss display-move failures using existing compact error presentation; test derived error messages and dismissal.
- [x] No per-display settings, new tabs or branding.
- [ ] Check the actual Settings recorder and keyboard navigation during T14.

**Tests/gate:** unit/fake presentation + full suite; native UI in T14. Suggested commit: `fix(tiling): clarify multi-display controls and errors`.

### T13 — Behavior documentation

**Where:** `README.md`, new `docs/spec/multi-display-tiling.md`, feature spec status, relevant primary-display claims in `docs/landing/prototype.html` if maintained. **Requirements:** MD-01–MD-16.

- [x] Write numbered living rules grounded in implemented behavior; mark draft/unaccepted until T14/review, not current shipped truth.
- [x] Update usage/configuration and avoid stale primary-only statements; leave README multi-display checkbox unchecked until acceptance.
- [x] Do not regenerate the conceptual landing film or claim it is an application recording.

**Tests/gate:** documentation review, `git diff --check`, full suite if any executable HTML changes; no application code in this task. Suggested commit: `docs(tiling): document multi-display behavior`.

### T14 — Manual acceptance and independent review

**Where:** `docs/qa/multi-display-tiling-validation.md`, `docs/reviews/multi-display-tiling-implementation-review.md` after approval to review. **Requirements:** all.

- [ ] Execute the matrix below with owner authorization; record version/commit, OS/SIP, display identities, resolution/scaling/refresh, actual steps and outcomes.
- [ ] Distinguish independently captured traces/screenshots from user-confirmed observations; skipped cases are not passes.
- [ ] Run final full suite and independent requirements review; fix blockers with tests in the corresponding code task.
- [ ] Only after acceptance update the README checkbox and spec status/link. This is source-preview acceptance, not authorization for a release.

**Tests/gate:** automated + native manual + independent review. Suggested commit: `docs(tiling): record multi-display acceptance`.

## Automated gate and test coverage

Use the existing Swift Testing / xcodebuild workflow; no new formatter or test runner is required. Start by recording a fresh pre-change baseline; the previous Keep Awake validation reported 93 tests, but that is historical evidence, not a test count verified here. Preserve all existing tests; record added test counts and explain any removals.

```bash
QA_BUILD=$(mktemp -d /tmp/momentum-multi-display.XXXXXX)
xcodebuild -project Momentum.xcodeproj -scheme Momentum \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$QA_BUILD/DerivedData" \
  -resultBundlePath "$QA_BUILD/Tests.xcresult" test
git diff --check
```

Use a new temporary directory for each result bundle. Configure the owner's development team if required; do not silently edit repository signing settings. Test host isolation is already implemented in AppEnvironment. New tests must inject topology/windows/native writes/clock/link drivers, not start real tiling, change real config or register new production shortcuts. Existing isolated Carbon test cleanup remains required.

| Tasks | Layer / required coverage | Co-located coverage | Granularity check |
|---|---|---|---|
| T1 | Native feasibility | Probe + recorded evidence in T1 | One feasibility deliverable |
| T2–T4 | Pure topology/Spaces/state | Unit tests in each task | One component per task |
| T5–T7 | Tiling refresh/animation/focus | Unit + fake integration in each task | One cohesive coordinator responsibility per task |
| T8 | Config/action discovery/routing | Unit tests in T8 | One action-extension deliverable |
| T9 | Move service | Unit tests in T9 | One component |
| T10–T11 | Command/drop integration | Unit + fake integration in each task | One handler responsibility per task |
| T12 | Copy/error presentation | Error/dismissal tests in T12; native UI additionally T14 | One cohesive presentation deliverable |
| T13 | Documentation | Link/content review + whitespace gate | One documentation deliverable |
| T14 | Native acceptance | Live matrix + independent review | One acceptance deliverable |

No code task defers its automated tests to T14. Native testing complements, not replaces, fake integration.

## Acceptance-to-test traceability

| Rule | Automated tasks | Manual case |
|---|---|---|
| MD-01–MD-02 | T4–T6 | M1 |
| MD-03 | T2–T5 | M2 |
| MD-04 | T2, T5–T6 | M3 |
| MD-05–MD-06 | T7 | M4 |
| MD-07–MD-08 | T2, T9–T10 | M5 |
| MD-09 | T11 | M6 |
| MD-10 | T9–T11 | M7 |
| MD-11 | T4–T6, T10–T11 | M8 |
| MD-12, MD-15 | T3, T10, T12 | M9 |
| MD-13 | T2–T3, T5, T7, T9–T11 | M10 |
| MD-14 | T8 | M11 |
| MD-16 | T9–T12 | M12 |

## Manual validation matrix

Run M1–M7 and M9–M11 in **both** separate/shared Spaces modes and **horizontal/vertical** arrangements: four setup combinations. Use the owner's two mixed-scaling/refresh-rate displays; the alternate Spaces setting/logouts are owner-controlled. M8/M12 need selected representative combinations plus automated fault coverage; record which, don't imply every permutation was tested.

| Case | Steps and expected result |
|---|---|
| M1 | Open/close/focus/float windows on each display; only the affected layout's order changes. Retile correctly targets both displays. |
| M2 | Switch Desktops on either display using native controls and existing shortcuts. Return to previous Desktops and check independent layouts. Verify shared mode does not merge display trees. Record actual system-shortcut switching behavior without promising display-local switching. |
| M3 | Check physical bounds, usable areas, gaps, padding, different scale factors and smooth concurrent transitions on both refresh rates. Toggle animations/Reduce Motion; verify no drift or dual-writer jitter. |
| M4 | Focus in all four directions across display edges; swap at those edges and confirm swaps remain local. Include an empty destination and an offset arrangement. |
| M5 | Temporarily bind previous/next; transfer tiled windows both ways, including an empty destination; focus follows after successful placement. With two displays wrapping means both commands reach the other display; test three-display/tie order with pure fixtures, not a false hardware claim. |
| M6 | Drag tiled windows across and back; no fight while dragging; center-based transfer on release; both layouts update. Same-display swap and resize behavior remains intact. |
| M7 | Transfer manually floating and excluded-app windows; size/position are sensible on the smaller usable display and they remain untiled. Drag across and confirm floating state persists. |
| M8 | Disconnect/reconnect, change primary display and change resolution/scaling/arrangement. Windows follow actual macOS relocation, no Momentum-driven move-back; no stale animation or off-screen targets. Test disconnect during a move/drop if safely reproducible. |
| M9 | Send to another existing Desktop from each display. Verify per-display ordinal/order, unchanged physical display/source Desktop visibility, same-Desktop no-op and missing-Desktop error. Test with fully enabled SIP. |
| M10 | Make one display fullscreen. Focus/transfer skips it; no automatic exit/switch. Restore normal Desktop and confirm eligibility returns. Try the action while the focused window itself is fullscreen; leave it unchanged. |
| M11 | Existing config/bindings unchanged; new actions start unbound. Bind, clear, reload JSON and relaunch; validate the Settings recorder and keyboard operation. Keep Awake still works with tiling unavailable. |
| M12 | Exercise user-visible failure/dismissal with controlled injected failures; native move membership/frame must be verified in T1/live runs. Tiling disabled/AX unavailable are guarded. Restore real config and stop all temporary builds/probes. |

Additional limitations: mirroring and app minimum-size refusal require evidence if available; otherwise list them explicitly in review. A single supported macOS run is not proof across all OS versions. Never request SIP disablement to make the feature pass.

## Implementation progress

- 2026-10-08 — João authorized foundation implementation. Created `feat/multi-display-tiling` at `../.worktrees/multi-display-tiling` from local `main` `58d1b9f`; copied the approved planning artifacts. No origin operation or commit.
- T2/T3/T4/T8 completed with co-located automated tests. New action titles explicitly say “not available yet”; `Action.isPendingDisplayIntegration` blocks native dispatch until T10. The existing Keep Awake action-order test now verifies the unchanged old-action prefix; no tests removed.
- Validation: baseline 102 tests; subsequent gates 112, 118, 128 and 133 tests passed. No Swift warnings; existing AppIntents tooling warning only. See `docs/qa/multi-display-tiling-validation.md` for result bundles, development failures/fixes and limits.
- Added current **foundation-stage only** living behavior rules (MDF prefix), not unimplemented MD acceptance claims. README checklist unchanged. No new live readers/movers, screen changes, real window moves, smoke-launch, commit or push. T1/T5 onward remain blocked/pending.

- 2026-10-08 — Owner requested foundation review. Fresh requirements-led review saved to `docs/reviews/multi-display-tiling-implementation-review.md`: approved for T2/T3/T4/T8 only, zero blockers and one optional current-Space consistency recommendation for native wiring. Same-agent review, not separate reviewer sign-off. Fresh gates passed 133 full-suite / 57 focused tests; temporary adversarial checks passed and were removed. No production changes. T1 remains deferred; full-feature acceptance/review is not complete.

- 2026-10-08 — João authorized optional O1 hardening. Supplied Current Space types must be valid and exactly match the list record; otherwise active Space remains unmapped. Missing type remains compatible with fixtures. Four permanent regressions reproduced the old behavior before the fix; 21 focused / 137 full tests now pass. Review follow-up appended; O1 resolved at fixture level. No native callers changed, probes, commits or pushes; T1 still deferred.

- 2026-10-10 — João authorized live T1 probes. Accessory child-window probes verified 6 AX-only + 6 production-bridge/AX cross-display moves with five-sample AX/CG/membership settling, plus a primary Desktop round trip. Current separate-Spaces snapshots replayed through the actual parser/topology successfully. Installed Momentum PID 1715 left running; children/replay test cleaned up. Host SIP was already custom/partially disabled, not changed. Shared Spaces/full SIP/fullscreen/mirroring remain unverified; T1 is partial and T5 still blocked. Evidence and the transient native geometry finding are in `docs/qa/multi-display-tiling-validation.md`. No application code changes, commits, pushes or scope change.

- 2026-10-10 — João explicitly waived shared-Spaces live testing because he does not use it. Record skipped/not passed; no setting/logout needed. This waives that live-check gate only, not D5/MD-03 support or the other outstanding native checks. Shared compatibility remains unverified; no automatic T5 authorization or full-feature approval.

- 2026-10-10 — João authorized a secondary-display disposable fullscreen probe. Actual top-level managed Space type 4 and membership/AX fullscreen agreed; exit restored secondary Space 555 and pre-probe visible mapping/frontmost app. Captured fullscreen parser/topology replay passed, including exclusion from destinations and Desktop numbering. Helpers/replay test cleaned up; installed Momentum unchanged. Full SIP remains unverified; shared live tests owner-waived; mirroring conditional case untested. T5 still blocked absent evidence/explicit adjustment. No application code changes or commits.

- 2026-10-10 — João authorized native integration after being told the second monitor is not required for coding/automated tests. Proceed with T5–T13 in the existing worktree; fully enabled SIP remains explicitly pending, shared-Spaces live tests owner-skipped, mirroring untested, and T14 product/manual acceptance still required. No authorization to install/run live tiling, commit/push or release is inferred.

- 2026-10-10 — Implemented T5–T13 after explicit gate adjustment: consistent native screen/Space inventory, keyed layouts, per-display animation state/links, cross-display focus, stable verified transfers, source-display Desktop ordinals and center-based drop reconciliation. Added TilingEnvironment as the narrow fake/native seam and NativeAnimationSmokeTests for real CADisplayLink startup with virtual windows only. No normal-profile tiling launch or installation. Unbound action scaffolds now enabled; current living rules supersede the old MDF staging-only behavior. README tracker remains unchecked/awaiting validation.
- Co-located full gates passed 145 (T5), 149 (T6), 152 (T7), 159 (T9), 165 (T10), 168 (T11), 170 (T12), 178 (hardening) and 179 (final). Corrected a local bounds-variable shadow and a no-op transfer that initially refreshed/wrote source geometry before checking destination availability; regression retained. Additional tests cover cancellation, transient geometry, fixed-size floating windows, failed animation caches and pointer-release deferral. No tests deleted; 77 additions over the 102-test pre-feature baseline.
- T14 review and actual two-display product acceptance remain pending; full-SIP compatibility pending, shared live tests skipped, mirroring untested. Fullscreen/transfer helper probes are earlier feasibility evidence, not a product acceptance pass. No new review verdict was written automatically. No commit, push, release or installed-app replacement.

- 2026-10-12 — Owner requested native review/QA with both monitors connected. Unmodified production core passed 16 targeted native coordinator checks using verified disposable windows; fresh full suite 179 tests, source fingerprint unchanged. Code review saved separately to `docs/reviews/multi-display-tiling-native-integration-review.md`: no confirmed code blockers, one observer-path verification recommendation, same-agent review. Harness serialization/setup failures corrected without product changes; cleanup verified. T14 remains partial because actual production observer/mouse/hotkey/UI and physical-display matrix were not exercised. Installed app/normal config untouched; no commit/push/release. See QA record for provenance and limits.

- 2026-10-12 — Completed 19-step guided manual suite in the owner-authorized, fixture-restricted preview; all owner-confirmed pass, including real observer/mouse/keyboard/UI, reconnect, vertical geometry and Reduce Motion. QA-copy guard path mismatch fixed outside worktree; timeouts/restarts documented. Preview Quit/fixture cleanup independently verified, installed PID 1715 unchanged. Restricted acceptance only: unrestricted regular apps/startup and app-driven movement concern still unverified; full SIP pending, shared live tests skipped, mirroring untested. No commit/push/install/release. QA and review follow-up updated.

- 2026-10-12 — João authorized committing and preparing a new release. Fresh pre-commit suite: 179 tests passed. Local implementation commits `6e459cf` (topology/state) and `50cd7f1` (native integration), with co-located tests. Source-only prerelease policy and documented full-SIP/unrestricted/shared/mirroring limits preserved. Release version will be confirmed before release branch/version/tag publication; no installer or installed-app replacement inferred.

## Sequencing revision log

- 2026-10-08 — João requested deferring live testing and approved foundation-first work. Reordered tasks without renumbering: T2/T3/T4/T8 can run with pure/fixture/mocked tests; live T1 remains unperformed and blocks native integration. Final manual acceptance stays at T14. This revision does not authorize probes, change behavior scope or mark any implementation task complete.

## File inventory and completion conditions

**New production files implemented:** `DisplayTopology.swift`, `DisplayLayoutState.swift`, `DisplayMover.swift`, `TilingEnvironment.swift` (T5's narrow injection boundary). **New automated test files:** corresponding component tests plus `MultiDisplayTilingTests.swift`. Existing TilingManager/Spaces/SpaceMover/Config/presentation tests change as described. Reuse the existing native bridge unless T1 proves a narrow extension necessary; record any extension and review its unsupported-API risk before proceeding. Xcode folder synchronization should pick up new Swift files; verify target membership rather than assuming.

Completion requires all MD rules mapped and verified, no review blockers, explicit manual evidence/limitations, living-spec update and accurate README status. No release/version bump, PR or origin operation is included. Follow `AGENTS.md` account-switch/restore rules if separately authorized origin work is later needed.
