---
name: design
description: "Design an evaluation suite for an LLM-based application or a Claude Code skill: interview for measurable success criteria, pick a grading method per criterion, and scaffold a criteria doc plus eval cases into the consumer repo. Use when: 'design evals', 'create an eval suite', 'scaffold evals', 'write evals for my skill', 'define success criteria for this app', 'set up LLM testing', 'build a test set for my prompt' — not for eval-design theory questions (use /evals:methodology), not for statically validating an existing evals.json (use /skill-quality:check validate-evals when installed), and it does not execute evals."
argument-hint: "[target: app | skill <name> | <path>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Interview for success criteria and scaffold an eval suite in the consumer repo
---

# Design an evaluation suite

Guides the consumer from "I want to evaluate X" to committed artifacts: a success-criteria document
and a graded eval suite. Method follows Anthropic's official evaluation guidance — load
`/evals:methodology` reference files as each phase needs them (they carry the distilled source).

## Arguments

`$ARGUMENTS` names the target. Two shapes:

- **`app`** (or a path/description of an LLM-powered feature) — evals for the consumer's own
  LLM-based application behavior.
- **`skill <name>`** — evals for a consumer-authored Claude Code skill, emitted as
  `evals/evals.json` next to that skill.

No argument → ask which target, with one example of each.

## Phase 1 — success criteria (before any cases)

Interview until each criterion is **specific, measurable, achievable, relevant**
([success-criteria.md](../methodology/reference/success-criteria.md)):

1. What does success look like, concretely? Reject unmeasurable phrasings by proposing a
   measurable rewrite ("good answers" → "≥90% of answers judged correct against their rubric").
2. Which dimensions matter? Walk the eight (fidelity, consistency, relevance/coherence,
   tone/style, privacy, context use, latency, price); keep the ones with a real user need. Most
   targets are multidimensional — press for at least fidelity plus one guardrail dimension.
3. What is achievable? Anchor each target to a baseline (current behavior, prior experiment, or a
   published benchmark); when no baseline exists, record the first run AS the baseline.

Write the result to `docs/eval-criteria/<target>.md` in the consumer repo (create the directory if
absent; respect an existing consumer convention for criteria docs if one is documented in the
consumer's own `CLAUDE.md` or rules). Each criterion: dimension, metric, target number/scale,
rationale line.

## Phase 2 — eval suite

Per criterion, pick the cheapest reliable grading method
([grading.md](../methodology/reference/grading.md), [recipes.md](../methodology/reference/recipes.md)):
code-graded where the output can be constrained to allow it; LLM-graded with a tight rubric and
constrained verdict otherwise; human grading only with stated justification.

Case authoring ([eval-design.md](../methodology/reference/eval-design.md)):

- Mirror the target's real input distribution; include edge cases explicitly — irrelevant or
  nonexistent input, overly long input, poor/harmful/irrelevant user input for chat surfaces,
  ambiguous cases.
- Every case carries a golden answer: an exact answer for code-graded cases, rubric-instructions
  for LLM/human-graded cases.
- Draft a baseline set by hand with the consumer, then offer to generate more cases from it —
  volume over polish — and have the consumer review the generated batch before it lands.

**Target = app:** scaffold `evals/<target>/cases.jsonl` (one JSON object per case: `id`, `input`,
`golden_answer`, `grading` (`exact|string_match|llm_rubric|human`), optional `rubric`) plus a
`README.md` documenting how the consumer's own tooling should run and grade them, with the grader
prompt skeleton from [grading.md](../methodology/reference/grading.md) inlined for `llm_rubric`
cases. Honor an existing consumer eval layout when one is already present — extend, don't rename.

**Target = skill:** emit `<skills-root>/<skill>/evals/evals.json` in this shape — `skill_name`,
`evals[]` of `{id, name (kebab-case), prompt, expected_output, expectations[]}` — covering
trigger/routing, the happy path, at least one refusal/guardrail, and one anti-pattern the skill
must not exhibit. When the `skill-quality` plugin is installed, validate with
`/skill-quality:check validate-evals <skill>` (its bundled schema is the contract);
otherwise state that the file follows the marketplace's evals schema and validation was skipped.

## Phase 3 — grading hygiene gate

Before finishing, confirm and record in the criteria doc:

- LLM-graded cases name a grader model DIFFERENT from the generator, constrain the verdict format,
  and instruct reasoning-then-discard.
- The consumer's first act is to sample-check grader verdicts against their own judgment before
  trusting the suite at scale.
- Re-run cost is stated (which cases are code-graded and free vs LLM-graded and metered).

## What this skill does NOT do

- **Does not execute evals.** No marketplace command runs model-graded evals; running the suite is
  the consumer's tooling (for Claude Code skills, Anthropic's `skill-creator` plugin can run skill
  evals when installed).
- Does not overwrite an existing criteria doc or eval suite without showing the diff and getting
  explicit confirmation.
- Does not invent baselines — a target with no anchor is recorded as provisional.

## Gotchas

- A consumer saying "just write some tests" still gets Phase 1 — criteria first is the method, not
  a preference; keep it to the few questions that unblock measurable targets.
- Refuse to emit an eval case with no golden answer or rubric — a case that can't be graded is not
  an eval.
