# Replace Implementation

Replace mode covers a rewrite, a port to another language, a framework or library migration, or a
service replacement: a second implementation that takes over from the first and must behave the same
except for differences someone named and approved. It differs from refactor mode in where the oracle
comes from. A refactor changes structure in place with the existing tests as its net. A replace
builds new code beside old, and the old implementation, or its recorded output, is the oracle.

**What this rests on.** The steps below follow human-led practice: GitHub's Scientist experiments,
shadow traffic, and characterization and approval testing. No accepted source shows an agent
validating a rewrite this way, so the guidance is extrapolated, not measured on agents. A recorded
baseline proves the new code matches the old, never that either is correct.

## Sequence

1. **Keep the old implementation runnable.** Side by side in-process, as a pinned build or container,
   or, when it cannot run after the change, as a recorded corpus of its outputs captured now. Do not
   delete it until step 8
2. **Build the differential harness before the new code.** Feed the same inputs to old and new and
   diff the outputs. The base is a recorded corpus: real inputs from logs, fixtures, and existing
   tests, persisted so a run can be reproduced. Random or property-generated inputs are an optional
   add-on and lower-evidence; the claim that they find bugs a recorded corpus misses is not
   established here. A failure report names the input that diverged. Author the harness through
   `/testing:write` (when the `testing` plugin is installed)
3. **Normalize nondeterminism before comparing.** Fix the clock, seed randomness, sort what has no
   meaningful order, and scrub volatile fields (Jest property matchers and a mocked clock, Verify
   scrubbers, or the stack's equivalent). Where a field cannot be normalized, compare old against
   old first to see its noise. The evidence for this step is MEDIUM: two tools document it, the
   third source only offers a compare hook
4. **Keep an intentional-differences ledger** beside the plan (`<memory_dir>/<slug>/DIFFERENCES.md`).
   Each entry has an id, a predicate (which inputs or fields), the reason, and the user's sign-off.
   An ignore rule in the harness cites its ledger id. The comparator stays strict everywhere else;
   never widen it to make a run green, and never add an entry for a difference your own change
   caused without the user's sign-off
5. **Build the new implementation under the normal cadence**, slice by slice ([feature.md](feature.md)
   for the TDD cadence of new behavior), running the harness after each block
6. **Report counts, not "tests pass".** Inputs run, mismatches, mismatches covered by a ledger id
   (listed by id), unexplained. An unexplained mismatch means the slice is not done
7. **Ramp or cut over.** A Scientist-style experiment (the old result is returned, the new one is
   compared and mismatches are published) or shadow traffic runs only on read-only paths; anything
   that writes needs an isolated sink, since the shadow's side effects still happen. Shadow traffic
   also needs a separate comparator. Starting an experiment, mirroring traffic, or cutting over
   touches production: ask first, and in an unattended run stop at a green harness and hand off
8. **Delete the old implementation** once cutover holds. Then delete the harness or convert its pins
   into behavior tests per [refactor.md](refactor.md), "Characterization tests", step 6

## Handoff to verification

`/verification:confirm` judges a replace as a high-risk refactor and needs differential evidence, not
a green suite. Hand it the step 6 counts, the ledger with each entry's sign-off, the corpus location,
and the harness command so it can re-run the comparison.

## Checkpoints

- Harness and recorded corpus committed and green against the recorded baseline before any new code (old vs old where a field cannot be normalized)
- Each slice of the new implementation committed with zero unexplained mismatches
- Ledger entries signed off before the slice they excuse is committed
- Old implementation deleted in its own commit, after cutover

## Common pitfalls

- **Treating sameness as correctness**: a mismatch-free run can carry the old bug forward. A bug found
  in the old output becomes a ledger entry (the new code fixes it, with sign-off) or a follow-up, never
  a silent match
- **Widening the comparator**: ignoring a whole field or response to quiet one difference hides every
  other difference in it
- **Deleting the old code early**: once it is gone, the oracle is gone with it
- **Experimenting on writes**: a candidate path with side effects runs twice in production

- **Pointer**: [Scientist README](https://github.com/github/scientist) (control and candidate,
  compare, ignore, the side-effect warning); [Jest snapshot testing](https://jestjs.io/docs/snapshot-testing)
  (property matchers, deterministic tests); [Verify scrubbers](https://github.com/VerifyTests/Verify/blob/main/docs/scrubbers.md);
  [Istio traffic mirroring](https://istio.io/latest/docs/tasks/traffic-management/mirroring/)
  (mirrored responses are discarded, comparison is separate)
- **As of**: 2026-10-06
- **Recheck trigger**: a page above changes its comparison, ignore, or scrubbing mechanism, or a
  study shows agents validating rewrites by differential comparison (then restate the basis
  paragraph)
