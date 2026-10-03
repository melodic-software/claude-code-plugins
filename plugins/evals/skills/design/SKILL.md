---
description: "Design an evaluation suite for an LLM-based application or a Claude Code skill: interview for measurable success criteria, pick a grading method per criterion, and scaffold a criteria doc plus eval cases into the consumer repo. Use when: 'design evals', 'create an eval suite', 'scaffold evals', 'write evals for my skill', 'define success criteria for this app', 'set up LLM testing', 'build a test set for my prompt', 'evals for an LLM feature built on the Messages API', 'which eval route each part of a repo takes'. Not for eval-design theory questions (use /evals:methodology), not for statically validating an existing evals.json (use /skill-quality:check validate-evals when installed), and not for running or scoring a suite, which is /evals:plugin-eval and the CLI it guides."
argument-hint: "<app|skill <name>|plugin <path>>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Interview for success criteria and scaffold an eval suite in the consumer repo
---

# Design an evaluation suite

Guides the consumer from "I want to evaluate X" to committed artifacts: a success-criteria document
and a graded eval suite. Method follows Anthropic's official evaluation guidance. This page and
the `/evals:methodology` page state the rules; work from them. The methodology reference files
linked below are background for a human reader.

## Arguments

`$ARGUMENTS` names the target. Three shapes:

- **`app`** (or a path/description of an LLM-powered feature): evals for the consumer's own
  LLM-based application behavior.
- **`skill <name>`**: evals for a consumer-authored Claude Code skill, emitted as
  `evals/evals.json` next to that skill.
