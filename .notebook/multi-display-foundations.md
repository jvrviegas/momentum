# Multi-display integration
> Native implementation on worktree; full review/product acceptance pending

Entry: `Momentum/TilingManager.swift:start/refresh/perform`
Flow: `Spaces.displayInventory` → `DisplayTopology` owner/key → `DisplayLayoutState.reconcile` → per-display animation/runtime links.

- `TilingEnvironment.swift`: injected window/clock/driver/native boundary. Injected start never attaches real AX observers or prompts; production start still waits for AX. Native CAD smoke uses only virtual-window writes.
- `Spaces.swift:inventory`: strict per-display IDs; shared snapshots normalize only when consistent/unambiguous. Shared live tests owner-skipped. Conflicting Current Space type fails closed.
- `DisplayMover.swift:move`: source Space request only if needed, bounded 5-consecutive-sample AX/CG/membership settling; destination changes/closure/refusal/cancellation fail safely.
- `TilingManager.swift:sendToDisplay/transfer/drop`: enabled unbound actions, no-op checked before refresh; focus only after successful keyboard transfer. Drag transfers insert without focus-stealing; same-layout swap/resize behavior retained.
- `TilingManager.swift:apply/animateFrame`: independent links/caches; native ticks validate Space/bounds. No programmatic frame writes while left button held; pointer-release refresh is cancelled when tiling stops.
- `AXWindow.swift:serverFrame`: independent CG bounds. T1 gotcha: immediate AX request can precede WindowServer placement; never assume one AX read proves stable native transfer.
- Evidence: `docs/qa/multi-display-tiling-validation.md`; 179 tests incl safe native-driver smoke. Installed app unchanged. T14 pending, full SIP unverified, shared live tests skipped, mirror/mixed-rate product QA pending.
- Worktree: `../.worktrees/multi-display-tiling`, uncommitted `feat/multi-display-tiling`. Native review/16 owned-window coordinator checks recorded 2026-10-12; production observer/mouse/UI/physical QA still pending. Foundation/O1 report remains historical.

Updated: 2026-10-12
