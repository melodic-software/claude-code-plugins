# batch-simplify Checklist

Copy into your project's working-notes location. Tick as each phase completes.

## Phases

- [ ] Phase 1: Discover changed code files — `git diff` / `git log` against the scope; collect the candidate set
- [ ] Phase 2: Filter to code files — exclude lockfiles, docs, generated content, vendor, append-only records
- [ ] Phase 3: Verify existence — confirm each candidate still exists in the working tree
- [ ] Phase 4: Group files — by project/ecosystem, dependency-ordered
- [ ] Phase 5: Create tasks — one TaskCreate per group; track via TaskUpdate
- [ ] Phase 6: Run simplification waves — simplifier agent per group; capture findings + deferrals
- [ ] Phase 6.5: Capture deferred items as work items — file findings out of scope this run
- [ ] Phase 7: Final cross-ecosystem verification — build/test/lint across all touched ecosystems
- [ ] Phase 8: Summary report — per-group outcomes + deferred-item links

## Skip criteria

- Phase 6.5 SKIPPED when no deferred items surfaced (no out-of-scope findings)
- Phase 5 task tracking SKIPPED for single-group changes (1 wave)
