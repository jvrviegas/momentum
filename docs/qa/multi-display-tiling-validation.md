# Multi-display tiling — validation record

## Scope and environment

- Worktree: `../.worktrees/multi-display-tiling`; branch `feat/multi-display-tiling`, base `58d1b9f`.
- Completed code scope: T2–T13 foundations/native integration/documentation. Early foundation gates and inert-action staging below are historical; current branch actions are enabled/unbound, and the draft MD functional rules describe current implementation. T14 full review/manual acceptance remains pending.
- Foundation phase: no live native probes or real window transfers. Subsequent authorized T1 helper probes are recorded below; no user-window transfer, display reconfiguration, logout, installed-app replacement, origin operation or commit performed.
- Existing test-host isolation remains active. New tests use synthetic frames/snapshots and fake hotkey/power dependencies. The pre-existing Carbon collision test retains its own registration/cleanup.
- Results directory: `/tmp/momentum-multi-display-baseline.h3VJeg`. These are local temporary artifacts, not committed binaries.

## Automated gates — 2026-10-08

All gates used the approved xcodebuild Debug/macOS test command. The baseline used a fresh DerivedData directory; subsequent gates reused it for incremental builds with separate result bundles.

| Gate | Result bundle | Outcome |
|---|---|---|
| Baseline | `Tests.xcresult` | 102 tests / 12 suites passed |
| T2 | `T2-fixed.xcresult` | 112 tests / 13 suites passed |
| T3 | `T3.xcresult` | 118 tests / 13 suites passed |
| T4 | `T4-fixed.xcresult` | 128 tests / 14 suites passed |
| T8 | `T8-fixed.xcresult` | 133 tests / 14 suites passed |

31 new tests; no baseline test deleted. The only existing test assertion updated was the Keep Awake last-action assumption: it now checks the end of the unchanged old-action prefix, with a new test proving both new actions append after that prefix.

Development failures were corrected before the passing gates: new test suites needed the project's MainActor convention; Swift Testing mutating-method assertions needed intermediate results; the Keep Awake action-order assertion needed the appended-action prefix described above. Failed result bundles/logs are retained alongside passing runs.

Xcode reports only the existing “Metadata extraction skipped, no AppIntents.framework dependency found” tooling warning. No Swift compiler warning in the passing final gate. Tracked diff whitespace and new-file trailing-whitespace checks passed.

## Coverage and evidence limits

| Component | Automated evidence | Not proven |
|---|---|---|
| Topology | Coordinate flip against one primary reference; negative/vertical/offset geometry; point-based usable bounds and safe padding; display order/wrap/ties; center/intersection/nearest ownership; fullscreen/unknown exclusion; invalid/empty/mirrored inputs | Live identity/mirroring inventory, physical scaling or display behavior |
| Spaces parser | Strict exact-identifier resolution; normal/fullscreen/unknown fixture classification; ordinal filtering; explicit normalized shared input; missing/ambiguous/malformed records rejected | Actual current private snapshot schema/shared mapping on the owner's OS |
| Layout state | Independent display/Space keys; unaffected-tree preservation; retained inactive layouts with explicit membership evidence; source collapse/destination insertion; deterministic deduplication; disconnect cleanup without move-back; local swaps and per-key focus | AX window discovery, live refresh/pruning, native transfer atomicity |
| Actions | Old binding preservation; raw values/titles; binding/null roundtrip; appended collision priority; fake routing without power changes; pending/inert dispatcher | Actual native transfer, configured production shortcut/UI manual acceptance |

No automated foundation result is a pass for live MD-01–MD-16 acceptance. The implemented user-visible staging behavior is documented separately in `docs/spec/multi-display-tiling.md`.

## Review validation — 2026-10-08

Fresh full-suite reruns passed 133 tests / 14 suites (`Review.xcresult`, `ReviewFinal.xcresult`); focused suites passed 57 tests / 5 suites (`ReviewFocused.xcresult`). Four disposable adversarial checks passed after correcting one disproven reviewer hypothesis (`ReviewProbes-corrected.xcresult`). Probe source/results remain in the temporary results directory; the temporary repository test file was removed. No production code changed or live probe ran. See the review for provenance, scoped criteria and the optional inconsistent-current-record finding.

