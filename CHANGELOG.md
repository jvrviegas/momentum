# Changelog

Notable changes to Momentum are documented here. Versions follow Semantic Versioning; `0.x` releases are early-stage and may change before stabilization.

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
