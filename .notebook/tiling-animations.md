# Tiling animations
> Accessibility frame interpolation, not compositor animation

Entry: `Momentum/TilingManager.swift:apply()`
Flow: BSP target frames → `Momentum/WindowAnimation.swift:retarget()` → shared async tick → `Momentum/AXWindow.swift:setFrame()`

- `WindowAnimation`: pure state, 200 ms cubic ease-out; monotonic uptime supplied by manager; same target preserves deadline; new target starts at actual AX frame.
- `TilingManager.shouldAnimate`: config toggle + live NSWorkspace Reduce Motion check.
- `TilingManager.trackDrag()`: cancels before tracking user movement. Tick pauses writes while mouse held; ordinary click finishes on release.
- `TilingManager.perform()` / `sendToDesktop()`: cancel before Desktop commands; source gap closes immediately before synthetic drag. Tick also checks current Space for externally initiated switches.
- `WindowObserver.handle()`: ignores programmatic move/resize unless left mouse button held. Do not refresh on every animated AX update.
- `AXWindow.setFrame()`: size → position → size; AX calls synchronous, app-dependent latency/minimum sizes remain constraints. No compositor/private animation APIs added.
- `Config.animationsEnabled`: defaults true for old/partial JSON; settings toggle under Layout.

Verification: `MomentumTests/WindowAnimationTests.swift` (timing, easing, retarget, removal, cancellation); `MomentumTests/MomentumTests.swift:ConfigTests` (compatibility, toggle persistence, invalid type).
Manual checks still needed: rapid swaps; open/close and float windows; click/drag mid-transition; toggle animations and Reduce Motion; switch/send Desktops mid-transition; compare smoothness with multiple apps.

Updated: 2026-10-04
