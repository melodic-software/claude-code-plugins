# Annotated bibliography

Every source this plugin cites, what it claims, what it does not claim, and how strongly the
citation is backed. HIGH means the primary text is read directly; MEDIUM means the terminal source
is a preview, a secondary, or an authority record standing in for a paywalled or unavailable body.

## McCabe 1976, cyclomatic complexity

T. J. McCabe, "A Complexity Measure", IEEE Transactions on Software Engineering SE-2(4), December
1976, pp. 308-320, DOI 10.1109/TSE.1976.233837. Primary read. **HIGH.**

- **Claims.** A control-flow-graph measure, `v(G) = e - n + 2p`, whose value is the number of
  linearly independent paths through a module, "the size of a basis set". The stated purpose is
  modularizing software so the modules are "testable and maintainable", and the paper pairs the
  measure with a testing methodology. Reports an operational upper bound of 10 in use at the
  author's organization, with an explicit exception for a large case statement.
- **Does not claim.** That 10 is derived, optimal, or validated: the paper calls it "a reasonable,
  but not magical, upper limit". It sets no other threshold, defines no bands, and offers no model
  of reading effort or nesting; that gap is what Campbell's measure addresses.
- **Two propagated errors worth avoiding.** Several bibliographic aggregators render the issue as
  July 1976; the paper's own masthead says December 1976. And the author was at the Department of
  Defense, National Security Agency, not NIST; the NIST connection is twenty years later.

## Watson and McCabe 1996, NIST SP 500-235

Arthur H. Watson and Thomas J. McCabe, *Structured Testing: A Testing Methodology Using the
Cyclomatic Complexity Metric*, NIST Special Publication 500-235, September 1996. Primary read from
NIST's own host. **HIGH.**

- **Claims.** Restates the metric and its variants, sets the number of tests a module needs equal
  to its cyclomatic complexity (basis path testing), reaffirms "the original limit of 10 as proposed
  by McCabe", and allows that "limits as high as 15 have been used successfully as well", reserved
  for projects with six named advantages: experienced staff, formal design, a modern programming
  language, structured programming, code walkthroughs, and a comprehensive test plan.
- **Does not claim.** That 15 is unconditional. The document calls the precise limit "somewhat
  controversial" and frames the relaxation as an organization deciding it "knows what it is doing"
  and accepting the extra testing effort. It shares an author with McCabe 1976, so the two are one
  authorship pool rather than independent corroboration of each other.
- **Contains no threshold of 22.**

## Halstead 1977, software science

Maurice H. Halstead, *Elements of Software Science*, Elsevier North-Holland, 1977, ISBN
0-444-00205-7. No online full text exists and the book is not read here; the bibliographic data is
confirmed through an authority record, and the formulas through independent reproductions that all
attribute them to the book: NASA NTRS N90-14803, IBM Rational Asset Analyzer documentation, and the
`radon` documentation, whose implementation computes the same difficulty as the formula on any
input. **MEDIUM for the book as a primary; HIGH for the formulas by consensus of reproductions.**

- **Claims.** A family of measures derived from counts of distinct and total operators and operands:
  vocabulary, length, volume, difficulty `D = (n1/2) * (N2/n2)`, effort `E = D * V`, and estimates of
  programming time and delivered bugs.
- **Does not claim.** Any threshold, for difficulty or for anything else. Nor does difficulty carry
  an explicit length term: it depends on the distinct-operator count and the operand-reuse ratio,
  both of which change per half when a file is split, so per-file difficulty moves on a split even
  though it does not track size.

## Campbell, cognitive complexity

G. Ann Campbell, SonarSource S.A., *Cognitive Complexity: a new way of measuring understandability*,
version 1.7, 29 August 2023, served from SonarSource's own site; earlier versions of the same paper
exist and are not the version cited. **HIGH for the content of version 1.7.**

- **Claims.** That cyclomatic complexity measures testability well and maintainability poorly, that
  it predates modern language structures such as `try`/`catch` and lambdas, and that it is "of
  little use above the method level". Proposes a measure that abandons the graph model, increments
  on structures that interrupt linear reading, and penalizes nesting. On `switch`, verbatim: "A
  switch and all its cases combined incurs a single structural increment."
