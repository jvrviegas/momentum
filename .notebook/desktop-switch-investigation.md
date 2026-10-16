# Desktop switch / unwanted window restore investigation
> Reproduced: Dock termination restores minimized windows on this macOS build

Entry: `Momentum/TilingManager.swift:perform()` → `Momentum/SpaceMover.swift:switchTo()`
- Desktop hotkey posts system shortcut; unchanged current-Spaces set after 20 × 50 ms polls triggers `TilingManager.restartDockOnce()` → `SpaceMover.restartDock()` (SIGTERM), then shortcut retries.
- Restart allowed once per launch; wake or changed display IDs re-arm it. Introduced by c431bbc; display-change re-arm by f17f8df.
- `WindowObserver.start()` Space notification only schedules layout refresh. `AXWindow.focus()` is reached by directional focus commands, not normal Space refresh.
- `AXWindow.isStandard` rejects known minimized windows, but missing AX minimized value is accepted. `TilingManager.animateFrame()` does not recheck minimized state before frame writes.

Observed locally: installed Momentum 0.3.1 (build 5), running since 16:00:10 on 2026-10-07. Dock PID changed 26209 → 39213 at 23:11:22; Momentum logged Dock connection interruption. WindowServer destroyed unmanaged Spaces 394/393/392 during exit. Logs inspected do not identify the sender of Dock termination or prove a minimized window restored.

Controlled reproduction (user authorized): disposable AppKit regular-policy process creates one miniaturizable window; minimizes it; pumps events for 2 s, then another 2 s control; sends SIGTERM to Dock (same operation as `SpaceMover.restartDock()`); samples native `NSWindow.isMiniaturized` / `isVisible`. Two runs: minimized=yes / visible=no throughout control; after Dock termination minimized=no / visible=yes; Dock relaunched both times (39213 → 42377 → 42751). No desktop switching or focus commands sent. Fixture windows closed; temporary probe removed.

Conclusion: automatic Dock restart is sufficient to reproduce unwanted restore on this machine. Full original shortcut sequence was not replayed; logs do not identify the sender of the earlier 23:11:22 termination. Minimized windows are excluded from layout, but Dock termination restores them, making them eligible for normal tiling again.

Fix implemented: `SpaceMover.switchTo()` sends at most three shortcuts, polling each for 20 × 50 ms. Returns completed / unchecked / shortcutUnavailable / timedOut / cancelled; no Dock-restart dependency. Unknown membership and already-visible target send once; any display changing stops retries. `TilingManager.perform()` cancels superseded switches; timeout exposes recovery, disabled shortcuts expose settings guidance only. Removed wake/display restart re-arming. `MenuBarContent` recovery action requires a destructive confirmation warning about minimized-window restoration; `TilingManager.recoverDesktopSwitching()` guards recovery availability, cancels retries, restarts only on explicit request, and never automatically switches afterward.

Verification: regression against old implementation failed (1 restart, 7 sends vs expected 0 / 3). Revised suite: 102 tests passed, including retries, timeout, cancellation, multi-display change, unavailable shortcut, and guarded recovery. Native standalone probe compiled actual `Momentum/SpaceMover.swift` with unused dependency stubs, injected shortcut sender / Space snapshot but real 50 ms waits: timedOut after three sends; own minimized window stayed minimized; Dock PID unchanged. Fixture closed and temporary probe removed. Confirmation UI not manually exercised; installed running Momentum remains old 0.3.1 until rebuilt app is installed/relaunched.

## Inline recovery confirmation (2026-10-16)

User reports the SwiftUI alert in the `.window` MenuBarExtra closes the popover on either button click and remains pending when reopened; recovery is therefore never invoked. `Momentum/MenuBarContent.swift:dockRestartConfirmation` now renders the warning and Cancel / Restart buttons inline instead of presenting a modal. Confirmation clears on disappearance, error dismissal, loss of recovery eligibility, and either button. The existing explicit recovery guard remains unchanged. Build and all 187 tests pass; no UI automation seam exists for popover click routing. A signed Release build was installed and relaunched, and the user confirmed the recovery UI works. Installation did not restart Dock.

Updated: 2026-10-16
