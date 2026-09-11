# Reference values and where each one came from

A reference here is a value to count against, never a bar. The report prints how many rows sit at or
above it and stops; nothing fires, nothing fails, and no exit code changes. A `null` reference means
the plugin found no defensible value to ship, so it reports the measure and counts nothing as over.

## The bundled defaults

| Measure | Default | Provenance | Strength |
|---|---|---|---|
| Cyclomatic complexity | `20` | ISO/IEC 5055:2021 §8.2.117, the normative detection pattern `ASCQM Limit Algorithmic Complexity via Cyclomatic Complexity Value`, whose `<MaxCyclomaticComplexityValue>` default is 20 | Normative in the standard |
| Cognitive complexity | `null` | Campbell, SonarSource. The white paper prescribes no threshold | No standard sets one |
| Halstead difficulty | `null` | Halstead 1977 defines the measure and sets no limit | No standard sets one |
| Lines per file | `1000` | As the report prints it: the plugin's own number, not ISO-backed. It coincides with the informative figure in the ISO/IEC 5055:2021 §6.3 Table 1 row for CWE-1080, which is not normative, while the normative form (§8.2.115) is a function-level percentage; 500 is selectable, and `size.mode: iso-8.2.115` selects the normative alternative | Plugin default, labelled as such |
| Function lines percentage | `5` | ISO/IEC 5055:2021 §8.2.115 (normative), read by this plugin as a function's non-empty lines against its file's; the clause states the 5% with no base (see the verification record below) | Normative value, plugin's reading of the base |
| Duplication | none | No key ships. `duplication.min_tokens` and `duplication.min_lines` are collector floors, not references; ISO/IEC 5055 §8.2.116 measures element similarity between two functions (default 90%), which is a different quantity from a duplicated-lines percentage | Nothing comparable to cite |
| CRAP | `null` | Savoia and Evans 2007. Their own suggested value was 30, offered as a starting point they reserved the right to change | Authors' suggestion, no standard |
| Coverage | `null` | No standard states a percentage. ISO/IEC 25023:2016 files test coverage under Reliability and Maturity and sets no value | No standard sets one |
| Type coverage | `null` | No standard and no CWE anchors the measure | Nothing to cite |

The two cited alternatives for cyclomatic complexity, selectable through config:

- **10**, McCabe 1976. His own words: "The particular upper bound that has been used for cyclomatic
  complexity is 10 which seems like a reasonable, but not magical, upper limit." The same paragraph
  records the exception he shipped with it: the limit "seemed unreasonable [...] when a large number
  of independent cases followed a selection function (a large case statement), which was allowed".
  A flat dispatch `switch` flagged at 12 is being counted against a rule its author carved out.
- **15**, NIST SP 500-235 (Watson and McCabe, September 1996). Also conditional, and the document
  calls the precise number "somewhat controversial": limits above 10 "should be reserved for
  projects that have several operational advantages over typical projects, for example experienced
  staff, formal design, a modern programming language, structured programming, code walkthroughs,
  and a comprehensive test plan". Those six named practices are part of the citation. Reporting 15
  without them presents a conditional figure as an unconditional standard.

Four qualifications the table above cannot hold:

- **The ISO clause map matters more than the ISO name.** Clause 7 (the weakness list) and clause 8
  (the detection patterns) are both normative; clause 6 is informative. Clause 7.1.10 names the
  cyclomatic weakness (CWE-1121) and carries no number at all. The number lives at §8.2.117. The
  1000-line figure lives only in the informative §6.3 Table 1 row for CWE-1080, while the
  normative pattern attached to the same weakness, §8.2.115, is a percentage on a function. So
  "1000 lines per file, per ISO/IEC 5055" would cite an informative row against a normative clause
  that says something different at a different granularity, and this plugin does not say it.
