# Code review fixes

Tracks the fixes from the code and architecture review of 2026-10-03.

Status:
- `[x]` fixed and verified (test, build or runtime check)
- `[~]` fixed in code and builds, but not yet checked in the running app (see [Manual checks](#manual-checks))
- `[!]` code fixed, but **needs you** before it takes effect
- `[-]` won't fix (reason given)

Decisions taken with the reviewer:
- Default hotkeys stay on ⌥; Settings gets a note about non-US layouts.
- Shortcuts stay bound to physical key positions; Settings shows the key as printed on the current layout.
- Minimum macOS stays at 27.
- While tiling is disabled, only the Switch/Send to Desktop hotkeys work.

Last full check: clean `xcodebuild test` (Swift 6, no warnings): 17/17 tests pass.

## Release and build

- [!] **1. Release 1.0 is rejected by Gatekeeper.** Signed with "Apple Development", not Developer ID, and not notarized. Also `--publish` tagged whatever is on GitHub's default branch, not the code that was built.
  - Fix (`scripts/release.sh`): exports the archive with Developer ID, checks the signature, notarizes and staples the DMG, verifies it with `spctl`, and only then generates the appcast (stapling changes the DMG's bytes). `--publish` now requires a clean git checkout whose HEAD is pushed, and tags that exact commit. Prerequisites are checked before the slow steps.
  - Verified: `shellcheck` clean (one note on an unchanged line); export options plist lints; the script stops at the certificate check on this Mac. Export, notarization and publishing were **not** run.
  - **Needs you:**
    1. Create a "Developer ID Application" certificate (Xcode › Settings › Accounts › Manage Certificates). Only "Apple Development" is in the keychain today.
    2. Store notary credentials: `xcrun notarytool store-credentials momentum-notary --apple-id <apple-id> --team-id KL88H3WKQ9`.
    3. Put the project under git and push it to `jvrviegas/momentum`. Initialize the repo in the project root (`~/Projects/Personal/macos/Momentum`, which contains `Momentum.xcodeproj`; the extra nested folder was removed on 2026-10-03). The GitHub repo exists but is empty (checked 2026-10-03).
    4. Run `scripts/release.sh --publish`. The broken 1.0 DMG was never published (the GitHub repo has no commits, so no releases), so this release can stay 1.0; bump the version for every release after it.
- [x] **2. A clean test build fails.** The test target has no dependency on the app target.
  - Fix: added the app as a target dependency of the test target (`project.pbxproj`).
  - Verified: `xcodebuild test` from an empty DerivedData folder builds and passes.

## Behaviour bugs

- [~] **3. Hotkeys ignore "Tiling Enabled".** Move and send-to-desktop applied the old layout while tiling was off.
  - Fix (`TilingManager.perform`): with tiling off, only Switch/Send to Desktop run; send no longer re-tiles the old Desktop. No hotkey runs while a window is being carried to another Desktop (see 8).
- [~] **4. Resizing can swap two windows.** Dragging the shared edge into the neighbour's tile swapped them on release.
  - Fix: `WindowObserver` reports whether each drag step is a resize; `TilingManager` remembers any resize during the drag (resizing from the left/top edge also moves) and only swaps after a pure move.
  - Verified: the drop decision (`BSPTree.window(at:excluding:in:gap:)`) is unit-tested; the move/resize distinction needs a manual check.

## Robustness

- [~] **5. Accessibility calls can freeze the app.** No messaging timeout (default ~6 s), and every window was re-registered for close notifications on every refresh.
  - Fix: 1 s global AX timeout set at startup (`TilingManager.start`); `WindowObserver.allWindows()` only registers windows it didn't see last time.
  - Known side effect: if an app stops answering for over 1 s, its windows drop out of the layout until it answers again (before, Momentum froze instead).
- [~] **6. Slow-launching apps lose notifications.** Registration results were ignored and only tried once, 500 ms after launch.
  - Fix (`WindowObserver.observe` / `retryObserving`): a busy app (`cannotComplete`) is retried every 500 ms for 5 s, both at launch and for apps already running at startup. Stops at the first timeout instead of waiting on each notification. The app is tracked either way, so its windows are still tiled if it never answers.
- [~] **7. Config live reload can stop permanently.** Also: error messages named `config.json` instead of `tiling.json`, and gap/padding weren't validated.
  - Fix (`ConfigStore`): while the file is missing, the folder is watched and the file is reloaded and watched again once it reappears. Error messages use the real file name. Gap and padding must be 0–100: out-of-range values in the file are rejected like an invalid hotkey (previous config stays), and Settings clamps typed values.
  - Verified: validation is unit-tested. The watcher fallback needs a manual check (testing it automatically would touch your real config file).
- [~] **8. Send-to-desktop can click blindly.** The fallback grab point was used even when no title bar was found; a second move could start during the first.
  - Fix: `AXWindow.titleBarGrabPoint` returns nil when no safe spot is found, so the move is skipped and the window snaps back. `TilingManager.perform` ignores hotkeys while a move is in progress.
  - Verified: the same hit-test found a safe spot on the one window open in this Desktop (Zen). Behaviour change: for an app with no detectable title bar, Send to Desktop now does nothing instead of risking a click.
- [~] **9. Hidden apps (⌘H) probably leave empty tiles.** Their windows weren't excluded.
  - Fix: `AXWindow.isStandard` excludes windows of hidden apps (cheap local check, done before any AX call).
  - Not verified: no app was hidden during the review, and hiding one of yours to test wasn't appropriate.

## Smaller items

- [~] **S1. ⌥ defaults on non-US layouts.** Kept ⌥ (decision); the Hotkeys footer in Settings explains it and suggests rebinding.
- [x] **S2. Key labels on non-US layouts.** `KeyCombo.displayString` shows what the key types on the current layout; keys that don't type a visible character keep their names. The config file still uses US-position names (noted in Settings).
  - Verified: ran the same translation against this Mac's layouts. The US "y" key shows Z on German and the "q" key shows A on French; space, arrows, return and F-keys keep their names.
- [x] **S3. Hotkey failures are silent.** `HotKeyManager.register` registers in a fixed order and returns the actions it couldn't register (bound twice, or refused by macOS); Settings shows a warning icon next to them.
  - Verified: unit test (a combo bound to two actions fails for the later one).
- [x] **S4. Uneven gaps.** Splits are rounded down to a whole point and the second child takes the remainder, so the gap stays exact.
  - Verified: unit test (1001 pt wide, 8 pt gap → 496 + 8 + 497).
- [x] **S5. Private calls declared with `@_silgen_name`.** Move them to a bridging header.
  - Fix: `Momentum/Momentum-Bridging-Header.h` declares the five private functions in C; removed the `@_silgen_name` declarations from `Spaces.swift` and `AXWindow.swift`.
  - Verified: app builds; a small program compiled against the same header returned the real Space IDs, a window's Space and its CGWindowID.
- [x] **S6. State that never shrinks.** `TilingManager.pruneState` drops windows from other Desktops' trees once they're closed or moved off that Desktop, removes empty trees, and forgets closed floating windows.
  - Verified: checked at runtime that a minimized window still reports its Desktop (so it isn't pruned) and a closed window reports none.
- [-] **S7. Minimum macOS 27.** Kept at 27 by decision (macOS 14 was checked and builds).
- [x] **S8. Template leftovers.** iOS Info.plist keys, `MyApp`/`MyAppTests` names, Swift 5 mode.
  - Fix: scheme `MyApp` → `Momentum` (also in `scripts/release.sh`); test target, folder and file `MyAppTests` → `MomentumTests`; removed iOS `INFOPLIST_KEY_UI*` keys and the test target's iOS/visionOS deployment targets; Swift 6 language mode for both targets (fixed the two resulting errors in `Permissions.swift` and `WindowObserver.swift`). Project-level per-platform deployment targets are Xcode defaults and were left alone.
  - Verified: clean build with Swift 6, tests pass.
- [~] **S9. macOS's own edge tiling competes with Momentum.** The Layout footer in Settings says to turn off "Drag windows to screen edges to tile".

## Architecture

- [x] **A1. Untested core logic in `TilingManager`.** The refresh reconcile step is now `BSPTree.sync(with:focused:bounds:)` and the drop target is `BSPTree.window(at:excluding:in:gap:)`; both are unit-tested.
- [x] **A2. `SpaceMover` assumes ⌃1–⌃9.** `SpaceMover.desktopShortcut` reads the user's "Switch to Desktop N" shortcuts from `com.apple.symbolichotkeys`, skips ones that are turned off, and falls back to ⌃N when there's no entry.
  - Verified: unit tests parse the real plist format (custom shortcut, disabled shortcut, missing entry). On this Mac, Desktop 9 is turned off, so Send/Switch to Desktop 9 now does nothing instead of sending ⌃9.
- [~] **A3. Main display only.** The Layout footer in Settings says so.

## Manual checks

Build and run the app from Xcode, then:

- [ ] **3:** Turn off "Tiling Enabled". ⌥⇧H/J/K/L doesn't move windows; ⌥2 still switches Desktop; ⌥⇧2 still sends the window without re-tiling.
- [ ] **4:** Drag the shared edge between two tiled windows well into the neighbour and release: the windows snap back, no swap. Drag a window by its title bar onto another: they swap.
- [ ] **5/6:** Launch a slow app (e.g. Xcode) while Momentum runs: its first window tiles, and dragging it snaps back.
- [ ] **7:** Delete `~/.config/momentum/tiling.json`, wait a few seconds, then restore it with a different `gap`: the layout updates. Put `"gap": -5` in the file: Settings shows an error and the layout keeps the old gap.
- [ ] **8:** Send a Finder, Safari and a browser window to another Desktop: each moves, and nothing in the title bar gets clicked.
- [ ] **9:** Hide an app with ⌘H: the other windows fill its space. Show it again: it tiles back in.
- [ ] **S1/S9/A3:** Read the Layout and Hotkeys footers in Settings.
- [ ] **S3:** Bind two actions to the same shortcut: the later one shows a warning icon.
