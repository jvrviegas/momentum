# Functional Spec: Flow

> Layer 2 behavior, accepted by the owner on 2026-10-29. Not a public release claim. Any PR changing these behaviors must update this file. Words follow `docs/GLOSSARY.md`.

| | |
|---|---|
| **Area owner** | João |
| **Last verified** | 2026-10-29: 203 automated tests. Agent-verified UI states, Keep Awake handoff, shortcuts, and accessibility names. Owner-confirmed notifications, sleep and wake, VoiceOver, and keyboard use. Evidence: [validation record](../qa/flow-validation.md) |

## Overview

Flow times focused work sessions and the breaks between them, from the menu-bar popover or optional shortcuts. Sessions, breaks, and deadlines exist only in memory; preferences live in `~/.config/momentum/tiling.json`. Flow needs no Accessibility permission and works whether or not tiling runs.

## Concepts

| Term | Meaning |
|---|---|
| Flow session | A running or paused countdown of the chosen session duration |
| Break | The countdown that follows a session that reached zero |
| Paused session | Keeps its time left and has no deadline until resumed |
| Held Keep Awake | An Until stopped Keep Awake session that Flow started and nobody has changed since. Flow tracks it through Keep Awake's revision, which changes on every start, stop, and mode change, but not on sleep or wake |

## Behaviors

### Sessions

- **FL-01.** When inactive, the Flow panel (first in the popover) shows a **Duration** picker and **Start Flow**. Durations: 15, 25, 30, 45, 50, 60, and 90 minutes; default 25. A choice saves immediately without starting a session.
- **FL-02.** While a session runs, the panel shows the time left as `m:ss` (`h:mm:ss` from one hour), rounded up, plus "Flow session · ends at <time>", with **Pause** and **End Flow**. Seconds redraw only while the popover is open.
- **FL-03.** **Pause** freezes the time left and shows "Paused" with **Resume** and **End Flow**. **Resume** sets a new deadline from the time left.
- **FL-04.** **End Flow** stops the session at once: no break, no notification.
- **FL-05.** At zero, Momentum posts a notification. With breaks on, a break starts from the session's end time; with breaks off, Flow becomes inactive.

### Breaks

- **FL-06.** Breaks are on by default and last 5 minutes (choices 5, 10, 15, 20). Settings › Flow turns them off or changes their duration; the change applies when the current session ends.
- **FL-07.** During a break, the panel shows the time left and "Break · ends at <time>" with **Skip Break**. At zero, Momentum posts a notification and Flow becomes inactive. The next session never starts on its own.
- **FL-08.** **Skip Break** ends the break without a notification.

### Notifications

- **FL-09.** The first **Start Flow** asks macOS for notification permission (alert and sound), never at launch. The session starts whatever the answer.
- **FL-10.** The texts are:
  - Session complete with breaks on: "Flow session complete" / "Time for a N-minute break."
  - Session complete with breaks off: "Flow session complete" / "Start another session when you're ready."
  - Break over: "Break's over" / "Start your next Flow session when you're ready."

  They use the default sound and show as banners even while the popover is open. One identifier means a newer Flow notification replaces the previous one. macOS Focus modes and notification settings still apply.
- **FL-11.** Settings › Flow shows the permission state:
  - On: "Notifications are on."
  - Off: a warning with **Open Notification Settings**.
  - Not asked yet: a note that Momentum asks the first time you start Flow.

  The popover never warns about notifications.

### Menu bar and shortcuts

