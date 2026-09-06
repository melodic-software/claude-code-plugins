---
description: "Metric literacy for the measures this plugin reports: what cyclomatic complexity, cognitive complexity, Halstead difficulty, lines per file, duplication, coverage, CRAP, and type debt mean, and what none of them can tell you. Four reference files carry the definitions and what each collector really computes, every bundled reference value with its provenance (why cyclomatic 20, why 22 and 80 have no citation), the CRAP formula with its corrected name history and coverage join, and an annotated bibliography (McCabe, Halstead, NIST SP 500-235, Campbell, Lewis 2013, ISO/IEC 5055 and 25023). The plugin's cross-metric caveats live here once, and the owners of the measures it leaves alone are named behind a presence gate. Use when: 'what does cyclomatic complexity mean', 'is CRAP a real metric', 'why is the cyclomatic reference 20', 'what is a good coverage number', 'which metric should I look at', 'code metrics principles'; for the numbers themselves run the sibling /code-metrics:audit-* skills."
argument-hint: "[question or concept]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: What each code measure can and cannot tell you
---

# Code metrics knowledge base

The five `audit-*` skills in this plugin print numbers with their provenance and stop. This skill
says what each number means, where its reference value came from, and where reading it as a verdict
goes wrong. Reference files in `reference/` are source-attributed; the sections below answer the
common questions without a load.

## Routing table

| Query about... | Load |
|---|---|
| What a measure is, its formula, per-lane collector behavior, artifact formats | [measures.md](reference/measures.md) |
| Where a reference value came from, the operator's original list, how to set your own | [thresholds.md](reference/thresholds.md) |
| The CRAP formula, its two authorial names, the coverage join, what it does not predict | [crap.md](reference/crap.md) |
| Who published what, what a paper claims and does not claim, confidence per source | [literature.md](reference/literature.md) |

Load the one file the question lands in. Load a second only when the first leaves the question open.

## Quick decision guide (no file load needed)

- **"Which measure should I look at?"**. The one attached to the change in front of you. Complexity
  and size are per function or per file and move with an edit; duplication and coverage are
  properties of the tree around it. No measure here ranks changes by risk.
- **"Is 22 the cyclomatic threshold?"**. No source found in this plugin's research attributes 22 to
  anyone. The bundled reference is 20, from ISO/IEC 5055:2021 §8.2.117, with 10 (McCabe 1976) and
  15 (NIST SP 500-235) as the cited alternatives you can select.
- **"What is a good coverage number?"**. No standard sets one, so this plugin ships no coverage
  reference. A percentage counts executed lines; it says nothing about whether anything was checked.
- **"Is CRAP a real metric?"**. It is real and authored (Savoia and Evans, 2007), and it is not a
  validated change-risk predictor. See [crap.md](reference/crap.md) before quoting a CRAP number.
- **"Is this file too long at 1200 lines?"**. The report tells you it is at or above the reference
  of 1000, which is this plugin's own number. ISO/IEC 5055's normative file-size clause is a
  percentage of a function against its file, not a line count.
- **"Cyclomatic or cognitive?"**. Cyclomatic counts independent paths through a function, which is
  what makes it a testing measure. Cognitive weights nesting and forgives a flat `switch`, which is
  what makes it a readability measure. They disagree on the same function by design.
- **"Halstead difficulty rose when I split the file. Why?"**. It should not have. Difficulty has no
  length term: it is operator variety times operand reuse. A difficulty that tracks file size is
  measuring something else, so check which collector produced it.
- **"Type coverage is 96%. Is that good?"**. No standard and no CWE anchors the measure, so there is
  no external answer. The percentage also counts `unknown` as typed, so an `any`-to-`unknown` sweep
  raises it without adding type information.
- **"Why does the report never fail?"**. A reference here is a value to count against, never a bar.
  This version reports measures and emits no finding, no severity, and no gate exit code.

## Cross-metric caveats

The whole plugin carries these once, here; the `audit-*` skills point at this section rather than
repeating it. Every one of them is a way a true number supports a false conclusion.

- **Coverage responds to tests that assert nothing.** A line is counted as covered when it executed,
  and a test that calls a function without an assertion executes it. Raising a coverage percentage is
  therefore always possible without improving the suite, which is why no coverage reference ships and
  why the number is reported beside the code rather than as a score.
- **A complexity refactor usually moves complexity rather than removing it.** Splitting a function of
  cyclomatic 30 into six functions leaves roughly the same number of paths in the file and turns one
  measured row into six smaller ones. Per-function complexity falls, the file's total does not, and
  the reader who compares only the maximum sees an improvement that the sum of the rows denies.
