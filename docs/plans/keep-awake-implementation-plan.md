# Keep Awake — Implementation Plan

> **Scope:** `jvrviegas/momentum`, native macOS app. One feature branch/worktree and PR to `main` (`daf18d874c9fc8cb876e9cf4a76afc8c80145b4d` at planning time).
> **Canonical proposal:** `docs/plans/keep-awake-feature-spec.md`, approved by João, changelog 2026-10-06, KA-01–KA-20. Repository-local feature; no Linear issue, blockers, due date or estimate supplied.
> **Owner:** João · **Technical reviewer:** pending.
> **Revision:** v2 — 2026-10-06. Implementation and automated quality gate complete; manual acceptance pending.
> **Readiness:** D1–D8 remain approved. João explicitly authorized the normal profile instead of a disposable one. Native assertion probes, production-service/controller smoke and UI compilation passed; empirical sleep and interactive UI/accessibility checks remain open, blocking shipping claims. See `docs/qa/keep-awake-validation.md`.

## Outcome

Add an independent Keep Awake service, remembered preferences and optional hotkey, and a compact native menu-bar popover. Public macOS idle-sleep assertions provide system-only or system-plus-display protection. Sessions never restore after relaunch and never override explicit sleep, lid close, locking or critical battery protections.

## Progress tracker

Commit-sized vertical changes, with tests alongside implementation (not necessarily one commit per file).

| Task | What | Suggested commit | Status |
|---|---|---|---|
| T1 | Verify native API/lifecycle and popover feasibility | `docs(keep-awake): record native feasibility checks` | Partial: native probes passed; empirical sleep/UI pending |
| T2 | Preferences/action schema and isolated ConfigStore seam | `feat(keep-awake): add persisted preferences` | [x] |
| T3 | Transactional native assertion adapter | `feat(keep-awake): add power assertion adapter` | [x] |
| T4 | Session state, deadlines and lifecycle | `feat(keep-awake): implement session lifecycle` | [x] |
| T5 | App-level action/config routing independent of tiling | `refactor(hotkeys): separate application action routing` | [x] |
| T6 | Native popover and dynamic menu-bar label | `feat(keep-awake): add menu bar controls` | Code/tests done; M6 pending |
| T7 | Full regression suite and manual OS/accessibility validation | `test(keep-awake): verify integration and OS behavior` | 84 tests passed; manual matrix partial/pending |
| T8 | Living behavior spec and README, gated by evidence | `docs(keep-awake): document verified behavior` | Draft docs done; shipping/sign-off pending |
| — | Quality gate passed, review requested, PR opened after authorization | — | Quality passed; review offered; no PR authorized/opened |

## Decisions (approved by João 2026-10-06)

João explicitly confirmed in chat that all decisions D1–D8 are agreed. No decision remains awaiting approval. No product decisions are reopened. A failed feasibility check is a blocker, not permission to weaken the spec silently.

