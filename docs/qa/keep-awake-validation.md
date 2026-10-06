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
| M1 assertions and actual idle/display behavior | Partial | Native probe creates/releases both intended types; actual idle behavior pending |
| M2 expiry/extension/countdown with closed popover | Pending | Requires development app interaction |
| M3 explicit sleep/lid/lock and wake deadlines | Pending | User-assisted disruptive checks required |
| M4 power changes/exit/crash/relaunch | Partial | Probe forced-exit cleanup passed; app/power checks pending |
| M5 AX-denied/tiling-disabled and shortcuts/config | Pending | Unit routing tests do not replace native checks |
| M6 keyboard/VoiceOver/appearance/Settings commands | Pending | Interactive UI verification required |
| M7 injected error UI | Pending | Unit transactions do not replace UI checks |

T1 empirical sleep and UI checks and T7 manual acceptance remain open. Production implementation may be developed on the authorized normal profile, but must not be declared shipped or README tracker boxes checked before the remaining evidence and reviewer sign-off.
