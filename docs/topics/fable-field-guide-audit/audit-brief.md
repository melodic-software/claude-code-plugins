# Audit brief — shared rules for tasks #1-#14

Read this before executing any S-unit audit task.

## What is being compared

- **Source**: `source-article.md` (S1-S14), a user-facing field guide written for a human
  operating Claude Code.
- **Target**: `plugins/playbooks/skills/fable-5/` — `SKILL.md` plus 13 chapters under `context/`.
  Agent-facing introspected doctrine written as standing instructions to the model.

The audience difference is load-bearing. A claim addressed to the human ("disclose your experience
level", "only merge after you pass the quiz") may have no agent-side counterpart by design. That is
a legitimate finding at the unit level, not only in the final disposition — say so explicitly rather
than forcing a gap verdict.

## Verdict vocabulary

- **covered** — the playbook states the claim, anywhere, in any wording.
- **partial** — a weaker, narrower, or differently-scoped version is present.
- **missing** — no counterpart exists.
- **contradicted** — the playbook instructs something incompatible with the claim.
- **out-of-scope (audience)** — the claim is directed at the human operator and has no meaningful
  agent-side form. Requires a one-line reason.

Every verdict carries `file:line` evidence. Absence verdicts state where you looked.

## Rules that change verdicts

1. **One home per doctrine** (`SKILL.md` meta-rule 2). A shared rule has exactly one owning section
   and other chapters cite it. Finding a claim in a chapter other than the one you expected is
   still **covered** — never a gap. Search the whole skill before declaring anything missing.
2. **Model-specific claims live in `context/opus-adaptation.md`** and nowhere else (`SKILL.md`
   "What this skill is NOT"). Do not propose adding model-behavior claims to other chapters.
3. **The playbook governs how, never what** (meta-rule 1). Proposals that encode project
   convention, task content, or user preference belong outside this skill.
4. **Silent application** (meta-rule 4). The playbook forbids narrating compliance, so absence of a
   user-visible ceremony is not evidence a rule is missing.

## Repo doctrine that binds any remediation you propose

`docs/PLUGIN-PHILOSOPHY.md` governs. The clauses that shape remediations here:

- **Design boundary** — a plugin is a reusable vertical slice that must work outside this repo and
  org. Runtime behavior never depends on publisher names, org-specific variables, repo names, or
  absolute paths.
- **Two-lane convention posture** — a convention a consumer could reasonably do differently is
  discovered and externalized as configuration, never shipped as a baked-in default. A bare
  hardcode in a skill declared agnostic is a defect.
- **Fresh-eyes checkpoints** — a step whose output judges work produced in the same context
  delegates that judgment to a fresh-context (non-fork) subagent. Relevant to any remediation you
  propose that adds a self-review step.
- **Evidence and validation** — for Claude Code behavior, fetch current official documentation in
  the same session; never rely on memory or an old summary.

## Model-name coupling — standing constraint on remediations

The operator's standing direction: skill content must not hardcode model names, because a named
model becomes drift the moment the fleet moves. The doctrine in this playbook is meant to hold
across the Claude 5 generation and beyond, not for one model.

Consequences for your findings:

- Never propose a remediation whose wording depends on a specific model name or version.
- Prefer capability- or behavior-conditioned phrasing ("when the model's default is X") over
  identity-conditioned phrasing ("Fable does X").
- If the source article's claim is *inherently* model-specific, say so and mark it as a
  model-coupling risk rather than proposing text that embeds the name.
- Report, do not resolve, any tension you find between this constraint and the playbook's existing
  structure (its name, `context/opus-adaptation.md`, and the naming exception in
  `docs/PLUGIN-PHILOSOPHY.md` that sanctions provenance-named playbooks). That tension is tracked
  separately.

## Deliverable

Findings only. No edits under `plugins/playbooks/skills/fable-5/**`. The repo is on `main` with a
clean tree; branch before any file edit lands.
