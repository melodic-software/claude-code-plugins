# Research methods and instruments

Load when: choosing a user research method for a question, or writing a research instrument (a
discussion guide, a screener, a test script, a survey or an inclusive-research plan).

Confidence labels on each `Basis:` follow the plugin's research: HIGH means three or more
independent authoritative sources agree; HIGH (single source) is what one publisher states about its
own guidance; MEDIUM is one or two sources, used only as labeled judgment for a decision that is not
consequential. Every recommendation made from this file carries its `Basis:` into the deliverable
(`reference/deliverable.md`).

## Pick the method from the question

1. Write the research question in one sentence and name the decision its answer will change. A
   question no decision depends on does not need a study. Basis: judgment.
2. Choose the kind of data. Qualitative research observes people directly and finds why;
   quantitative research measures indirectly and finds how many. Guidance recommends mixing both. Basis: [nng-methods], [digital-gov], HIGH.
3. Choose generative or evaluative. Generative research learns about people, their behavior and
   their problems before a solution exists; evaluative research tests a candidate solution with
   users once one exists. Basis: judgment over MEDIUM evidence ([digital-gov]); USWDS groups the
   methods for its own design-system research this way ([uswds-research], HIGH (single source)).

| Method | Data | Kind | Answers (judgment) | Needs participants |
|---|---|---|---|---|
| Interview | qualitative | generative | goals, current behavior, problems, vocabulary | yes |
| Field study, contextual inquiry | qualitative | generative, in the person's own setting | what people actually do and what surrounds the task | yes |
| Usability test | qualitative (finding problems) or quantitative (metrics) | evaluative | whether people understand and complete tasks; where they fail | yes |
| Survey | self-reported, usually quantitative | either (judgment) | how many people hold an attitude or report a behavior | yes |
| Card sort, tree test | see `reference/flows-ia.md` | generative (card sort), evaluative (tree test) | grouping and labels; findability | yes |
| Evidence review | existing data | generative (judgment) | what analytics, search logs, support data and prior research already show | no recruiting |

Basis: [nng-methods], [digital-gov], HIGH for the Data and Kind of the interview, field study and
usability test rows and for surveys being self-reported and usually quantitative. The card sort and
tree test row: [uswds-research], HIGH (single source; USWDS describes its own research). The Answers
column, the survey's Kind and the evidence review's Kind are judgment.

## Fit the method to the app's stage

State the stage first (`reference/discovery-phase.md`, `## Stage checklist`), then pick from its
row. Basis: judgment.

| Stage | Start with | Basis |
|---|---|---|
| idea | Understand the people and the problem before building. Ask who the likely users are, what they try to achieve, how they do it now and what blocks them, through interviews, observation and a review of any evidence that exists. | [gds-discovery-phase], [uswds-principles], HIGH for understanding users before building (UK and US public-sector normative guidance); judgment for the activity list |
| greenfield | Shift to testing concepts and prototypes, and to usability testing, moderated and remote. | [gds-alpha], [nng-methods], [digital-gov], HIGH |
| existing | Review the evidence the product already produces (analytics, search logs, support data, earlier research) before recruiting; usability testing on the live product shows its current problems. | [gds-needs], [nng-secondary], HIGH for the review; judgment over MEDIUM evidence ([gds-moderated]) for testing a live product |
| legacy | No source defines a separate method set for a legacy app. Treat it as existing, and start with a UX-debt inventory (`reference/discovery-phase.md`). | judgment |

## What the agent can do without participants

- **Evidence review.** Reading analytics, search logs, support or call-center data, earlier
  research reports and published secondary research is a recognized research activity that needs
  no recruiting. Analytics and logs record real people's behavior, so they are evidence about
  users, yet GOV.UK lists this review beside interviewing and observing users, not instead of them.
  Basis: [gds-needs], [nng-secondary], HIGH.
- **Instruments.** Drafting plans, screeners, discussion guides, test scripts and surveys needs no
  participants. The plugin writes instruments only: it never recruits, contacts anyone or runs a
  session. Basis: judgment.
- **Everything else is an assumption.** A claim about users that does not come from users,
  including any synthetic-user output, is an assumption to test with real people, and the
  deliverable labels it so. Basis: [gds-needs], [nng-synthetic], [cambridge-synthetic], HIGH.

## Synthetic users

- Use simulated participants only to prepare: generate hypotheses, explore an unfamiliar user group
  as desk research, pilot a guide or study materials, draft proto-personas, and cross-check early
  open-ended questions, then verify the output against real users. Basis: [nng-synthetic],
  [cambridge-synthetic], [gsb-simulation], HIGH. The Stanford result covers US survey and
  social-science experiments, not usability tasks.
