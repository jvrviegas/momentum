# Multi-display tiling — native integration review

**Date:** 2026-10-12
**Worktree:** `../.worktrees/multi-display-tiling`
**Branch/base:** `feat/multi-display-tiling`, `58d1b9f` plus uncommitted changes
**Reviewed Swift snapshot SHA256:** `464ce261df1ce0da6c952e82721f88cddc93a99f6c48b5ac436fe577775a0723`
**Linear / PR:** N/A / none

## ✅ Result: Approved for code scope; QA sign-off incomplete

No confirmed blocking implementation defect was found in the reviewed snapshot. The full suite passed 179 tests and 16 targeted native checks passed on both connected displays. This is **not full T14 acceptance or release/merge readiness**: production observer/mouse/hotkey/UI paths and the remaining physical-display matrix require manual verification.

Review was a fresh requirements-led pass by the same agent, not independently authored external sign-off. The earlier foundation review remains a historical record of its earlier snapshot; this report covers native integration.

## Acceptance criteria

Criteria reproduced from the approved feature spec. “Verified” below is limited to the named evidence; untested paths are explicit.

| ID | Criterion | Status / evidence |
|---|---|---|
| MD-01 | When normal Desktops are visible on multiple displays, Momentum maintains an independent BSP layout for each display/Desktop pair. | ✅ Coordinator/native geometry verified with four owned windows, two per display; production discovery/startup still requires manual QA. `TilingManager.refresh`, `DisplayLayoutState.reconcile`, native M1. |
| MD-02 | When one display's windows change, another display's layout order remains unchanged unless its own windows or usable area change. | ✅ Unit/fake isolation and live local-swap/tree-independence checks. `MultiDisplayTilingTests`, native M4. Broader real-app lifecycle remains manual. |
| MD-03 | When separate Spaces are enabled, layouts follow each display's active Desktop; when disabled, displays share the active Desktop but retain separate layouts. | ✅ Separate-mode native inventory/parser and synthetic shared-mode normalization. Shared live validation explicitly owner-skipped, not passed. `Spaces.inventory`, `NativeSpaceMoveTests`. |
| MD-04 | When tiling runs, each layout uses its display's usable area and the shared gap, padding, animation and Reduce Motion settings, including mixed scaling and refresh rates. | ⚠️ Bounds and native animation settling verified on 60/120 Hz displays; Reduce Motion tested through injection. Subjective smoothness, more real apps/scaling variants and system-setting UI remain unverified. Native M1/M3. |
| MD-05 | When directional focus has no local tiled neighbor, it can focus the nearest eligible tiled window on another display in that direction; it does not wrap directionally. | ✅ Local-first/half-plane/no-wrap unit cases and real native cross-display AX focus. `DisplayTopology.crossDisplayNeighbor`, `TilingManager.focus`, native M4. |
| MD-06 | When a directional swap runs, it swaps only within the focused window's display/Desktop layout. | ✅ Unit and native local-swap/other-tree invariance. `DisplayLayoutState.swap`, native M4. |
| MD-07 | When previous/next-display transfer succeeds for a tiled window, it joins the destination's active normal Desktop layout, both affected displays retile, and focus follows it. | ✅ Live production command, native bridge, AX/CG placement, membership and actual AX-focused-window checks. Native M5. |
| MD-08 | When previous/next-display transfer runs, eligible displays are ordered by center left-to-right, then top-to-bottom for equal horizontal centers, and transfers wrap. With no other eligible display, the command is a no-op. | ✅ Three-display/vertical/tie cases synthetic; wrapping/empty eligible target behavior covered by unit tests and native two-display return. Physical vertical setup remains manual. |
| MD-09 | When a tiled window is dragged across displays and released, its center selects the destination and it joins that layout; floating windows remain floating. | ⚠️ Production drop reconciliation passed after controlled AX movement; mouse-held/release logic tested synthetically. Actual user drag → WindowObserver → tracking/drop chain was not exercised by the scoped native harness. |
| MD-10 | When a floating or excluded-app window is sent to another display, it stays untiled, preserves its size where possible, is positioned inside the destination's usable area, and retains focus. | ✅ Live floating transfer fitted the smaller display and stayed out of BSP trees; fixed-size/excluded cases and clipping covered in unit tests. Native M7. |
| MD-11 | When a display disconnects, Momentum tiles displaced windows wherever macOS relocates them. Reconnecting does not make Momentum actively move windows back. | ⚠️ Unit/fake topology and state cleanup passed. Physical unplug/replug/primary-display change not performed; needs owner participation while testing a preview. |
| MD-12 | When Send to Desktop N runs, N selects the Nth normal Desktop in Mission Control order on the focused window's display, without moving it to another display or switching Desktops. Shared-Spaces mode uses the shared Desktop order. | ✅ Native focused-display ordinal/membership and visible-Desktop invariance, including a 300 ms post-command check; fixture restored separately through low-level native move. Shared live validation skipped. Native M9. |
| MD-13 | When a display shows a fullscreen Space, it is excluded from cross-display focus/transfer destinations; native fullscreen windows are untouched. Commands do not automatically switch Desktops or exit fullscreen. | ✅ Native fullscreen target skip plus earlier captured type-4 parser tests; the harness explicitly entered/exited only its own fixture window, not a product command. Original normal secondary Desktop restored. Native M10. |
| MD-14 | When an existing config loads, existing bindings remain unchanged and the two new transfer actions are unbound. Users can bind or clear them through Settings or JSON. | ✅ Config/null/priority/routing tests passed and Settings discovery compiled. Real keyboard registration/event dispatch and Settings recorder interaction remain manual; native harness invoked `perform` directly. |
| MD-15 | When Desktop N does not exist on the selected display, Momentum reports an error without moving the window. | ✅ Native error publication/dismissal and unit error text. Native M9. Menu/Settings error presentation not exercised live. |
| MD-16 | When a native transfer fails or its destination disappears, Momentum does not publish an unverified successful transfer; it reconciles actual geometry/membership and reports failure. It never requires disabling SIP or automatically restarts the Dock. | ✅ Injected failure/cancellation/closure/topology tests, bounded five-sample AX/CG/membership validation, explicit Dock-recovery guards. No SIP change performed. Full-SIP compatibility is an owner-approved pending validation gap, not a pass. |

