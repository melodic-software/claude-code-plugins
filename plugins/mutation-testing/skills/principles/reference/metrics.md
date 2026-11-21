# Metrics: which number means what

A mutation run yields two scores. This file defines them and says which to report.

Sources: [Stryker mutant states and
metrics](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/);
Ojdanic et al., *Mind the Gap: The Difference Between Coverage and Mutation Score Can Guide Testing
Efforts* (<https://arxiv.org/abs/2309.02395>). Fetched 2026-08-10. Recheck when Stryker renames or redefines a metric on its own docs page, or at the next fleet audit; the cited paper is fixed.

## The aggregates

Stryker's definitions, which the rest of this file uses:

```text
Detected   = killed + timeout
Undetected = survived + no coverage
Covered    = detected + survived
Valid      = detected + undetected
Invalid    = runtime errors + compile errors
```

Invalid mutants are excluded from scoring. A mutant that would not compile was never a test of
anything.

## The two scores

```text
Mutation score                       = detected / valid   * 100
Mutation score based on covered code = detected / covered * 100
```

The difference is the denominator, and it is the whole point:

- **Mutation score** includes `no coverage` in the denominator. It answers *"across all the code I
  asked about, how much is protected?"*, and it degrades when you have no tests **and** when you have
  bad tests, without distinguishing them.
- **Covered-code mutation score** counts only mutants a test actually reached. It answers *"of the
  code my tests do exercise, how much do they genuinely check?"*

**Report the covered-code score.** Report the plain score beside it only as context. The two
together tell a story neither tells alone.

## The oracle gap

The academic formalization of the same intuition:

```text
oracle gap = mutation score − code coverage    (per file or per component)
```

A file with high coverage and a large negative gap is *exercised but not checked*. The paper's
framing is that it identifies "source files where it is likely a weak oracle tests important code."

This is the most actionable single number for prioritization, because it ranks by *surprise*: it
surfaces the files a coverage report already declared healthy. A file at 30% coverage and 30%
mutation score has an honest problem you already knew about. A file at 95% coverage and 45% mutation
score is lying to you.

## What these numbers cannot do

- **They are not comparable across repos.** Operator sets, language, and suppression policy all move
  the number. A 60% here and a 60% elsewhere are not the same measurement.
- **They have a hard ceiling below 100%.** Equivalent mutants are undecidable in general and cannot
  all be removed, so some fraction of every score is permanently unreachable. The size of that
  fraction is unknown and codebase-specific.
- **They are gamed by suppression.** Every point of score is purchasable by declaring a mutant
  uninteresting. This is why a threshold gate is the wrong instrument. See
  [scaling-and-suppression.md](scaling-and-suppression.md).
- **They are inflated by flaky tests.** A flaky test kills mutants by accident. Any suite with known
  flakiness reports a mutation score that is too high by an unknown margin; fix the flakes first or
  state the caveat with the number.

## Reporting shape

A useful report is per-file and ranked, not a single repository number: one row per file with its
coverage, covered-code score, gap and survivor count.

Rank by gap, not by score. The top row is where a reader's belief about the suite is most wrong,
which is the only thing a metric like this is good for.