## O1 snapshot-consistency hardening — 2026-10-08

Owner authorized the optional recommendation. Added four permanent regression tests before changing the parser; the focused red run (`O1-red.xcresult`) reproduced conflicting and malformed supplied current types being treated as mapped. The fix leaves activeSpace nil on any supplied type mismatch/invalid type, preserving the independently parsed Desktop list. Matching types retain normal/fullscreen/unknown classification; an absent type retains the existing fixture fallback. Existing live callers remain unchanged.

- Focused green: **21 tests / 1 suite passed**, `O1-focused.xcresult`.
- Full green: **137 tests / 14 suites passed**, `O1-full.xcresult` (35 added tests versus baseline; no tests removed).
- No Swift compiler warnings; existing AppIntents tooling warning only. Source snapshot hash: `31e778b074ffc85b9376ce500d978dc5ebf9cb7532d5512bf6a2bb15dfd86857`, manifest `o1-source-manifest.json` in the results directory.
- O1 resolved at the fixture-contract level. No live schema verification, native wiring, commit or push; T1 remains deferred.

## T1 live feasibility — 2026-10-10 (partial)

João explicitly authorized live probes in chat. These were isolated helper processes linked against the worktree's unchanged production `NativeSpaceMove.m`, not a new Momentum build or product acceptance test.

### Environment and limits

- macOS **27.0.1 (26A434)**; `NSScreen.screensHaveSeparateSpaces == true`.
- **SIP is an existing custom configuration**, with filesystem/debugging/NVRAM/boot-argument protections disabled. No SIP setting was changed. **Fully enabled SIP compatibility is NOT verified.**
- Installed Momentum stayed running as PID **1715** before and after; it was not paused, quit or replaced. No Keep Awake command/config edit was performed.
- Probe child processes were verified as accessory applications (excluded by the existing regular-app observer) and their CG window ownership was checked before any move. Only those child-owned temporary windows were moved, then terminated in cleanup.
- Existing screens were side-by-side/offset, not vertically stacked or mirrored. Both report backing scale **2**; different configured logical resolutions and refresh rates were observed, but a 1×/2× backing-scale mixture was not tested.

| Display | Runtime ID | Logical AppKit full frame | Usable AppKit frame | Mode raster / refresh |
|---|---|---|---|---|
| Primary LG HDR 4K | 3 | `(0, 0, 2560, 1440)` | `(0, 0, 2560, 1410)` | 5120×2880 / 60 Hz |
| Built-in Retina | 1 | `(-1800, -187, 1800, 1169)` | `(-1800, -187, 1800, 1130)` | 3600×2338 / 120 Hz |

Mode raster sizes are CGDisplayMode pixel sizes, not an assertion of panel-native resolution. AX conversion uses the primary AppKit maxY = 1440. Requested frame `(-1720, 577, 420, 240)` on the built-in display and `(80, 110, 420, 240)` on the primary matched actual AX and CG geometry in the settled pass.

### Results

| Check | Result / evidence |
|---|---|
| Display UUID → managed display mapping | Passed in current separate-Spaces mode: both public display UUIDs matched their managed records, and CGSManagedDisplayGetCurrentSpace agreed with the snapshot. |
| Actual raw snapshot → production parser/topology | Passed: temporary test replayed both saved snapshots through `Spaces.displaySnapshot` and `DisplayTopology`, without live reads inside the test. One test passed across two captures. |
| AX-only cross-display moves | 6/6 in the first pass; **6/6 in the settled pass**, verifying target Space plus AX and CG geometry. This demonstrates feasibility here, not that AX-only will always work on supported configurations. |
| Production native bridge + AX geometry | 6/6 in the first pass; **6/6 in the settled pass**, using the existing bridge. No synthetic drag/system shortcut was used. |
| Same-display native Desktop moves | 2/2 per pass: primary source Desktop → primary Desktop 1 → source. Membership confirmed while visible Desktops remained unchanged. |
| Display-local ordinal resolution | Actual replay resolved primary Desktop 1→Space 1, Desktop 2→Space 3. Built-in display has only one normal Desktop (Space 555): Desktop 1 resolves; Desktop 2 is unavailable. A distinct same-display Desktop move on the built-in screen could not be tested without creating a Desktop. |
| Visible Desktops and frontmost app | Unchanged within **each** pass. Primary active Space changed from 8 in the first pass to 3 before the second; do not claim it stayed unchanged across the entire session. Built-in active Space was 555. |
| Cursor | First pass comparison differed, so **not a pass** for cursor invariance then. Second pass recorded unchanged cursor. No probe code warps the cursor. |
| Cleanup | Both verified child processes terminated; no probe executable remained running. Temporary repository replay-test file was removed. Installed Momentum retained PID 1715. |

