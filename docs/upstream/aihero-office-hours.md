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

The rows cover the sessions of 2026-11-13 and 2026-11-20. Each disposition is an owner decision; an idea
without one is left out. The author's reports on his in-progress `chief-of-staff` skill
(2026-11-09 and 2026-11-13) and the re-check of his `software-factory` skill are in
[mattpocock-skills.md](mattpocock-skills.md), rows `chief-of-staff` and `software-factory`.

- **Pointer**: for the guest talk's research claims, read the two papers under
  [The guest talk on code health](#the-guest-talk-on-code-health) at their arXiv pages.
- **As of**: 2026-11-25
- **Recheck trigger**: a row's target lands or changes (the **Lands in** cell names it), or a new
  version of either paper appears on arXiv. Session pages are not observable events.

## Attribution table

Disposition is `take`, `adapt`, `already have`, `reject` or `watch`, with the reason.

### Factory security

| Idea | What it does | Disposition | Lands in |
|---|---|---|---|
| A model job holds no write access | The job that runs the model gets only its model credential and a read-only token; a later job with no model treats the output as untrusted and pushes it | **already have**: [ADR 0085](../adr/0085-run-org-lanes-from-ci-workflows-under-one-lanes-app-with-central-grants.md) states the rule for lane model steps. **adapt**: one repository-wide check fails a model-running job that gains a write scope, a write credential or a dependency cache; a write credential beside a model needs a new ADR | [`model-job-permissions.test.mjs`](../../.github/scripts/lib/model-job-permissions.test.mjs), beside `model-credential.mjs` and run by the affected-tests gate; landed |

### Review and the human role

| Idea | What it does | Disposition | Lands in |
|---|---|---|---|
| Judge agents by the defects their changes cause | Traces a bug back to the change and the run that made it | **adapt**: join the failure signals we already record (post-merge demotion records, silent-revert hits, reverts) to the merge-risk rating per rated commit, with the lane run on the record; the gate question in [#13657](https://github.com/melodic-software/claude-code-plugins/issues/13657) returns once the groups can be compared | [`/work-items:measure-delivery`](../../plugins/work-items/skills/measure-delivery/SKILL.md) `--merge-risk`, its "Merge-risk failures" section, which reads the rating from the lanes App marker comment; landed |
| Sample human review beyond the one-way doors | A person reads one change in ten, or a change in an area nobody has looked at lately | **reject** for this repository: a recurring manual step with no defect it is shown to catch | none |
| A factory with no person reading the code degrades | Each bad change becomes input to the next agent, so quality compounds downward | **adapt**: the unattended-merge goal stays, and a trend the owner reads is added: a weekly complexity count beside change fail rate | one line in [`/work-items:morning-brief`](../../plugins/work-items/skills/morning-brief/SKILL.md) fed by a scheduled read-only [`/code-metrics:audit`](../../plugins/code-metrics/skills/audit/SKILL.md) `complexity --all` run; not started, waits on the automation design |
| Stop an unattended merge for the owner on any high merge-risk reason | A high or critical rating holds the merge until a person reads it | **adapt**: a reason no owner decision covers goes to the owner only when it is a token or secret leak, an account compromise or a billing risk; any other reason gets one PR comment and the merge proceeds | [`merge.md`](../../plugins/source-control/skills/pull-request/reference/merge.md), the merge-risk step; landed |
| Count changes per author to find hotspots | Ranks files by who touches them | **reject**: we never measure per person; hotspots stay churn times complexity | none |
| Keep every agent session in a shared store and mine it in retros | Uploads each transcript to one bucket the retro reader can search | **reject**: transcripts stay local with no shared archive; a retro across lanes reads each lane's sessions through [`/fleet:reach`](../../plugins/fleet/skills/reach/SKILL.md) | none |

### Models and evals

| Idea | What it does | Disposition | Lands in |
|---|---|---|---|
| A/B a recurring task with a judge | Runs the task on two models; a judge picks, and the verdicts become a data set | **watch**: the evidence comes first, with no runner built: a judge from a third model with the order swapped, its verdicts kept out of production | none in this repository yet |
| Measure a model change by running both models | The same loop runs on two models and a judge compares the outputs | **adapt**: one pre-registered comparison of Opus against Sonnet on the `fix-docs` activity, two [`/evals:plugin-eval`](../../plugins/evals/skills/plugin-eval/SKILL.md) runs of the `ai-slop` `audit-fix-*` cases with a judge from neither arm, spend shown first | the mechanical-model basis in [`defaults.yaml`](../../plugins/multi-agent/reference/defaults.yaml), which records the runs on those cases, scored by deterministic graders with no judge; landed |

### Docs and memory

| Idea | What it does | Disposition | Lands in |
|---|---|---|---|
| A scheduled run finds superseded ADRs | Checks decision records on a timer and proposes retirements | **adapt**: the ADR audit and the glossary audit become two presence-gated, report-only checks in the weekly drift sweep; retiring stays a person's yes | [`drift-delta-sweep.md`](../../plugins/autonomy/reference/routines/drift-delta-sweep.md); not started, waits on the automation design |
| A refactoring playbook the agent writes for its next run | Each run records what it learned in a file later runs read | **watch**: decided with lane memory; a recipe worth repeating becomes code (a helper, a lint rule) | none in this repository yet |

### Where the factory lives

| Idea | What it does | Disposition | Lands in |
|---|---|---|---|
| The factory can live in the home repo | The hub that operates over many repositories also holds the factory's code | **reject** for lanes: each lane stays in the repository it acts on, with tokens scoped to it, and no factory or orchestrator state sits in the hub; only agent sessions start in the hub | the "Does it work in CI?" row of [aihero-home-repo-pattern.md](aihero-home-repo-pattern.md); the [loop-lane contract](../contracts/loop-lane/README.md) |
| Lanes act under a person's token | A lane pushes and comments as the person who set it up | **already have** the opposite: every lane acts as a GitHub App, never under one person's token | the [loop-lane contract](../contracts/loop-lane/README.md) |
| One tracker for work across repositories | Files every issue in one place | **already have**: each issue stays in the repository it belongs to, and a GitHub project gives the cross-repository view | the "Where do issues go?" row of [aihero-home-repo-pattern.md](aihero-home-repo-pattern.md) |

### Removing comments

| Idea | What it does | Disposition | Lands in |
|---|---|---|---|
| Sort comments into four kinds, each with an action | Deletes restating and stale comments, moves a decision to an ADR, and files an issue for a comment excusing hacky code | **already have** the sort and the deletions ([ADR 0110](../adr/0110-remove-existing-comments-without-per-deletion-approval-and-block-new-ones.md)); an excuse comment is listed as open root-cause work in the findings file, with no issue per comment | [`/code-tidying:remove-comments`](../../plugins/code-tidying/skills/remove-comments/SKILL.md) |
| A decision comment hides a domain term | A comment worth an ADR often uses a term the glossary lacks | **adapt**: when `remove-comments` sends on an ADR candidate, it also lists each term in that comment the consumer's glossary lacks, as a glossary candidate in its findings file | [`/code-tidying:remove-comments`](../../plugins/code-tidying/skills/remove-comments/SKILL.md); in progress |
| Ratchet the comment count down | Holds a count of comments and lowers it as they go | **reject**: no count; a lint on added lines blocks new comments ([ADR 0108](../adr/0108-stop-new-comments-with-a-lint-on-added-lines-and-review-not-a-count.md)) | none |
| Design code so no comment is needed | Every comment can be designed away, or else linked to an ADR | **already have**, with two kept kinds: public-API doc comments and comments on behavior an outside party forces | the keep list of [`/code-tidying:remove-comments`](../../plugins/code-tidying/skills/remove-comments/SKILL.md) |
| A comment-deletion skill per repository, run on a schedule | Repeats the cleanup as a scheduled agent | **reject**: one plugin skill serves every repository, and after the one-time bulk pass the blocking lint leaves nothing for a schedule to do | none |

## The guest talk on code health

One session played Adam Tornhill's
[GOTO Copenhagen 2026 talk](https://gotocph.com/2026/speakers/4284/adam-tornhill) on code that
agents can change safely. Its claim: agents break unhealthy code more often than healthy code, so code health
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
