# prompt-audit-skills

## Brief

### TLDR

Run the bundled `/claude-api prompt-audit` over every skill in this marketplace against Claude Fable 5.1, apply the high and medium confidence findings in waves, and ship one PR with a durable record, per-plugin version bumps, updated evals, and an inventoried follow-up list.

### Goal

Every skill body, its context and reference files, and every agent definition has been audited for dated prompting patterns using `shared/prompt-audit.md` (Groups 1a to 1f, 2, 3, 4 and the keep list), with Claude Fable 5.1 as the target model. Findings at high or medium confidence are applied; low-confidence and flag items are recorded. Findings are mapped to the in-repo catalog row (`claude-config:audit-instructions` I1 to I29) where one exists so catalog gaps are visible.

### Constraints

- Target model is Claude Fable 5.1. Where the migration guide has Opus 5 guidance and no Fable 5.1 guidance, use the Opus 5 guidance; on conflict Fable 5.1 wins.
- Existing ADRs, CI gates, `check-skill.sh`, and repo conventions are not binding on the audit. When one blocks a warranted change it is updated or removed in the same commit, and a superseding ADR is written at the end for every accepted decision the audit contradicted.
- Scope is `plugins/*/skills/**/*.md` excluding `vendor/` and `evals/`, plus `plugins/*/agents/*.md`. Hooks prompt text, output styles, `.claude/rules`, `CLAUDE.md` and `AGENTS.md` are out of audit scope except for edits that codify the Group 2 history rule.
- Descriptions and trigger text are in scope under prompt-audit's own split: routing text may keep calibrated urgency; enumerated near-synonym trigger lists become intent categories; a dropped phrase that `check-skill.sh` check 3 rejects means the check is updated, not the phrase restored.
- Group 2 history narratives are applied as written: incident IDs, PR numbers, past-tense narration, pinned model names, and date-conditional guidance are removed from skill bodies. A dated verification with a recheck trigger is kept; an undated volatile claim is verified or removed.
- Findings carry a label, `fleet` or `fable-5-1`. Both labels are applied at high and medium confidence; the label is recorded so a consumer on another model can read what changed.
- Every touched plugin gets a patch version bump and a one-line CHANGELOG entry in the same commit as its hunks. One commit per plugin.
- A skill's `evals/evals.json` is updated in the same commit whenever its body changes.
- One worktree, one branch (`docs/prompt-audit-skills`), one PR.

### Acceptance criteria

- The record `docs/specs/prompt-audit-skills-2026-09.md` exists with: stated assumptions (scope, target model), corpus, per-wave findings tables (file:line, evidence, pattern, why obsolete, confidence, action, label, catalog row), applied versus withheld, catalog gaps, and a `## Follow-ups` section.
- Every skill in scope has a row in the record: findings applied, findings withheld, or `clean`.
- Execution contract, per skill: audit report written to `.work/prompt-audit-skills/reports/<plugin>.md`; accepted hunks applied; evals in step; `bash plugins/skill-quality/scripts/check-skill.sh <skill-dir>` passes (or the check was updated and its test updated); plugin commit landed with bump and CHANGELOG entry. Per wave: every plugin closed, record updated, handoff written.
- Static gates green on the branch: `scripts/affected-tests.sh --run`, `scripts/check-changelog-parity.sh --check`, `--check-bump origin/main`, `--check-preserved origin/main`, `--check-order`, `scripts/check-purged-em-dashes.sh`, markdownlint, `scripts/check-skill-precompute-compose.sh --all`.
- Behavioral spot-check recorded for wave 1's five most-used skills (session-flow handoff, orchestrate, keep-going, source-control commit, planning interview): before and after invocation on one fixture by a fresh subagent, difference described in the record.
- A path-scoped rule under `.claude/rules/` states the Group 2 history rule for `plugins/*/skills/**` and is indexed in AGENTS.md's on-demand table.
- A superseding ADR records every accepted ADR decision the audit contradicted (at minimum ADR 0004 D-1 and D-3, ADR 0006's applied-set gate).
- `docs/topics/prompt-audit-skills/PLAN.md` is graduated into the record and removed before the PR, so the contract-slice prune gate passes.
- The PR body carries the follow-up inventory verbatim from the record.

### Captured assumptions

- The bundled `claude-api` skill at Claude Code 2.1.258 is the current authority for prompt-audit; its guide and the Fable 5.1 migration sections are read from the session's bundled-skills directory.
- Local `skillUsage` counts from one machine are the usage signal; they rank session-flow, planning, and source-control first.
- Behavioral A/B across all 241 skills is not affordable; the record says so and routes behavior measurement to `claude-config:unhobble`.

### Out-of-scope

- Hooks prompt text, output styles, `.claude/rules`, `CLAUDE.md`, `AGENTS.md` as audit targets.
- Marketplace-level docs under `docs/` except the record, the new rule, the ADR, and conventions that tell skill bodies to carry archaeology.
- Pushing or opening the PR from a subagent.

### Deferred questions

- Q1 (arbiter: USER-RESERVED at PR time): whether the superseding ADR should also retire ADR 0005 and ADR 0008, decided once the audit shows what they blocked.

## Plan

(empty; execution runs directly from the Brief's execution contract)
