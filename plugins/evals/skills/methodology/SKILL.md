---
name: methodology
description: "Answers LLM-evaluation design questions from Anthropic's official evaluation guidance — success criteria, eval-suite design, and grading methods for LLM-based applications and Claude Code skills. Use when: 'define success criteria', 'how do I eval this', 'LLM eval', 'measure prompt quality', 'LLM judge', 'model-graded eval', 'golden answer', 'grading rubric', 'eval grading method', 'exact match vs LLM-graded', 'how many eval cases', 'is my success criteria measurable' — knowledge (WHY/WHAT of eval design), not a runner; for scaffolding a suite use /evals:design, and no marketplace command executes model-graded evals."
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
Reference files carry per-file source stamps; re-fetch the source page for runnable code or when a
specific must be current.

## Routing table

| Query about... | Load |
|---|---|
| Success criteria: specific/measurable/achievable/relevant, quantifying hazy qualities (safety, empathy), metric menu (F1, BLEU, accuracy, latency, price), criteria dimensions, multidimensional targets | [success-criteria.md](reference/success-criteria.md) |
| Eval anatomy (input/output/golden answer/score), golden-answer-as-rubric, design principles, edge-case taxonomy, real-distribution mirroring, volume over polish, authoring vs grading cost asymmetry, generating cases with Claude | [eval-design.md](reference/eval-design.md) |
| Grading ladder (code > LLM > human), LLM-grader rubrics, constrained verdicts, reasoning-then-discard, grader-output validation, different-model grading, testing the grader first | [grading.md](reference/grading.md) |
| Concrete recipes: exact match, cosine similarity/consistency, ROUGE-L/summarization, Likert/tone, binary/privacy-leak, ordinal/context utilization | [recipes.md](reference/recipes.md) |

Load the most relevant file first; a second only if the first doesn't fully answer.

**Quick decision guide** (no file load needed):

- "Where do I start?" → Define measurable success criteria first; evals test against them; only
  then iterate on prompts.
- "Is this criterion good?" → It names a specific quality, a number or defined scale, a realistic
  target, and ties to a user need. "Good performance" fails all four.
- "Which grading method?" → The fastest, most reliable, most scalable that fits: code-based if the
  output can be constrained to allow it; LLM-graded for judgment; human only as a last resort.
- "Can I automate this seemingly subjective eval?" → Usually — constrain the output format,
  reformat to multiple choice, or use an LLM grader with a tight rubric and constrained verdict.
- "How many cases?" → Prefer volume with automated grading over a few hand-graded showpieces;
  generate more from a baseline set with Claude, human-reviewed.
- "Can I trust my LLM grader?" → Only after reading samples of its verdicts against your own
  judgment; and grade with a different model than the one that generated the output.
- "One metric or several?" → Several — most use cases need multidimensional criteria (fidelity +
  safety + latency + cost); a single headline metric hides regressions.

## Maintainer `update` action

`/evals:methodology update` — maintainer-only drift check: re-fetch the source page (raw markdown)
and the cookbook notebook, diff against the four reference files, apply content corrections, and
refresh every "fetched YYYY-MM-DD" stamp with the new date. Consumers never need this; it exists
because this skill distills a live upstream doc.

## Scope boundary

This skill is **knowledge** (WHY/WHAT of evaluation design), not **workflow**. It never runs,
scores, or scaffolds evals. To interview for criteria and scaffold an eval suite in your repo, use
`/evals:design`. To statically validate a Claude Code skill's eval file, use
`/skill-quality:skill-quality validate-evals` when the `skill-quality` plugin is installed. No
marketplace command executes model-graded evals.

## Gotchas

- The reference files are a distillation with fetch-date stamps, not the source: for runnable
  recipe code or any load-bearing specific, re-fetch the source page — its code samples and model
  names move with releases.
- Do not "verify" a claim about the guidance against this skill's own spokes; the spokes ARE the
  derived copy. Verification means fetching the upstream page.
