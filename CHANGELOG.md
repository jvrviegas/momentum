# Changelog

Notable changes to Momentum are documented here. Versions follow Semantic Versioning; `0.x` releases are early-stage and may change before stabilization.

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
