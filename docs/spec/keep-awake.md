# Functional Spec: Keep Awake

> Layer 2 behavior for the implementation branch, accepted for merge with the owner's explicit VoiceOver-test exception. Not a public release claim. Any PR changing these behaviors must update this file.

| | |
|---|---|
| **Area owner** | João |
| **Last verified** | 2026-10-06: 93 automated tests; native lifecycle/power/expiry checks and bold Charged icon comparison; remaining manual acceptance documented below |

## Overview

Keep Awake requests macOS idle-sleep protection independently of window tiling. Users choose remembered duration and mode preferences, then explicitly start a session. Sessions, deadlines and assertion IDs exist only in memory. macOS retains authority over explicit sleep, locking, lid close and critical-battery protections.

## Concepts

| Term | Meaning |
|---|---|
| System mode | Requests system idle-sleep prevention; display may sleep |
| System and display mode | Requests system and display idle-sleep prevention |
| Remembered preferences | Duration/mode used on the next explicit Start |
| Timed session | Active session with a sleep-inclusive monotonic deadline |
| Until stopped | Active session without a deadline; ends on Stop or process exit |
| Sleep-suspended session | Retains mode/deadline while Momentum releases its assertions; reconciled on wake |

## Behaviors

The rules below describe implemented branch behavior. Automated tests verify state/persistence/presentation; native smoke verifies assertion requests and process-local lifecycle notifications. Actual lock, explicit sleep, lid-close, valid timed/indefinite wake, power-source transitions, native expiry and app-exit/relaunch checks passed in the normal profile. The owner confirmed the remaining idle-effect, wake-after-expiry and ordinary UI checks; native failure UI was independently verified with injected clients. Evidence levels and the explicit VoiceOver exception are in the [validation record](../qa/keep-awake-validation.md).

### Configuration and commands

- **KA-01.** When users start a session, system mode requests system idle-sleep protection; system-and-display mode requests both system and display idle-sleep protection. No active state is published until all requested assertions are acquired.
- **KA-02.** When preferences are missing, defaults are 30 minutes and system-only. Available durations are 15 minutes, 30 minutes, 1 hour, 2 hours, 4 hours, 8 hours and Until stopped.
- **KA-03.** When inactive duration or mode selections succeed, they save immediately without starting protection. The popover contains inline selectors and Start.
- **KA-04.** When inactive, Start, the toggle and the optional shortcut start the remembered preferences. When active, Stop, the toggle and the shortcut release Momentum's owned requests and clear the session. Repeated Start does not reset an active deadline.
- **KA-05.** When a finite deadline is reached, the session stops silently. Until stopped has no scheduled expiry.
- **KA-06.** When a valid timed session is extended by +15/+30/+60 minutes, that amount is added to the existing deadline without changing saved duration or imposing an eight-hour accumulated cap. Inactive, indefinite or expired sessions cannot be extended; indefinite sessions omit extension controls.
- **KA-07.** When an active mode change succeeds, protection changes immediately, the original deadline remains, and the new default mode is saved. Existing protection remains held while additions are acquired and preferences are saved.
- **KA-08.** When a session is active, the label selects the static Charged icon: the Momentum mark with a bold central lightning bolt. Timed sessions add minutes rounded up and the popover derives its status from the same deadline; indefinite sessions omit the number. Inactive sessions select the existing icon. Native rendering, closed-popover countdown and expiry passed; the owner confirmed keyboard/light-appearance checks.

### Lifecycle and independence

