# Keep Awake — Implementation Review

**Date:** 2026-10-06  
**Worktree:** `/Users/joaoviegas/Projects/Personal/macos/.worktrees/keep-awake`  
**Branch:** `feat/keep-awake`  
**Commit:** `380cfae0056c9dd5e0ba0c8fea2301eab6f86a9f`  
**Base:** `daf18d874c9fc8cb876e9cf4a76afc8c80145b4d` (`main`)  
**Linear state:** N/A — repository-local feature  
**PR:** None; no remote operation performed

## Current verdict — re-review 2026-10-06

**Commit:** `54b1cad7ede55f887c5a60208e4ac109854cc540`  
**Result:** ❌ **Changes Requested — manual acceptance gate only**  
**B1:** ✅ Resolved · **B2:** ✅ Resolved · **B3:** ❌ Still open  
**Fresh validation:** 38 focused tests and all 93 regression tests passed; no new code blockers found.

The original review below is preserved as historical evidence. See the appended round-1 re-review for its statuses and verification. Subsequent partial native testing, final bold Charged icon selection (`594a0d9`) and local installation are recorded in `docs/qa/keep-awake-validation.md`; this report remains a snapshot of the reviewed commits, not a new full manual sign-off.

## Initial review: ❌ Result: Changes Requested

The ordinary lifecycle, persistence, routing and presentation tests pass, but two reproducible failure/boundary defects violate the approved session/mode contracts. Required manual OS/accessibility acceptance is also incomplete.

### Review scope and method

Criteria were re-derived from the canonical feature proposal and plan, not accepted from the implementation summary or tracker checkmarks. Reviewed the implementation diff, source, tests, documentation and relevant tiling/config/Carbon integration. Fresh validation includes focused and full Xcode suites plus a separately compiled fake-client reproduction harness against the actual production source.

This is a fresh requirements-based review pass by the same assistant, not a separate human/model reviewer; no independent reviewer tool or `code-review` skill was available. No implementation/test code was changed. Only this report was added. User authorization to use the normal macOS profile was honored; it does not waive the approved manual acceptance criteria.

## Acceptance Criteria

