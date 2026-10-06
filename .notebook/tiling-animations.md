# Tiling animations
> Accessibility frame interpolation, not compositor animation

Entry: `Momentum/TilingManager.swift:apply()`
Flow: BSP target frames → `Momentum/WindowAnimation.swift:retarget()` → main-display CADisplayLink → `Momentum/TilingManager.swift:animateFrame()` → `Momentum/AXWindow.swift:setFrame()`

- `WindowAnimation`: pure state, 200 ms cubic Hermite; fresh transitions match original ease-out. `CACurrentMediaTime()` clock; same target preserves deadline. Retarget starts at actual AX frame, carries velocity from last displayed sample (not between-frame wall time). Per-axis native deviations >2 points reset velocity; sizes stay >=1. Completion uses deadline, not intermediate target crossing.
- `TilingManager.shouldAnimate`: `Config.shouldAnimate(reduceMotion:)` + live NSWorkspace preference; `ignoreReduceMotion` is an opt-in Momentum-only exception, defaults false. Master animations toggle always wins; no system preference writes.
- `TilingManager.trackDrag()`: cancels before tracking user movement. Tick pauses writes while mouse held; ordinary click finishes on release.
- `TilingManager.perform()` / `sendToDesktop()`: cancel before Desktop commands; source gap closes immediately before synthetic drag. Tick also checks current Space for externally initiated switches.
- `WindowObserver.handle()`: ignores programmatic move/resize unless left mouse button held. Do not refresh on every animated AX update.
- `AXWindow.frameChanges()`: 1 write for pure moves/resizes, 2 for combined intermediate updates, no writes for duplicates. Final resize and unknown geometry use size → position → size repair. Manager caches only acknowledged requests; AX success doesn't guarantee exact geometry (native minimum size/edge clamping). Failed writes discard cache.
- CADisplayLink runs in main run-loop common modes; retained selector proxy weakly references manager. Completion/cancellation invalidates link; abandoned manager causes proxy to invalidate on next callback. AX remains synchronous, so slow apps can still miss refreshes. No compositor/private animation APIs added.
- Local scheduler probe: 60 callbacks/500 ms (~8.33 ms interval, 120 Hz); invalidation stopped callbacks. This verifies frame driver, not real-window rendering smoothness.
- `Config.animationsEnabled`: defaults true for old/partial JSON; settings toggle under Layout.

Verification: `MomentumTests/WindowAnimationTests.swift` (timing, easing, retarget velocity, clamping, target crossing, removal, cancellation); `MomentumTests/AXWindowFrameTests.swift` (write counts/repair); `MomentumTests/MomentumTests.swift:ConfigTests` (compatibility, toggle persistence, invalid type).
Manual checks still needed: rapid swaps; open/close and float windows; click/drag mid-transition; toggle animations and Reduce Motion; switch/send Desktops mid-transition; compare smoothness with multiple apps.

Updated: 2026-10-05
