# /debugging:debug Checklist

Copy into your project's working-notes location, or track inline. Tick as each phase completes.

## Phases

- [ ] Phase 1: Build the reproduction loop. One command, quick to run, that reports pass or fail for this bug
- [ ] Phase 2: Reproduce. Confirm the bug manifests deterministically or characterize non-determinism, then minimize the reproduction
- [ ] Phase 3: Hypothesize. List candidate root causes in priority order
- [ ] Phase 4: Instrument. Add logging / breakpoints; gather evidence per hypothesis
- [ ] Phase 5: Fix + regression test. Apply minimal fix; at a correct seam, add a test that would have caught the bug; with no correct seam, write no test and record the gap as the finding
- [ ] Phase 6: Cleanup + post-mortem. Remove instrumentation; search for siblings of the defect and fix or file each; record the root-cause pattern; propose an always-on signal when `always_on_signal` says to

## Skip criteria

- Phase 4 skipped if Phase 3 hypothesis is conclusively verified by Phase 2 repro alone
- Phase 6 cleanup is never skipped for tagged probes. A probe worth keeping as permanent observability loses its `[DEBUG-...]` tag and is reviewed as a production logging change, so the cleanup grep still returns nothing
