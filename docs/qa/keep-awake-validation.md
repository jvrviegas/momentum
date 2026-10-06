# Keep Awake validation

## Environment and safety

- Base: `daf18d8`; macOS 27.0.1 (26A434), Xcode 27.0 (27A266a).
- User authorized the normal `joaoviegas` profile instead of a disposable profile. Tests must still use temporary configs and the app-host guard; no permanent power preferences are changed.
- No forced sleep, lid close, lock or unsafe battery exhaustion is performed automatically.

## T1 native probe

Compiled `/tmp/momentum-keep-awake-probe.swift` with `xcrun swiftc`, importing `IOKit.pwr_mgt` without extra link flags, entitlements or privileges.

- System create: status 0, ID 36805; display create: status 0, ID 36806. Both releases returned 0.
- A second release of the already released ID returned -536870206 (invalid/not found). Production will retain failed-release ownership, retry once, and report unresolved cleanup rather than silently discard it.
- Second run held both types: IDs 36807/36808. `pmset -g assertions` showed both named `Momentum feasibility probe`; after `kill -9` and a one-second wait neither appeared. No unrelated assertion was released.
- A separate `caffeinate` process was already present. This prevents claiming real idle-sleep behavior from these assertion-list checks.
- Partial creation/save rollback and bounded release retries will be checked with injected failures; real API failure is not deliberately induced.
- Sleep-inclusive clock verified in the installed `mach_time.h` contract, not yet by explicit sleep.
- Custom SwiftUI window-style label/picker API feasibility will be verified by building the app. Actual keyboard/VoiceOver and label rendering remain manual checks.

## Manual matrix

| Case | Status | Evidence / remaining work |
|---|---|---|
| M1 assertions and actual idle/display behavior | Partial | Native probe and production-service smoke create/release intended types; actual idle behavior pending |
| M2 expiry/extension/countdown with closed popover | Passed | Closed-popover countdown, +15 extension, indefinite no countdown/extension controls and actual 15-minute natural expiry verified |
| M3 explicit sleep/lid/lock and wake deadlines | Partial | Lock, explicit Sleep and lid-close sleep passed; valid timed wake preserves elapsed deadline. Indefinite/wake-after-expiry still pending |
| M4 power changes/exit/crash/relaunch | Passed (safe scope) | Awake battery↔AC, Stop, actual app Quit, SIGKILL cleanup and inactive relaunch with preferences retained passed; unsafe critical-battery exhaustion explicitly excluded |
| M5 AX-denied/tiling-disabled and shortcuts/config | Partial | Fake routing, live atomic edits, feedback and existing Carbon collision regression pass; native interaction pending |
| M6 keyboard/VoiceOver/appearance/Settings commands | In progress | User reported no Tab highlight/activation and no ⌘, response; keyboard navigation is disabled. Agent reproduced successful ⌘, Settings opening with real popover focus. User retest pending; VoiceOver declined by user, not passed |
| M7 injected error UI | Partial | Native/save/rollback/release failure unit tests and Retry presentation pass; actual injected-error UI interaction pending |

## Automated quality gate (2026-10-06)

The exact plan `xcodebuild ... test` gate passed on the authorized normal profile, with a fresh `mktemp` build directory:

```text
/tmp/momentum-keep-awake-quality.71Hcod/Tests.xcresult
84 tests in 12 suites passed
TEST SUCCEEDED
```

`git diff --check` passed. No formatter/linter is configured. Only Xcode's benign AppIntents metadata extraction warning remains; no Swift compiler warnings. Existing tiling, animation, Desktop and config tests all pass. C1–C5, P1–P4, S1–S9, A1–A4 and U1–U3 have automated coverage; native interaction remains a separate gate. Tests use unique temporary stores and fake power clients. The existing Carbon collision test uses only Ctrl+Alt+Shift+Cmd+F12 and explicitly removes its handler afterward.

## Production-service/controller smoke

