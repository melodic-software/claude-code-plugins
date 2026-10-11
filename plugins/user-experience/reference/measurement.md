# Experience measurement

Load when: choosing how to measure the experience (task, attitudinal or behavioral measures), taking
a baseline, or listing the signals a tracking plan must carry.

Confidence labels on each `Basis:` follow the plugin's research: HIGH means three or more
independent authoritative sources agree; HIGH (single source) is what one publisher states about its
own guidance; MEDIUM is one or two sources, used only as labeled judgment.

## Select, never instrument

This plugin chooses measures and says which signals the data must carry. It never adds tracking
code, builds an event pipeline, defines funnels or runs experiments: those belong to the team's
product analytics, reached through the analytics tools `detect.mjs` reports. When no analytics tool
or export is visible, say which access would help (an analytics MCP server, a CLI, or an export) and
continue with task and attitudinal measures. Basis: judgment.

| This plugin | Product analytics |
|---|---|
| Choosing experience metrics (HEART, Goals-Signals-Metrics) | The event pipeline and tracking-plan implementation |
| Task measures: success, time, errors | Funnels, retention, cohorts |
| Attitudinal measures: questionnaires | Activation definitions and growth questions |
| The signals a tracking plan must capture | Experiments, guardrails and their statistics |

Basis: judgment over MEDIUM evidence: user experience measurement and product analytics share one
behavioral data layer and differ in the question asked [heart-paper], [mixpanel-analytics].

## Usability as an outcome

ISO 9241-11 defines usability as the extent to which specified users can use a system, product or
service to achieve specified goals with effectiveness, efficiency and satisfaction in a specified
context of use. Measure each part for named users, tasks and context. Basis: [iso-9241-11], HIGH
(single source) for the definition; judgment for the measuring instruction.

| Part | Task measure |
|---|---|
| Effectiveness | Task success rate; errors that stop completion |
| Efficiency | Time on task; errors and backtracks on the way |
| Satisfaction | A post-task rating and a post-study questionnaire |

Basis for the table: judgment over MEDIUM evidence; the research records the mapping from the ISO
parts to task measures as a gap.

## HEART and Goals-Signals-Metrics

HEART names five user-centered metric categories: Happiness, Engagement, Adoption, Retention and
Task success. Goals-Signals-Metrics maps each product goal to the signals that show progress and
then to metrics. Pick only the categories relevant to the product. HEART draws behavior from usage
logs and attitudes from surveys, since surveys measure attitudes well and behavior poorly. Basis:
judgment over MEDIUM evidence ([heart-paper], [kerry-rodden-heart]).

| Category | Goal | Signal | Metric | Where the data comes from |
|---|---|---|---|---|
| Task success | People renew without help | Renewal completed; support contact during renewal | Completion rate; contacts per renewal | analytics; support data |

The `Signal` column is the list handed to whoever writes the tracking plan. Basis: judgment.

## Questionnaires

Use a published questionnaire with its exact wording and scale, never a paraphrase. Basis:
judgment.

- **UMUX**: four Likert items on perceived usability. Basis: judgment over MEDIUM evidence
  ([finstad-umux]).
- **UMUX-LITE**: two items, with a published regression adjustment that aligns its scores with SUS.
  Basis: judgment over MEDIUM evidence ([lewis-umux-lite]).
- **SEQ**: one seven-point ease rating after each task, taken from its published wording. Basis:
  judgment over MEDIUM evidence ([measuringu-seq]).
- **Net Promoter Score**: when a team already tracks it, keep it as one input; do not choose it as
  the only experience metric, since its claimed superiority over other measures did not replicate
  in one study while later work finds it carries some signal. Basis: judgment over MEDIUM evidence
  ([keiningham-nps], [lee-nps]).

## Published service measures

Where the GOV.UK published performance indicators fit the app, this plugin helps define the
user-facing ones, satisfaction and task completion, for any app; the rest belong to the service
owner. Read the current list at the pointer below rather than from here. Basis: [gds-kpis], HIGH
(single source) that the list exists; judgment for the use outside UK government.

- **Pointer**: for the current list and how each indicator is defined, read the GOV.UK Service
  Manual, "Data you must publish", at
  <https://www.gov.uk/service-manual/measuring-success/data-you-must-publish>.
- **As of**: 2026-10-04
- **Recheck trigger**: GDS updates that page or the Service Standard point on publishing
  performance data.

## By stage

Basis: judgment.

| Stage | Measurement work |
|---|---|
| idea | Name the target signals and what success would look like; nothing to measure yet. |
| greenfield | Write the HEART signal list for whoever builds the tracking plan; plan task measures for the first usability tests. |
| existing | Read funnels and retention through the installed analytics tools; benchmark key tasks with task measures and UMUX-LITE or SEQ. |
| legacy | Take a baseline of the tasks a redesign will change before changing them; check the existing tracking plan against the HEART signals. |

## Hand-offs to product analytics

- Kohavi, Tang and Xu describe guardrail metrics as critical metrics that alert experimenters when
  an assumption is violated; one chapter covers sample ratio mismatch alongside other trust-related
  guardrails. Basis: [kohavi-guardrails], HIGH (single source).
- Repeatedly checking a fixed-horizon test and stopping early makes its p-values unreliable; the
  team's experimentation tool or analyst handles this. Basis: judgment over MEDIUM evidence
  ([johari-peeking]).
- "Activation" and "aha moment" are vendor and practitioner terms; no study found shows that
  reaching an activation event causes retention. Basis: judgment over MEDIUM evidence
  ([mixpanel-analytics]); see
  `reference/first-run.md`.

[heart-paper]: https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/36299.pdf
[kerry-rodden-heart]: https://kerryrodden.com/heart/
[mixpanel-analytics]: https://mixpanel.com/blog/what-is-product-management-analytics/
[iso-9241-11]: https://www.iso.org/standard/63500.html
[finstad-umux]: https://doi.org/10.1016/j.intcom.2010.04.004
[lewis-umux-lite]: https://dl.acm.org/doi/10.1145/2470654.2481287
[measuringu-seq]: https://measuringu.com/seq10/
[keiningham-nps]: https://journals.sagepub.com/doi/10.1509/jmkg.71.3.039
[lee-nps]: https://wrap.warwick.ac.uk/id/eprint/154989/1/WRAP-use-Net-Promoter-Score-(NPS)-predict-sales-growth-Lee-2021.pdf
[gds-kpis]: https://www.gov.uk/service-manual/measuring-success/data-you-must-publish
[kohavi-guardrails]: https://www.cambridge.org/core/books/trustworthy-online-controlled-experiments/D97B26382EB0EB2DC2019A7A7B518F59/listing
[johari-peeking]: https://arxiv.org/abs/1512.04922