### Important integration finding: wait for stable geometry

The first pass sometimes saw AX geometry already at the requested target while CGWindowList geometry still reflected an intermediate bridged-move position, e.g. AX `(-1720, 577)` versus CG `(-1749, 543)`. A single immediate AX read is therefore not sufficient settling evidence.

The revised probe required **five consecutive samples, 20 ms apart**, in which requested AX geometry, WindowServer/CG geometry and destination Space membership all agreed. All 12 cross-display moves passed this stronger check. T9 should handle this transient disagreement with bounded settling before publishing success/following focus; this does not require changing the approved product behavior or prove the future implementation correct.

### Local artifacts and provenance

Directory: `/tmp/momentum-multi-display-live.zi8HFz`.

- `snapshot-before.json`, `snapshot-after.json`: read-only public-screen/private-managed-Space captures.
- `snapshot.m` / executable: read-only inventory helper.
- `probe.m` / executable: settled disposable child-window helper; compiled with AppKit and the actual production native bridge.
- `probe.jsonl`, `probe-settled.jsonl`, corresponding stderr files: raw per-move results, invariants and cleanup.
- `os.txt`, `sip.txt`, `momentum-before.txt`, `momentum-after.txt`: environment/process evidence.
- `CapturedDisplaySnapshotProbe.swift`, `CapturedReplay.xcresult`, `captured-replay.log`: isolated production parser replay. This temporary test is not part of the permanent 137-test suite.
- `PostProbeFull.xcresult`, `post-probe-full.log`: post-cleanup full suite passed **137 tests / 14 suites**. Production/test Swift source checksum still matches the O1 snapshot; no application/test implementation changed during probing.
- Settled source SHA256: `2e0092eb423008f2ad79ed9e0e0129bb8399e8b921a37df1f93cc5e977bd76a4`.
- Settled result SHA256: `0487fb924505f36fda4d3ded221cc5c1b14649e7a0161c47ba3ec18ef11c33bf`.
- Probe build had a helper-only identifier collision (`Rect` vs MacTypes typedef), corrected before execution. No production source changed.

### Remaining T1 gate

**T1 is partial, not complete.** Shared-Spaces live testing was subsequently **skipped at João's explicit request** because he does not use that mode; it is not a pass, and planned support for both modes has not been removed. Shared-mode compatibility remains unverified. Fullscreen mapping/transition checks subsequently passed in the follow-up below. Fully enabled SIP remains unverified; mirrored behavior remains an untested conditional hardware case. The full product/manual M1–M12 matrix remains separate. No Desktop was created, no user window moved, and no Spaces setting/log-out/SIP change performed. T5/native integration remains blocked unless these checks pass or João explicitly approves a documented gate/scope adjustment.

## T1 fullscreen follow-up — 2026-10-10

João explicitly approved briefly covering the secondary display with a disposable fullscreen probe. The helper verified child ownership/accessory activation policy before the child toggled its own window using public AppKit fullscreen APIs. Existing user windows were not toggled, moved or closed.

