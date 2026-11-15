# Upstream source: AI Hero Cohort 005, Workshop 9 "Office Hours" (Matt Pocock)

This page records what this repository takes from, adapts, already has, rejects or watches in the
**Office Hours** workshop of Matt Pocock's AI Hero cohort (Cohort 005): live question-and-answer
sessions on running a software factory, one of which played a guest talk on code health. Rows hold
our decisions and our own descriptions of each idea, under the upstream-drift convention's
[What a row may describe](../contracts/upstream-drift/README.md#what-a-row-may-describe). The
course is paid and account-gated, so no session text is recorded or linked here; the skills the
sessions discuss are public in [mattpocock/skills](https://github.com/mattpocock/skills), whose
record is [mattpocock-skills.md](mattpocock-skills.md). Earlier course units have their own
records: [aihero-course.md](aihero-course.md), [aihero-shipping-course.md](aihero-shipping-course.md),
[aihero-domain-language.md](aihero-domain-language.md), [aihero-wayfinder.md](aihero-wayfinder.md)
and [aihero-review.md](aihero-review.md).

The rows cover the two sessions of 2026-11-13. Each disposition is an owner decision of
2026-11-14; an idea without one is left out. The author's reports on his in-progress
`chief-of-staff` skill (2026-11-09 and 2026-11-13) and the re-check of his `software-factory`
skill are in [mattpocock-skills.md](mattpocock-skills.md), rows `chief-of-staff` and
`software-factory`.

- **Pointer**: for the guest talk's research claims, read the two papers under
  [The guest talk on code health](#the-guest-talk-on-code-health) at their arXiv pages.
- **As of**: 2026-11-14
- **Recheck trigger**: a row's target lands or changes (the **Lands in** cell names it), or a new
  version of either paper appears on arXiv. Session pages are not observable events.

## Attribution table

Disposition is `take`, `adapt`, `already have`, `reject` or `watch`, with the reason.

### Factory security

| Idea | What it does | Disposition | Lands in |
|---|---|---|---|
| A model job holds no write access | The job that runs the model gets only its model credential and a read-only token; a later job with no model treats the output as untrusted and pushes it | **already have**: [ADR 0085](../adr/0085-run-org-lanes-from-ci-workflows-under-one-lanes-app-with-central-grants.md) states the rule for lane model steps. **adapt**: one repository-wide check fails a model-running job that gains a write scope, a write credential or a dependency cache; a write credential beside a model needs a new ADR | a permission assertion beside [`model-credential.mjs`](../../.github/scripts/lib/model-credential.mjs), run by the affected-tests gate; not started |

### Review and the human role

| Idea | What it does | Disposition | Lands in |
|---|---|---|---|
| Judge agents by the defects their changes cause | Traces a bug back to the change and the run that made it | **adapt**: join the failure signals we already record (post-merge demotion records, silent-revert hits, reverts) to the merge-risk rating per rated commit, with the lane run on the record; the gate question in [#13657](https://github.com/melodic-software/claude-code-plugins/issues/13657) returns once the groups can be compared | the lanes App marker comment, and [`/work-items:measure-delivery`](../../plugins/work-items/skills/measure-delivery/SKILL.md) or the [`/review:merge-risk`](../../plugins/review/skills/merge-risk/SKILL.md) report; not started |
| Sample human review beyond the one-way doors | A person reads one change in ten, or a change in an area nobody has looked at lately | **reject** for this repository: a recurring manual step with no defect it is shown to catch | none |
| A factory with no person reading the code degrades | Each bad change becomes input to the next agent, so quality compounds downward | **adapt**: the unattended-merge goal stays, and a trend the owner reads is added: a weekly complexity count beside change fail rate | one line in [`/work-items:morning-brief`](../../plugins/work-items/skills/morning-brief/SKILL.md) fed by a scheduled read-only [`/code-metrics:audit`](../../plugins/code-metrics/skills/audit/SKILL.md) `complexity --all` run; not started, waits on the automation design |
| Keep every agent session in a shared store and mine it in retros | Uploads each transcript to one bucket the retro reader can search | **watch**: not adopted, and transcripts stay local; whether a shared archive adds anything over the local session audit is under research | none in this repository yet |

### Models and evals

| Idea | What it does | Disposition | Lands in |
|---|---|---|---|
| A/B a recurring task with a judge | Runs the task on two models; a judge picks, and the verdicts become a data set | **watch**: the evidence comes first, with no runner built: a judge from a third model with the order swapped, its verdicts kept out of production | none in this repository yet |
| Measure a model change by running both models | The same loop runs on two models and a judge compares the outputs | **adapt**: one pre-registered comparison of Opus against Sonnet on the `fix-docs` activity, two [`/evals:plugin-eval`](../../plugins/evals/skills/plugin-eval/SKILL.md) runs of the `ai-slop` `audit-fix-*` cases with a judge from neither arm, spend shown first | the result becomes that role's basis in [`defaults.yaml`](../../plugins/multi-agent/reference/defaults.yaml); not started |

### Docs and memory

| Idea | What it does | Disposition | Lands in |
|---|---|---|---|
| A scheduled run finds superseded ADRs | Checks decision records on a timer and proposes retirements | **adapt**: the ADR audit and the glossary audit become two presence-gated, report-only lanes of the weekly drift sweep; retiring stays a person's yes | [`drift-delta-sweep.md`](../../plugins/autonomy/reference/routines/drift-delta-sweep.md); not started, waits on the automation design |
| A refactoring playbook the agent writes for its next run | Each run records what it learned in a file later runs read | **watch**: decided with lane memory; a recipe worth repeating becomes code (a helper, a lint rule) | none in this repository yet |

## The guest talk on code health

One session played Adam Tornhill's GOTO Copenhagen 2026 talk on code that agents can change
safely. Its claim: agents break unhealthy code more often than healthy code, so code health
gates agent speed. Two papers back it, both with Tornhill as an author:

- Tornhill and Borg, "Code Red: The Business Impact of Code Quality",
  <https://arxiv.org/abs/2203.04374> (TechDebt 2022). Its abstract reports 39 proprietary
  codebases analyzed "using the CodeScene tool", with low quality code holding "15 times more
  defects than high quality code". It was submitted in March 2022, before coding agents were in common use.
- Borg, Hagatulah, Tornhill and Söderberg, "Code for Machines, Not Just Humans",
  <https://arxiv.org/abs/2601.02200> (FORGE 2026). Its abstract reports "a meaningful association
  between CodeHealth, a quality metric calibrated for human comprehension, and semantic
  preservation after AI refactoring", measured on 5,000 competitive-programming Python files.

| Idea | Disposition | Lands in |
|---|---|---|
| Let an agent climb toward a code-health score | **reject** the climb: a code-health number is a floor, never a target. **already have** the floor: [`/toolchain:ratchet`](../../plugins/toolchain/skills/ratchet/SKILL.md) holds a violation count so it cannot rise | none |
| The case study's outcome figures | **reject** as evidence: vendor-reported, not reproduced by us | this record |

The case study's figures, each vendor-reported and none reproduced by us:

- About 70% fewer AI-induced defects after the uplift (vendor-reported).
- About 45% less token waste when building later features (vendor-reported).
- About 4,000 USD of tokens as the cost of the uplift (vendor-reported).

## License notice

The course is paid content under its provider's terms; no session text, caption, image or code is
copied here. The quoted lines are from the public arXiv abstracts linked above. The public skills
repository reads MIT on the host and in [mattpocock-skills.md](mattpocock-skills.md); no text or
code from it is copied either.

- **Pointer**: when a license question arises, read the skills repository's
  [LICENSE](https://github.com/mattpocock/skills/blob/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/LICENSE).
- **As of**: 2026-11-14
- **Recheck trigger**: the skills repository's license file changes.
