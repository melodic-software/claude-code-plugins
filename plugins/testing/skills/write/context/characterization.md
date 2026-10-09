# Write Characterization, Approval and Differential Tests

Use this route when the task changes code whose current behavior must be kept: a replace, rewrite,
migrate or port, or a refactor of legacy code with thin tests. The old implementation, or its
recorded output, is the oracle for the new one.

These tests are **pins, not correctness claims**. A recorded baseline asserts that the output is
the same as before, so a bug in the old code is pinned along with everything else. Name them as
pins (in the test name or a one-line comment) so nobody later reads them as a specification, and
follow `testing:test-value` for where a pin's expected value may come from.

## Three shapes

| Shape | What it compares | Fits |
|---|---|---|
| Characterization | Current output, captured into an ordinary assertion | Legacy code before a refactor; a handful of behaviors |
| Approval / snapshot (golden master) | Current output, recorded to a file and reviewed on change | Large or structured outputs: reports, rendered documents, serialized objects |
| Differential | Old and new implementations, run on the same inputs | A replace or migrate where both can still run |

## Characterization recipe

Feathers' recipe, per behavior you are about to touch:

1. Call the code with a real input and assert a value you know is wrong.
2. Run it. The failure message shows the actual value.
3. Put the actual value in the assertion. The test now documents what the code does.
4. **Sabotage check**: temporarily break the code under test (flip a condition, change a constant)
   and confirm each pin fails, then restore it. A pin that survives sabotage pins nothing.
5. Commit the pins on their own, before the change, so the history shows the baseline.

After the change, delete each pin or rewrite it as a specification test whose expected value comes
from intent. Pins left behind turn every later intended change into a re-approval.

## Harness shape for approval and differential tests

- **Recorded corpus.** Real inputs (captured requests, production-shaped fixtures, the existing
  test data) fed to both sides, persisted with the tests so a run can be reproduced. This is the
  base. Random or property-generated inputs (see [property.md](property.md)) are an optional extra:
  the claim that they catch bugs a recorded corpus misses rests on LOW evidence in the research, so
  do not treat them as a substitute for the corpus.
- **Comparator.** One function that decides equal or not, strict by default. Compare outputs and
  observable effects, not internal state.
- **Scrubbers for nondeterminism.** Normalize timestamps, generated ids, ordering of unordered
  collections, and machine paths before comparing, rather than dropping the comparison. Approval
  tools ship scrubbers or matchers for this. Where a value cannot be normalized, running old
  against old shows how much the output varies on its own; treat that as a suggestion, since its
  backing in the research is thin.
- **Intentional-differences ledger.** Every difference the change means to make gets an entry: an
  id, a predicate that matches exactly that difference, the reason, and the user's sign-off. The
  comparator skips a mismatch only through a ledger entry. Never widen the comparator, add a
  blanket scrubber, or re-approve a snapshot to turn a run green.
- **Failure report that names the input.** On a mismatch, print the input (or its corpus id), the
  old output, the new output, the diff, and whether any ledger entry was close. A report that says
  only "outputs differ" cannot be acted on.
- **Counts, not "tests pass".** Report inputs run, mismatches, mismatches covered by each ledger id,
  and unexplained mismatches. Any unexplained mismatch means the replacement is not done.

Compare only read-only paths against live traffic or in production. A path with side effects (a
write, a send, a charge) runs the new side against an isolated sink.

## Re-approving a changed snapshot

A snapshot your own change broke is a finding, not paperwork. Read the diff, decide whether it is
an intended difference (add a ledger entry or say why in the commit) or a regression (fix the
code), and only then re-approve. Re-approving in bulk records whatever bug produced the diff.

## Sources

Feathers, [Characterization Testing](https://michaelfeathers.silvrback.com/characterization-testing)
(2016); Seemann,
[Empirical characterization testing](https://blog.ploeh.dk/2025/11/03/empirical-characterization-testing/)
(the sabotage check, 2025-11-03); GitHub
[Scientist README](https://github.com/github/scientist) (control and candidate, ignored
mismatches, the side-effect warning); tool docs for scrubbers and review:
[Verify scrubbers](https://github.com/VerifyTests/Verify/blob/main/docs/scrubbers.md),
[Jest snapshot testing](https://jestjs.io/docs/snapshot-testing),
[ApprovalTests](https://approvaltests.com/). As of 2026-10-06. Recheck trigger: a tool renames
its scrubber or matcher mechanism, or Scientist drops its side-effect warning.

Basis: the agent-self-check research slice (2026-10-06), prompted by Addy Osmani's 2026-10-05 post
(<https://x.com/addyosmani/status/2106995301802541481>). The practices come from human-led
rewrites; no accepted source shows an agent validating a rewrite this way, so the agent
application is extrapolated. Recheck trigger: a measured study of agents validating rewrites by
differential comparison.