Canonical wording is copied verbatim from `docs/plans/keep-awake-feature-spec.md`. ✅ means demonstrated from code/tests; ⚠️ means implementation evidence exists but required runtime acceptance is outstanding; ❌ means a reproduced contradiction. Passing unit tests are not proof of native UI or OS behavior.

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| KA-01 | When starting a session, users choose **Keep system awake** (display may sleep normally) or **Keep system and display awake** (both idle-sleep protections requested). | ⚠️ Probable | `Momentum/PowerAssertions.swift:8–9,24–32`; `MomentumTests/PowerAssertionTests.swift:36,62`. Requests verified; actual idle/display effect pending M1. |
| KA-02 | When first used, defaults are **30 minutes, system-only**. Duration choices are **15 minutes, 30 minutes, 1 hour, 2 hours, 4 hours, 8 hours, Until stopped**. | ✅ Met | `Momentum/Config.swift:175–227,231,282`; `MomentumTests/ConfigStoreTests.swift:22`. |
| KA-03 | When inactive, the compact native menu-bar popover exposes inline duration/mode selectors and **Start**. Selecting either preference saves it immediately without starting a session. | ⚠️ Probable | `Momentum/MenuBarContent.swift:96–114,123`; `Momentum/KeepAwakeService.swift:112–154`; `MomentumTests/KeepAwakeServiceTests.swift:215`. Persistence/no-activation verified; actual native selector interaction pending M6. |
| KA-04 | When inactive, Start, the toggle, or the optional shortcut starts the remembered configuration. When active, the toggle, Stop, or shortcut ends the session and releases Momentum's sleep-prevention requests. | ⚠️ Probable | `Momentum/KeepAwakeService.swift:66–101`; `Momentum/AppController.swift:51–55`; `MomentumTests/KeepAwakeServiceTests.swift:45,255`. State/cleanup tested; native UI/shortcut exercise pending M1/M5. |
| KA-05 | When a timed deadline is reached, the session ends without a normal-expiry notification. An indefinite session continues until stopped or the app exits, subject to macOS protections. | ❌ Not met | `Momentum/KeepAwakeService.swift:156–160,199–201`. Normal expiry passes, but Retry mode change at expiry creates a fresh session: B1. |
| KA-06 | When a timed session is active, **+15 / +30 / +60 min** adds that amount to its existing deadline without modifying the saved duration. No eight-hour accumulated-session cap applies. Indefinite sessions hide these buttons. | ✅ Met | `Momentum/KeepAwakeService.swift:103–110`; `Momentum/MenuBarContent.swift:115–121`; `MomentumTests/KeepAwakeServiceTests.swift:96`; presentation tests verify indefinite visibility. |
| KA-07 | When users change an active session's mode in the popover, a successful change takes effect immediately, preserves the deadline, and saves the new default mode. | ⚠️ Probable | `Momentum/KeepAwakeService.swift:126–154`; `MomentumTests/KeepAwakeServiceTests.swift:122`. Ordinary successful changes preserve deadline/default; release-failure transaction is incorrect (B2), native interaction pending M7. |
| KA-08 | When timed sessions are active, a distinct awake variant of Momentum's menu-bar icon appears alongside remaining time rounded up to whole minutes. Indefinite sessions show the active icon without a countdown; inactive sessions show the existing icon. The open popover shows mode and remaining time or indefinite status; no indicator animations. | ⚠️ Probable | `Momentum/MenuBarContent.swift:11–46`; `Momentum/KeepAwakeService.swift:56–64,215–225`; `MomentumTests/KeepAwakePresentationTests.swift:6,14`. Derived values tested, actual menu-bar rendering pending M2/M6. |
| KA-09 | When macOS sleeps, elapsed sleep counts toward the deadline. On wake, only unexpired sessions resume protection; expired sessions end. | ⚠️ Probable | `Momentum/KeepAwakeService.swift:5–10,167–190`; `Momentum/AppController.swift:43–47`; `MomentumTests/KeepAwakeServiceTests.swift:155,182`. Sleep-inclusive API and synthetic notifications tested; actual sleep/lid wake checks pending M3. |
| KA-10 | When Momentum quits or crashes, its session ends. Relaunch starts inactive, retaining preferences but never restoring runtime session state or deadlines. | ⚠️ Probable | `Momentum/AppController.swift:57–66`; `Momentum/KeepAwakeService.swift:193–197`; `MomentumTests/KeepAwakeServiceTests.swift:45`; `MomentumTests/AppControllerTests.swift:64`. No runtime persistence; previous probe establishes process cleanup, app relaunch interaction pending M4. |
| KA-11 | When tiling is disabled or Accessibility permission is absent, Keep Awake and its configured shortcut remain usable without new permission prompts. | ⚠️ Probable | `Momentum/MyApp.swift:13–26`; `Momentum/AppController.swift:32–55`; `Momentum/TilingManager.swift:255–270`; `MomentumTests/AppControllerTests.swift:136`. Routing/guards verified; native AX-denied and disabled-tiling interaction pending M5. |
| KA-12 | When users optionally bind `toggle-keep-awake` through Settings or JSON, it follows KA-04. No shortcut is assigned by default; existing duplicate/unavailable-binding feedback applies. | ✅ Met | `Momentum/Config.swift:13,18,36,48`; `Momentum/SettingsView.swift:80–94`; `Momentum/AppController.swift:35–41`; `MomentumTests/MomentumTests.swift:82–88`; `MomentumTests/ConfigStoreTests.swift:22`. Schema, recorder wiring and Carbon collision regression pass. |
| KA-13 | When power changes between battery and external supply, the session and deadline remain unchanged. | ⚠️ Probable | `Momentum/AppController.swift:43–47` subscribes only to sleep/wake/termination; service has no power-source automation. Actual supply transition pending M4. |
| KA-14 | When the screen locks, the session and deadline remain unchanged. Display protection remains requested, but macOS may turn the locked display off; Momentum never unlocks the screen or simulates input. | ⚠️ Probable | `Momentum/AppController.swift:43–47`; `Momentum/PowerAssertions.swift:23–39`. No lock observer, simulated input or unlock code; actual lock/display result pending M3. |
| KA-15 | When Keep Awake is active, it does not bypass explicit Sleep, lid-close sleep, locking, or critical-battery protections. It does not guarantee wakefulness under every macOS condition. | ⚠️ Probable | `Momentum/PowerAssertions.swift:4–9,23–32`; `docs/qa/keep-awake-validation.md:14–19,21–31`. Public idle types only; explicit Sleep/lid/lock checks pending M3, critical-battery exhaustion intentionally not performed. |
| KA-16 | When preferences are saved, default duration, mode, and optional binding use `~/.config/momentum/tiling.json`. Runtime state is never persisted. External valid JSON edits affect future sessions only, not the current mode or deadline. | ✅ Met | `Momentum/ConfigStore.swift:48–75`; `Momentum/Config.swift:213–227,231,282`; `MomentumTests/KeepAwakeServiceTests.swift:45,215`; `MomentumTests/AppControllerTests.swift:108`. Atomic external edits retain active mode/deadline, runtime absent from JSON. |
| KA-17 | When the native SwiftUI popover replaces the existing menu, Keep Awake appears first, existing tiling/error controls remain below, and Settings, Check for Updates, and Quit remain accessible. Controls support keyboard focus and accessibility; no reference-app tabs or oversized branding. | ⚠️ Probable | `Momentum/MyApp.swift:32–42`; `Momentum/MenuBarContent.swift:57–81,84–136`. Ordering/commands/labels present, but actual keyboard focus, VoiceOver, Settings and Command shortcuts unverified: B3. |
| KA-18 | When activation fails, the UI stays inactive and presents an inline error with Retry, not a modal alert. No active indication appears before the requested protection succeeds. | ✅ Met | `Momentum/KeepAwakeService.swift:66–83`; `Momentum/MenuBarContent.swift:18,127–134`; `MomentumTests/KeepAwakeServiceTests.swift:200`; `MomentumTests/PowerAssertionTests.swift:62,94`. Failed acquisition is inactive, owned rollback IDs retained and diagnostics surfaced. |
| KA-19 | When an active mode change fails, the previous working mode, deadline, and saved default remain unchanged; an inline error is shown. | ❌ Not met | `Momentum/KeepAwakeService.swift:140–149,156–160`; `Momentum/PowerAssertions.swift:74–79`. Downgrade release failure changes old mode/default (B2); late failed-mode Retry resets deadline (B1). |
| KA-20 | When configuration values are invalid, the previous valid configuration remains active and the existing Settings error mechanism reports the failure. | ✅ Met | `Momentum/Config.swift:223–227,282–283`; `Momentum/ConfigStore.swift:64–75`; `Momentum/SettingsView.swift:20–25`; `MomentumTests/ConfigStoreTests.swift:22,50,93`. Invalid complete reload retains previous config/error feedback. |

