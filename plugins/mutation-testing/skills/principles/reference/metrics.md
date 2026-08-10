# Metrics: which number means what

Four ecosystems invented the same two metrics under four names. This file reconciles them and says
which to report.

Sources: [Stryker — mutant states and
metrics](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/);
[Infection — MSI](https://infection.github.io/guide/); [PIT](https://pitest.org/); Ojdanic et al.,
*Mind the Gap: The Difference Between Coverage and Mutation Score Can Guide Testing Efforts*
(<https://arxiv.org/abs/2309.02395>). Fetched 2026-08-10.

## The aggregates

Stryker's definitions, which the rest of this file uses:

```text
Detected   = killed + timeout
Undetected = survived + no coverage
Covered    = detected + survived
Valid      = detected + undetected
Invalid    = runtime errors + compile errors
```

Invalid mutants are excluded from scoring — a mutant that would not compile was never a test of
anything.

## The two scores

```text
Mutation score                       = detected / valid   * 100
Mutation score based on covered code = detected / covered * 100
```

The difference is the denominator, and it is the whole point:

- **Mutation score** includes `no coverage` in the denominator. It answers *"across all the code I
  asked about, how much is protected?"* — it degrades when you have no tests **and** when you have
  bad tests, without distinguishing them.
- **Covered-code mutation score** counts only mutants a test actually reached. It answers *"of the
  code my tests do exercise, how much do they genuinely check?"*

**Report the covered-code score.** Report the plain score beside it only as context. The two
together tell a story neither tells alone.

## The same metric, four names

| Ecosystem | "All mutants" | "Only covered mutants" |
|---|---|---|
| Stryker | Mutation score | Mutation score based on covered code |
| PIT | Mutation coverage | **Test strength** |
| Infection | **MSI** (Mutation Score Indicator) | **Covered Code MSI** |
| Literature | Mutation score | Mutation adequacy over covered code |

Infection also reports **Mutation Code Coverage** = `covered / total * 100`, which tracks ordinary
line coverage closely and is mostly useful as a sanity check that the harness saw the tests it
should have.

Infection's own reading of the gap: when MSI and Covered Code MSI diverge widely, unit tests are
"far less effective than Code Coverage alone could detect."

## The oracle gap

The academic formalization of the same intuition:

```text
oracle gap = mutation score − code coverage    (per file or per component)
```

A file with high coverage and a large negative gap is *exercised but not checked* — the paper's
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
  uninteresting. This is why a threshold gate is the wrong instrument — see
  [scaling-and-suppression.md](scaling-and-suppression.md).
- **They are inflated by flaky tests.** A flaky test kills mutants by accident. Any suite with known
  flakiness reports a mutation score that is too high by an unknown margin; fix the flakes first or
  state the caveat with the number.

## Reporting shape

A useful report is per-file and ranked, not a single repository number:

```text
| File | Coverage | Covered-code score | Gap | Survivors |
|---|---|---|---|---|
| src/pricing.ts |  96% | 41% | −55 | 7 |
| src/audit.ts   |  88% | 84% |  −4 | 2 |
```

Rank by gap, not by score. The top row is where a reader's belief about the suite is most wrong,
which is the only thing a metric like this is good for.