Compiled the actual `Config`, `ConfigStore`, `PowerAssertions`, `KeepAwakeService`, `HotKeyManager` and `AppController` sources into a temporary harness using Swift 6/MainActor isolation. The harness substitutes a no-op hotkey registration client, a temporary config and a controllable clock; real native IOKit assertions and controller notification subscriptions run. No updater, AX wait, window moves, real-profile config writes or power preference edits.

- PID 36873: system Start held ID 37104 (`0x90f0`); display upgrade added 37105 (`0x90f1`) without replacing system protection or resetting deadline.
- +15 minutes added exactly 900 seconds to the existing deadline.
- Process-local synthetic `willSleepNotification` released both requests; `pmset` showed no Momentum Keep Awake requests.
- Process-local synthetic wake reacquired IDs 37106/37107, preserving the extended deadline.
- Advancing the injected clock to the exact deadline ended the session and removed requests.
- A new indefinite session followed by the real controller's app-termination notification hook removed requests and the config callback.
- These synthetic notifications do **not** sleep the machine and are **not** evidence of actual lid/lock/sleep behavior.
- GUI app process also survived a three-second startup under the XCTest isolation guard (PID 38098), then was terminated. No real config/services were started. A macOS sandbox-extension warning was logged; this boot does not establish interaction/accessibility correctness.

Temporary logs/probes are under `/tmp/momentum-keep-awake-*` and are not shipped. The installed Momentum process remained untouched.

## Review fixes validation (2026-10-06)

Code-review findings B1/B2 were addressed in commits `f990a4c` and `7c24ce3`; formal re-review is not yet performed. B3 (manual acceptance) remains open.

- B1 regression was observed failing before the fix (10 assertions at exact/after deadline); it now passes. Active mode-change Retry no longer becomes Start on expiry. Before-deadline Retry still preserves the deadline; failed-Start/wake-failure Retry Start still works.
- B2 regressions were observed failing before the fix (9 assertions). Failed display release now retains the working display ID/mode/deadline, restores previous saved preferences, emits no candidate config callback, and keeps Retry targeted at the attempted mode.
- Added tests for unchanged externally edited defaults, successful downgrade Retry, Stop after failed downgrade, save failure before native release, low-level ownership, live watcher rollback, and double-failure file restoration diagnostics.
- Fresh complete gate: **93 tests in 12 suites passed**, no Swift warnings. Result: `/tmp/momentum-keep-awake-fixes.GFe9ec/Tests.xcresult`; log: `/tmp/momentum-keep-awake-fixes-full.log`.
- Focused persistence/power/session suites: **30 tests in 3 suites passed**. `git diff --check` passed.
- The separately compiled fake-client review harness now observes expired Retry inactive with zero new requests, and failed downgrade retaining system-and-display mode/default plus both IDs. Successful Retry then removes display protection without deadline reset.
- Recompiled production-service/controller native smoke (PID 54059): system ID `0x9462` remained during upgrade/downgrade; display ID `0x9463` disappeared after downgrade. Synthetic sleep/wake resumed the original extended deadline with new IDs `0x9465/0x9466`; expiry and termination left no Momentum Keep Awake requests. Log: `/tmp/momentum-keep-awake-fixes-smoke.log`.
- As before, configs are temporary, no actual sleep/lid/lock is requested, no permanent power preferences change, and installed Momentum is untouched. This does not complete M1–M7 interactive acceptance.

## Interactive session — 2026-10-06 (partial acceptance)

User explicitly confirmed readiness to switch builds and interrupt the normal session for manual checks. macOS 27.0.1, hardware `Mac16,1`, AC power, battery 100%; tested source/build `54b1cad` from `/tmp/momentum-keep-awake-rereview.Ru0ad5/DerivedData/Build/Products/Debug/Momentum.app`.