- Child PID **49580**, owned window **14233**; built-in display ID **1**.
- Native enter completed: current managed Space **562**, `type == 4`; probe membership **[562]**, AXFullScreen **true**.
- Actual fullscreen record also contains nested tile/wall Spaces (types 5/6); top-level display active Space/list entry remained the type-4 managed group. Production parser correctly ignores these nested details.
- Native exit completed: probe membership returned to original secondary Space **555**, AXFullScreen **false**.
- Per-probe visible mapping restored to primary **8**, secondary **555**. Frontmost app restored and child terminated. Read-only captures taken outside the probe interval may reflect intervening user Desktop changes; restoration is compared to the helper's own immediate pre-probe mapping.
- Installed Momentum remained PID **1715**. No Spaces-setting/SIP/config change, user-window move, app replacement, native product integration, commit or push.

### Production-code replay

A second disposable test replayed `fullscreen-active-managed.json` through the unchanged production parser/topology with captured screen geometry. It confirmed:

- Built-in active kind is fullscreen; display is ineligible as a transfer destination.
- Normal Desktop 1 still resolves to Space 555; Desktop 2 remains absent — fullscreen group 562 is excluded from Desktop numbering.
- Only primary display 3 is eligible; previous/next from it are no-ops rather than fullscreen transfers.
- Geometry ownership still identifies the built-in display, avoiding reassignment of its windows to the normal primary display.

**Two captured-replay tests passed** in `FullscreenReplay.xcresult`; this includes the earlier normal-snapshot replay. The temporary repository test was removed. Post-cleanup full suite passed **137 tests / 14 suites** (`PostFullscreenFull.xcresult`, `post-fullscreen-full.log`), and the permanent Swift source checksum still matches O1. These replays are input/parsing proofs, not end-to-end tests of future product commands.

Artifacts under `/tmp/momentum-multi-display-live.zi8HFz`: `fullscreen-probe.m`, executable/log/stderr, `fullscreen-before.json`, `fullscreen-after.json`, `fullscreen-active-managed.json`, `FullscreenReplay.xcresult`, `fullscreen-replay.log`.

- Fullscreen source SHA256: `44fac3e90f0c15c76d4a9edcbfc9fec77357aa92f931a26a1b4a4f9637ef965e`.
- Probe log SHA256: `1152b4673eb4f64da72bc0c61fec7c623f374d690964a9c10f1d7ecb8589ad79`.
- Helper-only compilation initially used a nonexistent ObjC `activate` selector; corrected to the SDK-declared `activateWithOptions:` before any fullscreen probe ran. No production code changed.

**Fullscreen mapping/enter/exit check passed in this separate-Spaces/custom-SIP environment.** Shared live tests remain owner-skipped; mirror-specific behavior remains untested (conditional hardware case). Fully enabled SIP compatibility remains unverified and still requires evidence or explicit approval to proceed with that validation gap; T1 is not automatically complete.

## Native integration — 2026-10-10

João explicitly authorized implementation with full-SIP compatibility pending; shared-Spaces live checks remain skipped. Implemented T5–T13 without installing or running the new tiler against real user windows. Installed Momentum retained PID 1715 during development.

| Code gate | Result bundle in `/tmp/momentum-multi-display-baseline.h3VJeg` | Passing tests |
|---|---|---|
| T5 refresh/native inventory | `T5-native.xcresult` | 145 |
| T6 independent animations | `T6-native.xcresult` | 149 |
| T7 directional focus | `T7-native-fixed.xcresult` | 152 |
| T9 verified mover | `T9-native.xcresult` | 159 |
| T10 commands | `T10-native-fixed.xcresult` | 165 |
| T11 drop reconciliation | `T11-native.xcresult` | 168 |
| T12 UI/errors and native-driver smoke | `T12-native.xcresult` | 170 |
| Additional failure/cancellation coverage | `Integration-hardening.xcresult` | 178 |
| Final integration/documentation | `Integration-final.xcresult` | **179 / 17 suites** |

77 added tests over the 102-test pre-feature baseline; no tests removed. The foundation pending-title/gate tests were updated for enabled integration, with production trust guards retained. Developer-time failures were fixed before green gates: a bounds-variable shadow and an unavailable-destination command refreshing source frames before recognizing a no-op. Both behaviors are covered in the final tests.

