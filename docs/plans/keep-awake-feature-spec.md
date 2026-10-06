# Feature Spec: Keep Awake

*Layer 1 — proposed behavior, not a claim of shipping functionality. Merge rules into `docs/spec/keep-awake.md` when implemented. Target length: two pages.*

| | |
|---|---|
| **Status** | Approved and implemented on the feature branch; validation accepted with explicit VoiceOver-test exception; awaiting merge |
| **Owner** | João |
| **Tech reviewer** | Requirements-based review completed; see `docs/reviews/keep-awake-implementation-review.md` |
| **Client sign-off / Linear project** | N/A — personal Momentum project; repository-local spec |
| **Merged into** | Branch behavior documented at `docs/spec/keep-awake.md`; proposal archival pending main-branch merge |

## Problem

Momentum users cannot currently prevent idle sleep during unattended work or keep the display on during presentations. Switching to another utility interrupts the keyboard-first workspace and adds another menu-bar app.

## Goal

Users can start, inspect, extend, and stop predictable Keep Awake sessions from Momentum, independently of window management.

## Behaviors (acceptance criteria)

- **KA-01.** When starting a session, users choose **Keep system awake** (display may sleep normally) or **Keep system and display awake** (both idle-sleep protections requested).
- **KA-02.** When first used, defaults are **30 minutes, system-only**. Duration choices are **15 minutes, 30 minutes, 1 hour, 2 hours, 4 hours, 8 hours, Until stopped**.
- **KA-03.** When inactive, the compact native menu-bar popover exposes inline duration/mode selectors and **Start**. Selecting either preference saves it immediately without starting a session.
- **KA-04.** When inactive, Start, the toggle, or the optional shortcut starts the remembered configuration. When active, the toggle, Stop, or shortcut ends the session and releases Momentum's sleep-prevention requests.
- **KA-05.** When a timed deadline is reached, the session ends without a normal-expiry notification. An indefinite session continues until stopped or the app exits, subject to macOS protections.
- **KA-06.** When a timed session is active, **+15 / +30 / +60 min** adds that amount to its existing deadline without modifying the saved duration. No eight-hour accumulated-session cap applies. Indefinite sessions hide these buttons.
- **KA-07.** When users change an active session's mode in the popover, a successful change takes effect immediately, preserves the deadline, and saves the new default mode.
- **KA-08.** When timed sessions are active, a distinct awake variant of Momentum's menu-bar icon appears alongside remaining time rounded up to whole minutes. Indefinite sessions show the active icon without a countdown; inactive sessions show the existing icon. The open popover shows mode and remaining time or indefinite status; no indicator animations.
- **KA-09.** When macOS sleeps, elapsed sleep counts toward the deadline. On wake, only unexpired sessions resume protection; expired sessions end.
- **KA-10.** When Momentum quits or crashes, its session ends. Relaunch starts inactive, retaining preferences but never restoring runtime session state or deadlines.
- **KA-11.** When tiling is disabled or Accessibility permission is absent, Keep Awake and its configured shortcut remain usable without new permission prompts.
- **KA-12.** When users optionally bind `toggle-keep-awake` through Settings or JSON, it follows KA-04. No shortcut is assigned by default; existing duplicate/unavailable-binding feedback applies.
- **KA-13.** When power changes between battery and external supply, the session and deadline remain unchanged.
- **KA-14.** When the screen locks, the session and deadline remain unchanged. Display protection remains requested, but macOS may turn the locked display off; Momentum never unlocks the screen or simulates input.
- **KA-15.** When Keep Awake is active, it does not bypass explicit Sleep, lid-close sleep, locking, or critical-battery protections. It does not guarantee wakefulness under every macOS condition.
- **KA-16.** When preferences are saved, default duration, mode, and optional binding use `~/.config/momentum/tiling.json`. Runtime state is never persisted. External valid JSON edits affect future sessions only, not the current mode or deadline.
- **KA-17.** When the native SwiftUI popover replaces the existing menu, Keep Awake appears first, existing tiling/error controls remain below, and Settings, Check for Updates, and Quit remain accessible. Controls support keyboard focus and accessibility; no reference-app tabs or oversized branding.

### Edge cases and errors

- **KA-18.** When activation fails, the UI stays inactive and presents an inline error with Retry, not a modal alert. No active indication appears before the requested protection succeeds.
- **KA-19.** When an active mode change fails, the previous working mode, deadline, and saved default remain unchanged; an inline error is shown.
- **KA-20.** When configuration values are invalid, the previous valid configuration remains active and the existing Settings error mechanism reports the failure.

## Out of scope

- Custom durations, clock-time deadlines, lid-close overrides, power-source automation, and normal-expiry notifications.
- Focus timer, automatic focus-session activation, and restoring a prior Keep Awake state after focus ends; specify these with the future focus feature.
- Unrelated UI tabs, analytics, or simulated activity.

## Implementation guidance

Use an independent Keep Awake service, not state inside `TilingManager`. Reuse `Config.swift`, `ConfigStore.swift`, and `HotKeyManager.swift`; use `MenuBarExtra` window style in `MyApp.swift`. Current hotkey ownership/dispatch resides in `TilingManager`: separate app-level action routing from tiling enablement and permission lifecycle. `ConfigStore` has a single `onChange` callback: avoid replacing the existing tiling subscriber when adding Keep Awake.

Prefer public macOS power assertions with an injectable adapter and clock; verify actual system/display, sleep/wake, lock, exit, and failure behavior on supported macOS before marking the README feature tracker implemented. Unit-test transitions, persistence, deadlines, extensions, and rollback; manually validate OS behavior and popover accessibility. Final API/schema and task breakdown belong in the implementation plan.

## Open questions

No unresolved product decisions from this interview. Validation evidence and owner-authorized exceptions are recorded in `docs/qa/keep-awake-validation.md`; this spec does not promise unsupported sleep overrides.

## Changelog

| Date | Change | Agreed with |
|---|---|---|
| 2026-10-06 | Captured grill-me decisions; no application implementation started | João |
| 2026-10-06 | Feature spec reviewed and approved; scope and acceptance criteria unchanged | João |