- **KA-09.** On sleep notification, Momentum releases its assertions while retaining mode/deadline. On wake notification, it expires elapsed sessions before acquiring anything, or resumes valid sessions with the original deadline. Actual timed and indefinite sleep/wake passed and the clock empirically included sleep time; the owner also confirmed wake after the timed deadline stays inactive.
- **KA-10.** On termination, Momentum cancels scheduling, removes lifecycle listeners/global registrations, and releases its requests. A new service always starts inactive and retains only preferences. Actual app Quit, forced-exit cleanup and inactive relaunch with retained preferences passed M4.
- **KA-11.** When Accessibility is absent, tiling is disabled, or tiling commands are suspended, Keep Awake routing remains independent and does not request Accessibility. Tiling retains its existing startup prompt and command guards.
- **KA-12.** When users bind `toggle-keep-awake` in Settings or JSON, it follows the same toggle behavior. It is unassigned by default; duplicate/unavailable-binding feedback uses the existing Settings mechanism. Earlier actions retain priority in collisions.
- **KA-13.** When power source changes, Momentum has no power-source automation that modifies the session or deadline. Actual awake battery/external-supply transitions preserved the session and assertion IDs in M4.
- **KA-14.** When the screen locks, Momentum does not change its session/deadline or simulate input/unlock. Display idle protection is only a request; macOS can turn the locked display off. User-confirmed lock/unlock preserved both requests and the elapsed deadline in M3.
- **KA-15.** When protection is active, Momentum uses only public idle-sleep assertions, not unconditional system-sleep prevention. Explicit Sleep, lid-close, lock and critical-battery safeguards remain governed by macOS. This is an API boundary, not a guarantee of wakefulness; critical battery exhaustion is not tested.
- **KA-16.** When preferences or bindings are saved, they use the shared `~/.config/momentum/tiling.json`. Runtime state is never encoded. Valid external edits update future defaults/bindings without changing an active mode/deadline.
- **KA-17.** The native window-style popover places Keep Awake first, existing tiling/move-error controls below, and Settings, Check for Updates and Quit afterward. Controls have accessibility labels and native selectors; Settings activation and Command-comma/Command-Q are retained. The owner confirmed keyboard/appearance/command checks. VoiceOver testing was explicitly declined by the owner, not recorded as passed.

### Errors and limits

- **KA-18.** When activation fails, the session stays inactive and the UI presents an inline error with Retry Start, never an optimistic active indicator or modal alert. A successful Retry clears the error. Wake-reacquisition failure ends the session; Retry Start begins the current remembered configuration.
- **KA-19.** When acquiring an active mode's additions, saving its preferences, or releasing display protection on downgrade fails, the previous working mode/deadline/default remain unchanged and the attempted mode is available through Retry mode change. Partial additions are rolled back; a failed downgrade retains the display request as working protection rather than orphaned cleanup. If the session expires before Retry mode change executes, it ends without starting a replacement session.
- **KA-20.** When JSON or present Keep Awake values are invalid, the entire reload fails, the previous valid config remains and Settings exposes the error. Missing preferences/fields default; explicit nulls, wrong types and unknown enum values do not.

## Permissions

| Action | Requirements | Notes |
|---|---|---|
| Keep Awake requests and controls | Ordinary local user | No AX permission or added entitlement |
| Tiling | Existing Accessibility permission | Existing startup prompt retained |
| Preference saves | Writable config location | Failed transactional saves preserve prior defaults/session |

## Integrations and side effects

- Public IOKit `PreventUserIdleSystemSleep` and optional `PreventUserIdleDisplaySleep` assertions are owned and released by Momentum; unrelated process requests are not touched.
- One app controller owns global hotkey registration and the shared config callback. Changes re-register bindings and notify tiling without resetting Keep Awake.
- A single cancellable scheduler updates timed state even when the popover is closed; stale callbacks cannot affect a later session.
- App-hosted unit tests use a temporary store and skip updater, tiling startup, global registration, native power requests and lifecycle listeners. Explicit unit tests inject fake clients/listeners.

## Known gaps and quirks

- Merge approval combines independent native/component evidence with owner-reported idle/display, expired-wake and ordinary UI results. VoiceOver was skipped at owner request, not passed. Critical-battery exhaustion was intentionally excluded. This is not a guarantee of all macOS behavior or a public release claim; evidence is recorded in the validation document.
- Assertion release failures retain unresolved IDs and surface a diagnostic. Cleanup makes at most two attempts per ID per command and can be retried; stopping clears session state but does not claim every request was removed if an error remains. OS process-exit cleanup is the final boundary.
- Mode changes save the candidate before native completion, but publish preferences only after completion succeeds. If native completion fails, the previous file is restored. If that restoration also fails because the filesystem has become unavailable, runtime mode and in-memory preferences remain unchanged and both failures are reported; successful on-disk restoration cannot be claimed until the filesystem is repaired.
- There is no custom duration, clock-time deadline, input simulation, power automation, focus timer or session restoration.
- UI tests prove derived status/visibility/Retry choices, not keyboard focus or VoiceOver behavior.

---

Update affected rules in the same PR as behavior changes. Keep KA identifiers stable. Do not archive the approved [feature proposal](../plans/keep-awake-feature-spec.md) until required acceptance is complete.