## Blockers

No confirmed code blockers found.

**Outstanding acceptance gate:** T14 is not complete. The native harness intentionally restricted discovery and selected-focus inputs to child-owned windows so the installed app/Keep Awake/user windows remained untouched. It therefore did not test production WindowObserver registration, real mouse notifications, global hotkey dispatch, actual Settings/menu UI, monitor disconnect/reconnect or vertical rearrangement. Do not mark the README checklist complete or claim final feature acceptance from this result.

## Optional recommendation

### O1 — Check app-driven inter-display movement through the real observer

`WindowObserver.handle` ignores non-mouse AX move/resize notifications; its polling observes only the on-screen window-ID set. An app's own Move-to-Display command can move a window between two already visible displays without changing that set. The scoped native harness calls production reconciliation explicitly and cannot prove this event path.

Verify that case in the full preview/manual pass. If no other notification causes reconciliation, add a narrowly tested display-ownership-change trigger rather than refreshing on every animation acknowledgment. This is an unverified coverage concern, not a reproduced blocker in this review.

## Validation performed

| Check | Result |
|---|---|
| Fresh full suite | ✅ 179 tests / 17 suites passed in `ReviewFull.xcresult` |
| Targeted native coordinator QA | ✅ 16/16 checks passed, `results-focused-fs.jsonl` |
| Real native display links | ✅ Both displays' targets settled after controlled geometry perturbation; separate native-driver smoke remains in permanent suite |
| Frame verification | ✅ Independent AX/WindowServer geometry and Space membership; native focus queried separately |
| Tracked whitespace | ✅ `git diff --check` |
| Permanent source integrity | ✅ Same reviewed SHA256 before/after; no production edits during review/QA |
| Formatter/linter | N/A — none configured |
| Test diagnostics | Existing AppIntents metadata tooling warning only; no Swift warnings/errors in passing final run |
| Full-SIP/shared/mirroring | Full SIP unverified and implementation-gap approved; shared live tests owner-skipped; mirroring untested |
| Real mouse/hotkey/UI and physical display changes | Not performed; final manual QA pending |

