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
| M2 expiry/extension/countdown with closed popover | Pending | Requires development app interaction |
| M3 explicit sleep/lid/lock and wake deadlines | Pending | User-assisted disruptive checks required |
| M4 power changes/exit/crash/relaunch | Partial | Probe forced-exit and production controller termination cleanup passed; power changes/app relaunch interaction pending |
| M5 AX-denied/tiling-disabled and shortcuts/config | Partial | Fake routing, live atomic edits, feedback and existing Carbon collision regression pass; native interaction pending |
| M6 keyboard/VoiceOver/appearance/Settings commands | Pending | Interactive UI verification required |
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

## Remaining interactive procedure

1. Quit the installed Momentum before launching the development build normally (avoid duplicate tiling/hotkeys). Back up the normal config first if testing saved selections or bindings.
2. Open the development build from the quality-gate `DerivedData/Build/Products/Debug/Momentum.app`; run M1–M7 above using the detailed procedures in the implementation plan.
3. In particular, confirm the active icon/countdown actually render with the popover closed, keyboard/VoiceOver work, and original commands remain accessible.
4. Run explicit sleep/lid/lock checks only when ready to interrupt work; do not change permanent power preferences or deliberately exhaust the battery. The pre-existing `caffeinate` process may mask idle behavior; arrange that check with its owner, do not kill unrelated processes automatically.
5. Record observed results and reviewer acceptance here before checking README feature boxes or marking the proposal shipped.

T1 empirical sleep and UI checks and T7 manual acceptance remain open. Production implementation may be developed on the authorized normal profile, but must not be declared shipped or README tracker boxes checked before the remaining evidence and reviewer sign-off.