- Backed up the pre-test config to `/tmp/momentum-keep-awake-manual.gBCv9m/original-tiling.json`; restoration and installed-app restart are pending completion of this session. No power preferences changed.
- Gracefully quit installed Momentum (PID 45358); normal development app now runs as PID 58939. Keep Awake starts inactive; inactive popover screenshot confirms 320-point native window, 30-minute/system-only selectors, Start and all existing commands. Screenshot: `/tmp/momentum-keep-awake-popover-inactive.png`.
- A system-only timed session is now active. `pmset -g assertions` confirms exactly one Momentum system-idle request, ID `0x980a`, with no Momentum display request. UI automation of popover controls was inconsistent; do not infer individual toggle/keyboard/VoiceOver acceptance from it.
- With the popover closed, the menu-bar accessibility help and actual cropped screenshot both show remaining time updating (30 minutes initially, 28 at 16:24:30 WEST) with the distinct static awake icon. Screenshot: `/tmp/momentum-keep-awake-active-label.png`. Closed-popover expiry/extension remain untested.
- User completed direct interaction: tiling off, mode changed to system-and-display, +15 minutes. At 16:27:05 WEST, `pmset` showed original system ID `0x980a` retained and display ID `0x9853` added; menu-bar help showed 41 minutes remaining. Saved preferences remain `30m` with mode `system-and-display` and no runtime fields. This verifies native mode upgrade and extension without overwriting saved duration; tiling-off is user-confirmed, not independently AX-inspected.
- A temporary observation-only monitor (PID 61346) now samples the power source/assertion list every ten seconds and logs actual NSWorkspace sleep/wake notifications plus continuous-vs-absolute clock deltas to `/tmp/momentum-keep-awake-manual.gBCv9m/os-observations.log`. It creates no assertions, changes no preferences and exits after one hour; explicit teardown is also required at session end.
- User reported completing Control–Command–Q lock, ~30 seconds locked, then unlock. At 16:33:04 WEST both original IDs (`0x980a`/`0x9853`) remained; status was system-and-display with 35 minutes remaining, consistent with the original extended deadline rather than a reset. Ten-second samples retained both requests and recorded no sleep notification during that interval. Locked-display appearance is not independently verified.
- User reported Apple-menu Sleep with the lid open, then wake/unlock. Monitor recorded sleep at 16:35:08, wake at 16:36:20, a further sleep at 16:36:40 and wake at 16:37:45 WEST. Momentum assertions disappeared during each sleep and were reacquired on each wake; latest IDs are system `0x9aa6` and display `0x9aa7`. Continuous clock included about 96.55 seconds that the absolute clock excluded across these cycles. At 16:38:07 the countdown was 30 minutes, consistent with the original extended deadline (~17:07), not a restored 45-minute duration. This provides empirical explicit-sleep and sleep-inclusive clock evidence, without assuming the extra cycle was a separate user action rather than OS wake behavior.
- External LG HDR 4K and built-in Retina displays are connected on AC power. A lid test must account for normal macOS closed-display/clamshell behavior; disconnect the external monitor for that test rather than attributing supported clamshell wakefulness to Momentum.
- User reported disconnecting the LG monitor, closing the lid ~30 seconds, reopening and reconnecting. Monitor recorded actual sleep at 16:40:26 and wake at 16:41:19 WEST, with no Momentum assertions while asleep. About 45.68 seconds of sleep were included by the continuous clock but excluded by the absolute clock. On wake, requests reacquired as `0x9c04`/`0x9c05`; at 16:41:52 status remained system-and-display with 26 minutes left on the original extended deadline.
- Disconnecting/reconnecting also produced Battery Power then AC Power. The awake battery→AC transition at 16:41:33 retained both wake assertion IDs and did not reset countdown. The AC→battery transition coincided with lid sleep, so that direction still needs an awake-only source transition check.
- User reported Stop, 15 seconds inactive, Until stopped selection/Start, then a lid-open charging disconnect/reconnect. The 16:44:43 WEST sample contained no Momentum assertions, confirming native Stop cleanup. A new indefinite session acquired `0x9deb`/`0x9dec` at ~16:44:44; both IDs persisted across awake AC→battery (16:45:03) and battery→AC (16:46:23), with no additional sleep notifications. At 16:46:41 menu-bar help said Until stopped and item width returned to 36 points (no numeric countdown); JSON retained `until-stopped`/`system-and-display` preferences. Power changes did not replace/restart the indefinite session.
- User confirmed indefinite extension buttons are hidden, then performed Sleep/wake. Actual sleep at 16:50:11 and wake at 16:52:15 WEST released old `0x9deb`/`0x9dec` and resumed as `0x9f7a`/`0x9f7b`; label still said Until stopped. Thus indefinite sessions resume rather than gaining a finite deadline.
- Added a temporary `ctrl+alt+shift+cmd+f12` binding atomically after verifying it did not collide with an existing Momentum action. Native Carbon shortcut delivery toggled the indefinite session inactive (no requests), then active again (`0xa117`/`0xa118`) while tiling was user-disabled. Original config and pre-shortcut config are backed up; temporary binding must be removed/restored at session end.
- Actual Quit at 16:55:21 removed both requests. Normal relaunch was inactive with remembered Until stopped preferences; the shortcut started a new session in PID 67385 (`0xa121`/`0xa122`). SIGKILL of that development process removed both requests; a second normal relaunch at 16:55:33 was again inactive. No old session was restored. Only development processes were terminated; installed Momentum remains quit during QA.
- User disabled tiling again and started a 15-minute system-and-display session in PID 67404 at ~17:02:39 WEST, then closed the popover. At 17:02:55 assertions `0xa227`/`0xa228` were active and menu-bar help showed 15 minutes; at 17:05:10 it showed 13 minutes. Expected natural expiry is ~17:17:39 without any further extensions/stops.
- The original observation probe stalled after its 16:52:15 wake callback in Foundation `Process.waitUntilExit` (stack sample confirms this is the QA helper, not Momentum). It was terminated at 17:04:40; no continuous sample coverage is claimed for the gap. A corrected observation-only probe (PID 69674) now avoids that wait and logs to `os-observations-round2.log` in the same QA directory. Quit/relaunch evidence above was independently captured by explicit commands, not inferred from the stalled probe.
- Other processes can also hold idle-system/user-activity assertions (`coreaudiod`, `powerd`, intermittent `caffeinate`/`rcd`), so actual idle-effect checks must not attribute all machine wakefulness solely to Momentum. No unrelated process has been stopped.
- Actual natural expiry passed: requests were present at 17:17:35 (14:55 assertion age), absent at 17:17:45, and label was Inactive by 17:18:00. The popover was closed, no extension/Stop/relaunch occurred, and expiry produced no observed alert. This matches the expected ~17:17:39 deadline within the monitor's ten-second sampling precision.
- User reported Tab/Shift–Tab lacked focus/highlight, Retile could not be activated via keyboard, and ⌘, did not open Settings. AppKit independently reports `isFullKeyboardAccessEnabled == false`; the global keyboard-navigation preference is unset/default, not enabled. Do not infer a focus implementation defect until retesting with native keyboard navigation enabled.
- A throwaway minimal menu-bar probe and the actual development app both opened Settings via ⌘, after a real CG mouse click opened/focused their popovers. Earlier System Events AXPress menu-item automation did not open the window-style popover reliably; this was an automation limitation, not evidence of the Settings action failing. The real app's Momentum Settings window appeared in the native AX window list at 17:19:30. No implementation changes have been made during this diagnosis.
- User explicitly declined VoiceOver testing ("ignore it"). Record that as skipped at owner request, not passed. Other keyboard/focus checks and dark/light/native command validation remain required.
- User shifted to active-icon design options; QA is paused. The round-2 observation probe was terminated at ~17:28 WEST. No QA observer is intentionally left running. User keyboard-navigation retest, wake-after-expiry and other remaining manual checks are still pending; do not declare the full matrix passed.
- For the requested live comparison, the active SVG now temporarily uses Charged's original smaller bolt (not the bolder refinement). The native asset build and all 93 tests pass; result bundle is `/tmp/momentum-keep-awake-icon-build.HJjWeR/Tests.xcresult`. Final icon choice/commit is pending comparison.
- Quit the prior normal development process and atomically restored `~/.config/momentum/tiling.json` byte-for-byte from the original backup, removing the temporary QA shortcut. Equality with the backup was checked again after launching the icon preview. Unrelated settings were not overwritten.
- Launched the smaller-bolt icon build in isolated app-host mode (PID 83017); its XCTestConfigurationFilePath guard was verified. It uses temporary preferences and skips tiling, hotkey and updater startup. For the requested active-icon inspection, Start was pressed in its popover: it held a real timed 30-minute system-idle assertion (`0xa76b`) and displayed the smaller-bolt template plus countdown. Screenshot: `/tmp/momentum-keep-awake-icon-before-live.png`. This is icon-only inspection, not a lifecycle/shortcut acceptance run.
- User requested the next comparison. Quit the smaller-bolt preview and verified no remaining Momentum requests, replaced only the lightning path with the larger refinement, then reran all 93 tests successfully (`BolderTests.xcresult` in the icon build directory). Relaunched the isolated preview as PID 86674 with its guard verified. The live bolder template is now visible; observed preview state is system-and-display with a two-hour duration (119 minutes in the screenshot), IDs `0x8240`/`0x8241`. Screenshot: `/tmp/momentum-keep-awake-icon-bolder-live.png`. The real normal-profile config still exactly matches its original backup. User selected the bolder icon after this comparison. It is committed in `594a0d9`; the smaller alternative and other throwaway comparison files are removed after capturing the choice. Overall manual acceptance is still incomplete; see the per-case statuses above. The user separately authorized a local installation of the normal build, not a release or a claim that all manual checks passed.