| # | Decision | Value | Basis / task |
|---|---|---|---|
| D1 | Persisted schema | Add `keepAwake: { "duration": "30m", "mode": "system" }`. Duration enum values: `15m`, `30m`, `1h`, `2h`, `4h`, `8h`, `until-stopped`; mode: `system`, `system-and-display`. Missing object/fields use defaults; present null, wrong types and unknown values reject the entire reload. Binding remains under `bindings["toggle-keep-awake"]`, unassigned by default. | KA-02/12/16/20; `Config.swift:208`; T2 |
| D2 | Assertion strategy | Hold `PreventUserIdleSystemSleep` in both modes; additionally hold `PreventUserIdleDisplaySleep` in display mode. Acquire any additions before publishing state or releasing old requests. Roll back partial acquisitions on failure. Never use `PreventSystemSleep`, activity simulation or `caffeinate` as the production engine. | KA-01/15/18/19; SDK evidence below; T1/T3 |
| D3 | Deadline clock | Inject a sleep-inclusive monotonic clock, implemented using `mach_continuous_time()` converted with `mach_timebase_info`. Store an in-memory deadline in the clock's seconds domain, not calendar time. A single cancellable scheduler reevaluates expiry and countdown; wake reevaluates before reacquisition. | KA-05/06/09/10; SDK `mach_time.h:59`; T4 |
| D4 | Config fan-out and hotkeys | New `AppController` owns one `HotKeyManager` and the existing single `ConfigStore.onChange` callback. It registers/re-registers all bindings, owns failed-binding feedback, routes Keep Awake directly and delegates other actions to TilingManager. Keep Awake reads defaults from the shared store at start; UI observes the store. No additional callback subscriber or multicast registry is needed. | `TilingManager.swift:46–55`, `ConfigStore.swift:20`; KA-11/12/16; T5 |
| D5 | Sleep/wake handling | On `willSleep`, release Momentum's assertions but keep runtime mode/deadline. On `didWake`, expire first; only a still-valid timed or indefinite session reacquires. A reacquisition failure ends protection, becomes inactive and shows an inline error; Retry starts the remembered configuration, never silently extends the expired deadline. | KA-09/18, safety choice for unspecified wake failure; T1/T4 |
| D6 | Preference-save failures | Provide a narrow throwing ConfigStore update path for Keep Awake controls: write candidate config atomically before publishing it. Inactive selection failures retain previous preferences and use existing Settings error feedback. Active mode changes acquire candidate protection first, save the candidate default, then commit; a disk failure releases additions and preserves the old session/default. Normal existing tiling edits retain their current behavior. | KA-03/07/19/20; `ConfigStore.swift:9–14,47`; T2/T4 |
| D7 | Popover and indicator | Extract `MenuBarContent` to its own file; use `.menuBarExtraStyle(.window)` and a custom label. Inactive label uses existing `MenuBarIcon`; active uses new static template `MenuBarAwakeIcon`. Timed label is `ceil(remainingSeconds / 60)` followed by `m`; indefinite has no number. Target a compact ~320 pt content width, adjusting only for usability/accessibility. | KA-08/17; `MyApp.swift:22–60`; T6 |
| D8 | Tests and host side effects | Add injected file URL and optional watcher startup to ConfigStore. In XCTest hosting use a temporary config directory and do not start updater, tiling, hotkey registration, power assertions or lifecycle listeners. Unit tests use fake assertions, clock and scheduler; only explicitly labelled manual checks exercise the OS. | `MyApp.swift:10–18` currently guards only tiling/updater; `ConfigStore.swift:24`; T2/T5/T7 |

## Read this first: handoff notes

### Base and worktree

Code evidence was read from a read-only `git archive origin/main` snapshot at `/tmp/momentum-plan.du63EI`, not inferred from a potentially modified checkout. The canonical feature spec is currently an untracked local document and is absent from `origin/main`: carry it and these planning files into the implementation worktree deliberately; do not lose or overwrite the originals. Recheck source references if the base moves.

Suggested branch: `feat/keep-awake`; worktree: `../.worktrees/keep-awake`. Before **every** origin/GitHub operation follow `AGENTS.md`: switch to `jvrviegas`, verify active via `gh auth status` (and login identity), use an EXIT trap to restore `joao-viegas-procimo`, verify restoration even on errors. Never log auth tokens. No implementation branch or PR is created by this planning task.

### Existing code to reuse

| Need | Existing seam | Evidence on base |
|---|---|---|
| JSON action identity, Settings row enumeration | `Action.allCases`, `rawValue`, `title` | `Momentum/Config.swift:13,27,38` |
| Missing defaults / explicit unbinding | `Config.init(from:)`, `defaultBindings` | `Momentum/Config.swift:183,208` |
| Persistence/reload errors | `ConfigStore.config`, `reload`, `save`, watcher | `Momentum/ConfigStore.swift:9,34,47,60` |
| Native global shortcuts and collision ordering | `HotKeyManager.register(_:)`, `unregisterAll()` | `Momentum/HotKeyManager.swift:21,40` |
| Existing AX startup and tiling gates | `start()`, `refresh()`, `perform(_:)` | `Momentum/TilingManager.swift:46,87,262` |
| Settings recorder / error presentation | `SettingsView.body`, `HotKeyRecorder` | `Momentum/SettingsView.swift:11,81,242` |
| Existing commands and Settings activation | `MenuContent.body` | `Momentum/MyApp.swift:37–60` |
| App-host test guard | `MomentumApp.init()` | `Momentum/MyApp.swift:10–18` |
| Test conventions / collision example | Swift Testing `@MainActor`, `ConfigTests`, `HotKeyManagerTests` | `MomentumTests/MomentumTests.swift:6,80` |
| Automatic new-file membership | Synchronized app/test folders | `Momentum.xcodeproj/project.pbxproj:38–52` |

### API evidence and feasibility boundaries

Planning verified these APIs against the installed Xcode 27 SDK, not against a live assertion experiment:

