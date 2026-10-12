# Settings Preferences
> Sidebar pages and next-session Keep Awake preferences

Entry: `Momentum/MyApp.swift:MomentumApp.body` → `Momentum/SettingsView.swift:SettingsView`
- Native NavigationSplitView owns sidebar/detail toolbar separation; sidebar navigation title is Momentum, detail title follows selected page. Content retains subtitle only. Column visibility is fixed to all; sidebar toggle removal MUST be attached to the sidebar List, not the outer NavigationSplitView (outer placement builds but leaves the toggle visible on macOS 27). `Momentum/MyApp.swift:MomentumApp.body` sets Settings toolbar to unifiedCompact to avoid a second toolbar row.
- `SettingsPage`: stable raw values stored under AppStorage `settings.selectedPage`; invalid stored values fall back to Layout.
- `SettingsShortcutGroup.actions`: partitions Action.allCases; coverage test prevents dropped/duplicated shortcuts.
- Normal config bindings save via `Momentum/ConfigStore.swift:ConfigStore.config` didSet.
- Settings Keep Awake pickers → `ConfigStore.updateKeepAwake()`; transactional save, errors exposed through lastError; do not mutate the active session.
- Popup uses separate Keep Awake and Window Tiling panels; one primary Start/Stop action (no duplicate session toggle), conditional timed extensions, labeled Settings button and version in the header, plus side-by-side bordered Check for Updates and Quit footer actions. `KeepAwakePresentation.sessionTitle/actionTitle` derive the visible state; menu-bar accessibility status remains unchanged.
- Menu-bar controls intentionally differ: `Momentum/MenuBarContent.swift:keepAwakeControls` → `KeepAwakeService.changeMode()` updates the running mode; `selectDuration()` only accepts inactive sessions.
- Config file actions use store.location (not static default URL).
- `Momentum/AppVersion.swift:AppVersionLabel` is shared by the popup header and Settings sidebar bottom inset; version/build come from Bundle.main metadata, not a hardcoded release value.

Verification: `MomentumTests/SettingsNavigationTests.swift`; full xcodebuild test suite. System Events accessibility inspection confirmed the installed app had a toolbar button before the sidebar-scoped fix and no toolbar on any of the five pages afterward. System Settings deep links still require manual verification.

Updated: 2026-10-12
