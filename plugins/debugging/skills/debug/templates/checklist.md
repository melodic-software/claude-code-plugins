# /debugging:debug Checklist

Copy into your project's working-notes location, or track inline. Tick as each phase completes.

## Phases

- [ ] Phase 1: Build a feedback loop — minimal repro command, fast iteration cycle, observable output
- [ ] Phase 2: Reproduce — confirm the bug manifests deterministically OR characterize non-determinism
- [ ] Phase 3: Hypothesise — list candidate root causes in priority order
- [ ] Phase 4: Instrument — add logging / breakpoints; gather evidence per hypothesis
- [ ] Phase 5: Fix + regression test — apply minimal fix; add test that would have caught the bug
- [ ] Phase 6: Cleanup + post-mortem — remove instrumentation; record the root-cause pattern

## Skip criteria

- Phase 4 SKIPPED if Phase 3 hypothesis is conclusively verified by Phase 2 repro alone
- Phase 6 instrumentation cleanup SKIPPED when the instrumentation is a desirable permanent observability addition
