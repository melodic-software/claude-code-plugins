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
| Lines per file | `1000` | This plugin's own number. It coincides with the informative figure in ISO/IEC 5055:2021 §6.3 Table 1, which is not normative | Plugin default, labelled as such |
| Function lines percentage | `5` | ISO/IEC 5055:2021 §8.2.115 (normative): a function whose non-empty lines exceed this percentage of the file's | Normative in the standard |
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

Three qualifications the table above cannot hold:

- **The ISO clause map matters more than the ISO name.** Clause 7 (the weakness list) and clause 8
  (the detection patterns) are both normative; clause 6 is informative. Clause 7.1.10 names the
  cyclomatic weakness (CWE-1121) and carries no number at all. The number lives at §8.2.117. The
  1000-line figure lives only in informative clause 6.3 Table 1, while the normative pattern
  attached to the same file-size weakness, §8.2.115, states 5% of a function against its file. So
  "1000 lines per file, per ISO/IEC 5055" would cite an informative table against a normative clause
  that says something different at a different granularity, and this plugin does not say it.
- **ISO/IEC 5055:2021 is the ISO designation of OMG's ASCQM text.** Cite the standard by version and
  clause, never by page number. The version ISO adopted is OMG's v1.0, dated 2020; OMG's own current
  release is v1.1 (July 2022), verified by diff to keep the §8.2.115 and §8.2.117 defaults and the
  clause-7 numbering. The two are not interchangeable if a later revision diverges.
- **The 25023 coverage row is MEDIUM confidence and preview-sourced.** The official ISO preview
  confirms the clause structure (8.6 Reliability, 8.6.1 Maturity) and the measure-id grammar, from
  which `RMa-4-S` is a structurally valid id for a fourth, Specific-category Maturity measure. The
  normative body naming individual measures is paywalled and was not read. Even if the id is exactly
  right, the reproduction describes it as counting capabilities, operational scenarios, or functions
  performed against those included in the test suites, which is scenario coverage rather than the
  line coverage a coverage tool emits. Grouping a line-coverage percentage under that id would
  overclaim twice.

## The operator's starting list, checked

The list this plugin was commissioned from carried ten numbers: 22, 22, 80, 500, 100, 25, and four
zeros for the count-based concerns. They came from a social post rather than a standard, and the
interview asked for them to be scrutinized. The result:

| Value | Concern | Verdict |
|---|---|---|
| 22 | Cyclomatic complexity | **No provenance found.** McCabe 1976 and NIST SP 500-235 were downloaded and full-text searched twice, along with the threshold pages of Aivosto, ESLint (20), ReSharper (20), Microsoft CA1502 (25), NDepend (15 and 30), and NASA SWEHB (15). None attributes 22 to anyone. Dropped, not shipped |
| 22 | Cognitive complexity | **No provenance found**, and no standard sets any cognitive threshold. SonarSource's own rule default is 15, which is a vendor product decision |
| 80 | Halstead difficulty | **No provenance found.** Halstead 1977 defines difficulty and sets no limit, and no source in this plugin's research attributes 80 to anyone |
| 500 | Lines per file | Traceable to the social post and to nothing else. The nearest standards figure is the informative 1000, and the normative form is a percentage. Selectable through config, labelled as the operator-list figure |
| 100 | Coverage percentage | A policy, not a standard. No standard sets a coverage percentage, and a coverage number rises whenever a line executes, with or without an assertion |
| 25 | CRAP | **Not the authors' number.** Savoia and Evans suggested 30, and said so as a starting point after "a LOT of opinions". 25 traces to no source found |
| 0 | The count-based concerns | A target of zero is a policy choice. Three of those concerns belong to other plugins, which the routing section of `SKILL.md` names with a presence gate |

Two of these numbers, 20 for cyclomatic and 1000 for lines per file, survived in the shipped
defaults because a citation exists for them, not because the empirical literature validates them.
No study reviewed in [literature.md](literature.md) supports a fixed threshold that transfers across
projects, and two of them argue against it directly.

## Why nothing here fires

The marketplace's ADR 0003 requires a measured corpus sweep before anything emits a finding
default-on. Reporting a number beside a cited reference is a measurement; deciding that the number
is a defect is a finding. This version stays on the measurement side, so no sweep is owed, no
false-positive budget is spent, and there is no `check` gate to argue with. That boundary is stated
in every audit skill's description. A future gate would need the sweep first.

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