- `IOKit.framework/.../Headers/pwr_mgt/IOPMLib.h:275–314`: idle system/display types; system assertion allows display sleep and does not prevent lid-close, Apple-menu or low-battery sleep. Display assertion does not light an already-off display; do not use user-activity declarations to work around that.
- Same header `:757–780`: `IOPMAssertionCreateWithName`, level-on, returned ID, `kIOReturnSuccess`, no special privileges needed. `:648–663`: creation must be paired with `IOPMAssertionRelease`.
- SDK `usr/include/mach/mach_time.h:59–62`: `mach_continuous_time` advances during sleep.
- SDK SwiftUI `arm64e-apple-macos.swiftinterface:2092–2094,5974–5975`: custom `MenuBarExtra` label and window style exist.
- OS automatic assertion cleanup on process death, actual lock/wake behavior, release failure behavior and keyboard navigation remain T1/T7 empirical checks. Do not describe them as tested yet.

### Do not touch / conventions

- Preserve window layout, animation, floating-app defaults, Desktop move logic and current tiling-action guards. Desktop actions retain their existing behavior while tiling is disabled; all tiling actions still require AX trust and obey native move suspension. KA-11 is not a reason to remove those protections.
- Keep the existing tiling startup Accessibility prompt; Keep Awake must not call `Permissions.waitForAccessibility()` or introduce any additional prompt. That helper currently prompts at app startup (`Permissions.swift:5–8`). Clarify the Settings banner as a **tiling** requirement, not a Keep Awake requirement.
- Preserve Sparkle, Settings activation, updater command, Quit, config errors and move-error dismissal.
- Conventional Commits from `CONTRIBUTING.md:3`; history groups coherent implementation/tests across multiple files (e.g. `f6f642c`, `41cd556`). No fabricated issue IDs in comments. Swift Testing, `@MainActor` tests, Swift 6 and default app MainActor isolation (`project.pbxproj:365,369`).
- Deployment target is macOS 27.0 (`project.pbxproj:264,414`); do not lower it or broaden compatibility here. New files in synchronized folders normally need no project edit; verify IOKit linking through a build before deciding otherwise.
- No formatter/linter configuration was found; match surrounding Swift style and run build/tests plus `git diff --check`.
- Unit tests must not read/write the real `~/.config/momentum/tiling.json` or create real power assertions. João authorized the normal profile; all automated tests/native smoke harnesses still use temporary configs and skip unrelated services. Do not disturb the installed Momentum or its shortcuts. Native Carbon collision regression uses an otherwise unassigned four-modifier F12 and cleans up its handler.

## Architecture and proposed interfaces

`MomentumApp` creates shared ConfigStore → TilingManager + KeepAwakeService → AppController. AppController starts global action registration and lifecycle listeners synchronously before launching the independent asynchronous tiling startup. Config changes re-register hotkeys and call a narrow `TilingManager.configurationDidChange()` refresh hook; they do not mutate an active Keep Awake session.

`MenuBarContent` → KeepAwakeService commands (`start`, `toggle`, `stop`, `extend(by:)`, `changeMode`) → injectable `PowerAssertionClient` → IOKit. Inactive controls update only `Config.keepAwake`. Active mode picker reads runtime mode, not the externally editable default. Duration controls are shown only while inactive. Settings hotkey recorder writes the existing shared bindings dictionary.

Proposed internal types (final names may follow surrounding style without changing contracts):

- In `Config.swift`: `KeepAwakeDuration: String, Codable, CaseIterable`, `KeepAwakeMode`, `KeepAwakePreferences: Codable, Equatable`; duration maps to optional finite seconds.
- In `PowerAssertions.swift`: small injected create/release interface and owned assertion IDs. Native adapter wraps `IOPMAssertionCreateWithName`/`IOPMAssertionRelease`; use descriptive names such as `Momentum Keep Awake — System`. Keep errors diagnostic but readable.
- In `KeepAwakeService.swift`: `@Observable` MainActor service with private mutable runtime state; expose active mode, optional deadline, remaining minutes, and inline error. Distinguish inactive, active protected, and sleep-suspended internally so the toggle can stop a suspended session. Inject clock and scheduler closures/protocols; no unnecessary general framework.
- In `AppController.swift`: `@Observable` owner of failed hotkeys and routing, plus lifecycle notification tokens; injectable registration/routing seams for tests. KeepAwakeService handles its own session lifecycle. AppController shuts down listeners, timers and owned registrations on termination.

### State transitions