## Blockers

### B1 — [P2] Retry mode change at expiry silently starts a new session

**Status:** ❌ Open

**Location:** `Momentum/KeepAwakeService.swift:156–160,199–201`; related UI `Momentum/MenuBarContent.swift:26–28,133`.

Concrete reproduction using a temporary config, fake assertions/clock/scheduler and the production service:

1. Start a 30-minute system session at clock 100: deadline 1900.
2. Fail acquisition of display protection during a mode change. Runtime remains system; `retryMode` is system-and-display.
3. Advance the clock to 1900 without delivering the queued scheduler callback.
4. Invoke the displayed **Retry mode change** action.

`retry()` calls `reevaluate()`, which stops the expired session and clears `retryMode`. It then falls through to inactive `start()` and acquires a new system assertion with deadline **3700**. A user action intended to retry a mode change is converted into a new Start, rather than preserving/ending the old session.

Observed output:

```text
RETRY AT EXPIRY: expected inactive, no new assertions;
observed active=true, oldDeadline=1900.0, newDeadline=Optional(3700.0), extraCreates=1
```

This contradicts KA-05 and the T6/S9 requirement that active-mode Retry repeats the attempted mode without resetting its deadline. The main-thread expiry callback can be delayed behind input; every command must enforce the boundary itself.