- **`plugin <path>`**: behavioral cases for a whole Claude Code plugin, measured against a
  no-plugin baseline. This target is not scaffolded here: hand it to `claude plugin eval init`,
  which interviews for the cases and graders and writes them in the layout its own runner reads.
  Phase 1 still applies, because criteria come before cases whoever writes them. Before the
  hand-off, say in one line: read and approve every case input before it is written, and keep raw
  transcripts out of the cases under [Transcripts](#transcripts).

No argument → ask which target, with one example of each.

## Route by repository kind

Decide the kind from the repository before Phase 1, then name the route:

| Repository | Route |
|---|---|
| A Claude API app (its code calls Claude through the Anthropic SDK or API) | The first step is `/claude-api build-eval`, which the user types; this skill never starts it. Lead the answer with it, do not run the phases below by hand before it, and stop. The `app` target below is for an LLM app that does not call Claude, or for when `/claude-api` does not resolve |
| A skill or plugin repository (a `.claude-plugin/plugin.json` or `SKILL.md` files) | Continue here with the `skill` or `plugin` target; `/evals:plugin-eval` runs a plugin suite |
| Both | Report both routes, each for its own part of the repository |
| No model in the loop | Say that LLM eval design does not apply, and stop |

Same-model reminder: `${user_config.same_model_warning}`. If it renders empty or as the literal
placeholder text, use `true`, the manifest default, and say so. When it is `true`, add one line
beside the build-eval route: give the grader a different model from the app under test.

## Phase 1: success criteria (before any cases)

Interview until each criterion is **specific, measurable, achievable, relevant**
(background: [success-criteria.md](../methodology/reference/success-criteria.md)):

1. What does success look like, concretely? Reject unmeasurable phrasings by proposing a
   measurable rewrite ("good answers" → "≥90% of answers judged correct against their rubric").
2. Which dimensions matter? Walk the eight (fidelity, consistency, relevance/coherence,
   tone/style, privacy, context use, latency, price); keep the ones with a real user need. Most
   targets are multidimensional. Press for at least fidelity plus one guardrail dimension.
3. What is achievable? Anchor each target to a baseline (current behavior, prior experiment, or a
   published benchmark); when no baseline exists, record the first run AS the baseline.

Write the result to `docs/eval-criteria/<target>.md` in the consumer repo (create the directory if
absent; respect an existing consumer convention for criteria docs if one is documented in the
consumer's own `CLAUDE.md` or rules). Each criterion: dimension, metric, target number/scale,
rationale line.

## Phase 2: eval suite

Per criterion, pick the cheapest reliable grading method (background:
[grading.md](../methodology/reference/grading.md), [recipes.md](../methodology/reference/recipes.md)):
code-graded where the output can be constrained to allow it; LLM-graded otherwise, with a rubric
of checkable pass/fail claims a grader can verify one by one and a constrained verdict (this
repository's default; background:
[rubric form](../methodology/reference/local-decisions.md#rubric-form)); human grading only with
stated justification.

Case authoring (background: [eval-design.md](../methodology/reference/eval-design.md)):

- Mirror the target's real input distribution. Include edge cases explicitly: irrelevant or
  nonexistent input, overly long input, poor/harmful/irrelevant user input for chat surfaces,
  ambiguous cases.
- Every case carries a golden answer: an exact answer for code-graded cases, rubric-instructions
  for LLM/human-graded cases.
- Draft a baseline set by hand with the consumer, then offer to generate more cases from it,
  favoring volume over polish. Volume means cheaper grading per case, never easier cases.

### Gathering cases

Take input sources in the order at the pointer below, and use the first one the consumer can use.
A transcript source is subject to [Transcripts](#transcripts) before any of its text becomes a
case.

- **Pointer**: for the source order, see
  [build-eval Step 1](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md#step-1-find-or-build-the-input-set)
  at the pinned commit.
- Correlate with <https://claude.dev/blog/automating-eval-design-and-hillclimbing#designing-examples>.
- **As of**: 2026-10-01
- **Recheck trigger**: a commit to `anthropics/skills` changes Step 1 of `build-eval.md`, or a docs
  page starts covering eval input sources; then the pointer moves there.

### Case selection

- A case is in the suite because a person can say why it is hard, or because it guards a routine
  behavior. Never pick a case only because today's model fails it.
- Write the reason down before the case lands. If no one can say why a case is hard, mark it
  `routine` or drop it.
- Every skill-eval case carries `difficulty` (`hard` or `routine`), `source` (where it came from:
  an observed failure, a rewritten transcript, a documentation example, the consumer's own
  writing) and, for a `hard` case, `why_hard`.

- **Pointer**: for task design checks on a case set, see
  [eval-audit.md section 1](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-audit.md#1-task-design).
- Correlate with <https://claude.dev/blog/automating-eval-design-and-hillclimbing#adversarial-sampling>.
- **As of**: 2026-10-01
- **Recheck trigger**: a commit to `anthropics/skills` changes section 1 of `eval-audit.md`, or a
  docs page starts covering case selection; then the pointer moves there.

### Transcripts

Check the repository's visibility before any transcript text becomes a case:
`gh repo view --json visibility --jq .visibility`. Only `PRIVATE` counts as private. `PUBLIC`,
`INTERNAL`, an error, no `gh`, or no GitHub remote all count as public.

- **Public**: no raw session or product transcript goes into a committed case. A one-to-one rewrite
  is allowed: one case per original, with every sensitive or identifying detail changed. Its
  review is the input approval below, with the identifying-details checklist.
- **Private**: for data handling, see the Step 1 pointer in [Gathering cases](#gathering-cases).

### Input approval

Every input is approved by the consumer before it is written. This covers every suite this skill
writes (a skill's `evals.json`, an app's `cases.jsonl`).

1. Write the candidate cases as a JSON array to a scratch file outside the repository.
2. Format: `${user_config.review_format}`. If it renders empty, as the literal placeholder text,
   or as any value other than `markdown` or `html`, use `markdown`, the manifest default, and say
   so. Render:
   `python3 "${CLAUDE_PLUGIN_ROOT}/skills/design/scripts/render-review.py" <cases.json> --format <format> --out <scratch file>`
   and point the consumer at the file it prints. The `html` output escapes every field; the
   [review output record](../methodology/reference/local-decisions.md#review-output) gives a
   human reader the reason this repository offers it.
3. Ask the consumer to read every case, then say whether the set is representative and what is
   missing or unneeded. State any observation about the set as counts and named cases.
4. For each one-to-one transcript rewrite, walk this checklist with the consumer and get a yes on
   each line: names of people and organizations; email addresses, phone numbers, postal
   addresses; account, order, ticket and user IDs; URLs, hostnames, IP addresses; internal
   project, product and code names; file paths carrying user names; dates and times that pin one
   event; secrets, tokens, keys; any sentence a search engine could match to the original; a rare
   combination of details that singles out one person or incident.
5. Write nothing until the consumer says yes. When they approve with changes, make the changes,
   re-render, and ask again.

- **Pointer**: for input approval, see
  [build-eval, Get the inputs approved](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md#get-the-inputs-approved).
- **As of**: 2026-10-01
- **Recheck trigger**: a commit to `anthropics/skills` changes that section of `build-eval.md`.

**Target = app:** scaffold `evals/<target>/cases.jsonl` (one JSON object per case: `id`, `input`,
`golden_answer`, `grading` (`exact|string_match|llm_rubric|human`), optional `rubric`) plus a
`README.md` documenting how the consumer's own tooling should run and grade them. For
`llm_rubric` cases the README inlines the grader prompt skeleton from
[grading.md](../methodology/reference/grading.md). Honor an existing
consumer eval layout when one is already present. Extend, don't rename.

**Target = skill:** emit `<skills-root>/<skill>/evals/evals.json` with `skill_name` and
`evals[]` of `{id, name (kebab-case), prompt, expected_output, expectations[], difficulty, source,
why_hard}` (`why_hard` on `hard` cases), covering
trigger/routing, the happy path, at least one refusal/guardrail, and one anti-pattern the skill
must not exhibit. When the `skill-quality` plugin is installed, validate with
`/skill-quality:check validate-evals <skill>` (its bundled schema is the contract);
otherwise state that the file follows the marketplace's evals schema and validation was skipped.

This file is `skill-creator`'s format, which `claude plugin eval` does not read. To measure the same
skill against a no-plugin baseline instead, wrap it in a directory carrying a minimal
`.claude-plugin/plugin.json` and run `claude plugin eval init` there; the two suites coexist and
neither is a migration of the other. Say which one the consumer is asking for before scaffolding.

An `evals/evals.json` case grades the skill's output only and has no no-skill arm. That answers
"does the output meet these expectations". A baseline arm is required when the claim is
comparative: the skill improves on what the model does without it, or the claim covers a whole
plugin (its skills, agents and hooks together). Route those to `claude plugin eval` through
`/evals:plugin-eval`; its with/without delta is the answer. Whether the skill fires is not a
delta question: the no-plugin arm has no skill to invoke, so read it from the with-arm
`tool_used: Skill` indicator, which is unscored.

Verified 2026-09-11 against <https://code.claude.com/docs/en/plugin-evals.md> and
`claude plugin eval --help` (recorded in `docs/native-surfaces.md`, the `plugin eval` entry).
Recheck when a Claude Code release changes `--ablation`'s default or which graders it excludes from scoring.

## Phase 3: grading hygiene gate

Before finishing, confirm and record in the criteria doc:

- LLM-graded cases name a grader model DIFFERENT from the generator and constrain the verdict
  format. Add a reasoning-then-discard instruction only where the grader model does not already
  think before answering; a grader with always-on thinking reasons before it decides, so an
  output-side reasoning block buys nothing and roughly doubles the output tokens every re-run
  pays for.
- Re-run cost is stated (which cases are code-graded and free vs LLM-graded and metered).

### Grader check

Check each grader before its scores are trusted. This grades sample outputs, not a suite run.

1. Grade a handful of cases with the proposed grader, using outputs the consumer supplies or
   already has. Show each verdict beside its output.
2. Ask where the consumer would have scored differently.
3. On any disagreement, revise the rubric and repeat with a fresh handful until the consumer says
   yes.
4. Record the agreement in the criteria doc: cases checked, cases where the consumer agreed, and
   the date.

Labeled set: `${user_config.labeled_grader_check}`. If it renders empty or as the literal
placeholder text, use `false`, the manifest default, and say so. When it is `true`, also have the
consumer label a larger set pass or fail on their own, grade the same set, and record the
agreement rate and every disagreement in the criteria doc.

- **Pointer**: for the grader check, see
  [build-eval, Get the grading method approved](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/build-eval.md#get-the-grading-method-approved);
  for an LLM judge, see
  [eval-audit.md, When the grader is an LLM judge](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-audit.md#when-the-grader-is-an-llm-judge).
- Correlate with <https://claude.dev/blog/automating-eval-design-and-hillclimbing#validating-the-grader>.
- **As of**: 2026-10-01
- **Recheck trigger**: a commit to `anthropics/skills` changes either section, or a docs page starts
  covering grader validation; then the pointer moves there.

## What this skill does NOT do

- **Does not run or score a suite.** Scaffolding is where this skill stops; the grader check grades
  a handful of sample outputs and nothing more. A plugin suite is run
  by `claude plugin eval`, which `/evals:plugin-eval` guides; an `evals/evals.json` is run by
  Anthropic's `skill-creator` plugin when the consumer has it, or by the consumer's own tooling for
  an app suite.
- Does not overwrite an existing criteria doc or eval suite without showing the diff and getting
  explicit confirmation.
- Does not invent baselines. A target with no anchor is recorded as provisional.

## Next

- Scaffolded an `evals/evals.json`: `/skill-quality:check validate-evals <skill>`.
- Routed a plugin target to `claude plugin eval init`: `/evals:plugin-eval`.

## Gotchas

- A consumer saying "just write some tests" still gets Phase 1. Criteria first is the method, not
  a preference. Keep it to the few questions that unblock measurable targets.
- Refuse to emit an eval case with no golden answer or rubric. A case that can't be graded is not
  an eval.
- A raw transcript stays out of a public repository's cases even when the consumer asks for it.
  Offer the one-to-one rewrite and its checklist instead.