Coverage includes per-display bounds/tree isolation, shared normalized input, fullscreen/unknown exclusion, consistent inventory parsing, local-first cross-display focus/local swaps, independent display links/retargets/stale ticks, pointer-held deferral, Reduce Motion, failed-write cache clearing and final clamping repair, fixed-size floating transfers, native failures/partial topology changes, bounded stable AX+CG+membership sampling, cancellation/closure, source-display Desktop ordinals, serialized commands, release-only drag insertion/local resize behavior, and error dismissal.

`NativeAnimationSmokeTests` boots the injected coordinator and drives a **real native CADisplayLink against virtual windows**, with temporary config and no live AX observer, permission prompt, actual window move, hotkey registration or focus activation. It completed the 200 ms target and invalidated its link. This is a safe native-driver/lifecycle smoke, not end-to-end product tiling QA.

A read-only inventory capture after the monitor was unplugged showed one display, separate Spaces enabled, and matching public/managed display UUIDs (`/tmp/momentum-multi-display-live.zi8HFz/integration-inventory.json`). No test requires reconnecting the second monitor to code/build.

Final Swift source snapshot SHA256: `464ce261df1ce0da6c952e82721f88cddc93a99f6c48b5ac436fe577775a0723`; manifest `integration-source-manifest.json`. Only existing AppIntents metadata tooling warnings, no Swift warnings/errors. Tracked/new-file whitespace checked; README JSON example parsed and landing inline JavaScript syntax checked without opening a browser. No formatter/linter is configured. No signing/project-file edits, commits, pushes or release/version changes.

Implementation review of this new native snapshot is **not yet performed**. Earlier foundation/O1 review remains historical and does not approve this integration. README multi-display checkbox remains unchecked/awaiting validation; draft living MD rules supersede MDF staging rules.

## Native coordinator QA and review — 2026-10-12

Owner requested review and QA with both displays reconnected. The isolated harness compiled the unmodified production components, restricted discovery/selected focus to four verified accessory-child windows, and used real AX, WindowServer, native Space move and per-screen display-link clients. Installed Momentum remained running as PID 1715; no normal config/Keep Awake command was performed.

**Final batch: 16/16 targeted native checks passed**, including:
- Four windows tiled within both displays' usable bounds, with independent layout trees and local-only swapping.
- Actual AX focus crossing displays; verified tiled transfers/wrapping/focus-following with unchanged visible Desktops.
- Floating transfer stayed untiled and correctly shrank from 1268×1394 to 1268×1130 to fit the smaller display.
- Real native animation links settled on both 60/120 Hz screens after geometry perturbation. This is not a subjective smoothness/load assessment.
- Production drop reconciliation after controlled native geometry movement (not a user mouse gesture/observer-path pass).
- Unavailable Desktop error and native source-display ordinal send; visible Desktops checked again 300 ms after sending.
- Fullscreen fixture entry, production destination skip, normal Desktop restoration and close reconciliation.

Harness directory: `/tmp/momentum-multi-display-product-qa.bae8qL`.
Final results: `results-focused-fs.jsonl`, SHA256 `df21bdc475b1af73b1900660ba3eb1e2562c4599100434550f843f8a4b1f5729`.
Fresh complete suite: **179 tests / 17 suites passed**, `ReviewFull.xcresult`, `review-full.log`.
Reviewed source SHA256 remains `464ce261df1ce0da6c952e82721f88cddc93a99f6c48b5ac436fe577775a0723`; no production code changed during QA.

Earlier harness attempts are retained, not counted as passes. Numeric JSON dictionary keys caused Objective-C serialization exceptions/stalls. Fixture-only expectations for shrinking floating windows and fullscreen key-window/entry/exit sequencing were corrected; closed-window ownership was released so cleanup could be proven. A temporary hosted test was removed and no helper/test-host process remains. Do not attribute those harness failures to production code or claim an initial pass.

Code review: [native integration review](../reviews/multi-display-tiling-native-integration-review.md), same-agent requirements-led pass, no confirmed code blockers. One optional concern requests testing an app's own Move-to-Display command through the real observer. Previous foundation review is historical, not the native verdict.