- **FL-12.** While Flow is active, the menu-bar item shows a state symbol (timer, pause, walking figure) and the minutes left rounded up (`24m`). The symbol is drawn into the icon image because a menu-bar item shows only one image. Flow's countdown replaces Keep Awake's, while the Keep Awake (Charged) icon still shows. The item's accessibility name carries the state, e.g. "Momentum, Flow session, 24 minutes left, Keep Awake on", because macOS passes on only the name. The tooltip repeats the state and Keep Awake's status.
- **FL-13.** Optional shortcuts `toggle-flow` ("Start or pause Flow") and `end-flow` ("End Flow") are unassigned by default and listed under Settings › Keyboard Shortcuts › Other.
  - `toggle-flow` starts, pauses, or resumes. During a break it ends the break and starts the next session.
  - `end-flow` ends a session or skips a break.

  Both come after every earlier action, so earlier actions keep priority in collisions.

### Keep Awake

- **FL-14.** With **Keep Mac awake during sessions** on (off by default), a session that starts while Keep Awake is off starts Keep Awake Until stopped in the remembered Keep Awake mode. Keep Awake's saved duration does not change.
- **FL-15.** Flow stops only a held Keep Awake: when its session reaches zero, on End Flow, and on quit. Keep Awake stays on while a session is paused.
- **FL-16.** When Keep Awake was already on, Flow leaves it as it was. When people stop, restart, or change the mode of a held session, Flow lets go and never stops it.
- **FL-17.** While Flow holds Keep Awake, the Keep Awake panel shows "Ends with your Flow session."

### Lifecycle

- **FL-18.** Countdowns use the same sleep-inclusive clock as Keep Awake. On wake, Flow moves past every end the clock has reached and posts one notification for the latest. Flow handles wake before Keep Awake, so a held Keep Awake whose session ended during sleep is released rather than resumed. A paused session stays paused.
- **FL-19.** Quitting ends Flow and releases a held Keep Awake. Relaunch starts inactive with the saved preferences; runtime state is never saved.
- **FL-20.** Preferences are saved under `flow` in `tiling.json`: `duration`, `breakDuration`, `breaksEnabled`, and `keepAwake`. They use the same transactional save as Keep Awake. Missing keys default; nulls, wrong types, and unknown values fail the whole reload, and the previous configuration stays (as in KA-20).

### Errors and limits

- **FL-21.** When Flow cannot start Keep Awake, the session still runs and the Keep Awake panel shows its usual inline error with Retry (KA-18).
- **FL-22.** When a notification cannot be delivered, the session continues silently.
- **FL-23.** Flow works without Accessibility permission and when tiling is off.

## Permissions

| Action | Requirements | Notes |
|---|---|---|
| Sessions, breaks, shortcuts | Ordinary local user | No Accessibility permission |
| Notifications | macOS notification permission, asked on the first Start Flow | When it's denied, sessions still run and Settings › Flow says so |
| Preference saves | Writable config location | A failed save keeps the previous value and shows the Settings error |

## Integrations and side effects

- `UNUserNotificationCenter`: Momentum's delegate presents banners while the app is active.
- `KeepAwakeService.start(duration:)` overrides the duration for one session only. Its `revision` lets Flow tell a held session from one people changed.
- A single cancellable scheduler wakes at each whole-minute change and at the deadline; stale callbacks cannot affect a later countdown.
- `AppController` routes the two shortcuts. On wake it calls Flow before Keep Awake; on quit it shuts Flow down before Keep Awake.
- Debug builds only: `-MomentumFlowPreview running|paused|break|ending` and `-MomentumFlowNotificationPreview allowed|denied|notDetermined` stage states for snapshots and manual checks.

## Known gaps and quirks

- Notifications have no actions, and clicking one opens nothing (Momentum has no Dock window).
- No long breaks, session cycles, auto-start of the next session, history, custom durations, or added time.
- The menu bar shows whole minutes; seconds appear only in the open popover. VoiceOver reads minutes, not seconds.
- With notifications off, a session's end shows only in the menu bar and popover.
- Keyboard navigation of the popover's buttons needs macOS Full Keyboard Access.

---

Update affected rules in the same PR as behavior changes. Keep FL identifiers stable. The approved [feature proposal](../plans/flow-feature-spec.md) is kept for history.
