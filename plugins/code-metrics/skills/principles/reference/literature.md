# Annotated bibliography

Every source this plugin cites, what it claims, what it does not claim, and how strongly it was
verified. Confidence is the level the plugin's own research pass recorded: HIGH where a primary was
downloaded and read, MEDIUM where the terminal source was a preview, a secondary, or an authority
record standing in for a paywalled body.

## McCabe 1976, cyclomatic complexity

T. J. McCabe, "A Complexity Measure", IEEE Transactions on Software Engineering SE-2(4), December
1976, pp. 308-320. Primary downloaded and full-text searched. **HIGH.**

- **Claims.** A control-flow-graph measure, `v(G) = e - n + 2p`, whose value is the number of
  linearly independent paths through a module. Reports an operational upper bound of 10 in use at
  the author's organization, with an explicit exception for a large case statement.
- **Does not claim.** That 10 is derived, optimal, or validated: the paper calls it "a reasonable,
  but not magical, upper limit". It sets no other threshold, defines no bands, and says nothing
  about maintainability or readability, only testability and module size.
- **Two propagated errors worth avoiding.** Several bibliographic aggregators render the issue as
  July 1976; the paper's own masthead says December 1976. And the author was at the Department of
  Defense, National Security Agency, not NIST; the NIST connection is twenty years later.

## Watson and McCabe 1996, NIST SP 500-235

Arthur H. Watson and Thomas J. McCabe, *Structured Testing: A Testing Methodology Using the
Cyclomatic Complexity Metric*, NIST Special Publication 500-235, September 1996. Primary downloaded
and full-text searched from two hosts. **HIGH.**

- **Claims.** Restates the metric and its variants cleanly, reaffirms "the original limit of 10 as
  proposed by McCabe", and allows that "limits as high as 15 have been used successfully as well",
  reserved for projects with six named advantages: experienced staff, formal design, a modern
  programming language, structured programming, code walkthroughs, and a comprehensive test plan.
- **Does not claim.** That 15 is unconditional. The document calls the precise limit "somewhat
  controversial" and frames the relaxation as an organization deciding it "knows what it is doing"
  and accepting the extra testing effort.
- **Also does not contain 22.** A full-text search of this document, twice, found no threshold of
  22 anywhere.

## Halstead 1977, software science

Maurice H. Halstead, *Elements of Software Science*, Elsevier North-Holland, 1977. The book itself
was not read; the origin is confirmed through an authority record and the formulas through vendor
implementation documentation. **HIGH for the formulas, HIGH for the origin via the authority
record.**

- **Claims.** A family of measures derived from counts of distinct and total operators and operands:
  vocabulary, length, volume, difficulty `D = (n1/2) * (N2/n2)`, effort `E = D * V`, and estimates of
  programming time and delivered bugs.
- **Does not claim.** Any threshold, for difficulty or for anything else. Nor does difficulty
  measure size: it carries no length term, so an implementation whose difficulty scales with file
  size is not computing this.

## Campbell, cognitive complexity

G. Ann Campbell, SonarSource S.A., *Cognitive Complexity: a new way of measuring understandability*.
The version read was 1.7, dated 29 August 2023, served from SonarSource's own site; earlier versions
of the same paper exist and were not read. **HIGH for the content of version 1.7.**

- **Claims.** That cyclomatic complexity measures testability well and maintainability poorly, that
  it predates modern language structures such as `try`/`catch` and lambdas, and that it is "of
  little use above the method level". Proposes a measure that abandons the graph model, increments
  on structures that interrupt linear reading, and penalizes nesting.
- **Does not claim.** Any threshold. The default of 15 belongs to SonarSource's rule `S3776`, a
  product decision by the same vendor, and citing the paper for that number misattributes it.

## Savoia and Evans 2007, CRAP

Alberto Savoia with Bob Evans, Agitar Labs, July 2007, and the Crap4j project FAQ. Authorial
publications read directly. **HIGH for the formula, the rename, and the suggested cutoff.**

- **Claims.** The formula `comp^2 * (1 - cov/100)^3 + comp` over basis path coverage on a 0-to-100
  scale, an initial "crappiness" cutoff of 30 chosen after debate, and, in the FAQ, the authors'
  own replacement of the expansion with "Change Risk Anti-Patterns".
- **Does not claim.** Any validation. There is no study, no dataset, and no evaluation behind the
  cutoff or the combination; the authors present it as a start and say metrics should evolve.
- The full history, including the earlier "Change Risk Analysis and Predictions" wording that still
  appears on the authors' own homepage, is in [crap.md](crap.md).

## Lewis et al. 2013, bug prediction at Google