**Full T14 acceptance is still incomplete:** actual production observer startup/registration and user mouse gestures, global hotkey dispatch/Settings/menu UI, vertical arrangement, physical disconnect/reconnect/primary-display change and subjective animation/load checks were not exercised. The harness intentionally did not expose the user's real windows to the development tiler. Shared live tests remain skipped, full SIP pending, mirroring untested. These limits remain documented; README checkbox stays unchecked.

## Manual preview prepared — 2026-10-12

Owner approved a temporary preview. Running preview PID **32142** and accessory fixture PID **31541** under `/tmp/momentum-manual-preview.isqwY2`; installed Momentum stayed PID **1715**.

The preview was built from a **temporary source copy**, not by editing the worktree, with QA-only isolation: dedicated config/bundle identity, QA badge/header, no Sparkle, observer/AX focus/frame/Space writes restricted to the fixture PID, accessory-fixture discovery allowed, no Desktop switching/Dock restart, unique Ctrl+Option+Command shortcuts, and fixture termination on preview Quit. Algorithms otherwise retain reviewed behavior. This does not prove unrestricted production discovery/coexistence.

Signed build verified. Read-only WindowServer checks confirmed all four labeled fixture windows on screen, tiled two per display. Two fixture windows initially belonged to an inactive Desktop after intervening user navigation; only those owned windows were moved to their displays' current Desktops, without switching user Desktops. No user window or normal config was modified.

Manual instructions/cleanup are in the preview directory's README. Owner subsequently confirmed the actual drag-across-and-back check: the test window joins the destination layout, both displays retile, and the preview does not fight the mouse before release. Record M6 actual mouse/observer flow as **user-observed pass in the restricted preview**, not an independently captured trace or unrestricted-production sign-off. Hotkey/Settings and hardware checks remain pending.

### Preview restart after safety timeout

The initial fixture exited on its 20-minute watchdog while the QA menu app remained running. At owner's request for the missing windows, restarted the isolated preview/fixtures: preview PID **35011**, fixture PID **34593**, owned windows **16208–16211**. Read-only checks confirmed all four on screen, two per display; installed PID 1715 unchanged. The temporary preview copy now reads and validates the exact fixture executable/PID at launch instead of hardcoding it; worktree production source is unchanged. No new manual check is implied by this restart.

### QA-only isolation-guard startup defect — corrected

Owner reported the restarted windows did not start tiled. WindowServer capture reproduced four 420×260 initial rectangles. Root cause was **the temporary preview copy**, not worktree integration: its launch-time PID guard compared the executable's resolved `/tmp/...` path against a hardcoded `/private/tmp/...` string, rejected the owned fixture and safely observed/wrote no windows. Both actual and expected URLs resolve to `/tmp/...` on this host.

Fixed only the temporary QAGuard/Quit cleanup to compare actual and expected URLs after applying the same resolution. Path-comparison regression probe proved old rejection and new match. Rebuilt preview PID **36290**, fixture still **34593**; all four windows independently confirmed visible and tiled (widths 888/888/1268/1268, within current usable bounds). Installed PID 1715 unchanged. Production source/tests unchanged; no full acceptance implied. Artifacts: `guard-inspection.json`, `status-reported-bug.json`, `guard-fixed-inspection.json`, `status-guard-fixed.json` under the preview directory. Manual checks should continue on this corrected preview.

### Manual windows reopened with longer watchdog

Owner requested reopening after the fixture timed out again. Reopened fixture PID **37458** (windows **16564–16567**) and restarted the guarded preview as PID **37506**. Extended only the temporary fixture's watchdog to 90 minutes; no production source/config change. Read-only checks observed settling into two tiles per display, and only owned windows were brought to current Desktops when user navigation had made them inactive. Manual results are still pending; restart is not a pass.

### Step-by-step manual pass — initial layout

