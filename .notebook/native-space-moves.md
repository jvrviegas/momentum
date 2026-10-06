# Native Space moves
> Direct window transfer; no synthetic drag

Entry: `Momentum/TilingManager.swift:sendToDesktop()`
Flow: `Spaces.desktopSpace()` → `SpaceMover.move()` → `NativeSpaceMove.m:MomentumRequestNativeSpaceMove()` → membership polling → source tree update + refresh.
- Send stays on source Desktop; destination reconciles when visible. Switch still uses symbolic system shortcuts.
- Desktop N is Mission Control order of normal Spaces on main display, not Space ID N; shared-Spaces fallback matches current Space.
- Private operation function is local, not exported: dlsym alone fails. `NativeSpaceMove.m:FindSkyLightSymbol()` resolves exact Mach-O symbol; missing symbol/class/selector fails safely, no drag fallback.
- Request return is not completion. `SpaceMover.move(windowID:toSpace:request:membership:wait:)` verifies membership for up to ~2 s; same-Space no-op, closure/timeout/cancellation tested in `MomentumTests/NativeSpaceMoveTests.swift`.
- Errors: beep + menu/Settings message; layout isn't removed optimistically.

Verification: `bash scripts/native-space-smoke.sh` — separate disposable process/window; 10 round trips; asserts membership, unchanged visible Spaces and cursor. Needs GUI session + 2 existing Desktops. Don't interact during cursor/Space assertions.
- 2026-10-06: macOS 27.0.1 (26A434), arm64; production bridge 20/20 moves; 55 unit tests pass.
- Host SIP already partially disabled (`csrutil status`: custom configuration); no changes made. Full-SIP compatibility NOT verified here.
- Source reference: https://github.com/asmvik/yabai/blob/master/src/space_manager.c and src/misc/macho_dlsym.h; supported macOS API this is NOT.

Updated: 2026-10-06