- **Does not claim.** Any threshold. The default of 15 belongs to SonarSource's rule `S3776`, a
  product decision by the same vendor, and citing the paper for that number misattributes it.
  Independent implementations (gocognit, PMD's CognitiveComplexity rule) follow the same increment
  rules and cite the paper.

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
The quoted phrase is confirmed against Google Research's own publication record and the mechanism
against the paper's full text. **HIGH.**

- **Claims.** A bug-prediction algorithm was deployed across Google and produced "no identifiable
  change in developer behavior". The stated reason, from the paper: "unless there was an actionable
  means of removing the flag [...] developers did not find value in the bug prediction, and ignored
  it."
- **Does not claim.** That the predictions were wrong. Developers agreed the flagged files looked
  bug-prone. The null result is about behavior, not accuracy, which is exactly why it bears on how a
  metrics report is presented rather than on which metric it reports.

## Nagappan, Ball and Zeller 2006; Majumder, Mody and Menzies 2022

Two independent studies, sixteen years apart, that together carry the argument against shipping a
fixed default as validated. **MEDIUM-HIGH: sourced from the abstracts and confirmed against open
full texts.**

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

## Coverage and test effectiveness

Five primaries, each read from an author-hosted or publisher-hosted full text and each confirmed
against its Crossref record. They disagree with each other, and the disagreement is the finding.
**HIGH for what each paper says; the question itself is contested.**

- Inozemtseva and Holmes, "Coverage Is Not Strongly Correlated with Test Suite Effectiveness",
  ICSE 2014, DOI 10.1145/2568225.2568271. Over 31,000 suites across five Java systems: a low to
  moderate correlation between coverage and effectiveness once suite size is controlled for, and the
  conclusion that coverage "should not be used as a quality target because it is not a good
  indicator of test suite effectiveness". Effectiveness is measured as mutant kill score.
- Gopinath, Jensen and Groce, "Code Coverage for Suite Evaluation by Developers", ICSE 2014, DOI
  10.1145/2568225.2568278. In a per-project prediction setting, statement coverage predicts mutant
  kills best of the coverage criteria compared, with high correlation on the original suites.
- Kochhar, Thung and Lo, "Code Coverage and Test Suite Effectiveness: Empirical Study with Real Bugs
  in Large Systems", SANER 2015, DOI 10.1109/SANER.2015.7081877. Against 159 real bugs rather than
  mutants: coverage is "moderately to strongly correlated" with effectiveness, and the paper notes
  that mutants "do not necessarily represent real bugs".
- Jia and Harman, "An Analysis and Survey of the Development of Mutation Testing", IEEE TSE 37(5),
  2011, DOI 10.1109/TSE.2010.62: the mutation adequacy score "can be used to measure the
  effectiveness of a test set in terms of its ability to detect faults".
- Petrovic and Ivankovic, "State of Mutation Testing at Google", ICSE-SEIP 2018, DOI
  10.1145/3183519.3183521, and Petrovic, Ivankovic, Fraser and Just, "Practical Mutation Testing at
  Scale: A view from Google", IEEE TSE 48(10), 2022 (early access 2021), DOI 10.1109/TSE.2021.3107634:
  mutation analysis is "widely considered one of the strongest test-adequacy criteria". The two
  papers share an authorship pool.
- **What this plugin takes from them.** Coverage records which lines executed, not whether an
  assertion would catch a fault. Whether it predicts fault detection is contested between primaries,
  so no coverage reference ships and no coverage number is read as a quality score. Mutation
  analysis is the measure those studies use as ground truth, and it belongs to the mutation-testing
  plugin, behind the presence gate `SKILL.md` names.

## ISO/IEC 5055:2021 and OMG ASCQM

ISO/IEC 5055:2021, *Information technology - Software measurement - Software quality measurement -
Automated source code quality measures*, first edition 2021-03, is the ISO publication of the OMG
Automated Source Code Quality Measures specification v1.0 (October 2020). OMG's current release is
v1.1 (formal/2022-07-01, July 2022); the two carry identical text for every clause this plugin
cites. Both OMG-hosted PDFs are read directly. Cite by version and clause, never by page number.
**HIGH.**

- **Claims.** Clause 7 (normative) lists weaknesses, including 7.1.5 dead code (CWE-561), 7.1.10
  excessive cyclomatic complexity (CWE-1121), 7.1.18 redundant code (CWE-1041), and 7.1.26 an
  excessively large source file (CWE-1080). Clause 8 (normative) gives the detection patterns and
  their default measurement parameters, among them §8.2.117 cyclomatic complexity 20, §8.2.115 a
  function's non-empty lines with a default stated as 5% and no base named, and §8.2.116 similar
  code between two functions at 90%. Clause 6 is informative, and its §6.3 Table 1 summary rows
  carry different defaults from the patterns: 1000 lines per file for CWE-1080 and 10% for CWE-1041.
  MITRE's CWE entries corroborate the attachments from the other side through the ASCMM node IDs
  (CWE-1080 is ASCMM-MNT-8, CWE-1041 is ASCMM-MNT-19).
- **Does not claim.** A 1000-line normative default, a threshold anywhere in clause 7, or any
  coverage, mutation, Halstead, or cognitive-complexity measure: the full text contains none of
  those four. It also contains no weakness for weak or unsound type declaration, and neither does
  MITRE's CWE-136 Type Errors category, whose complete membership is three weaknesses about
  mishandling types at the point of use.
- **A trap worth naming.** CISQ's public standards page describes the measures in informal prose
  labels ("High cyclomatic complexity", "Excessive component size") that are not clause titles or
  usage names. Summarizing that page produces plausible names that do not exist in the standard.

## ISO/IEC 25023:2016

ISO/IEC 25023:2016, *Systems and software engineering - SQuaRE - Measurement of system and software
product quality*. Only the official free preview is available; the normative body is paywalled.
**MEDIUM, preview-sourced.**

- **Claims, from the preview.** The clause structure, including 8.6 Reliability with 8.6.1 Maturity,
  and the measure-id grammar from which `RMa-4-S` is a well-formed id for a fourth, Specific-category
  Maturity measure.
- **Not established.** That `RMa-4-S` is named "Test coverage". Reproductions that say so are not
  the standard's text. Even taken at face value, the measurement function they describe counts
  capabilities, operational scenarios, or functions performed against those included in the test
  suites, which is not line coverage from a coverage tool.
- **Recency.** The standard is mid-revision as ISO/IEC DIS 25000-23.2, which replaces it, so any id
  quoted today may be renumbered on publication.

## Mutation-testing literature

Deliberately not summarized beyond the coverage section above. Invoke `/mutation-testing:principles`
when the mutation-testing plugin is installed; it owns the primary sources, the vocabulary, and what
a surviving mutant means. Otherwise the concern is out of this plugin's scope and nothing here
substitutes for it: coverage tells you a line executed and cannot tell you it was checked, and no
measure in this plugin closes that gap.
