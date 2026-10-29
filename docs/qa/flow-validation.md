# Flow validation

## Environment and safety

- Base: `f4ff010` on `feat/flow`; macOS 27.2 (26B123), Xcode 27.1 (27A9275).
- Checks ran on the owner's normal profile with the installed app quit, then restarted. The one check that writes `~/.config/momentum/tiling.json` backed it up first and restored it byte for byte (`cmp` clean).
- No check asked macOS for notification permission, slept the Mac, or changed a system setting. Debug-only launch options stand in for those states:
  - `-MomentumFlowPreview running|paused|break|ending` puts Flow into one state (`ending` leaves 5 seconds).
  - `-MomentumFlowNotificationPreview allowed|denied|notDetermined` fakes the permission without asking macOS.

## Automated quality gate (2026-10-29)

- `xcodebuild test` (Debug): 203 tests passed, 0 failed, including 11 Flow tests covering FL-01–FL-09, FL-12–FL-20, the presentation strings, and shortcut routing.
- Debug and Release builds: zero warnings. Release contains no preview code (`#if DEBUG`).
- `scripts/grid-lint.sh`: PASS. Design-token check: no hits outside `Momentum/UI/`.

## Matrix

| Case | Status | Evidence / remaining work |
|---|---|---|
| V1 Popover states (FL-01–FL-03, FL-07) | Passed — agent verified | Light and dark snapshots: inactive (Duration, "Then a 5-minute break.", Start Flow), running (live `24:07`, "Flow session · ends at 13:41", Pause, End Flow), paused ("Paused", Resume, End Flow), break ("Break · ends at 13:21", Skip Break). Popover height 572–579 pt (limit 640) |
| V2 Menu-bar label (FL-12) | Passed — agent verified, after a fix | The first build lost the state symbol, because a menu-bar item draws only one image. The symbol is now drawn into the icon: timer `25m`, pause `19m`, walking figure `5m`. With Keep Awake on, the Charged icon shows beside Flow's timer |
| V3 Settings › Flow (FL-06, FL-11, FL-14) | Passed — agent verified | Light and dark snapshots of all three permission states: "Notifications are on.", the warning with Open Notification Settings, and the first-start note. Settings pages that Flow did not change differ only by the new sidebar row |
| V4 Keep Awake held by Flow (FL-14, FL-15, FL-17) | Passed — agent verified end to end | Clicked the "Keep Mac awake during sessions" switch (saved `keepAwake: true`), then Start Flow. `pmset` showed "Momentum Keep Awake — System" and "— Display", the owner's remembered mode. The popover showed "Until stopped" and "Ends with your Flow session.". After End Flow, `pmset` showed 0 Momentum assertions |
| V5 Shortcuts (FL-13) | Passed — agent verified | Settings › Keyboard Shortcuts › Other lists "Start or pause Flow" and "End Flow", both unassigned. Routing, the toggle behavior during a break, and End Flow are unit-tested |
| V6 Accessibility names (FL access rules) | Passed — agent verified, after two fixes | Read through the AX API. Countdown: `AXStaticText` "Flow session", value "25 minutes left". It had lost its value inside the `TimelineView`; the modifiers now sit on the Text. Menu-bar item name: "Momentum, Flow session, 25 minutes left". macOS passes on only the name for menu-bar items, so the state moved into it. Buttons read Pause, End Flow, Skip Break, Start Flow |
| V7 Real notification permission and delivery (FL-05, FL-07, FL-09, FL-10) | **Owner check** | Needs the macOS prompt and a click on Allow. Steps below |
| V8 Real sleep and wake (FL-18) | **Owner check** | Sleep catch-up and the order Flow → Keep Awake on wake are unit-tested. A real sleep was not forced |
| V9 VoiceOver and keyboard-only use | **Owner check** | Full Keyboard Access is off on this Mac, so Tab does not move between popover buttons, and the agent did not change that setting. Accessibility names are verified (V6); VoiceOver speech was not heard |

## Owner checks

1. **Notifications (V7).**
   1. Quit Momentum and run the Debug build: `<DerivedData>/Build/Products/Debug/Momentum.app/Contents/MacOS/Momentum`.
   2. Click **Start Flow**. Expect the macOS prompt; click **Allow**. Click **End Flow**.
   3. Quit and run it again with `-MomentumFlowPreview ending`. After 5 seconds, expect a banner, "Flow session complete / Time for a 5-minute break.", with sound, and the panel in Break.
   4. Wait for the break to end, or set Break duration to 5 minutes first. Expect "Break's over".
2. **Sleep (V8).** Start Flow, sleep the Mac past the session's end, and wake it. Expect the break, or the inactive panel if both ended, and a single notification.
3. **VoiceOver and keyboard (V9).** With VoiceOver on, open the popover. Expect "Flow session, 24 minutes left" on the countdown, and each button by name. With Full Keyboard Access on, Tab should reach Duration, Start Flow, Pause and End Flow.

Record each result in this matrix. Then merge the rules into `docs/spec/flow.md` and update the README tracker.
