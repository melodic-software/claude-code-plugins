# batch-simplify Checklist

Copy into your project's working-notes location. Tick as each phase completes.

## Phases

- [ ] Phase 0 (repo mode only): Precondition — no tracked modifications in the sweep universe (working-notes location excluded); run state initialized
- [ ] Phase 1: Discover changed code files — `git diff` / `git log` against the scope, or `git ls-files` for repo mode; collect the candidate set
- [ ] Phase 2: Filter to code files — exclude lockfiles, docs, generated content, vendor, append-only records
- [ ] Phase 3: Verify existence — confirm each candidate still exists in the working tree
- [ ] Phase 4: Group files — by project/ecosystem, dependency-ordered
- [ ] Phase 4.5 (repo mode only): Confirmation gate. Inventory summary (surviving file count, groups, wave plan, scale estimate, exclusions by class) presented and confirmed, or an explicit-prose unattended authorization recorded for Phase 8
- [ ] Phase 5: Create tasks — one TaskCreate per group; track via TaskUpdate
- [ ] Phase 6: Run simplification waves — simplifier agent per group; capture findings + deferrals
- [ ] Phase 6.1 (repo mode only): Refutation verifier per group — fresh context, tries to refute "behavior preserved"; a confirmed refutation reverts that group's file list
- [ ] Phase 6.2 (repo mode only): Land the wave — per-group commits pushed to the run's single feature branch; base branch merged in at the wave boundary; the run's one PR opened after the first wave and updated thereafter
- [ ] Phase 6.5: Resolve deferred items in-run — fix-first resolution wave, each agent given the full file set its concern spans; edits land like the primary wave's (working-tree in diff modes, run-branch commits in repo mode); only Needs-human, Too-large, and wave-unfinished items survive to the report
- [ ] Phase 7: Final cross-ecosystem verification — build/test/lint across all touched ecosystems; unmapped groups reported as unmapped, not as passing
- [ ] Phase 8: Summary report — per-group outcomes + resolved and remaining deferrals

## Skip criteria

- Phases 0, 4.5, 6.1 and 6.2 SKIPPED outside repo mode
- Phase 6.5 SKIPPED when no deferred items surfaced
- Phase 5 task tracking SKIPPED for single-group changes (1 wave)

## Deferral posture

- Fix-first in every mode: deferrals are resolved in the same run by the Phase 6.5 resolution
  wave, whose edits land like the primary wave's (uncommitted working-tree changes in the
  diff-scoped modes, commits on the run's single branch in repo mode). No work items are filed
  by default
- Only Needs-human items, Too-large items, and deferrals the resolution wave could not finish
  remain after resolution; they go to the Phase 8 report (and, in repo mode, the run-state
  inventory) with their grounds, where the user decides
- Filing happens only on an explicit user request: one item per concern, not per site, with no
  numeric cap
