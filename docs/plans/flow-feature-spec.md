# Feature Spec: Flow

*Layer 1 — proposed behavior, not a claim of shipping functionality. Merge rules into `docs/spec/flow.md` when implemented. Terms follow `docs/GLOSSARY.md`.*

| | |
|---|---|
| **Status** | Approved and implemented on `feat/flow`; automated tests and state snapshots pass; manual validation (real notifications, sleep/wake, VoiceOver, keyboard-only) pending |
| **Owner** | João |
| **Tech reviewer** | Pending implementation plan |
| **Client sign-off / Linear project** | N/A — personal Momentum project; repository-local spec |
| **Merged into** | Not yet; README "Road to v1" › "Stay focused" tracks it |

## Problem

Momentum arranges the workspace and keeps the Mac awake, but nothing helps people work in focused stretches with breaks between them. A separate timer app means another menu-bar item, and macOS's own Focus modes silence notifications without timing anything.

## Goal

People can start a timed Flow session from the menu bar or a shortcut, see the time left at a glance, take a break when it ends, and optionally keep the Mac awake while they work, without Flow changing anything it didn't start.

## Behaviors (acceptance criteria)

### Sessions

- **FL-01.** When inactive, the Flow panel shows a **Duration** picker and **Start Flow**. Durations: **15, 25, 30, 45, 50, 60, 90 minutes**; default **25 minutes**. Choosing a duration saves it immediately without starting a session.
- **FL-02.** When a session runs, the panel shows the time left as `m:ss` (`h:mm:ss` from one hour) and the clock time it ends, with **Pause** and **End Flow**.
- **FL-03.** When paused, the countdown stops and keeps the time left; the panel shows **Paused** with **Resume** and **End Flow**. Resume continues from the time left.
- **FL-04.** When people choose End Flow, the session stops at once, no break follows, and no notification is sent.
- **FL-05.** When a session reaches zero, Momentum sends a notification. With breaks on, a break starts at once; with breaks off, the panel returns to inactive.

### Breaks

- **FL-06.** Breaks are on by default and last **5 minutes** (choices: **5, 10, 15, 20 minutes**). Settings › Flow can turn them off or change their duration. Only a session that reaches zero starts a break.
- **FL-07.** During a break, the panel shows the time left and the clock time it ends, with **Skip Break**. When the break ends, Momentum sends a notification and the panel returns to inactive. The next session never starts on its own.
- **FL-08.** Skip Break ends the break at once without a notification.

### Notifications

- **FL-09.** Momentum asks for notification permission the first time people start Flow, never at launch. The session starts whatever the answer.
- **FL-10.** Notifications use the default sound and show as banners even while the popover is open. macOS Focus modes and notification settings decide whether they appear.
- **FL-11.** When notifications are off for Momentum, Settings › Flow says so and offers **Open Notification Settings**. The popover does not nag; the menu-bar label still shows the countdown.

### Menu bar and shortcuts

- **FL-12.** While Flow is active, the menu-bar label shows a symbol for the state (running, paused, or break) and the time left in whole minutes rounded up (`24m`), like Keep Awake. Flow's countdown replaces Keep Awake's countdown in the label; the Keep Awake icon still shows when Keep Awake is on. The label does not animate.
- **FL-13.** Two optional shortcuts, unassigned by default, appear under Settings › Keyboard Shortcuts › Other and in `tiling.json`:
  - `toggle-flow` **"Start or pause Flow"** starts when inactive, pauses when running, and resumes when paused. During a break it ends the break and starts the next session.
  - `end-flow` **"End Flow"** ends a session (FL-04) or skips a break (FL-08).

  Both use the existing duplicate and unavailable-shortcut feedback.

### Keep Awake

- **FL-14.** Settings › Flow has **Keep Mac awake during sessions**, off by default. When it is on and Keep Awake is off at the start of a session, Flow starts Keep Awake **Until stopped** in the remembered Keep Awake mode. Keep Awake's saved duration does not change.
- **FL-15.** Flow stops only the Keep Awake it started. It does so when the session ends at zero, on End Flow, and on quit. Keep Awake stays on while a session is paused.
- **FL-16.** When Keep Awake was already on at the start, Flow leaves it exactly as it was. When people stop or change Keep Awake themselves during a session, Flow lets go of it and never restarts or stops it.
- **FL-17.** While Flow holds Keep Awake, the Keep Awake panel shows **Ends with your Flow session.**

### Lifecycle

- **FL-18.** Sleep time counts toward a running session or break. On wake, Flow shows the state the clock has reached and sends at most one notification, for the latest event. A paused session stays paused.
- **FL-19.** Quitting ends Flow. Relaunch starts inactive with the saved preferences. Runtime state is never saved.
- **FL-20.** Preferences (session duration, break duration, breaks on or off, Keep Awake option) save to `~/.config/momentum/tiling.json` under `flow`. Invalid values fail the reload like other settings (KA-20).

### Edge cases and errors

- **FL-21.** When Flow cannot start Keep Awake, the session still runs and the Keep Awake panel shows its usual inline error with Retry (KA-18).
- **FL-22.** When a notification cannot be delivered, the session continues silently; there is no alert.
- **FL-23.** Flow needs no Accessibility permission. It works when tiling is off or not permitted.

## UX