| Event | Result |
|---|---|
| Start while inactive | Read remembered config; acquire all requested assertions; only then publish mode/deadline/active label. Failure leaves inactive + inline Retry. |
| Start while already active | Idempotent; must not restart or reset deadline. |
| Stop / active toggle | Release all owned assertions, cancel timer and clear runtime state. Repeated stop is safe; no preference change. |
| Finite deadline reached (`now >= deadline`) | Stop silently, including before any extension/mode-change command executed after deadline. |
| Extend valid timed session | Add 900/1800/3600 seconds to existing deadline, not to now; retain saved duration, allow total above 8h. Inactive/indefinite extension is refused/no-op. |
| Active mode change | Acquire additions; persist new default transactionally; commit runtime mode and release no-longer-needed requests. Deadline unchanged. Native/save failure retains old mode/deadline/default and displays inline error. |
| External valid config edit | Update defaults/bindings only. Runtime active mode/deadline are unchanged; next start reads new defaults. |
| Will sleep / did wake | Release while sleeping; on wake check deadline before requesting anything. Expired ends; valid resumes same mode/deadline; failure becomes inactive/error (D5). |
| Power source or lock changes | No session mutation, deadline reset or simulated input. OS may override display protection. |
| Quit | Explicit cleanup; crashes rely on OS process-scoped cleanup verified in T7. Relaunch always inactive. |

Native release errors must not be discarded: retain ownership of unreleased IDs for bounded cleanup retry and surface diagnostic error rather than claiming successful release. T1 must verify an acceptable strategy; if the API can leave an unremovable request, stop and report before shipping. Failed acquisition/rollback must never publish an active indication or lose an assertion ID. No infinite main-thread retries.

## Tasks

### T1 — Native feasibility and test environment

- [x] On the user-authorized normal macOS 27 profile, compile a temporary minimal IOKit probe and inspect `pmset -g assertions` for each requested type; do not change permanent energy preferences.
- [ ] Confirm import/linking, ordinary-user privileges, create/release result handling, partial-acquisition rollback, Quit and forced process-death cleanup. Keep probe files in a temporary directory, not production code.
- [ ] Verify the chosen clock advances during explicit sleep and confirm `.window` supports custom static image + countdown label, native selectors and keyboard focus.
- [ ] Record machine/OS build/Xcode, commands, expected/observed results and unresolved limitations in `docs/qa/keep-awake-validation.md`. Failures block dependent tasks; do not check README boxes.

**Verify:** probe assertions appear only while owned and disappear after release/process exit; clock delta includes sleep; capture evidence rather than merely documenting API availability.

### T2 — `Config.swift`, `ConfigStore.swift`, config tests

- [x] Add D1 enums/preferences and `Action.toggleKeepAwake` raw value/title/allCases; append action to keep existing collision order stable. Omit default binding; missing or explicit null stays unbound.
- [x] Implement strict nested preference decoding, with missing values defaulting and invalid present values failing the complete config reload. Preserve all old schema/defaults.
- [x] Allow injected ConfigStore file URL and watcher enablement; production defaults remain the existing path. Expose an internal reload seam for deterministic tests and a shutdown path cancelling watcher/task resources.
- [x] Implement D6 atomic candidate write-before-publish update for Keep Awake controls. Publish `onChange` once on success; failures set `lastError`, retain old config and do not emit changes. Leave existing direct config edits working.
- [x] Add config decode/action cases to `MomentumTests/MomentumTests.swift`; new `ConfigStoreTests.swift` uses unique temporary directories with cleanup and tests live/atomic reload separately from synchronous reload.

**Verify:** C1–C5 below; old config/animation tests pass; test fixtures contain no deadline, assertion ID, current state or active flag.

### T3 — `Momentum/PowerAssertions.swift` and tests (new)

- [x] Wrap public IOKit idle assertion creation/release with an injectable low-level client. System-plus-display acquisition is all-or-nothing; preserve old assertions during mode changes.
- [x] Track owned IDs exactly once; release on stop, rollback and shutdown. Do not release unrelated requests. Make same-mode changes idempotent.
- [x] Add `PowerAssertionTests.swift` with failure injection on first/second creation, transactional replacement, release-call counting and cleanup retry handling; production results match the T1 evidence.

**Verify:** P1–P4; build links without changing signing, entitlements or deployment target. No activity declarations, synthetic input or private power APIs.

### T4 — `Momentum/KeepAwakeService.swift` and tests (new)

- [x] Implement explicit runtime transitions and commands above; fake clock and scheduler make expiry deterministic. A new instance is always inactive, irrespective of preferences.
- [x] Use sleep-inclusive clock, cancellable scheduled expiry/countdown and observer updates even with popover closed. One scheduling owner; no accumulating timers or retain cycles. Countdown is derived from deadline, never decremented per tick.
- [x] Reevaluate expiry before start/stop/toggle/extend/mode changes and wake; stop/restart cancels stale scheduled callbacks using session identity/generation.
- [x] Implement D6 active-mode transaction with ConfigStore; inactive selectors save without starting. Extensions never save duration.
- [x] Implement sleep suspension/wake reconciliation and termination cleanup; errors are inline state, cleared by a successful retry/action, never alerts or normal-expiry notifications.
- [x] Add `KeepAwakeServiceTests.swift` for S1–S9, including native/save failures, deadline boundaries and reentrancy/stale callbacks.

