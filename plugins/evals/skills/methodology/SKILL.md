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

Distilled from a cover-to-cover reading of Anthropic's "Define success criteria and build
evaluations" (<https://platform.claude.com/docs/en/test-and-evaluate/develop-tests>) and its linked
evals cookbook (`anthropics/claude-cookbooks` `misc/building_evals.ipynb`), fetched 2026-08-08.

This page states the rules; answer from it. The reference files below are background for a human
reader, each with its own source stamp. For runnable code, or a specific that must be current,
the source page is the place to check.

## Background files

| Topic | Background for a human reader |
|---|---|
| Success criteria: specific/measurable/achievable/relevant, quantifying hazy qualities (safety, empathy), metric menu (F1, BLEU, accuracy, latency, price), criteria dimensions, multidimensional targets | [success-criteria.md](reference/success-criteria.md) |
| Eval anatomy (input/output/golden answer/score), golden-answer-as-rubric, design principles, edge-case taxonomy, real-distribution mirroring, volume over polish (volume means cheaper grading, never easier cases), authoring vs grading cost asymmetry, generating cases with Claude, effort/model sweeps as an eval axis | [eval-design.md](reference/eval-design.md) |
| Grading ladder (code > LLM > human), LLM-grader rubrics, constrained verdicts, reasoning-then-discard, grader-output validation, different-model grading, testing the grader first | [grading.md](reference/grading.md) |
| Concrete recipes: exact match, cosine similarity/consistency, ROUGE-L/summarization, Likert/tone, binary/privacy-leak, ordinal/context utilization | [recipes.md](reference/recipes.md) |
| Improving an app or skill against an existing suite with the bundled `hillclimb`: who starts it, the step map for a plugin eval suite, cost as the goal | [hillclimb.md](reference/hillclimb.md) |
| This repository's defaults where sources disagree: train/test split, interval method, repeat count, rubric form, and the settings that change them | [local-decisions.md](reference/local-decisions.md) |

**Quick decision guide**:

