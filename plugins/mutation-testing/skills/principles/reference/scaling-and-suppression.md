# Making it affordable: diff-scoping, arid nodes, and why not to gate

Mutation testing was academically settled and industrially unused for three decades. What changed was
not compute — it was scoping. This file is the operational core of the plugin.

Sources: Petrović & Ivanković, *State of Mutation Testing at Google* (ICSE-SEIP 2018,
<https://dl.acm.org/doi/10.1145/3183519.3183521>); Petrović, Ivanković, Fraser & Just, *Practical
Mutation Testing at Scale* (<https://arxiv.org/abs/2102.11378>); [Stryker.NET
configuration](https://stryker-mutator.io/docs/stryker-net/configuration/); [StrykerJS
incremental](https://stryker-mutator.io/docs/stryker-js/incremental/). Fetched 2026-08-10.

## The cost problem, stated honestly

Naive cost is `mutants × test-suite-runtime`. A repository with 10,000 mutable lines and a
five-minute suite is asking for weeks of machine time per run. No threshold, cache, or parallelism
fixes an exponent that shape.

## The four moves that fix it

Google runs mutation analysis against a codebase of roughly two billion lines with about 500 million
tests executed daily. Their approach is four decisions, in order of impact:

### 1. Diff-scope it

Mutate only the lines changed in the current change, at review time. Never the whole repository. Every
major tool supports this directly:

- **Stryker.NET** — `since`: "Use git information to test only code changes since the given target.
  Stryker will only report on mutants within the changed code." Target defaults to `master`.
- **StrykerJS** — `--incremental`: "track the changes you make to your code and tests and only runs
  mutation testing on the changed code," while still producing the full report. Cached results are
  reused when a killed mutant's culprit test still exists unchanged, or when an unkilled mutant has
  no new covering test and no test changed.
- **Infection** — `--git-diff-lines`.
- **PIT** — incremental analysis; its own front page recommends running "frequently against only the
  code that has been changed" as "the most effective way" to use it.

### 2. At most one mutant per line

Not every operator at every location. One, chosen by the historical productivity of the operators
available at that node. The marginal value of the second mutant on a line is close to zero — if the
line is unchecked, one mutant proves it.

### 3. Suppress arid nodes

An **arid** node is one whose mutation reliably produces an unproductive mutant — a logging call, a
trivial accessor, a debug string. The rule for compound statements is recursive and worth quoting
exactly:

> A compound node is an arid node iff *all* of its parts are arid.

So a block containing one meaningful statement is not arid, however much logging surrounds it. This
is what stops suppression from swallowing real code.

### 4. Surface it as a review prompt, not a report

The mutant appears where the code is being read — as a review comment on the changed line — with a
one-click way to say "not useful." A report nobody opens changes no tests.

### What the four moves are worth

| Regime | Mutants per changelist (median) |
|---|---|
| Traditional mutagenesis | 820 |
| One-per-line, unfiltered | 77 |
| One-per-line + arid suppression | **7** |

Two orders of magnitude, without changing the test suite or the hardware.

## Productive vs unproductive

The metric that actually governs adoption is not the score. It is:

> A **productive** mutant is one that "elicits an effective test, or otherwise advances code quality."

Everything else is noise, and noise is fatal — an audit whose report is permanently noisy is an audit
nobody reads.

The scale of the problem, measured: at Google's start, **developers classified about 85% of reported
mutants as unproductive.** After the suppression work, productivity reached roughly **89%**, with
about **82%** of surfaced mutants drawing "Please fix" feedback in aggregate. Note also that only
about **3.2%** of surfaced mutants received *any* explicit feedback (66,798 of 2,110,489) — the
feedback channel must be cheap, and absence of complaint is not endorsement.

**The operational consequence:** an un-suppressed mutation run is roughly 85% noise. Any rollout that
surfaces raw survivors to reviewers before a suppression loop exists will be switched off before the
loop can be built. Scope first, suppress second, surface third.

## Three dispositions for a surviving mutant

Telling these apart is the judgment the tooling cannot do:

| Disposition | Meaning | Action |
|---|---|---|
| **Productive** | A genuine gap — the behavior is unchecked | Write a test that kills it |
| **Equivalent** | The mutated program is semantically identical; no test can kill it | **Not** a suppression. The check is wrong for that node — fix or exclude the check |
| **Arid** | Killable, but killing it would not improve the suite | Suppress, with a written reason |

The equivalent/arid distinction matters procedurally. A suppression record exists to say "this
finding is known and accepted"; it is explicitly *not* for "a finding that is simply wrong (fix the
check)." Filing an equivalent mutant as a suppression hides a defective check behind an accepted
finding.

## Why not to gate on the score

A break-on-threshold option exists in most tools — Stryker's `thresholds.break` "will exit with a
non-zero code" below the configured score, "used in a CI pipeline to fail the pipeline." Do not use
it, for three compounding reasons:

1. **The ceiling is unknowable.** Equivalent mutants put a permanent, codebase-specific cap below
   100%. A threshold is a bet on a number nobody can compute.
2. **The metric is purchasable.** Every point is available by suppressing a mutant. Under a gate,
   suppression is the cheapest path to green, so a gate selects for suppression over testing —
   the exact inversion of intent.
3. **The signal is per-file, not per-repo.** A repository-level score aggregates away the only
   actionable thing (which file's tests are lying), so gating on it applies pressure everywhere and
   guidance nowhere.

Report the number. Rank by the gap. Let the surviving mutants be the finding.

## Corollary: what to do instead of a ratchet

A nightly whole-repository run with a ratcheted target is the shape this evidence argues against —
it is un-scoped (move 1 skipped), un-suppressed (move 3 skipped), reported rather than surfaced
(move 4 skipped), and gated. Prefer the diff-scoped run on changed code, ranked by oracle gap, with
survivors routed to the test-authoring lane.