**Verify:** fake-adapter assertions and runtime state agree in every transition; timers and requests are absent after stop/expiry/shutdown; no runtime state is encoded.

### T5 — `AppController.swift` (new), TilingManager/MyApp/Settings wiring

- [x] Move `HotKeyManager` ownership, failed hotkeys, registration and ConfigStore callback from TilingManager to AppController. It alone owns `onChange`; removing tiling startup ownership must not suppress future refreshes.
- [x] Expose narrowly scoped tiling `perform(_:)` and `configurationDidChange()`; retain existing AX/enabled/suspension guards. Exhaustively handle `.toggleKeepAwake` as an app action before delegation; TilingManager defensively ignores it.
- [x] Register app-level bindings without waiting for Accessibility. Start the existing tiling permission lifecycle separately. Keep Awake does not depend on trust, `isEnabled` or `isSuspended`.
- [x] Move Settings failed-binding feedback to AppController; preserve existing `HotKeyRecorder`, enumeration, collision order, null unbinding and refusal messages. Explain Accessibility is for tiling only.
- [x] Hook NSWorkspace `willSleepNotification`/`didWakeNotification` and app termination on MainActor; tear down notification tokens/registrations and service scheduler. Do not add power/lock automation.
- [x] For XCTest use a temporary ConfigStore and skip controller start/native listeners/AX/updater. Add injected registration/tiling dispatch seams and `AppControllerTests.swift`; do not make tests call the real permission loop.

**Verify:** A1–A4; Keep Awake works before AX trust and with tiling disabled/suspended; config edits notify both routing and tiling refresh, without resetting active sessions.

### T6 — `MenuBarContent.swift` (new), MyApp, icon assets and presentation tests

- [ ] Replace private menu content with compact native SwiftUI content; Keep Awake first, existing tiling/error controls next, Settings/Updates/Quit below. Avoid tabs, animations or large branding.
- [ ] Inactive: duration and mode pickers, Start and a toggle wired to the same service command. Selections save immediately without creating assertions. Active: toggle/Stop, runtime mode picker and remaining/indefinite text; +15/+30/+60 only for timed sessions.
- [ ] Show activation/mode errors inline. Retry while inactive repeats Start; Retry on failed active mode change repeats the attempted mode without resetting deadline. Disable or serialize repeated commands where needed.
- [ ] Use custom menu label with existing inactive icon, new static awake variant and derived finite countdown. Do not rely on `Label` title visibility to display the number; test actual macOS rendering. Expiry restores exact inactive label.
- [ ] Add template vector asset `MenuBarAwakeIcon.imageset` (`Contents.json` + `awake.svg`), visually related to existing icon; verify dark/light modes and Retina sizing.
- [ ] Add labels/help/accessibility values for state, countdown and icon-only controls; preserve Settings activation and ⌘,/⌘Q behavior under window-style popover. Provide usable keyboard order and VoiceOver reading.
- [ ] Extract only small pure presentation helpers if needed for `KeepAwakePresentationTests.swift` (U1–U3); do not create an unnecessary view-model architecture. Window interaction is proved manually in M6.

**Verify:** U1–U3 and M6; app updates label while the popover is closed; error handling never creates modal alerts.

### T7 — Regression and manual matrix

- [x] Complete automatic case matrix below, including failure/refusal cases; run the entire existing suite, not just new files.
- [ ] Execute M1–M7 in the authorized normal macOS profile, with only one development Momentum process; capture assertion IDs/types, screenshots and observed timing in the validation document.
- [ ] Explicitly record critical-battery test as not performed if unsafe; never deliberately drain hardware to unsafe levels. API limitation evidence and human reviewer acceptance are required, not a fabricated runtime pass.
- [ ] Fix only feature-related failures. Report unrelated regressions separately; do not change native Desktop moves or tiling behavior as cleanup.

**Verify:** exact quality gate below passes; each manual case has passed/failed/blocked status and evidence. A missing mandatory OS/accessibility check blocks declaring implementation complete.

### T8 — Shipping documentation