- **Duplication drops the moment you extract a helper, whether or not that helped.** The measure
  counts repeated token runs and has no view of whether the two copies change for the same reason,
  and the extraction leaves both call sites depending on the new helper. Some replication is
  deliberate, which is why a declared registry excludes a cluster rather than suppressing it, and
  whether the coupling that replaces it is an improvement is a question this plugin cannot measure.
- **Type coverage counts identifiers whose type is not `any`.** `unknown`, a widened supertype, and a
  falsely narrow annotation all count as typed. The TypeScript percentage and the Python
  Any-expression figures are different measures over different populations and never compare.
- **The measures interact, and none of them composes.** Coverage and complexity combine in CRAP, and
  that is the only combination this plugin computes. A function at 100% coverage and complexity 40
  still has CRAP 40; a small function with three untested branches can outrank a large tested one.
  There is no supported way to add or average these numbers into a quality score, and doing it is
  the mistake this section exists to prevent.

## Owners of the other measures

This plugin does not measure these. Each one has an owner, and each pointer is gated:

- **Surviving mutants and mutation score.** Invoke `/mutation-testing:principles` for what a
  surviving mutant means, and `/mutation-testing:audit` to run one, when the `mutation-testing` plugin is installed;
  otherwise the concern is out of this plugin's scope and nothing here substitutes for it. Coverage
  cannot answer it: a covered line can still be unchecked.
- **Tautological and assertion-free tests.** Invoke `/testing:audit` when the `testing` plugin is installed;
  otherwise the concern is out of this plugin's scope and nothing here substitutes for it.
- **Dead code.** Invoke `/code-tidying:audit-dead-code` when the `code-tidying` plugin is installed;
  otherwise the concern is out of this plugin's scope and nothing here substitutes for it. ISO/IEC
  5055 files dead code as its own weakness (7.1.5, CWE-561), separate from every measure here.
- **Coupling and fan-in.** Invoke `/coupling:reduce` when the `coupling` plugin is installed;
  otherwise the concern is out of this plugin's scope and nothing here substitutes for it.
- **Lint rules and style violations.** Invoke `/toolchain:lint` when the `toolchain` plugin is installed;
  otherwise the concern is out of this plugin's scope and nothing here substitutes for it. A lint
  rule fires a finding; the measures here do not.
- **Comparing two reports.** Feed an audit skill's `--json` document to `/verification:measure metrics` when the `verification` plugin is installed,
  treating a report whose `status` is `empty` on either side as INCONCLUSIVE; otherwise keep the
  JSON beside your notes and compare by hand.

## Sources

- **McCabe**: T. J. McCabe, "A Complexity Measure", IEEE Transactions on Software Engineering
  SE-2(4), December 1976, pp. 308-320.
- **Watson and McCabe**: NIST Special Publication 500-235, *Structured Testing*, September 1996.
- **Halstead**: Maurice H. Halstead, *Elements of Software Science*, Elsevier North-Holland, 1977.
- **Campbell**: G. Ann Campbell, SonarSource, *Cognitive Complexity: a new way of measuring
  understandability*, white paper version 1.7, 29 August 2023.
- **Savoia and Evans**: Alberto Savoia with Bob Evans, Agitar Labs, the CRAP score, July 2007, and
  the Crap4j project FAQ.
- **Lewis et al.**: "Does Bug Prediction Support Human Developers? Findings from a Google Case
  Study", ICSE 2013.
- **ISO/IEC 5055:2021** (adopted from OMG ASCQM; current OMG release v1.1) and **ISO/IEC
  25023:2016**, cited by clause and version, never by page number.

Per-source annotation, including what each does not claim and the confidence behind it, is in
[literature.md](reference/literature.md).

## Scope boundary

This skill is **knowledge**, not **workflow**. It measures nothing, runs no collector, and reads no
repository. The `audit-*` skills in this plugin produce the numbers; this one explains them. It also
renders no verdict on your code: a reference value with a citation is the most it offers, and
deciding what to do about a number is the reader's call.

## Gotchas

- Provenance strength varies inside one report. The cyclomatic reference is normative in a
  standard; the file-line reference is this plugin's own number; cognitive, Halstead, CRAP, coverage,
  and type debt ship `null` because nothing authoritative sets a value. Treating the four as one
  tier is the error [thresholds.md](reference/thresholds.md) exists to prevent.
- A citation for a threshold's existence is not evidence that the threshold predicts defects. The
  empirical literature does not support a fixed default that transfers across projects, and
  [literature.md](reference/literature.md) records which studies say so.
- Two collectors for one measure can disagree on the same function; they implement the same
  definition with different parsers and different variants. The report names the collector per row
  so the number is traceable, and comparing rows from different collectors is not supported.
- CRAP has two authorial expansions and one of them still appears on the authors' own homepage.
  Quoting one as canonical overstates the record; [crap.md](reference/crap.md) carries both.
