# /debugging:debug Checklist

Copy into your project's working-notes location, or track inline. Tick as each phase completes.

## Phases

- [ ] Phase 1: Build a feedback loop. Minimal repro command, fast iteration cycle, observable output
- [ ] Phase 2: Reproduce. Confirm the bug manifests deterministically OR characterize non-determinism
- [ ] Phase 3: Hypothesise. List candidate root causes in priority order
- [ ] Phase 4: Instrument. Add logging / breakpoints; gather evidence per hypothesis
- [ ] Phase 5: Fix + regression test. Apply minimal fix; add test that would have caught the bug
- [ ] Phase 6: Cleanup + post-mortem. Remove instrumentation; record the root-cause pattern

## Skip criteria

- Phase 4 SKIPPED if Phase 3 hypothesis is conclusively verified by Phase 2 repro alone
- Phase 6 cleanup is never skipped for tagged probes. A probe worth keeping as permanent observability loses its `[DEBUG-...]` tag and is reviewed as a production logging change, so the cleanup grep still returns nothing