- [ ] Create `docs/spec/keep-awake.md` from the functional-area template: overview, concepts, KA-01–KA-20 behavior rules, OS limitations, config and permission implications, evidence/known gaps. Preserve rule identifiers, describe verified current behavior only.
- [ ] Update feature spec's `Merged into`/status when implementation and required checks are complete; do not alter approved criteria to conceal gaps.
- [ ] Update README configuration/action documentation and usage. Only check relevant Keep Awake tracker items after T7's required OS evidence and reviewer sign-off; Focus remains unchecked and unchanged.

**Verify:** spec/README match actual behavior and validation evidence; no claims of sleep/lid/lock bypass or automatic session restoration.

## Automated case matrix

Cases belong to the test file named in the corresponding task; use fake adapters except the existing explicitly native Carbon test.

| Case | Asserts | Criteria |
|---|---|---|
| C1 | Legacy/missing nested config = 30m/system; all seven durations/two modes round-trip; existing fields unchanged | KA-02/16 |
| C2 | `toggle-keep-awake` raw/title/allCases; missing/null binding unassigned; valid custom combo round-trips | KA-12/16 |
| C3 | Invalid enum, null present preferences/fields, bad type or binding reject reload; full previous valid config retained and lastError shown | KA-20 |
| C4 | Inactive duration/mode save immediately, survive new store, make zero native requests; save failure retains config and reports error | KA-03/16/20 |
| C5 | Atomic valid external edit updates defaults/bindings, no runtime mutation; invalid edits retain prior config; normal tiling callback still runs | KA-16/20 |
| P1 | System mode requests only system; display mode requests both; zero/failed return never publishes active | KA-01/18 |
| P2 | Second creation failure releases first; first failure owns nothing; repeated stop/cleanup do not double-release | KA-04/18 |
| P3 | Mode acquisition failure leaves old IDs/mode/deadline/default; successful upgrade/downgrade releases only no-longer-needed requests | KA-07/19 |
| P4 | Release failure retains ID for bounded cleanup retry and exposes error; no false claim of successful cleanup | KA-04/18/19 |
| S1 | Start/toggle reads remembered prefs; active toggle/Stop ends; repeat Start does not reset deadline | KA-04 |
| S2 | Finite expires at exact deadline silently; indefinite never expires from elapsed time | KA-05 |
| S3 | +15/+30/+60 adds to old deadline, including totals >8h; saved duration unchanged; inactive/indefinite/expired extensions do not start/revive | KA-06 |
| S4 | Mode success preserves deadline and saves new default; assertion or save failure retains old runtime and default; same mode no-op | KA-07/19 |
| S5 | Sleep then wake before deadline reacquires same mode/deadline; wake at/after deadline acquires nothing; indefinite resumes; wake failure inactive/error | KA-09/18 |
| S6 | Stop/expiry/shutdown cancels scheduling; stale callbacks from earlier session cannot end/restart a new one | KA-04/05/10 |
| S7 | New service after simulated relaunch inactive; config encoding contains no runtime fields | KA-10/16 |
| S8 | External preferences differ from active mode: display still reflects active; subsequent start uses new defaults | KA-08/16 |
| S9 | Activation failure inactive/no active label, inline error; successful Retry clears error; failed active mode Retry preserves existing deadline | KA-18/19 |
| A1 | App route handles Keep Awake regardless of AX/tiling enabled/native move suspension; tiling actions retain old guards and delegation | KA-11/12 |
| A2 | One config callback re-registers bindings and refreshes tiling; no repeated callback registration or current-session mutation | KA-11/16 |
| A3 | Duplicate new binding loses to earlier existing action; injected unavailable-registration error reaches Settings feedback; recorder clear stays null | KA-12 |
| A4 | XCTest host creates no production ConfigStore/native services; termination hooks dispose listeners/hotkeys/service | KA-10/11 |
| U1 | Countdown 60.1s→2m, 60s→1m, 0.1s→1m; expiry inactive; label/popover use same deadline-derived value | KA-08 |
| U2 | Timed/indefinite/inactive visibility, mode/status and extension button rules | KA-06/08/17 |
| U3 | Inline errors and Retry target reflect failed Start vs failed active change; no optimistic active indicator | KA-18/19 |

## Manual OS and accessibility matrix

Record OS/hardware, power source, build SHA, steps, expected vs actual and evidence under `docs/qa/keep-awake-validation.md`. Use the authorized normal profile; isolate automated configs and back up normal preferences before interactive edits. Safely restore any test-only sleep preference changes afterward. Do not use `pmset sleepnow` until ready to interrupt the test machine; no shared environments or external APIs.