**Required change:** Capture the retry intent/session identity before expiry reconciliation. A retry intended for an active mode change must not become Retry Start if that session expires during reconciliation. Keep explicit failed-Start/wake-failure Retry Start working.

**Regression tests:** Failed active mode change followed by Retry exactly at and after the original deadline must remain inactive, acquire no new assertions and leave preferences unchanged. Cover a valid before-deadline retry as well.

### B2 — [P2] Failed downgrade release publishes the new mode and saves the new default

**Status:** ❌ Open

**Location:** `Momentum/KeepAwakeService.swift:140–149`; `Momentum/PowerAssertions.swift:74–79,94–107`.

Start system-and-display mode, then inject failures for both bounded attempts to release its display assertion and select system-only.

The candidate default is saved first. `PowerAssertions.commit` removes the display ID from the active ownership map, retains it as pending cleanup and records an error, but returns no failure result. The service unconditionally sets `mode = .system`. Both system and display requests remain live, the old display mode/default have been lost, and Retry targets cleanup rather than the failed mode change.

Observed output:

```text
FAILED DISPLAY RELEASE: expected previous mode/default system-and-display;
observed mode=system, savedMode=system, liveIDs=[1, 2], retryMode=nil,
error=review injected release failure
```

Ownership is not leaked, which is good, but this violates KA-19 and the plan's active-mode native-failure rollback contract. Reporting a diagnostic alone does not preserve the previous working mode/default or accurately reflect the retained display protection.

**Required change:** Make downgrade completion report/handle release failure transactionally. If the display request cannot be removed, retain the previous runtime mode/deadline and restore/preserve the previous remembered preference while retaining ownership of the unreleased ID. Do not publish a successful system-only mode while display protection is still held. Preserve bounded cleanup and diagnostic reporting, and provide the correct failed-mode Retry intent.

**Regression tests:** Inject display-release failure during downgrade and assert previous runtime mode, deadline, saved/default-on-disk mode, retained IDs and Retry target. Then let release succeed and verify Retry completes the downgrade without deadline reset. Also verify Stop still owns/releases the retained ID.

### B3 — Mandatory manual OS/accessibility acceptance remains unperformed

**Status:** ❌ Open — validation gate, not a reproduced native failure

**Evidence:** `docs/qa/keep-awake-validation.md:21–31,68`; `docs/plans/keep-awake-implementation-plan.md:119–126,168–187,231–243`.

M1–M7 are partial/pending. In particular there is no recorded pass for actual idle/display prevention, explicit sleep/lid wake before/after deadline, lock/power changes, closed-popover countdown rendering, AX-denied native shortcut behavior, keyboard/VoiceOver interaction, or the original Settings/Updates/Quit interactions.

API signatures, synthetic sleep/wake posts, presentation helpers and a three-second isolated GUI boot cannot prove these requirements. The plan explicitly says a missing mandatory OS/accessibility check blocks declaring the implementation complete. The QA/README documents correctly disclose this; leaving boxes unchecked avoids a false shipping claim but does not satisfy the acceptance gate.

**Required change:** Complete the remaining M1–M7 observations on the authorized normal profile, with a development build and only one interactive Momentum instance, and record expected/observed outcomes plus evidence. Arrange disruptive sleep/lid/lock checks with the user. Do not kill the unrelated `caffeinate` process or alter permanent power preferences automatically; it can mask idle behavior. Keep critical-battery exhaustion explicitly unperformed and record the documented API limitation/reviewer acceptance.