Chris Lewis, Zhongpeng Lin, Caitlin Sadowski, Xiaoyan Zhu, Rong Ou and E. James Whitehead Jr., "Does
Bug Prediction Support Human Developers? Findings from a Google Case Study", ICSE 2013, pp. 372-381.
The quoted phrase was confirmed verbatim from Google Research's own publication record and the
mechanism from the paper's full text. **HIGH.**

- **Claims.** A bug-prediction algorithm was deployed across Google and produced "no identifiable
  change in developer behavior". The stated reason, from the paper: "unless there was an actionable
  means of removing the flag [...] developers did not find value in the bug prediction, and ignored
  it."
- **Does not claim.** That the predictions were wrong. Developers agreed the flagged files looked
  bug-prone. The null result is about behavior, not accuracy, which is exactly why it bears on how a
  metrics report is presented rather than on which metric it reports.

## Nagappan, Ball and Zeller 2006; Majumder, Mody and Menzies 2022

Two independent studies, sixteen years apart, that together carry the argument against shipping a
fixed default as validated. **MEDIUM-HIGH as sourced from abstracts, each then confirmed from an
open full text.**

- Nagappan, Ball and Zeller, "Mining Metrics to Predict Component Failures", ICSE 2006, pp. 452-461,
  across five Microsoft systems: there is no single set of complexity metrics that acts as a
  universally best defect predictor; predictors have to be fitted per project and validated against
  comparable projects.
- Majumder, Mody and Menzies, "Revisiting process versus product metrics: a large scale analysis",
  *Empirical Software Engineering* 2022, over 700 GitHub projects and 722,471 commits: it is
  "unwise to trust metric importance results from analytics in-the-small studies since those change
  dramatically when moving to analytics in-the-large".
- **Neither claims** that complexity metrics are useless, and the 2022 paper's axis is study scale
  rather than strictly project-to-project transfer. What they support is narrower and enough: a
  threshold shipped as a default is a starting point, not a validated bar.

## ISO/IEC 5055:2021 and OMG ASCQM

ISO/IEC 5055:2021, *Information technology - Software measurement - Software quality measurement -
Automated source code quality measures*, Edition 1, published 2021-03-30, adopted from the OMG
Automated Source Code Quality Measures specification. The OMG PDF (288 pages, the v1.0 text dated
October 2020) was downloaded and searched exhaustively; OMG's current release is v1.1, July 2022,
diffed for the clauses this plugin cites. Cite by version and clause, never by page number. **HIGH.**

- **Claims.** Clause 7 (normative) lists weaknesses, including 7.1.5 dead code (CWE-561), 7.1.10
  excessive cyclomatic complexity (CWE-1121), 7.1.18 redundant code (CWE-1041), and 7.1.26 an
  excessively large source file (CWE-1080). Clause 8 (normative) gives the detection patterns and
  their default measurement parameters, among them §8.2.117 cyclomatic complexity 20 and §8.2.115 a
  function size of 5% of a file's non-empty lines. Clause 6 is informative and its Table 1 carries
  the 1000-line figure.
- **Does not claim.** A 1000-line normative default, a threshold anywhere in clause 7, or any
  coverage, mutation, Halstead, or cognitive-complexity measure: a search of the full text returns
  zero hits for each of those four. It also contains no weakness for weak or unsound type
  declaration, and neither does MITRE's CWE-136 Type Errors category, whose complete membership is
  three weaknesses about mishandling types at the point of use.
- **A trap worth naming.** CISQ's public standards page describes the measures in informal prose
  labels ("High cyclomatic complexity", "Excessive component size") that are not clause titles or
  usage names. Summarizing that page produces plausible names that do not exist in the standard.

## ISO/IEC 25023:2016

ISO/IEC 25023:2016, *Systems and software engineering - SQuaRE - Measurement of system and software
product quality*. Only the official free preview was read; the normative body is paywalled.
**MEDIUM, preview-sourced.**

- **Claims, from the preview.** The clause structure, including 8.6 Reliability with 8.6.1 Maturity,
  and the measure-id grammar from which `RMa-4-S` is a well-formed id for a fourth, Specific-category
  Maturity measure.
- **Not established.** That `RMa-4-S` is named "Test coverage". The reproduction saying so is an
  unauthorized scan reached through a search summary and was never fetched. Even taken at face
  value, its measurement function counts capabilities, operational scenarios, or functions performed
  against those included in the test suites, which is not line coverage from a coverage tool.
- **Recency.** The standard is mid-revision as ISO/IEC DIS 25000-23.2, which replaces it, so any id
  quoted today may be renumbered on publication.

## Mutation-testing literature

Deliberately not summarized here. Invoke `/mutation-testing:principles` when the mutation-testing
plugin is installed; it owns the primary sources, the vocabulary, and what a surviving mutant means.
Otherwise the concern is out of this plugin's scope and nothing here substitutes for it: coverage
tells you a line executed and cannot tell you it was checked, and no measure in this plugin closes
that gap.