| Case | Procedure / expected evidence | Criteria |
|---|---|---|
| M1 | Start each mode; `pmset -g assertions` shows only intended Momentum types. Observe system idle prevention and display allowed to idle in system-only vs kept on in combined mode. Stop and confirm Momentum requests disappear. | KA-01/04/15 |
| M2 | Timed expiry while popover closed restores icon, removes requests, emits no notification. Extend a real session and confirm existing-deadline arithmetic and unchanged saved duration; indefinite has no countdown/buttons. | KA-05/06/08 |
| M3 | Explicit Sleep and lid close still sleep. Wake before timed deadline resumes original mode/deadline; wake after deadline does not reacquire; test indefinite too. Lock does not reset state/deadline; display may go off. Never unlock or simulate input. | KA-09/14/15 |
| M4 | Battery↔external supply does not alter session/deadline; Quit and forced process death remove requests; relaunch inactive with preferences retained. Critical battery safety is an API-limited protection, not a claim of tested exhaustion. | KA-10/13/15 |
| M5 | Deny AX, dismiss existing startup tiling prompt and leave permission ungranted: popover and optional hotkey still work. Disable tiling, repeat. Bind/clear/collide/refuse shortcut via Settings and edit JSON; valid external edits leave active mode/deadline unchanged; invalid edit shows existing config error. | KA-11/12/16/20 |
| M6 | Keyboard-only Tab/Shift-Tab, Space/Return, native picker arrows, Escape/dismiss/reopen; VoiceOver reads labels/state/time/errors. Dark/light appearance, menu-bar countdown with popover closed, all original controls and Settings/Updates/Quit reachable. Verify Settings activation and existing shortcut behavior. | KA-03/08/17 |
| M7 | Use a development-only injected failing adapter (not a shipping user preference) to demonstrate inline Start Retry and active mode failure: no false active indicator, old protection/deadline/default preserved. Test second assertion and persistence failures. | KA-07/18/19 |

## Acceptance criteria → proof

The canonical wording remains in the feature spec; these mappings cover every numbered criterion, including OS-only limits.

| Criterion | Proof |
|---|---|
| KA-01 — two protection modes | P1, M1 |
| KA-02 — first-use defaults and duration choices | C1, U2 |
| KA-03 — inactive selectors save without start | C4, M6 |
| KA-04 — remembered start / toggle / stop / shortcut | P2, S1, A1, M1/M5 |
| KA-05 — silent finite expiry / indefinite | S2, M2 |
| KA-06 — extend original deadline, no cap, hide indefinite buttons | S3, U2, M2 |
| KA-07 — immediate successful mode change, preserve deadline/save | P3, S4, M7 |
| KA-08 — static icon + rounded countdown, status parity | S8, U1/U2, M2/M6 |
| KA-09 — elapsed sleep and wake reconciliation | S5, M3 |
| KA-10 — exit/crash ends; relaunch inactive | S6/S7, A4, M4 |
| KA-11 — independent of tiling/AX without new prompts | A1/A2/A4, M5 |
| KA-12 — optional Settings/JSON binding, feedback | C2, A3, M5 |
| KA-13 — unchanged on power-source change | M4 |
| KA-14 — unchanged on lock; OS display caveat | M3 |
| KA-15 — respect explicit/lid/lock/battery protections | T1 API evidence, M1/M3/M4; no unsafe battery test required |
| KA-16 — single JSON persistence, no runtime, external edit isolation | C2/C4/C5, S7/S8, M5 |
| KA-17 — native accessible popover and preserved controls | U2, M6 |
| KA-18 — failed activation inactive, inline Retry | P1/P2, S9, U3, M7 |
| KA-19 — failed mode change rollback | P3, S4/S9, U3, M7 |
| KA-20 — invalid config retains last valid + Settings error | C3/C5, M5 |

## Quality gate

Run from the implementation worktree in the authorized normal macOS profile with the isolated XCTest host. Unique outputs avoid modifying repository build artifacts. Signing uses existing project settings and may require a locally configured development team; do not commit personal signing changes. Xcode 27/macOS 27 required by the existing target.

```bash
set -e
QA_BUILD=$(mktemp -d /tmp/momentum-keep-awake-build.XXXXXX)
xcodebuild -project Momentum.xcodeproj -scheme Momentum \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$QA_BUILD/DerivedData" \
  -resultBundlePath "$QA_BUILD/Tests.xcresult" test
git diff --check
```

Automatic success is necessary but does not replace M1–M7. No build/test run was performed as part of writing this plan.

## Files touched by implementation

This is the implementation inventory (planning artifacts are not counted). 12 new entries + 8 modified files; the new icon entry contains two files.