- Simulated participants are not a substitute for research with real users. Never present their
  output as a finding; label it a hypothesis to test. Basis: [nng-synthetic], [mrs-synthetic], HIGH.
  Digital twins grounded in a person's own interviews predict survey answers far better than
  persona prompts; the limit is strongest for behavior and usability (a qualifier the research
  carries with the claim above).
- Disclose the AI use in the deliverable header, as `reference/deliverable.md` requires. Basis:
  judgment.

## Writing the instruments

Each instrument opens with a methods note that names the research question, the method, the people
it is for (as criteria, never names) and the AI-use disclosure. Basis: judgment.

- **Discussion guide.** Goals, a warm-up, open questions about past behavior ("tell me about the
  last time you..."), probes, and a wrap-up. Leave out leading questions and questions about what
  someone would do in future. Pilot it with one person before the real sessions. Basis: judgment.
- **Screener.** Criteria that follow from the research question, written as behavior and context
  rather than demographics, plus the inclusion criteria from `## Inclusive research planning`.
  Basis: judgment.
- **Test script.** Tasks stated as goals in the user's own words, never as instructions naming the
  control to use. Let participants work with realistic data, their own where the session allows:
  with dummy data in place of their own, participants engage less and raise fewer contextual
  problems. Nothing a participant enters goes into the deliverable. Basis: judgment over MEDIUM
  evidence ([gds-moderated]).
- **Survey.** One construct per question, neutral wording and a balanced scale; for standardized
  usability questionnaires use `reference/measurement.md`. Basis: judgment.
- **Sample size.** Size the study to its goal; `reference/evaluation.md` covers usability tests and
  `reference/flows-ia.md` covers card sorts and tree tests. Basis: judgment.

## Inclusive research planning

Plan research with disabled people from the start, and with older people when the audience
includes them. Basis: judgment.

- Include a few people with disabilities, and older users depending on the target
  audience. Informal evaluation throughout development works better than formal testing only at
  the end. Basis: [wai-involving-users], HIGH (single source; guidance, not a standard).
- Run an initial accessibility review before user testing. Research with disabled people alone cannot show a website is accessible (WAI's
  guidance is written for the web); it is paired
  with a conformance evaluation, which belongs to `/user-interface:design` when installed. Basis:
  [wai-involving-users], HIGH (single source; guidance, not a standard).
  - **Pointer**: for who to involve, when, and how user involvement relates to conformance
    evaluation, read W3C WAI "Involving Users in Evaluating Web Accessibility" at
    <https://www.w3.org/WAI/test-evaluate/involving-users/>.
  - **As of**: 2026-10-04
  - **Recheck trigger**: WAI revises that page, or publishes involvement guidance for apps beyond
    the web.

An inclusive-research plan covers, as judgment over the WAI guidance:

| Part | What to write |
|---|---|
| Who | The disabilities, assistive technologies and digital-skill levels the audience includes, and the age range when it matters, as recruitment criteria. |
| When | Which rounds include them; every round where the audience includes them, not a final check. |
| Access | Materials in accessible formats, the participant's own device and assistive setup where possible, remote or in-person, pacing and breaks. |
| Consent | Consent and information in formats each participant can use. |
| Split | What the sessions check (can people complete the tasks) and what the conformance evaluation checks (`/user-interface:design`). |

Record disability or health details only as aggregate recruitment criteria, never per person.
Basis: judgment.

[nng-methods]: https://www.nngroup.com/articles/which-ux-research-methods/
[digital-gov]: https://digital.gov/2024/10/04/uncovering-impactful-solutions-through-user-research
[uswds-research]: https://designsystem.digital.gov/about/research/
[uswds-principles]: https://designsystem.digital.gov/design-principles/
[gds-discovery-phase]: https://www.gov.uk/service-manual/agile-delivery/how-the-discovery-phase-works
[gds-alpha]: https://www.gov.uk/service-manual/user-research/user-research-in-alpha
[gds-needs]: https://www.gov.uk/service-manual/user-research/start-by-learning-user-needs
[gds-moderated]: https://www.gov.uk/service-manual/user-research/using-moderated-usability-testing
[nng-secondary]: https://www.nngroup.com/articles/secondary-research-in-ux/
[nng-synthetic]: https://www.nngroup.com/articles/synthetic-users/
[cambridge-synthetic]: https://www.cambridge.org/core/journals/proceedings-of-the-design-society/article/can-llmdriven-synthetic-participants-help-user-research-a-case-study-in-designing-augmented-reality-for-education/27F86D08049C21D27721E4229646393E
[gsb-simulation]: https://www.gsb.stanford.edu/faculty-research/publications/large-language-models-can-predict-results-social-science-experiments
[mrs-synthetic]: https://www.mrs.org.uk/pdf/MRS_Delphi_synthetic.pdf
[wai-involving-users]: https://www.w3.org/WAI/test-evaluate/involving-users/
