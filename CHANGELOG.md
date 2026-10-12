# Changelog

Notable changes to Momentum are documented here. Versions follow Semantic Versioning; `0.x` releases are early-stage and may change before stabilization.

## [0.5.0] - 2026-10-12

Early-stage prerelease with a development-signed app ZIP for local testing. It is not Developer ID-signed or notarized; automatic-update delivery is not validated.

### Added

- Settings now has dedicated Layout, Floating Apps, Keyboard Shortcuts, Keep Awake, and Advanced pages, with a persistent sidebar and remembered selection.
- Preferred Keep Awake duration and mode can be changed in Settings for the next session, without altering a running session.

### Changed

- Keyboard shortcuts are grouped by focus, window movement, Desktops, displays, and other actions. Desktop limitations and keyboard-layout guidance are available in expandable disclosures.
- Settings uses a compact native split-view layout without a sidebar toggle, focused page descriptions, contextual warnings, permission links, and immediate saving.
- Floating-app settings include empty-state guidance, accessible removal controls, and whitespace trimming for manually entered bundle identifiers.

### Compatibility

- Validation includes 182 automated tests and runtime accessibility checks confirming the sidebar toggle is absent on all five Settings pages.
- Existing native Desktop API, SIP, and multi-display validation limitations remain unchanged.
- The downloadable ZIP is a development build for testing, not a notarized installer or a signed Sparkle update.

## [0.4.0] - 2026-10-12

Source-only prerelease; a Developer ID-signed, notarized installer is not yet available.

### Added

- Independent tiling layouts for each display and native Desktop, with per-display usable bounds and animation pacing.
- Directional keyboard focus across display edges while window swaps stay on the current display.
- Optional previous/next-display shortcuts with wrapping, verified placement and focus following. Floating windows remain floating and fit within the destination's usable area.
- Dragging a tiled window across displays inserts it into the destination layout after release. Disconnect/reconnect follows macOS's relocation without actively restoring windows to their former monitor.

### Changed

- Send to Desktop N now targets the Nth normal Desktop on the focused window's display. Fullscreen destinations are excluded; per-display sending order may differ from macOS's global switching shortcut labels.
- Native display transfers wait for stable Space membership and matching Accessibility/WindowServer geometry before following focus. Failed or partial moves reconcile actual state and report a dismissible error.
- Spacing and animation settings remain shared across displays, with Reduce Motion support and no programmatic layout writes during a mouse drag.

### Fixed

- Desktop-switch recovery now requires explicit confirmation before restarting the Dock; an ignored shortcut never automatically restarts it or restores minimized windows.

### Compatibility

- Validation includes 179 automated tests, 16 targeted native coordinator checks and 19 owner-observed manual checks in a fixture-restricted preview on macOS 27.0.1 with mixed-refresh displays.
- Unsupported native Space APIs may break after macOS updates. The test host already had custom/partially disabled SIP; fully enabled SIP compatibility remains unverified. This is not a recommendation to disable SIP.
- Shared-Spaces live tests were skipped at the owner's request. Mirroring, unrestricted regular-app/startup behavior and app-driven inter-display movement remain unverified.
- This prerelease is source only; it does not provide an installer or validate automatic-update delivery.

## [0.3.1] - 2026-10-07

Source-only prerelease; a Developer ID-signed, notarized installer is not yet available.

### Fixed

- Desktop switching recovers when the macOS Dock stops responding to the “Switch to Desktop N” shortcuts, such as after waking with the lid closed or connecting a display. When a switch is ignored, Momentum restarts the Dock once and switches again. A restart is allowed once per launch, wake, or display being connected or disconnected.

### Compatibility

- The first switch after the Dock gets stuck takes about 2 seconds, and the Dock briefly restarts.
- Verified on macOS 27.0.1 after a lid-closed wake and after reconnecting a monitor.

## [0.3.0] - 2026-10-06

Source-only prerelease; a Developer ID-signed, notarized installer is not yet available.

### Added

- Keep Awake sessions with system-only or system-and-display idle-sleep protection, independent of tiling and its permissions.
- Remembered durations from 15 minutes to 8 hours or Until stopped, with +15/+30/+60 minute extensions and silent timed expiry. Elapsed sleep counts toward deadlines; relaunch always starts inactive.
- A bold Charged menu-bar icon with a rounded-up minutes indicator, plus an optional configurable Toggle Keep Awake shortcut.

### Changed

- The menu bar now opens a compact native popover with an on/off Keep Awake switch, mode/duration controls, inline errors and Retry. Existing tiling, Settings, update and Quit controls remain available.

### Fixed

- Permission guidance now uses macOS 27's Device Control and Data Access pane name.

### Compatibility

- Keep Awake uses public idle-sleep assertions and does not override explicit Sleep, lid-close, locking or critical-battery protections.
- Validation includes 93 automated tests, native lifecycle/error-UI checks and owner-confirmed manual checks. VoiceOver testing was explicitly skipped by the owner; unsafe battery exhaustion was not performed.
- Existing unsupported native Desktop-move/SIP limitations remain unchanged.

## [0.2.0] - 2026-10-06

Source-only prerelease; a Developer ID-signed, notarized installer is not yet available.

### Changed

- Sending a window to another Desktop now uses a direct native move instead of simulated title-bar dragging. The cursor stays put and the current Desktop remains visible.
- Sending no longer requires the system's "Switch to Desktop N" shortcuts. Those shortcuts are still needed for Desktop switching.

### Fixed

- Window layouts are updated only after macOS confirms the move. Failed moves leave the layout intact and report an error in the menu and Settings.
- Desktop destinations follow Mission Control order and exclude fullscreen Spaces.

### Compatibility

- Native moves use an unsupported private macOS API and may require changes after system updates.
- Verified on macOS 27.0.1 with SIP already partially disabled; fully enabled SIP has not been verified on that build.

## [0.1.0] - 2026-10-06

Initial public prerelease. Available as source; a Developer ID-signed, notarized installer is not yet available.

### Added

- Automatic BSP window tiling on the main display, with separate layouts for native macOS Desktops.
- Configurable shortcuts for focusing and swapping windows, toggling floating mode, retiling, and switching or sending windows to Desktops.
- Layout settings, floating-app exclusions, and live-reloaded JSON configuration.
- Animated tiling transitions with display-synchronised frame pacing, fewer Accessibility writes, and velocity-preserving interruption.
- An animation toggle and optional Momentum-only Reduce Motion override that leaves the system preference unchanged.

### Fixed

- More reliable handling of tiling suspension, hidden windows, duplicate shortcuts, and configuration reloads.
- Safer native Desktop moves and user drag/resize handling.