| File / entry | Change |
|---|---|
| `Momentum/PowerAssertions.swift` | New: public native adapter and ownership |
| `Momentum/KeepAwakeService.swift` | New: independent runtime/session/clock/scheduler |
| `Momentum/AppController.swift` | New: global action/config/lifecycle owner |
| `Momentum/MenuBarContent.swift` | New: native popover/presentation helpers |
| `Momentum/Assets.xcassets/MenuBarAwakeIcon.imageset/` | New: `Contents.json` and `awake.svg`, template active icon |
| `MomentumTests/ConfigStoreTests.swift` | New: isolated persistence/reload/save failure |
| `MomentumTests/PowerAssertionTests.swift` | New: adapter/ownership/failure tests |
| `MomentumTests/KeepAwakeServiceTests.swift` | New: deterministic lifecycle tests |
| `MomentumTests/AppControllerTests.swift` | New: registration/routing/regression tests |
| `MomentumTests/KeepAwakePresentationTests.swift` | New: countdown/visibility/error parity tests |
| `docs/qa/keep-awake-validation.md` | New: feasibility/manual evidence |
| `docs/spec/keep-awake.md` | New: living behavior on ship |
| `Momentum/Config.swift` | Modified: enums, defaults, decoding and action |
| `Momentum/ConfigStore.swift` | Modified: injection, transactional write and disposal |
| `Momentum/TilingManager.swift` | Modified: remove global registration; expose narrow tiling hooks |
| `Momentum/MyApp.swift` | Modified: composition, window style, custom label, test isolation |
| `Momentum/SettingsView.swift` | Modified: failed binding source and tiling-only permission copy |
| `MomentumTests/MomentumTests.swift` | Modified: config/action/Carbon duplicate regression cases |
| `README.md` | Modified: config/usage and evidence-gated tracker |
| `docs/plans/keep-awake-feature-spec.md` | Modified on ship: status and living-spec link |

Inventory totals: **12 new entries** (13 physical files) and **8 modified files**. Project file changes are conditional only if IOKit linking cannot be satisfied by module autolinking, and must be recorded if needed.

## Known integration hazards, not unrelated cleanup

- Current `MomentumApp.init()` constructs the production ConfigStore before checking XCTest; this can create/read the real config during tests (`MyApp.swift:10–18`). T2/T5 address this narrowly because new persistence tests require isolation.
- Current global shortcut registration and config callback belong to TilingManager, and its dispatcher gates all actions on AX trust (`TilingManager.swift:46–55,262–264`). T5 removes that dependency for the new app action while preserving tiling guards.
- Current `ConfigStore.config` publishes before save success (`ConfigStore.swift:9–14`). D6 adds a narrow transactional path, not a broad rewrite of existing tiling persistence.
- No unrelated bug was established during planning. Do not create unrelated tracker issues without João's agreement.

## Out of scope

Custom durations/clock-time deadlines; lid-close overrides; power-source automation; normal-expiry notifications; focus timers and focus-state restoration; UI tabs/branding/analytics/simulated activity; restoring sessions across launches; unrelated tiling/Spaces/refactoring; release/version/signing changes. No database/query-count test applies to this local native feature.

## Progress log

- 2026-10-06 — plan written against fetched `origin/main` `daf18d8`; approved local spec read in full. Native SDK signatures checked, but no live OS tests or app implementation performed. GitHub account restored and verified as `joao-viegas-procimo`. Decisions were awaiting approval at initial handoff.
- 2026-10-06 — João confirmed agreement with all decisions D1–D8 in chat. Plan ready to begin at T1; native feasibility and OS validation remain unperformed. No application code changed.
- 2026-10-06 — João authorized his normal profile. Created `feat/keep-awake` in `../.worktrees/keep-awake` from local `main` at `daf18d8`; deliberately copied the untracked planning artifacts without modifying their originals. No origin operation was needed.
- 2026-10-06 — Implemented T2–T6 and automated matrix; quality gate passed with 84 tests in 12 suites and no Swift warnings. Native assertion create/release/process-death probe and production-service/controller smoke passed with temporary configs and no real shortcut/tiling/updater side effects. Added explicit Carbon handler disposal in `HotKeyManager.swift` (one additional implementation file beyond the inventory) to avoid dangling registrations/callbacks. IOKit autolinking succeeded with no project/signing changes.
- 2026-10-06 — Added draft branch behavior spec and README usage/configuration. Kept feature boxes unchecked and the canonical proposal approved/not shipped: empirical sleep, idle/display, native UI/keyboard/VoiceOver checks and technical sign-off are still pending. Independent review offered; no review artifact or PR created without authorization.
