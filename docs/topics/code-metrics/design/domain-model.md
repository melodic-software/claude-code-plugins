# code-metrics domain model

The nouns the plugin's scripts and prose share, and the invariants that hold across every skill.

## Terms

| Term | Meaning | Rejected synonyms |
|---|---|---|
| measure | One named quantity read off code or an artifact: cyclomatic, cognitive, halstead_difficulty, file_lines, duplication, coverage, crap, type_coverage. ISO/IEC 25000 vocabulary; "metric" survives only in the plugin name, which the tooling register decided. | metric (in prose), KPI, score (except "CRAP score", the authors' own term) |
| lane | One ecosystem the plugin detects and measures: typescript, python, bash, go, dotnet (deferred). | language, stack, target |
| collector | An external tool an adapter wraps to produce a measure for a lane. | analyzer, engine, backend |
| parser | Plugin code that reads an existing artifact (lcov, Cobertura, coverage.py JSON) into per-line hits. | importer, loader |
| reference | A configured value a measure is compared against for counting only; never a bar. | threshold (in the report), limit, budget |
| provenance | The citation attached to a reference: standard and clause, or author and year, or "plugin default". | source |
| scope | The file set a run measures: change, explicit paths, or all. | target set |
| run row | One (lane, measure) entry in the "Coverage of this run" table with collector and status. | |
| exclusion | A clone group dropped because the target repository declares it as sanctioned replication. | suppression (reserved for kept findings, which V1 has none of) |

## Invariants

1. A run never executes tests, never edits source, and never installs a tool.
2. Every (lane, measure) pair the scope implies appears in `run[]` with a status; nothing is
   silently skipped.
3. A value that could not be measured is `null`, never `0`.
4. A reference is printed with its provenance every time it is printed.
5. A number the plugin computes rather than reads from a tool is labelled with the plugin's own
   name as its provenance (the bundled line counter, the CRAP formula, the size default).
6. A number that a tool computes under a name that differs from the standard definition is
   labelled with the tool's name (`gocyclo` text scrape; `multimetric` derived Halstead).
7. Cross-plugin references are presence-gated with a stated fallback; native surfaces are not
   referenced because none overlaps.
8. Configuration resolves through the cascade with per-key override; the report states which layer
   supplied any value a personal layer changed.

## Measures by skill

| Skill | Measures | Granularity | Collectors or parsers |
|---|---|---|---|
| audit-complexity | cyclomatic, cognitive, halstead_difficulty (plus the other Halstead derived values where available) | function | lizard, radon, ESLint complexity, eslint-plugin-sonarjs, gocyclo, gocognit, shellmetrics, multimetric |
| audit-size | file_lines (total, blank, comment, code) and the §8.2.115 function-percentage mode | file (function in iso mode) | scc, bundled counter |
| audit-duplication | duplicated_lines, duplicated_tokens, clone groups, debt after exclusions | clone group and file | jscpd, PMD CPD (xml), dupl |
| audit-coverage | line coverage per file and per function, function hit flag, crap | function | lcov, Cobertura, coverage.py JSON parsers; audit-complexity for `comp` |
| audit-type-debt | type_coverage_pct (TS), any_expressions and type-check coverage (Python) | lane | type-coverage, mypy reports |
| principles | none; the literacy router | | |
| setup | none; `check` and `apply` | | |

## CRAP, stated once

`crap(f) = comp(f)^2 * (1 - cov(f)/100)^3 + comp(f)`, Savoia and Evans (Agitar Labs), introduced
July 2007 as "Change Risk Analysis and Predictions" and later renamed by its authors to "Change
Risk Anti-Patterns". `comp` is cyclomatic complexity; `cov` is the function's line coverage
percentage. It is not a validated change-risk predictor. An unactionable score is ignored
(Lewis 2013 mechanism); the report therefore prints the two inputs beside it, which is what makes
it actionable.