## Local installation — 2026-10-06

- User approved the bolder Charged icon and explicitly requested committing/pushing the feature branch and reinstalling locally.
- Built a fresh **Release** application with the project's existing Apple Development signing settings; no version, signing-team, entitlement or notarization change. Build succeeded; only the benign AppIntents metadata warning remains. Build/result path: `/tmp/momentum-local-install.QfMdYe/Build.xcresult`.
- Closed the isolated icon preview and verified its Momentum assertions disappeared. Verified the source and staged/installed app with `codesign --verify --deep --strict`, confirmed no `.xctest` bundles in the install product, then installed at `/Applications/Momentum.app`.
- Previous installed app is backed up at `/tmp/momentum-local-install.QfMdYe/previous-Momentum.app` for rollback. This is a local development-signed build, not a notarized public release.
- Normal installed launch runs as PID 90584 from `/Applications/Momentum.app/Contents/MacOS/Momentum`, with no XCTest guard environment flags. Keep Awake is Inactive and holds no requests; full normal startup wiring is restored rather than the isolated icon-preview mode.
- Original real-profile config still matches the pre-test backup byte-for-byte. Temporary QA binding and observer processes have been removed/stopped. Comparison prototypes are removed after recording the final icon choice. Remaining manual acceptance gaps are unchanged; local installation is not a declaration of full QA approval.

## Remaining interactive procedure

1. Quit the installed Momentum before launching the development build normally (avoid duplicate tiling/hotkeys). Back up the normal config first if testing saved selections or bindings.
2. Open the development build from the quality-gate `DerivedData/Build/Products/Debug/Momentum.app`; run M1–M7 above using the detailed procedures in the implementation plan.
3. In particular, confirm the active icon/countdown actually render with the popover closed, keyboard/VoiceOver work, and original commands remain accessible.
4. Run explicit sleep/lid/lock checks only when ready to interrupt work; do not change permanent power preferences or deliberately exhaust the battery. The pre-existing `caffeinate` process may mask idle behavior; arrange that check with its owner, do not kill unrelated processes automatically.
5. Record observed results and reviewer acceptance here before checking README feature boxes or marking the proposal shipped.

T1 empirical sleep/clock and native lifecycle checks have passed; remaining UI checks and T7 manual acceptance remain open. Production implementation may be developed on the authorized normal profile, but must not be declared shipped or README tracker boxes checked before the remaining evidence and reviewer sign-off.
