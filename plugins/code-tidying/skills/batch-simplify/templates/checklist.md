# batch-simplify Checklist

Copy into your project's working-notes location. Tick as each phase completes.

## Phases

- [ ] Phase 0 (repo mode only): Precondition — no tracked modifications in the sweep universe (working-notes location excluded); run state initialized
- [ ] Phase 1: Discover changed code files — `git diff` / `git log` against the scope, or `git ls-files` for repo mode; collect the candidate set
- [ ] Phase 1.5 (repo mode only): Confirmation gate — inventory summary (file count, groups, wave plan, scale estimate, exclusions by class) presented and confirmed, or an explicit-prose unattended authorization recorded for Phase 8
- [ ] Phase 2: Filter to code files — exclude lockfiles, docs, generated content, vendor, append-only records
- [ ] Phase 3: Verify existence — confirm each candidate still exists in the working tree
- [ ] Phase 4: Group files — by project/ecosystem, dependency-ordered
- [ ] Phase 5: Create tasks — one TaskCreate per group; track via TaskUpdate
- [ ] Phase 6: Run simplification waves — simplifier agent per group; capture findings + deferrals
- [ ] Phase 6.1 (repo mode only): Refutation verifier per group — fresh context, tries to refute "behavior preserved"; a confirmed refutation reverts that group's file list
- [ ] Phase 6.2 (repo mode only): Deliver the wave — one independently mergeable PR, merged before the next wave opens
- [ ] Phase 6.5: Capture deferred items as work items — file findings out of scope this run
- [ ] Phase 7: Final cross-ecosystem verification — build/test/lint across all touched ecosystems; unmapped groups reported as unmapped, not as passing
- [ ] Phase 8: Summary report — per-group outcomes + deferred-item links

## Skip criteria

- Phases 0, 1.5, 6.1 and 6.2 SKIPPED outside repo mode
- Phase 6.5 SKIPPED when no deferred items surfaced (no out-of-scope findings)
- Phase 5 task tracking SKIPPED for single-group changes (1 wave)

## Filing tier

- Diff-scoped modes (time window, branch): file High + Medium by default; ask for Low and
  do-not-file items
- Repo mode: file High only — a deliberate narrowing, since Medium-priority filing at repo scale
  produces a tracker backlog nobody triages. All tiers still persist to the run-state inventory,
  with no numeric cap on what may be filed