- **The §8.2.115 base is this plugin's reading, not the clause's words.** Verification record.
  Claim: §8.2.115 `ASCQM Limit Size of Operations Code` flags a `FunctionProcedureOrMethod` whose
  `NumberOfNonEmptyLinesOfCode` exceeds `MaxNumberOfNonEmptyLinesOfCode`, whose stated default is
  "5%", and the clause names no base for that percentage; this plugin reads the base as the
  enclosing file's non-empty lines. Basis: OMG ASCQM v1.1 (formal/2022-07-01) §8.2.115, and the
  OMG-hosted ISO edition (v1.0, October 2020), whose clause text is identical. As of: 2026-09-11.
  Recheck when OMG or ISO publishes a new revision of the specification.
- **ISO/IEC 5055:2021 is the ISO publication of OMG ASCQM v1.0.** Cite the standard by version and
  clause, never by page number. ISO's first edition (2021-03) carries the v1.0 text dated October
  2020; OMG's own current release is v1.1 (July 2022), which carries identical text for §8.2.115
  and §8.2.117. The two are not interchangeable if a later revision diverges.
- **The 25023 coverage row is MEDIUM confidence.** The official ISO preview confirms the clause
  structure (8.6 Reliability, 8.6.1 Maturity) and the measure-id grammar, from which `RMa-4-S` is a
  structurally valid id for a fourth, Specific-category Maturity measure. The normative body naming
  individual measures is paywalled. Even if the id is exactly right, the measure as reproduced
  elsewhere counts capabilities, operational scenarios, or functions performed against those
  included in the test suites, which is scenario coverage rather than the line coverage a coverage
  tool emits. Grouping a line-coverage percentage under that id would overclaim twice.

## Popular numbers with no found source

These values circulate as thresholds. None of them traces to a standard or to the author of the
measure it is applied to, in any source this plugin cites.

| Value | Applied to | Where it was looked for | What was found |
|---|---|---|---|
| 22 | Cyclomatic complexity | McCabe 1976 and NIST SP 500-235 (full text); the threshold pages of Aivosto, ESLint (20), ReSharper (20), Microsoft CA1502 (25), NDepend (15 and 30), NASA SWEHB (15) | No source attributes 22 to anyone |
| 22 | Cognitive complexity | Campbell's white paper; SonarSource rule S3776 | No standard sets a cognitive threshold; SonarSource's rule default is 15, a product decision |
| 80 | Halstead difficulty | Halstead 1977 as reproduced by NASA NTRS, IBM, and radon; vendor threshold pages | Halstead defines difficulty and sets no limit; nothing attributes 80 to anyone |
| 500 | Lines per file | ISO/IEC 5055 clauses 6 and 8 | The nearest standards figure is the informative 1000, and the normative form is a percentage. Selectable through config |
| 100 | Coverage percentage | ISO/IEC 25023 preview; the coverage-effectiveness studies in literature.md | A policy, not a standard. A coverage number rises whenever a line executes, with or without an assertion |
| 25 | CRAP | The Crap4j FAQ and the 2007 announcement | Not the authors' number. Savoia and Evans suggested 30, as a starting point after "a LOT of opinions" |
| 0 | Count-based concerns (mutants, dead code, lint) | Not applicable | A target of zero is a policy choice; three of those concerns belong to other plugins, which `SKILL.md` names behind a presence gate |

Sources not checked for any of these rows: vendor products behind a login, and standards bodies
other than ISO, OMG, NIST, and MITRE. A reader who finds an authoritative source for one of these
values should send it; the row changes only on a citation.

Two of the shipped defaults, 20 for cyclomatic and 1000 for lines per file, exist because a citation
exists for them, not because the empirical literature validates them. No study reviewed in
[literature.md](literature.md) supports a fixed threshold that transfers across projects, and two of
them argue against it directly.

## Setting your own

Every reference resolves through `.claude/code-metrics.yaml` across three layers, user-global then
team then local overlay, with per-key override: setting one key replaces that value and leaves the
rest of the defaults intact. The full key list is `${CLAUDE_PLUGIN_ROOT}/reference/config.md`, and
`/code-metrics:setup` writes the team file and probes the collectors. The report prints the layer
that supplied any value a personal layer changed, so a number that differs from a teammate's is
traceable to the layer that changed it rather than to the code.

Setting a reference to `null` is a legitimate choice and turns the count off while the measure keeps
reporting. Setting one to a value you can defend for your codebase is a better choice than adopting
one of these because a standard prints it.
