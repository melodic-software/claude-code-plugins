---
description: "When the bundled claude-api skill resolves in this session, prefer its hillclimb for sweeping model and effort over a measurable suite; this skill before that suite or its criteria exist. Answers LLM-evaluation design questions from Anthropic's evaluation guidance: success criteria (including turning a vague quality goal into a measurable target before any data exists), eval-suite design, grading methods, and the eval route for each part of a repository. Use when: an eval success criterion, metric or target is being written or rewritten, with or without data (load this before answering), 'how do I eval this', 'LLM eval', 'measure prompt quality', 'LLM judge', 'model-graded eval', 'golden answer', 'grading rubric', 'eval grading method', 'exact match vs LLM-graded', 'how many eval cases', 'evals for a service that calls the Messages API', 'evals for the whole repo'. Knowledge, not a runner; scaffolding a suite is /evals:design, and running a plugin's suite against a no-plugin baseline is /evals:plugin-eval."
argument-hint: "[question or concept]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Answer LLM-evaluation design questions from Anthropic's official guidance
---

# LLM evaluation methodology

This page states the rules; answer from it. It runs, scores, scaffolds and edits nothing.

- **Pointer**: Anthropic's evaluation guidance is read live, never from a copy here:
  [Define your success criteria](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#define-your-success-criteria),
  [Build evaluations](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#build-evaluations)
  and [Grade your evaluations](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#grade-your-evaluations);
  the evals cookbook is `anthropics/claude-cookbooks` `misc/building_evals.ipynb`.

## Where each topic lives

Fetch the section for a specific; this repository's own decisions are in the files named below.

| Topic | Read |
|---|---|
| What makes a success criterion good, hazy qualities, metrics, dimensions | [Define your success criteria](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#define-your-success-criteria) and [Common success criteria](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#common-success-criteria); the target rules are in the decision guide below |
| Eval anatomy, golden answers, edge cases, volume, generating cases | [Eval design principles](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#eval-design-principles); this repository's reading, with effort and model sweeps: [eval-design.md](reference/eval-design.md) |
| Grading ladder, LLM-grader rubrics, constrained verdicts, testing the grader first | [Grade your evaluations](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#grade-your-evaluations) and [Tips for LLM-based grading](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#tips-for-llm-based-grading) |
| Recipes: exact match, similarity, ROUGE-L, Likert, binary, ordinal | [Example evals](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#example-evals) |
| How many cases and repeats, paired comparison, error bars | [A statistical approach to model evaluations](https://www.anthropic.com/research/statistical-approach-to-model-evals) |
| Regressions on a new model, a skill the model outgrows | [Improving skill-creator](https://claude.com/blog/improving-skill-creator-test-measure-and-refine-agent-skills) |
| Improving against an existing suite with the bundled `hillclimb`: who starts it, the step map for a plugin suite, cost as the goal | [hillclimb.md](reference/hillclimb.md) |
| This repository's defaults where sources disagree: train/test split, interval method, repeat count, rubric form, and their settings | [local-decisions.md](reference/local-decisions.md) |

## Quick decision guide

- "Where do I start?" For a Claude API app, with `/claude-api build-eval` (see
  [Route by repository kind](#route-by-repository-kind)). Otherwise, define measurable success
  criteria first; evals test against them; only then iterate on prompts.
- "Is this criterion good?" It names a specific quality, a number or defined scale, a realistic
  target, and ties to a user need. The target number is realistic only when a measured baseline, a
  prior result, a benchmark, or expert review justifies it; how severe a miss would be, or that a
  grader can check the number, does not. "Good performance" fails all four.
- "Rewrite this criterion" Answer with this template, every slot filled:

  ```text
  quality: <the specific behavior measured, and the user need it serves>
  measure: <the metric: a rate, a count or a defined scale>
  trials: <the trial set and its size, for example "500 conversations">
  target: <one threshold, taken from the basis>
  basis: <measured baseline | prior result | benchmark | expert review | baseline-relative>
  ```

  Each threshold gets its own block: a second bar on the same quality, such as a stricter one for
  its worst failures, is a second block with its own `basis:`. The `basis:` slot takes one of
  those five values, and the target must follow from it. The first four count only when the user
  supplied the figure or agreement; name it. When none applies, the basis is `baseline-relative`
  and the target is a fraction of the current rate, written without inventing its value (for
  example "at most half the current rate over 500 trials"). An absolute number, zero included,
  has no place in a `baseline-relative` block, so a "never" bar is written relative too ("at most
  a tenth of the current rate of refunds sent to the wrong account"). Never write a target as a
  placeholder (X/Y/Z, "set the target later") or a bare direction ("lower than the baseline").
  Severity, or that a grader can check the number, is not a basis. Never present a made-up
  baseline figure or expert agreement as fact.
- "Which grading method?" The fastest, most reliable, most scalable that fits: code-based if the
  output can be constrained to allow it; LLM-graded for judgment; human only as a last resort.
- "Can I automate this seemingly subjective eval?" Usually. Constrain the output format,
  reformat to multiple choice, or use an LLM grader with a tight rubric and constrained verdict.
- "How many cases?" Prefer volume with automated grading over a few hand-graded showpieces;
  generate more from a baseline set with Claude, human-reviewed. Volume means cheaper grading,
  never easier cases.
- "Can I trust my LLM grader?" Only after reading samples of its verdicts against your own
  judgment; and grade with a different model than the one that generated the output.
- "How do I grade an agent?" On the environment state it left, with a grader it cannot reach;
  see [Agent evals: grader hygiene](#agent-evals-grader-hygiene).
- "One metric or several?" Several. Most use cases need multidimensional criteria (fidelity,
  safety, latency, cost); a single headline metric hides regressions.

The target-number and rewrite rules are this repository's reading of the Achievable property.

- **Pointer**: for what grounds a target, see
  <https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#define-your-success-criteria>.

## Agent evals: grader hygiene

When the thing under test is an agent that acts over many turns and changes an environment:

- Grade the outcome, the state the agent left the environment in, not the transcript's claim that
  the work is done. An agent saying the record exists is not evidence that it does; the grader
  checks the record.
- Keep graders out of the agent's reach. A check the agent can read, edit or special-case is one
  it can pass without doing the task, so graders and their expected values sit where the agent
  under test cannot change them.
- Read transcripts anyway, in samples, to catch an agent gaming a grader that passed it.

- **Pointer**: Anthropic's "Demystifying evals for AI agents" (2026-01-09)
  <https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents>. Read through a fetch
  summary with quoted sentences, not a raw-text check.

## Route by repository kind

Decide the kind from the repository, then name the route. The user starts `build-eval` and
`hillclimb`; this skill never does.

| Repository | Route |
|---|---|
| A Claude API app (its code calls Claude through the Anthropic SDK or API) | With no eval yet, the first step is `/claude-api build-eval`, which the user types. Lead the answer with it; do not lay out criteria, cases and graders by hand before it. With an eval in place, `/claude-api hillclimb` improves against it |
| A skill or plugin repository (a `.claude-plugin/plugin.json` or `SKILL.md` files) | `claude plugin eval`, through `/evals:design` to scaffold the suite and `/evals:plugin-eval` to run it |
| Both | Report both routes, each for its own part of the repository |
| No model in the loop | Say that LLM eval design does not apply, and stop |

## Boundary

- `/evals:design` interviews for criteria and scaffolds a suite; `/evals:plugin-eval` runs a
  plugin's suite against a no-plugin baseline and reads the delta; `/evals:validate` checks a
  suite's case files before a run.
- The bundled `claude-api` skill's `hillclimb` searches model, effort and prompt against a suite
  you already have. When that skill resolves in this session, prefer its `hillclimb` for the
  search itself; prefer this skill when the suite does not exist yet or its criteria are not yet
  measurable. The two chain: design here, then hand the
  suite to the search. `hillclimb` applies accepted configuration and prompt changes to the
  application under test, so never chain into a `hillclimb` run on this skill's behalf; name the
  option and let the user invoke it.
- Availability is never assumed: bundled surfaces are gated by settings, environment, plan, and
  host, so state what to do when the surface resolves, never that it is present.

- **Pointer**: for the subcommands, see
  <https://code.claude.com/docs/en/skills#work-on-claude-api-projects>; for their guides, see
  [`eval-hillclimb.md`](https://github.com/anthropics/skills/blob/main/skills/claude-api/shared/evals/eval-hillclimb.md)
  and
  [`build-eval.md`](https://github.com/anthropics/skills/blob/main/skills/claude-api/shared/evals/build-eval.md).
- **As of**: 2026-10-01
- **Recheck trigger**: the Claude API skill docs page
  (<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/claude-api-skill>) lists
  `build-eval` and `hillclimb`; then repoint there.

## Maintainer `update` action

`/evals:methodology update` is a maintainer-only drift check. Fetch each linked section, confirm
the anchor still resolves and that this page's own decisions (the decision guide, `eval-design.md`,
`local-decisions.md`) still follow from what the section says, and fix a moved anchor or a decision
the section now contradicts. `local-decisions.md` and `hillclimb.md` carry their own recheck
triggers.

## Next

- Criteria settled and a suite is to be written: `/evals:design <target>`.
- A suite's case files are written and not yet run: `/evals:validate <eval-dir>`.
- A plugin suite exists and the question is what it measures: `/evals:plugin-eval run <target>`.

## Gotchas

- This page holds decisions and pointers, not Anthropic's text. For runnable recipe code or any
  detail that must be current, fetch the linked section: its code samples and model names move with
  releases.
- Verify a claim about Anthropic's guidance by fetching the upstream section, never against this
  skill's own pages.