Owner confirmed **Step 1 / M1 initial layout: pass** on the reopened guarded preview: two visible test windows per display, no overlap, small gaps and usable bounds respecting menu bar/Dock. Evidence is user-observed, not a captured independent trace. Owner confirmed **Step 2 / M4 cross-display focus: pass** using the actual preview global shortcuts in both directions; focus crosses at the edge without moving/resizing windows. Evidence is user-observed in the guarded preview. Owner confirmed **Step 3 / M4 local-only swaps: pass**: the two QA windows on one display swap via the actual shortcut, the other display is unchanged, and repeating at the edge does not transfer a window. Evidence is user-observed in the guarded preview. Owner confirmed **Step 4 / M5 tiled display-transfer shortcut: pass**: next-display moves the focused QA window, both displays retile, focus follows, and another invocation wraps back without switching Desktops or moving the cursor. Evidence is user-observed in the guarded preview. Owner confirmed **Step 5 / M6 actual cross-display mouse drag: pass** on the current corrected preview: free tracking while held, center-based destination insertion/retile on release, and return drag works. This exercises the restricted preview's actual observer/drag path; evidence is user-observed, not an independent trace or unrestricted production discovery proof. Owner confirmed **Step 6 / M7 floating toggle and display transfer: pass**: leaving the layout expands the remaining tile; a smaller floating window transfers and returns with its size/floating state intact, then rejoins tiling when toggled off. Actual preview shortcut/UI interaction, user-observed. Owner confirmed **Step 7 / M10 fullscreen destination exclusion: pass**: a fullscreen QA display stays fullscreen and is skipped by next-display transfer; exiting fullscreen restores transfer eligibility, and return transfer works. User-observed native button/shortcut interaction in the guarded preview. Owner confirmed **Step 8 / M11 actual Settings recorder and shortcut re-registration: pass**: clearing next-display via Delete unregisters the shortcut, so it does nothing on a test window; recording the same shortcut again re-enables transfer. This used QA Settings/temp config only; evidence is user-observed in the guarded preview. Later checks remain pending.

### Preview resumed after lunch

Owner requested reopening after lunch. Restarted isolated preview PID **44239** and fixture PID **44236**, windows **17136–17139**, with a four-hour fixture watchdog. Confirmed all four visible and tiled, two per display, at current geometry (built-in now to the right of primary). This restart is not a pass for live reconfiguration/disconnect; Step 9 still awaits owner results. Production source/config unchanged.

### Step 9 — physical disconnect/reconnect

Owner confirmed **Step 9 / M8: pass** after the lunch restart: visible QA windows retile on the remaining display, reconnect recovers valid targets, and next-display transfer works without restarting the preview. User-observed in the guarded preview; no independent relocation trace or full-SIP validation is implied. Remaining hardware/manual checks are still pending.

### Step 10 — vertical arrangement

Owner confirmed **Step 10 / M3–M4–M6: pass**: live vertical rearrangement preserves usable tiling, actual up/down focus shortcuts cross displays correctly, vertical mouse transfer joins the destination, and restoring the usual arrangement requires no restart or off-screen-window recovery. User-observed in the guarded preview; not an independent captured trace.

### Step 11 — animation controls

Owner confirmed **Step 11 / M3: pass**: QA swaps look smooth on each current display without noticeable flicker/jumps, disabling Animate tiling transitions gives immediate movement, and re-enabling works. Subjective user observation on disposable windows/current mixed-refresh hardware; not a frame-time benchmark or broad real-app load test. Reduce Motion still pending.

### Step 12 — Reduce Motion

Owner confirmed **Step 12 / M3: pass**: actual macOS Reduce Motion disables preview animation with the override off; enabling the preview-only override restores animation; override and original macOS preference were restored afterward. User-observed in the guarded preview, not independent instrumentation.

### Step 13 — source-display Desktop sending

Owner confirmed **Step 13 / M9: pass** on LG's existing normal Desktops: actual shortcut sends a QA window to that display's second Desktop without switching, Mission Control finds it there, and sending back to first Desktop again does not follow/switch. User returned through Mission Control. User-observed in the guarded preview; this is not full-SIP compatibility evidence.

### Step 14 — missing Desktop error UI

Owner confirmed **Step 14 / M9–M12: pass**: sending to nonexistent second Desktop on the built-in display leaves the QA window in place, the actual QA popover shows the unavailable-Desktop error, Dismiss Move Error clears it, and regular transfers still work. User-observed native error UI in the restricted preview.