- "Where do I start?" → For a Claude API app, with `/claude-api build-eval` (see
  [Route by repository kind](#route-by-repository-kind)). Otherwise, define measurable success
  criteria first; evals test against them; only then iterate on prompts.
- "Is this criterion good?" → It names a specific quality, a number or defined scale, a realistic
  target, and ties to a user need. The target number is realistic only when a measured baseline, a
  prior result, a benchmark, or expert review justifies it; how severe a miss would be, or that a
  grader can check the number, does not. "Good performance" fails all four.
- "Rewrite this criterion" → The rewrite carries, inline, a number or defined scale, the set of
  trials it is measured over, and a target grounded the way the Achievable property of the
  [success-criteria page](https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#define-your-success-criteria)
  allows (as of 2026-10-02; recheck when that section changes). When the user gives no data,
  state the target as a quantity relative to the current baseline (for example "at most half the
  current rate") over a trial set of stated size (for example "500 conversations"), without
  inventing the baseline's value; "lower than the baseline" is a direction, not a target. Never
  present a made-up baseline figure or expert agreement as fact. X/Y/Z placeholders and "set the target
  later" are not a usable criterion.
- "Which grading method?" → The fastest, most reliable, most scalable that fits: code-based if the
  output can be constrained to allow it; LLM-graded for judgment; human only as a last resort.
- "Can I automate this seemingly subjective eval?" → Usually. Constrain the output format,
  reformat to multiple choice, or use an LLM grader with a tight rubric and constrained verdict.
- "How many cases?" → Prefer volume with automated grading over a few hand-graded showpieces;
  generate more from a baseline set with Claude, human-reviewed. Volume means cheaper grading,
  never easier cases.
- "Can I trust my LLM grader?" → Only after reading samples of its verdicts against your own
  judgment; and grade with a different model than the one that generated the output.
- "One metric or several?" → Several. Most use cases need multidimensional criteria (fidelity +
  safety + latency + cost); a single headline metric hides regressions.

The target-number rule is this repository's reading of the achievable property:

- **Pointer**: for what grounds a target, see
  <https://platform.claude.com/docs/en/test-and-evaluate/develop-tests#define-your-success-criteria>.
- **As of**: 2026-10-02
- **Recheck trigger**: that section changes what it names as grounds for a target.

## Maintainer `update` action

`/evals:methodology update` is a maintainer-only drift check. It re-fetches the source page (raw
markdown) and the cookbook notebook, diffs against the four reference files, applies content
corrections, and refreshes every "fetched YYYY-MM-DD" stamp with the new date. Consumers never
need this; it exists because this skill distills a live upstream doc. It re-fetches only the four
distilled files: `reference/local-decisions.md` and `reference/hillclimb.md` are this repository's
own records, outside the action, and keep their own recheck triggers. Keep the one pointer line to
`local-decisions.md` in each distilled file through a refresh.

## Route by repository kind

Decide the kind from the repository, then name the route; never start a run on the user's behalf.

| Repository | Route |
|---|---|
| A Claude API app (its code calls Claude through the Anthropic SDK or API) | With no eval yet, the first step is `/claude-api build-eval`, which the user types. Lead the answer with it; do not lay out criteria, cases and graders by hand before it. With an eval in place, `/claude-api hillclimb` improves against it |
| A skill or plugin repository (a `.claude-plugin/plugin.json` or `SKILL.md` files) | `claude plugin eval`, through `/evals:design` to scaffold the suite and `/evals:plugin-eval` to run it |
| Both | Report both routes, each for its own part of the repository |
| No model in the loop | Say that LLM eval design does not apply, and stop |

The user starts `build-eval` and `hillclimb`; this skill never does. The step map in
[reference/hillclimb.md](reference/hillclimb.md) is background for a human reader.

## Scope boundary

This skill is **knowledge** (WHY/WHAT of evaluation design), not **workflow**. It never runs,
scores, or scaffolds evals. To interview for criteria and scaffold an eval suite in your repo, use
`/evals:design`. To run a plugin's suite against a no-plugin baseline and read the delta, use
`/evals:plugin-eval`. To statically validate a Claude Code skill's eval file, use
`/skill-quality:check validate-evals` when the `skill-quality` plugin is installed.

## Boundary, the bundled `claude-api` skill

One native surface consumes the eval suites this plugin teaches you to design, and the two get
conflated when the question is "how do I find the cheapest configuration that holds my target":

- **`claude-api` (bundled skill)**: its `hillclimb` and `build-eval` subcommands. What each does is
  read at the pointer under "Availability is never assumed";
  [reference/hillclimb.md](reference/hillclimb.md) links their steps for a human reader.
- **This skill (marketplace plugin).** Knowledge about designing the suite in the first place:
  success criteria, eval anatomy, grading methods, and effort as an eval axis. It runs nothing and
  edits nothing.

**Routing.** When the bundled `claude-api` skill resolves in this session, prefer its `hillclimb`
for the search itself: sweeping model and effort against a suite you already have. Prefer this skill
when the suite does not exist yet or its criteria are not yet measurable, and `/evals:design` to
scaffold it. The two chain: design the suite here, then hand it to the search.

**Mutation gate.** `hillclimb` proposes and, when accepted, applies configuration and prompt
changes to the application under test. This skill never runs or scores an eval and never edits a
prompt, so never chain into a `hillclimb` run on this skill's behalf; name the option and let the
user invoke it.

**Availability is never assumed.** Bundled surfaces are gated by settings, environment, plan, and
host; this section states what to do when the surface resolves, never that it is present.

- **Pointer**: for the subcommands, see
  <https://code.claude.com/docs/en/skills#work-on-claude-api-projects>; for their published guides,
  see
  [`eval-hillclimb.md`](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md)
  and
  [`build-eval.md`](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md)
  at the pinned commit.
- **As of**: 2026-10-01
- **Recheck trigger**: the Claude API skill docs page
  (<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/claude-api-skill>) lists
  `build-eval` and `hillclimb`; then repoint there.

## Next

- Criteria settled and a suite is to be written: `/evals:design <target>`.
- A plugin suite exists and the question is what it measures: `/evals:plugin-eval run <target>`.

## Gotchas

- The reference files are a distillation with fetch-date stamps, not the source: for runnable
  recipe code or any detail that must be current, re-fetch the source page. Its code samples and
  model names move with releases.
- Do not "verify" a claim about the guidance against this skill's own spokes; the spokes ARE the
  derived copy. Verification means fetching the upstream page.