## Evidence and cleanup

Directory: `/tmp/momentum-multi-display-product-qa.bae8qL`.

- Unmodified production Swift components were compiled with the project's actor/concurrency flags and actual production `NativeSpaceMove.m`.
- `qa.swift`, `fixture.m`, `main.m`, `results-focused-fs.jsonl`, logs and `ReviewFull.xcresult` retain the harness/evidence. Child windows were ownership-checked and accessory-process excluded from the installed tiler. Temporary config was confined to this directory.
- The helper used real inventory/membership/AX writes/focus/native bridge/CG reads/display links, but scoped window discovery/focused input to verified fixture IDs. No real global hotkeys or production AX observer were started.
- Early harness runs stalled because its JSON dictionary used numeric keys, causing an Objective-C serialization exception. A temporary hosted test was removed; stranded helper/test-host processes were checked and cleaned up. No implementation change was made for this harness issue.
- A floating-size assertion initially ignored required shrink-to-fit, and the fullscreen fixture initially requested exit before entry finished/without its target being key. These fixture expectations/protocols were corrected; normal exit and window close then passed. Failed logs remain; none are counted as product passes.
- Final native result SHA256: `df21bdc475b1af73b1900660ba3eb1e2562c4599100434550f843f8a4b1f5729`.
- Final helper/fixture processes stopped. Installed Momentum stayed PID 1715; no normal config edits, app replacement, commits, pushes, release, SIP changes or physical monitor rearrangement/disconnection performed. Frontmost-app restoration was requested on cleanup, not independently asserted as a final pass.

## Verdict

- **Code result:** ✅ Approved within the reviewed/tested scope.
- **Confirmed code blockers:** 0.
- **Optional recommendations:** 1 observer-path verification concern.
- **QA status:** Targeted native coordinator checks passed; full T14 manual/product sign-off remains pending.
- **Recommendation:** Complete the real mouse/hotkey/UI and physical-display checks with an owner-authorized preview before final acceptance. Preserve explicit full-SIP/shared/mirroring limitations.

## Manual-preview follow-up — 2026-10-12

Original review above describes the earlier snapshot/evidence. Subsequent guided manual suite completed **19/19 owner-observed passes** in the QA-only guarded source copy: actual mouse/AX tracking, keyboard focus/swaps/transfers, floating, fullscreen, Settings recording/spacing/animation controls, reconnect, vertical layout, Desktop sending/error UI, close lifecycle, pause/resume and cleanup. Observer discovery and all writes were intentionally restricted to disposable fixture windows. Independent final process check confirmed the preview/fixture stopped and installed Momentum stayed PID 1715.

The temporary preview's PID guard initially rejected `/tmp` versus hardcoded `/private/tmp`; this QA-copy-only defect was fixed by symmetric URL resolution, not a production change. Timeouts/restarts and provenance are recorded in the QA ledger. The completed suite supersedes the earlier statement that guided mouse/hotkey/UI/physical checks had not run, **but does not prove unrestricted production discovery/startup, excluded regular apps, full-SIP compatibility or optional O1's app-driven movement path**. Shared live tests remain skipped and mirroring untested. Code verdict remains approved within reviewed scope; no new blanket merge/release sign-off is asserted.
