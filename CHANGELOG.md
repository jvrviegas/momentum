# Changelog

Notable changes to Momentum are documented here. Versions follow Semantic Versioning; `0.x` releases are early-stage and may change before stabilization.

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
