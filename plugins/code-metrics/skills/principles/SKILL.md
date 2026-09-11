---
description: "Metric literacy for what this plugin reports: what cyclomatic complexity, cognitive complexity, Halstead difficulty, lines per file, duplication, coverage, CRAP, and type debt mean, and what none of them can tell a reader. Four reference files carry the definitions and what each collector computes, each bundled reference value with its provenance (why cyclomatic 20, why 22 and 80 have no citation), the CRAP formula with its name history and coverage join, and an annotated bibliography (McCabe, Halstead, NIST SP 500-235, Campbell, Lewis 2013, ISO/IEC 5055 and 25023). Cross-metric caveats live here once; owners of the measures it leaves alone are named behind a presence gate. Use when: 'what does cyclomatic complexity mean', 'is CRAP a real metric', 'why is the cyclomatic reference 20', 'what is a good coverage number', 'which metric should I look at', 'code metrics principles'; for the numbers themselves run the /code-metrics:audit-* skills."
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
goes wrong. It renders no verdict of its own, and neither does the plugin: a reference is a value to
count against, never a bar, and no skill here emits a finding, a severity, or an exit-code gate,
because a finding needs a measured corpus sweep behind it and none has been run. Reference files in
`reference/` are source-attributed; the sections below answer the common questions without a load.

## Routing table

| Query about... | Load |
|---|---|
| What a measure is, its formula, per-lane collector behavior, coverage artifact formats | [measures.md](reference/measures.md) |
| Where a reference value came from, which popular numbers have no source, how to set your own | [thresholds.md](reference/thresholds.md) |
| The CRAP formula, its two authorial names, the coverage join, what it does not predict | [crap.md](reference/crap.md) |
| Who published what, what a paper claims and does not claim, confidence per source | [literature.md](reference/literature.md) |
| The report vocabulary (`cov_source`, `not-applicable`, `partial`) and the JSON document shape | `${CLAUDE_PLUGIN_ROOT}/reference/report-schema.md` |

Load the one file the question lands in. Load a second only when the first leaves the question open.

## Quick decision guide (no file load needed)

- **"Which measure should I look at?"**. Start from the question, not from the report. How much
  testing a function needs is cyclomatic complexity: McCabe 1976 defines it as the size of a basis
  set of paths, and NIST SP 500-235 makes that the number of tests a module needs. How hard a
  function is to read is cognitive complexity: Campbell's measure penalizes nesting and charges a
  `switch` and all its cases once. Whether a diff is too large or copied is lines per file and
  duplication over the changed files, the two measures ISO/IEC 5055 files as weaknesses (CWE-1080
  and CWE-1041). Whether the suite would catch a fault is not a coverage question: coverage records
  which lines executed, the primary literature disagrees on how well that predicts fault detection,
  and the owner of that question is behind the mutation-testing gate below. No measure here ranks
  changes by risk.
- **"Is 22 the cyclomatic threshold?"**. No source this plugin cites attributes 22 to anyone. The
  bundled reference is 20, from ISO/IEC 5055:2021 §8.2.117, with 10 (McCabe 1976) and 15 (NIST SP
  500-235) as the cited alternatives you can select.
- **"What is a good coverage number?"**. No standard sets one, so this plugin ships no coverage
  reference. A percentage counts executed lines; it says nothing about whether anything was checked.
- **"Is 8% duplication bad?"**. No duplication reference ships, so the report counts nothing as
  over. The percentage moves with `duplication.min_tokens`, so two runs compare only at the same
  floor, and replication the repository declares in a registry is excluded rather than suppressed.
- **"Is CRAP a real metric?"**. It is real and authored (Savoia and Evans, 2007), and it is not a
  validated change-risk predictor. See [crap.md](reference/crap.md) before quoting a CRAP number.
- **"Is this file too long at 1200 lines?"**. The report tells you it is at or above the reference
  of 1000, which is this plugin's own number. ISO/IEC 5055's normative clause for the same weakness
  is a percentage on a function, not a line count on a file.
- **"Cyclomatic or cognitive?"**. Cyclomatic counts independent paths through a function, which is
  what makes it a testing measure. Cognitive weights nesting and forgives a flat `switch`, which is
  what makes it a readability measure. They disagree on the same function by design.
- **"Halstead difficulty rose when I split the file. Why?"**. Difficulty is `(n1/2) * (N2/n2)`,
  operator variety times operand reuse, with no explicit length term, so it does not track size. A
  split changes each half's operator count and reuse ratio, so per-file difficulty legitimately
  moves on a split, in either direction. Check which collector produced the row: `multimetric`
  reports Halstead per file and `radon` per function.
- **"Type coverage is 96%. Is that good?"**. No standard and no CWE anchors the measure, so there is
  no external answer. The percentage also counts `unknown` as typed, so an `any`-to-`unknown` sweep
  raises it without adding type information.

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
- **Coverage and test effectiveness**: Inozemtseva and Holmes, ICSE 2014; Gopinath, Jensen and
  Groce, ICSE 2014; Kochhar, Thung and Lo, SANER 2015; Jia and Harman, IEEE TSE 2011; Petrovic and
  Ivankovic, ICSE-SEIP 2018; Petrovic, Ivankovic, Fraser and Just, IEEE TSE 2022.
- **ISO/IEC 5055:2021** (the ISO publication of OMG ASCQM v1.0; OMG's current release is v1.1) and
  **ISO/IEC 25023:2016**, cited by clause and version, never by page number.

Per-source annotation, including what each does not claim and the confidence behind it, is in
[literature.md](reference/literature.md).

## Scope boundary

This skill is **knowledge**, not **workflow**. It measures nothing, runs no collector, and reads no
repository. The `audit-*` skills in this plugin produce the numbers; this one explains them, and
deciding what to do about a number is the reader's call.

## Next

- The number in question still has to be measured: `/code-metrics:audit-complexity`, or the
  `audit-*` skill for that measure.
- The bundled reference values are not the ones your codebase can defend: `/code-metrics:setup`.

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
