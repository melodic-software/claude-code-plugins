# Evaluation

Load when: judging a design, flow, journey or live app for usability problems, choosing between
inspection and usability testing, rating severity, or checking that choices are fair.

Confidence labels on each `Basis:` follow the plugin's research: HIGH means three or more
independent authoritative sources agree; HIGH (single source) is what one publisher states about its
own guidance; MEDIUM is one or two sources, used only as labeled judgment.

## Who evaluates

- When the thing to judge (a flow, journey or synthesis) was produced earlier in the same session,
  hand the evaluation to a fresh-context subagent, the plugin's evaluator agent, so the judge has
  not seen the reasoning that made it. Evaluating an existing app or another author's design runs
  inline. Basis: judgment (the plugin's own rule).
- One evaluator is not enough. Different evaluators applying the same method to the same interface
  report markedly different problems and severities; the standard remedy is several independent
  evaluators whose findings are merged. Agreement rises when tasks, procedure and problem criteria
  are fixed in advance. Basis: judgment over MEDIUM evidence ([hertzum-evaluator-effect],
  [measuringu-testing-effective]).

## Pick the method

| Method | Needs participants | Finds | Limits |
|---|---|---|---|
| Heuristic evaluation | no | problems against a heuristic set | evaluator-dependent; finds problems people may never meet |
| Cognitive walkthrough | no | where a first-time user would get stuck on a task | focuses on learnability of set tasks |
| Usability test with thinking aloud | yes | whether people understand and complete tasks, and why they fail | covers only the tasks tested |
| LLM inspection | no | candidates for the methods above | a pre-study filter only (see below) |

Basis for the table: judgment.

Inspection does not replace usability testing: sources disagree on whether expert review finds the
same problems as testing, so treat inspection findings as likely problems until people confirm
them. Basis: judgment over a conflict the research left open (NN/g against the CUE-4 comparison,
MEDIUM).

## Heuristic evaluation

- Use the heuristic sets `/user-interface:design` provides when it is installed. Otherwise cite
  Nielsen's ten usability heuristics directly. ISO 9241-110 is a set of interaction principles, not
  a heuristic set; cite it as principles. Basis: judgment (the plugin's boundary with
  `user-interface`).
  - **Pointer**: for the heuristics themselves when `/user-interface:design` is not installed, read
    Nielsen's "10 Usability Heuristics for User Interface Design" at
    <https://www.nngroup.com/articles/ten-usability-heuristics/>.
  - **As of**: 2026-10-04
  - **Recheck trigger**: NN/g revises the page or its review date moves.
- Three to five evaluators each work through the interface alone, because any one evaluator
  overlooks problems; then merge and de-duplicate their findings. Basis: judgment over MEDIUM
  evidence ([nng-heuristic-eval]).
- Rate severity 0 to 4 (not a problem, cosmetic, minor, major, catastrophe), weighing how often the
  problem occurs, its impact, whether it persists, and its effect on the market. A single
  evaluator's ratings are too unreliable; use the mean of at least three. Basis: judgment over
  MEDIUM evidence ([nng-severity]; a practitioner convention, not a validated scale).

## Cognitive walkthrough

At each action step of a task, ask four questions: will the person try to achieve the right
effect; will they notice the correct action is available; will they connect the action with the
effect they want; and will they see progress after acting. The questions may vary by interface.
Basis: judgment over MEDIUM evidence ([wharton-walkthrough], [nng-walkthrough]).

## Usability testing

- Thinking aloud, concurrent or retrospective, is the common core of task-based testing. Its known
  weaknesses are an unnatural setting, filtered speech, the facilitator's influence and the
  evaluator's interpretation. Basis: judgment over MEDIUM evidence ([nng-thinking-aloud]).
- The five-user guideline applies to finding problems in iterative rounds with one comparable user
  group, not to measuring or comparing. Five users is not a coverage guarantee: in one 60-person
  study, random groups of five found between 55% and 99% of the problems, and problems that affect
  few people are mostly missed. Basis: judgment over MEDIUM evidence ([nng-five-users],
  [faulkner-2003]).
- Write the test script with `reference/research-methods.md`; the plugin writes it and never runs
  the session. Basis: judgment.

## LLM inspection is a pre-study filter

An agent may run an inspection pass to find candidate problems before a study, never as evidence of
usability. Basis: judgment.

- Published comparisons disagree sharply on how much an LLM finds: GPT-4o found 21.2% of the
  problems experts found in one study, while a multimodal pipeline covered 73% to 77% of a master
  set (five experts, five research assistants and the model) in another, where five experts covered
  57% to 63%. The two use different ground truths. Studies also report false positives, and one
  reports severity ratings that change between runs of the same model, with no human comparison. Basis: [guerino-2025], [zhong-2025], [campos-2025], [platt-2025],
  HIGH. The samples are small, the models are GPT-4 and GPT-4o era with newer ones unmeasured, and
  two of the studies are preprints.
- A simulated walkthrough completes tasks more efficiently than people do, so it under-reports where
  people fail unless prompted for it. Basis: [synthetic-walkthrough], one preprint, carried as a
  qualifier of the claim above.
- Label each LLM-found problem "candidate (LLM inspection)" until a human evaluator or a test
  confirms it. Basis: judgment.

## Findings format

| Finding | Where | Heuristic or walkthrough question | Severity | Found by | Evidence | Recommendation |
|---|---|---|---|---|---|---|

`Found by` names the method (heuristic evaluation, walkthrough, usability test, LLM inspection) and
the evaluator role, never a person. Basis: judgment.

## Fair-choice check

Check every place the design asks a person to choose, agree or leave. This is a design check, not a
legal test: whether a design is lawful is a question for the organization's counsel, never for this
plugin. Basis: judgment.

| Check | Fails when | Basis |
|---|---|---|
| Equal weight | The option the business prefers is larger, brighter or first, and the alternative is hidden or worded to shame. | judgment |
| No after a no | The person declined and is asked again in the same session, or on every visit. | judgment |
| Exit as easy as entry | Cancelling, unsubscribing or deleting takes more steps, more channels or more effort than signing up did. | judgment, not a legal rule |
| Clear consent | Agreement is assumed from a failure to object (silence, inaction); consent must be an explicit act. | [gds-personal-info], HIGH (single source; written for UK government services) |
| Refusal still works | Saying no to an optional request blocks something that does not depend on it. | [gds-personal-info], HIGH (single source; written for UK government services) |
| Ask only what is needed | A question has no reason in the question protocol (`reference/flows-ia.md`). | [gds-personal-info], HIGH (single source; written for UK government services) |
| True picture | Prices, renewals, scarcity or deadlines are shown later than the commitment, or are not true. | judgment |
| Privacy choices in plain view | A privacy choice is harder to find, or its default less protective, than the person would expect. | judgment |

[hertzum-evaluator-effect]: https://forskning.ruc.dk/en/publications/the-evaluator-effect-a-chilling-fact-about-usability-evaluation-m/
[measuringu-testing-effective]: https://measuringu.com/testing-effective/
[nng-heuristic-eval]: https://www.nngroup.com/articles/how-to-conduct-a-heuristic-evaluation/
[nng-severity]: https://www.nngroup.com/articles/how-to-rate-the-severity-of-usability-problems/
[wharton-walkthrough]: https://www.colorado.edu/ics/sites/default/files/attached-files/93-07.pdf
[nng-walkthrough]: https://www.nngroup.com/articles/cognitive-walkthrough-workshop/
[nng-thinking-aloud]: https://www.nngroup.com/articles/thinking-aloud-the-1-usability-tool/
[nng-five-users]: https://www.nngroup.com/articles/why-you-only-need-to-test-with-5-users/
[faulkner-2003]: https://link.springer.com/article/10.3758/BF03195514
[guerino-2025]: https://arxiv.org/abs/2506.16345
[zhong-2025]: https://arxiv.org/abs/2507.02306
[campos-2025]: https://arxiv.org/abs/2510.17056
[platt-2025]: https://arxiv.org/abs/2512.04262
[synthetic-walkthrough]: https://arxiv.org/abs/2512.03568
[gds-personal-info]: https://www.gov.uk/service-manual/design/collecting-personal-information-from-users
