# Multi-display tiling — foundation implementation review

**Date:** 2026-10-08
**Worktree:** `../.worktrees/multi-display-tiling`
**Branch/base:** `feat/multi-display-tiling`, `58d1b9fad43bddb48c7a3105cf54668b5f2dcecd` plus uncommitted changes
**Swift source snapshot SHA256:** `94153c961d810909b4e5a6320e589916810479f0df6d0297b9194f4ef8c6f1fe` (manifest at `/tmp/momentum-multi-display-baseline.h3VJeg/review-source-manifest.json`)
**Linear state:** N/A
**PR:** None

## ✅ Result: Approved — foundation scope only

T2/T3/T4/T8 meet the approved foundation-first boundary with co-located tests and explicitly inert pending actions. No blocking defect found in that scope. This is **not** approval of multi-display tiling, native integration or release readiness.

**Review method:** fresh requirements-led inspection and adversarial checks by the same agent that implemented the foundations; no separate reviewer/model was available. Criteria below were re-derived from the written plan rather than the implementer's summary. Do not describe this as independently authored external sign-off.

## Acceptance criteria

The criteria below are copied from the approved plan's foundation tasks, omitting checkbox notation. The native MD-01–MD-16 contract is intentionally not claimed complete.

| # | Criterion | Status | Evidence |
|---|---|---|---|
| T2.1 | Implement pure normalized snapshot/geometry/ownership/order rules using synthetic inputs and public-coordinate contracts, without live private readers. List unverified mapping assumptions for T1; do not hard-code a speculative shared-Spaces schema. | ✅ Met | `Momentum/DisplayTopology.swift:5–106`; pure constructor and geometry only. Shared mapping remains explicit normalized input; QA/spec list unverified private mapping. No native caller wiring. |
| T2.2 | Unit fixtures cover negative origins, above/below/left/right layouts, unequal scale/size, usable insets, tiny bounds, center ties, gaps, empty inventories and unknown/fullscreen mapping. | ✅ Met at pure-input level | `MomentumTests/DisplayTopologyTests.swift:12–110`; 10 tests. Logical geometry excludes backing-scale conversion; actual mixed-scale/refresh behavior remains deferred. |
| T2.3 | Mixed backing scale does not alter point geometry; mirrored logical displays are not duplicated. | ✅ Met at normalized-input level | `DisplayTopology.swift:43–60`; point conversion has no backing-scale multiplication, exact duplicate frames are deduplicated. `DisplayTopologyTests.swift:23,90`. Actual mirrored logical-screen inventory remains T1 work. |
| T3.1 | Add fixture-tested active Space/type and Desktop ordinal parsing with explicit display identity. Do not switch production native readers/callers to the new resolver before T1; retain existing system-shortcut switching behavior. | ✅ Met | `Momentum/Spaces.swift:57–107`; existing primary-display native methods and SpaceMover callers unchanged. `NativeSpaceMoveTests.swift:40–72`. |
| T3.2 | Unit fixtures cover two display records, shared Spaces, missing record/UUID, malformed data, fullscreen exclusion, invalid ordinals and unrelated Space IDs. | ✅ Met at fixture level | `NativeSpaceMoveTests.swift:40–106`; strict parser rejects ambiguous identifiers/duplicate IDs, bool/fractional/string IDs and malformed list rows. Shared Spaces are supplied as explicitly normalized input, not a guessed live schema. See optional O1 for inconsistent-current-record hardening. |
| T3.3 | Missing secondary mapping never silently resolves a primary-display target. | ✅ Met | `Spaces.swift:68–71` requires exactly one matching display; `NativeSpaceMoveTests.swift:49`. Legacy main-display fallback remains deliberately unchanged and is not used by the new resolver. |
| T4.1 | Implement keyed tree/focus state and reconciliation without AX calls. | ✅ Met | `Momentum/DisplayLayoutState.swift:3–89`; explicit display/Space key, per-key focus, no native/AX dependencies. |
| T4.2 | Unit tests prove shared Space IDs do not merge displays, changing one key preserves the other's tree, inactive Desktop retention, one-owner transfer removal/insertion and disconnected-key cleanup without move-back intent. | ✅ Met | `DisplayLayoutStateTests.swift:15–99`; unknown membership retains inactive state, known closure/wrong Space or confirmed visible owner prunes it; duplicate visible IDs receive one owner. |
| T8.1 | Add previous/next-display actions, titles and JSON identifiers (`send-to-previous-display`, `send-to-next-display`); include in `allCases`, no assigned default shortcuts. If exhaustiveness requires a dispatcher case, make it an explicitly temporary inert scaffold until T10, with a test; no native move or completed-feature claim. | ✅ Met | `Momentum/Config.swift:13–24,40–61`; `TilingManager.swift:279,306–307`. Actions appended, unbound, titled “not available yet,” gated before native trust/state checks. `MomentumTests.swift:16–49`; `AppControllerTests.swift:155`. |
| T8.2 | Tests cover raw-value/title discovery, old config loading, JSON binding/null roundtrip, registration order/collision behavior and forwarding to tiling rather than Keep Awake. | ✅ Met | `MomentumTests.swift:16–58`; `AppControllerTests.swift:136–168`; existing Carbon collision test retained. Existing Keep Awake order assertion now checks the old-action prefix (`ConfigStoreTests.swift:42–43`); no baseline test deleted. |
| Boundary | No live feasibility probes/native integration before owner authorization; full manual acceptance remains at the end. | ✅ Met | No new native topology readers, moves or display links; only TilingManager pending-command guard/scaffold changed. README checklist remains unchecked. New foundation-stage MDF living rules do not assert delivery of MD rules. |