## Optional Recommendation

None found. No unrelated tiling, animation, Desktop, signing, release or compatibility refactoring is requested.

## Validation Performed

Environment: macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), authorized normal profile. Worktree clean at review start and unchanged apart from this report.

| Check | Result |
|-------|--------|
| Fresh focused Xcode suite | ✅ 29 tests in 5 suites passed |
| Fresh full Xcode suite | ✅ 84 tests in 12 suites passed |
| Separate fake-client boundary/failure reproduction | ❌ Both B1/B2 reproduced against reviewed production code |
| Whitespace gate | ✅ `git diff --check main..HEAD` |
| Swift compiler warnings | ✅ None; only Xcode's benign AppIntents metadata extraction warning on fresh build |
| Formatter/linter | N/A — no configured formatter/linter; no unrelated cleanup |
| Migrations | N/A — local native feature |
| Native/interactive M1–M7 rerun | Not performed; prior assertion/synthetic-lifecycle evidence inspected but not substituted for manual acceptance |

Focused command, run from the worktree:

```bash
REVIEW=$(mktemp -d /tmp/momentum-keep-awake-review.XXXXXX)
xcodebuild -project Momentum.xcodeproj -scheme Momentum \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$REVIEW/DerivedData" \
  -resultBundlePath "$REVIEW/Focused.xcresult" \
  -only-testing:MomentumTests/ConfigStoreTests \
  -only-testing:MomentumTests/PowerAssertionTests \
  -only-testing:MomentumTests/KeepAwakeServiceTests \
  -only-testing:MomentumTests/AppControllerTests \
  -only-testing:MomentumTests/KeepAwakePresentationTests test
```

Full command uses the same project/configuration/destination/derivedDataPath, removes all `-only-testing` options and sets `-resultBundlePath "$REVIEW/Full.xcresult"`. Review output directory: `/tmp/momentum-keep-awake-review.Kia02a`; logs: `/tmp/momentum-keep-awake-review-focused.log` and `/tmp/momentum-keep-awake-review-full.log`.

B1/B2 harness is temporary, not a shipping preference or code edit:

```bash
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  Momentum/Config.swift Momentum/ConfigStore.swift \
  Momentum/PowerAssertions.swift Momentum/KeepAwakeService.swift \
  /tmp/momentum-keep-awake-review-repro.swift \
  -o /tmp/momentum-keep-awake-review-repro
/tmp/momentum-keep-awake-review-repro
```

It injects a fake power client (no native create/release), a fake clock and a scheduler that intentionally withholds callbacks. All config writes go to a uniquely named temporary directory and are cleaned up.

## Verdict

- **Result:** ❌ Changes Requested
- **Blockers remaining:** 3 — two reproducible code defects and one required validation gate
- **Optional recommendations:** 0
- **Recommendation:** Fix B1/B2 with regression tests, complete the approved manual evidence and request re-review before declaring acceptance complete or checking the README feature tracker.

**Next step:** After the fixes are committed, ask me to `re-review keep-awake`; I will validate the previous blockers, rerun the checks and update this review file.

---

## Re-review — 2026-10-06 (round 1)

**Reviewed commit:** `54b1cad7ede55f887c5a60208e4ac109854cc540`  
**Previous reviewed commit:** `380cfae0056c9dd5e0ba0c8fea2301eab6f86a9f`  
**Fix commits:** `f990a4c` (B1), `7c24ce3` (B2), `54b1cad` (behavior/validation documentation)  
**Result:** ❌ **Changes Requested — manual acceptance gate only**

### Previous findings

