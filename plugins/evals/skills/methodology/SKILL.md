---
description: "When the bundled claude-api skill resolves in this session, prefer its hillclimb for sweeping model and effort against an existing eval suite; this skill when the suite does not exist yet or its criteria are not yet measurable, before handing the suite to that search. Answers LLM-evaluation design questions from Anthropic's official evaluation guidance: success criteria, eval-suite design, grading methods, and the eval route for each part of a repository. Use when: 'define success criteria', 'how do I eval this', 'LLM eval', 'measure prompt quality', 'LLM judge', 'model-graded eval', 'golden answer', 'grading rubric', 'eval grading method', 'exact match vs LLM-graded', 'how many eval cases', 'rewrite this success criterion', 'evals for a service that calls the Messages API', 'evals for the whole repo'. Knowledge, not a runner; for scaffolding a suite use /evals:design, and for running and scoring a plugin's suite against a no-plugin baseline use /evals:plugin-eval."
argument-hint: "[question or concept]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Answer LLM-evaluation design questions from Anthropic's official guidance
---

# LLM evaluation methodology

This page states the rules; answer from it. It runs, scores, scaffolds and edits nothing.

- **Pointer**: when a specific must be current, fetch
  [Define your success criteria](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#define-your-success-criteria)
  and [Build evaluations](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#build-evaluations)
  live; the evals cookbook is `anthropics/claude-cookbooks` `misc/building_evals.ipynb`.
- **As of**: 2026-08-08 (distilled); pointer anchors verified 2026-10-11
- **Recheck trigger**: either section is retitled, moves, or changes the guidance these rules rest
  on.

## Background files

Each is background for a human reader, with its own source stamp. For runnable code, or a
specific that must be current, check the source page instead.

| Topic | File |
|---|---|
| Success criteria: the four properties, quantifying hazy qualities, metric menu, dimensions | [success-criteria.md](reference/success-criteria.md) |
| Eval anatomy, golden answers, edge-case taxonomy, volume over polish, generating cases, effort and model sweeps | [eval-design.md](reference/eval-design.md) |
| Grading ladder, LLM-grader rubrics, constrained verdicts, testing the grader first | [grading.md](reference/grading.md) |
| Recipes: exact match, cosine similarity, ROUGE-L, Likert, binary, ordinal | [recipes.md](reference/recipes.md) |
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
- "Rewrite this criterion" The rewrite carries, inline, a number or defined scale, the set of
  trials it is measured over, and a target grounded the way the Achievable property allows. When
  the user gives no data, state the target as a quantity relative to the current baseline (for
  example "at most half the current rate") over a trial set of stated size (for example "500
  conversations"), without inventing the baseline's value; "lower than the baseline" is a
  direction, not a target. Never present a made-up baseline figure or expert agreement as fact.
  X/Y/Z placeholders and "set the target later" are not a usable criterion.
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
- **As of**: 2026-10-02
- **Recheck trigger**: that section changes what it names as grounds for a target.

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
- **As of**: 2026-10-06
- **Recheck trigger**: the post is revised, or the develop-tests page above starts covering agent
  evals; then the pointer moves there.

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
  plugin's suite against a no-plugin baseline and reads the delta;
  `/skill-quality:check validate-evals` validates a skill's eval file when the `skill-quality`
  plugin is installed.
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
  [`eval-hillclimb.md`](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md)
  and
  [`build-eval.md`](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md)
  at the pinned commit.
- **As of**: 2026-10-01
- **Recheck trigger**: the Claude API skill docs page
  (<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/claude-api-skill>) lists
  `build-eval` and `hillclimb`; then repoint there.

## Maintainer `update` action

`/evals:methodology update` is a maintainer-only drift check. Re-fetch the source page (raw
markdown) and the cookbook notebook, diff against the four distilled files (success-criteria,
eval-design, grading, recipes), apply content corrections, and refresh every "fetched YYYY-MM-DD"
stamp. `local-decisions.md` and `hillclimb.md` are this repository's own records, outside the
action, with their own recheck triggers. Keep the one pointer line to `local-decisions.md` in each
distilled file through a refresh.

## Next

- Criteria settled and a suite is to be written: `/evals:design <target>`.
- A plugin suite exists and the question is what it measures: `/evals:plugin-eval run <target>`.

## Gotchas

- The reference files are a distillation with fetch-date stamps, not the source: for runnable
  recipe code or any detail that must be current, re-fetch the source page. Its code samples and
  model names move with releases.
- Do not "verify" a claim about the guidance against this skill's own spokes; the spokes are the
  derived copy. Verification means fetching the upstream page.