## Blockers

None found in T2/T3/T4/T8.

**Outstanding gate, not a foundation defect:** T1 remains deferred by the owner. Do not begin T5/native-dependent integration or treat this review as authorization to move real windows. Full M1–M12 manual acceptance and full-feature review remain pending.

## Optional recommendation

### O1 — Define inconsistent-current-Space handling before native wiring

**Status:** Nonblocking, deferred to T1/T3 follow-up as evidence warrants.

`Spaces.displaySnapshot(for:in:)` derives active kind from the matching `Spaces` list row and ignores a `type` supplied in `Current Space` (`Momentum/Spaces.swift:86–90`). A temporary fixture with current record `{id64: 91, type: 4}` and list row `{id64: 91, type: 0}` therefore produces `.normal` active kind. This was reproduced without calling private APIs.

No live consumer is wired and the native snapshot consistency contract is deliberately unproven, so this is not a current user-visible bug or a blocker for the approved synthetic foundation scope. During T1, establish which record is authoritative and how snapshots behave around transitions. Before wiring eligibility to it, preferably fail closed on conflicting known kinds and retain an adversarial regression fixture, rather than risk treating an uncertain fullscreen destination as normal.

## Validation performed

| Check | Result |
|---|---|
| Fresh full suite | ✅ 133 tests / 14 suites passed, both initial review rerun and final rerun |
| Focused foundation-related suites | ✅ 57 tests / 5 suites passed: topology, layout state, native Space parser, config, controller |
| Temporary adversarial checks | ✅ 4 isolated checks passed after correcting one disproven reviewer hypothesis; temporary test file removed |
| Existing baseline coverage | ✅ 102 baseline tests retained; 31 added foundation tests |
| Tracked diff whitespace | ✅ `git diff --check` |
| New-file whitespace | ✅ Checked separately, since untracked additions are not covered by `git diff --check` |
| Swift compiler diagnostics | ✅ No Swift compiler warnings/errors in final passing review gates; only existing AppIntents metadata extraction tooling warning during rebuild |
| Formatter/linter | N/A — none configured; matched existing Swift/MainActor test style |
| Live native feasibility / manual acceptance | Not run, explicitly deferred; no real-window probes or screen changes |
| Production code changes during review | None |

### Local evidence

Directory: `/tmp/momentum-multi-display-baseline.h3VJeg`.

- `Review.xcresult`, `review.log`: initial 133-test review rerun.
- `ReviewFocused.xcresult`, `review-focused.log`: 57 focused tests.
- `ReviewFinal.xcresult`, `review-final.log`: final 133-test rerun after temporary probe cleanup.
- `FoundationReviewProbes.swift`, `ReviewProbes-corrected.xcresult`, `review-probes-corrected.log`: four disposable probe definitions/results, retained outside the repository.
- `ReviewProbes.xcresult`: initial probe run had one failed **reviewer hypothesis**, not an implementation regression. The hypothesis that a signed CGRect would yield a negative BSP output was disproven: existing BSP `.integral` standardizes the rectangle. The corrected probe confirms the actual positive output; no signed-bounds finding is raised.

Other disposable checks confirmed inactive unknown-membership retention/explicit closure pruning, a nonzero pure primary-reference origin, and the optional current-record/list inconsistency above. They were observational checks, not added permanent acceptance coverage or native evidence.

## Verdict

- **Result:** ✅ Approved for the staged foundation scope only.
- **Blockers remaining in reviewed scope:** 0.
- **Optional recommendations:** 1.
- **Recommendation:** Keep the pending action gate/titles intact and stop at T1 until explicit live-probe authorization. Full multi-display functionality is not ready to merge as a completed feature or release.

## O1 follow-up — 2026-10-08

João authorized implementing the optional recommendation. Original review above remains a record of its prior uncommitted snapshot.

**Updated source snapshot SHA256:** `31e778b074ffc85b9376ce500d978dc5ebf9cb7532d5512bf6a2bb15dfd86857` (manifest `/tmp/momentum-multi-display-baseline.h3VJeg/o1-source-manifest.json`).

- **O1 status:** ✅ Resolved at the fixture-contract level; no optional recommendations remain open in the reviewed foundation scope.
- `Spaces.displaySnapshot` now preserves raw validated list types and only maps active Space when an optionally supplied current type matches exactly. Invalid/mismatching supplied types leave activeSpace nil, so topology eligibility fails closed. Missing type still uses list classification; parsed Desktop order is preserved. A shared type-number validator rejects bools, strings, fractions and overflowing integer values.
- Four permanent regression tests cover normal/fullscreen/unknown conflicts, matching classifications, malformed types and absent-type compatibility, including topology ineligibility for conflicts. The focused red run reproduced the pre-fix behavior; green runs passed **21 focused tests / 1 suite** and **137 full tests / 14 suites**.
- Evidence: `O1-red.xcresult`, `O1-focused.xcresult`, `O1-full.xcresult` and corresponding logs under the results directory.
- No live reader/caller changes, native tests, commits or pushes. Native schema/transition behavior remains T1 work; strict fixture hardening does not establish macOS compatibility.
- **Scoped verdict remains Approved:** zero foundation blockers and zero outstanding optional findings; full-feature/native acceptance remains pending.