- **Flow:** Popover › Flow › Start Flow, or the `toggle-flow` shortcut → (first time only) macOS asks to allow notifications → the countdown runs (menu bar `⏱ 24m`) → at zero, a notification and a break start → the break ends with a notification → the panel is ready again. Ways back: End Flow at any time (no break follows), Pause and Resume, Skip Break, Escape closes the popover.
- **Surface:** a `Panel` in the existing menu-bar popover, first of three, above Keep Awake ("a few related choices tied to one control"). Preferences go on a new Settings sidebar page, **Flow**, just above Keep Awake. Session and break ends use system notifications, not alerts, because they need no action.
- **States:**

  | State | Panel | Menu-bar label |
  | --- | --- | --- |
  | Inactive | Duration picker, caption "Then a 5-minute break." (hidden when breaks are off), **Start Flow** (prominent) | No Flow part |
  | Running | Large `24:13`, caption "Flow session · ends at 10:45", **Pause** (prominent), **End Flow** | `timer` symbol + `24m` |
  | Paused | Large `24:13`, caption "Paused", **Resume** (prominent), **End Flow** | `pause.fill` symbol + `24m` |
  | Break | Large `4:12`, caption "Break · ends at 10:50", **Skip Break** | `figure.walk` symbol + `5m` |
  | Notifications off | Nothing in the panel; Settings › Flow shows a `WarningLabel` and Open Notification Settings | Unchanged |

- **Words:**
  - Panel title **Flow** with the `timer` symbol.
  - Settings › Flow subtitle: "Set how long Flow sessions and breaks last."
  - Settings › Flow, Sessions section: "Session duration", "Keep Mac awake during sessions". Footer: "Uses your Keep Awake mode. If Keep Awake is already on, Flow leaves it as it is."
  - Settings › Flow, Breaks section: "Take a break after each session", "Break duration" (disabled while breaks are off).
  - Settings › Flow, Notifications section, by permission state:
    - On: "Notifications are on."
    - Off: "Notifications are off. Momentum can't tell you when a session or break ends." + **Open Notification Settings**.
    - Not asked yet: "Momentum asks to send notifications the first time you start Flow."
  - Notifications:
    - Session ends with breaks on: **"Flow session complete"** / "Time for a 5-minute break."
    - Session ends with breaks off: **"Flow session complete"** / "Start another session when you're ready."
    - Break ends: **"Break's over"** / "Start your next Flow session when you're ready."
  - Shortcut titles: "Start or pause Flow", "End Flow".
- **Hover help:** every Flow control has a text label, so none needs a tooltip. The menu-bar label's `.help` lists Flow and Keep Awake status, e.g. "Flow session, 24 min left · Keep Awake: System only, until stopped".
- **Access:**
  - Tab moves Duration → Start Flow; while running, Pause → End Flow.
  - VoiceOver reads the countdown as "Flow session, 24 minutes left" (or "Flow paused…", "Break, 4 minutes left"). The value updates once a minute, never every second.
  - The menu-bar label's accessibility value includes the Flow state.
  - Paused and break states are named in words, not shown by color or symbol alone.
  - The countdown uses `.monospacedDigit()` and ticks without animation, so Reduce Motion needs nothing extra.

## Impact on existing specs

- **KA-17** changes: the popover order becomes Flow, Keep Awake, Window Tiling. Update `docs/spec/keep-awake.md` in the implementing PR.
- **KA-08** label rule gains FL-12 (Flow's countdown wins the label text).

## Out of scope

- Long breaks or session cycles.
- Starting the next session automatically.
- Statistics or history.
- Custom durations and adding time to a session.
- Actions in notifications (such as Start Flow from a banner).
- Choosing sounds.
- Turning on a macOS Focus mode.
- Hiding or dimming windows during a session.

## Implementation guidance

Build a `FlowService` beside `KeepAwakeService`, owned by `AppController`, with an injectable clock and notification client. Reuse its single-scheduler and sleep/wake patterns (KA-09). Track Keep Awake ownership as an explicit token: Flow releases only a session it started and that nobody has changed since (FL-15, FL-16).

Add the `flow` config block and the two actions through `Config.swift`, `ConfigStore`, and `HotKeyManager`, with the same transactional saves as Keep Awake. Build the panel with `Panel` and `WarningLabel` from `design/DESIGN-SYSTEM.md`.

Add a debug launch option that puts Flow into each state (running, paused, break, notifications off) so every state above can be snapshotted. Unit-test transitions, ownership, sleep catch-up, and persistence; validate notifications, sleep/wake, VoiceOver, and keyboard-only use manually.

## Decisions to confirm in review

The owner chose the name **Flow**, notifications at session and break end, and automatic, skippable breaks. The UX pass decided the rest:
- Flow panel first in the popover.
- Durations 15–90 minutes (default 25); breaks 5–20 minutes (default 5).
- Pause supported; Keep Awake kept during a pause.
- Keep Awake option off by default.
- Two unassigned shortcuts.
- Minutes in the menu bar, seconds in the popover.
- "Duration" instead of "Length", to match Keep Awake.

## Changelog

| Date | Change | Agreed with |
|---|---|---|
| 2026-10-29 | UX pass: name, notifications, and break model chosen by the owner; draft behaviors and UX written | João |
| 2026-10-29 | Spec approved as written, including the UX pass's own decisions; implementation started | João |
| 2026-10-29 | Implemented; the menu-bar state symbol is drawn into the icon because a menu-bar item shows only one image | — |