| Finding | Current status | Fresh evidence |
|---|---|---|
| B1 — expired failed-mode Retry starts a new session | ✅ Resolved | `Momentum/KeepAwakeService.swift:156–164` captures active intent/attempted mode before expiry, then returns if that active session expired. `MomentumTests/KeepAwakeServiceTests.swift:256–296` covers exact/after deadline, withheld scheduler callback, no new requests and unchanged preferences, plus valid before-deadline Retry. Separate compiled harness now observes inactive, nil deadline and zero extra creates at expiry. Failed activation and wake-failure Retry Start tests still pass. |
| B2 — failed downgrade changes working mode/default | ✅ Resolved | `Momentum/PowerAssertions.swift:74–81,107–109` throws after at most two unsuccessful releases and retains the display ID in working ownership. `Momentum/ConfigStore.swift:49–75` saves before native completion, restores the previous file on completion failure and publishes only after success. `Momentum/KeepAwakeService.swift:138–153` preserves runtime mode/deadline on failure and targets mode Retry correctly. Service tests at `155–227`, power test at `62–84` and config tests at `79–137` pass. |
| B3 — mandatory manual OS/accessibility acceptance | ❌ Still open | `docs/qa/keep-awake-validation.md:21–31` still marks M1–M7 partial/pending. The new native downgrade/synthetic-lifecycle smoke is useful but does not prove actual idle/display, sleep/lid/lock, closed-popover rendering, keyboard/VoiceOver or native shortcut/command interaction. |

B2 was verified with both possible remembered defaults (including external defaults already set to system-only), the exact previous on-disk preferences, no candidate publication/callback, retained live IDs, bounded attempts, successful Retry without resetting the deadline, and Stop releasing both still-owned requests. Save failure is checked before native downgrade release. A live-watcher test verifies rollback does not later publish the rejected candidate.

The simultaneous native-failure plus failed-file-restoration diagnostic test passes and the draft behavior document accurately describes that limitation: runtime/in-memory preferences remain old and both errors are surfaced, without claiming successful on-disk restoration when the filesystem is unavailable.

### Current acceptance matrix

This table supersedes the initial table's statuses for the new commit; canonical criterion wording remains in the original table above. All criteria were reconsidered for regressions, not only B1/B2.

| Criterion | Current status | Verification / outstanding evidence |
|---|---|---|
| KA-01 — two protection modes | ⚠️ Probable | Power requests/types and mode transitions tested; actual M1 idle/display behavior still pending. |
| KA-02 — defaults and duration choices | ✅ Met | Strict config/default/round-trip suite passes; schema unchanged by fixes. |
| KA-03 — inactive selectors persist without Start | ⚠️ Probable | Service/config tests pass; actual native picker interaction requires M6. |
| KA-04 — Start/toggle/Stop/shortcut | ⚠️ Probable | Lifecycle/routing/Stop regressions pass; M1/M5 native interaction pending. |
| KA-05 — silent finite expiry / indefinite | ✅ Met | Expiry/stale scheduler/indefinite tests pass; B1 exact/after deadline regression now passes without a replacement session. |
| KA-06 — existing-deadline extensions and visibility | ✅ Met | Extension arithmetic/default isolation/presentation regressions pass unchanged. |
| KA-07 — immediate successful mode change and persistence | ⚠️ Probable | Successful mode/Retry preserves deadline and saved default, B2 resolved; actual M7 interaction pending. |
| KA-08 — active icon/countdown/status | ⚠️ Probable | Presentation/boundary values pass; actual closed-popover label rendering pending M2/M6. |
| KA-09 — sleep-inclusive deadlines / wake reconciliation | ⚠️ Probable | Clock API and synthetic wake/expiry tests pass; actual sleep/lid checks pending M3. |
| KA-10 — exit/crash/relaunch inactive | ⚠️ Probable | Shutdown/cleanup/no-runtime-persistence tests pass; app relaunch/power interaction pending M4. |
| KA-11 — independent of AX/tiling guards | ⚠️ Probable | Routing and existing tiling guards unchanged and tests pass; native AX-denied shortcut interaction pending M5. |
| KA-12 — optional binding and feedback | ✅ Met | Schema, null unbinding, feedback and Carbon duplicate-priority regression pass. |
| KA-13 — no power-source session mutation | ⚠️ Probable | No power-source automation introduced; actual supply transitions pending M4. |
| KA-14 — lock leaves session/deadline unchanged | ⚠️ Probable | No lock automation/input simulation introduced; actual M3 lock behavior pending. |
| KA-15 — respect OS safety boundaries | ⚠️ Probable | Public idle assertion strategy unchanged; actual explicit Sleep/lid/lock evidence pending and unsafe battery exhaustion excluded. |
| KA-16 — shared config, no runtime persistence / external edit isolation | ✅ Met | Config/live atomic-edit suites pass; unchanged remembered preference still executes native completion and does not spuriously notify observers. |
| KA-17 — native accessible popover and preserved commands | ⚠️ Probable | UI structure/labels/commands unchanged; keyboard/VoiceOver and native command acceptance still pending M6. |
| KA-18 — activation failure stays inactive, inline Retry | ✅ Met | Failed first/second assertion, rollback, presentation and failed-wake Retry tests pass; fixes did not introduce optimistic activation. |
| KA-19 — failed mode change retains working state/default | ✅ Met | B2 resolved for native release failure as well as acquisition/save failures; old disk/runtime/deadline/ownership and Retry target checked. |
| KA-20 — invalid complete reload retains valid config/error | ✅ Met | Strict decoding and invalid reload/watcher suites pass; existing Settings error mechanism retained. |