### Step 15 — local drag swap and resize

Owner confirmed **Step 15 / M6: pass**: actual title-bar drop within the same display swaps QA tiles without changing the other display, and a small corner resize snaps back to its tile without swapping/floating. User-observed through the restricted preview's real mouse/observer path.

### Step 16 — actual close notification

Owner confirmed **Step 16 / M1: pass**: closing a QA window via its native red button expands the remaining tile on that display while preserving the other display's layout. User-observed through the restricted preview's native lifecycle/observer path; preview still running.

### Step 17 — actual pause/resume controls

Owner confirmed **Step 17 / M12: pass**: QA Tiling Enabled off permits manual placement/resizing without snap-back, new display-transfer shortcut does nothing, and re-enabling retiles current-display windows. User-observed native menu/global shortcut interaction in the guarded preview.

### Step 18 — actual shared layout settings

Owner confirmed **Step 18 / M3: pass**: changing gap/padding from 8 to 24 applies to both displays without restart, stays within usable bounds, and restoring both to 8 works. QA Settings/temp configuration only; user-observed.

### Final cleanup and restricted manual-suite result

Owner confirmed **Step 19 / cleanup: pass**: QA Quit removed the preview item and remaining windows while regular Momentum remained running. Independently verified no fixture/preview process remains and installed Momentum is still PID **1715**.

**All 19 guided manual checks passed in the guarded preview**, by owner observation. This includes actual mouse/AX observer, global shortcut registration/dispatch, Settings binding/layout controls, error dismissal, fullscreen, physical reconnect, vertical arrangement and animation/Reduce Motion behavior. Earlier user confirmations are not independent traces; the initial guard defect and fixture timeouts are QA-copy setup failures, fixed/restarted and separately documented. Permanent source and normal config were not changed by this pass.

This closes the restricted-preview manual suite, **not unrestricted regular-app/production startup validation**. Full-SIP compatibility remains unverified, shared live checks explicitly skipped, mirroring untested and review O1 (app-driven inter-display movement) still unverified. Keep those limits explicit; no public release/install/merge or commit/push follows automatically.

### Pre-commit validation and release request

Owner authorized commit/release preparation on 2026-10-12. Fresh full suite passed **179 tests / 17 suites**, `/tmp/momentum-multi-display-baseline.h3VJeg/PreCommit.xcresult`; whitespace gate passed. Implementation committed locally as `6e459cf` and `50cd7f1`. This is not additional native compatibility evidence; source-only prerelease preparation retains documented limitations and awaits explicit version confirmation.

## Pending gates

- **T1 partially performed with owner authorization:** current separate-Spaces/custom-SIP checks passed. Shared-Spaces live tests are owner-waived/skipped, not passed. Fullscreen checks passed in this environment. Fully enabled SIP remains unresolved; mirroring is an untested conditional case. João subsequently authorized T5/native integration with full-SIP compatibility explicitly pending; that is not a compatibility or product acceptance pass.
- **T5–T13 implemented/tested; code review, 16 targeted native checks and all 19 owner-observed guarded-preview manual checks passed. T14 remains limited by unrestricted regular-app/startup validation and explicit compatibility gaps, not by the completed guided mouse/hotkey/UI/hardware suite.**
- Guided M1/M3/M4/M5/M6/M7/M8/M9/M10/M11/M12 have restricted-preview owner-confirmed passes. Unrestricted regular apps/excluded-app discovery, app-driven Move-to-Display behavior and broader app/load/OS compatibility remain outside that evidence.
- Foundation review performed at owner request: `docs/reviews/multi-display-tiling-implementation-review.md`, approved within T2/T3/T4/T8 scope, no blockers, one optional snapshot-consistency recommendation subsequently resolved in the O1 follow-up above. This was a fresh requirements-led pass by the same agent, not separately authored reviewer sign-off. Full-feature/native review remains pending. Do not mark the README multi-display checklist complete.

Current-session live-probe authorization is recorded. Obtain owner cooperation before Spaces-setting changes/logout or other disruptive remaining checks; do not change SIP or infer permission to install/run live tiling, commit/push or release from integration authorization.