### Fresh validation

| Check | Result |
|---|---|
| Focused Keep Awake/config/controller/presentation suites | ✅ **38 tests in 5 suites passed** |
| Full regression suite | ✅ **93 tests in 12 suites passed** |
| Separately recompiled B1/B2 fake-client harness | ✅ Both corrected behaviors verified; successful downgrade Retry preserves deadline |
| `git diff --check main..HEAD` | ✅ Passed |
| Swift warnings | None; fresh Xcode build emits only the benign AppIntents metadata extraction warning |
| Manual M1–M7 | Not rerun/completed; still partial/pending |
| New code blockers | None found in this re-review |
| Implementation changes by reviewer | None |

Both Xcode runs used the original review's command structure with a new `mktemp` output directory: `/tmp/momentum-keep-awake-rereview.Ru0ad5`. Result bundles are `Focused.xcresult` and `Full.xcresult`; logs are `/tmp/momentum-keep-awake-rereview-focused.log` and `/tmp/momentum-keep-awake-rereview-full.log`.

The separate reproduction harness was compiled freshly from the reviewed source with Swift 6/MainActor isolation; observed output:

```text
RETRY AT EXPIRY: active=false, oldDeadline=1900.0, newDeadline=nil, extraCreates=0
FAILED DISPLAY RELEASE: mode=system-and-display, savedMode=system-and-display,
liveIDs=[1, 2], retryMode=system, error=review injected release failure
Both review regressions now satisfy expected behavior; downgrade Retry preserves deadline.
```

Harness output: `/tmp/momentum-keep-awake-rereview-repro.log`. It uses only fake power requests, a withheld scheduler and temporary configs; no native power preference changes or disruptive sleep/lid/lock actions were performed. Normal-profile authorization remains in force, and no origin/GitHub operation was needed.

### Current verdict

- **Result:** ❌ Changes Requested **solely because B3 remains open**
- **Code blockers remaining:** 0
- **Required validation gates remaining:** 1 (M1–M7 manual acceptance)
- **Optional recommendations:** 0
- **Recommendation:** No further implementation fix is requested by this review. Complete and record the approved manual OS/UI/accessibility evidence before full approval, shipping claims or README checkbox changes.

**Next step:** Complete the manual checks and ask me to `re-review keep-awake`; I will verify the remaining B3 evidence, rerun the relevant checks and update this file.

