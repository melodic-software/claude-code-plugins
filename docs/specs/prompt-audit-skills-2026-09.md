# prompt-audit over every skill, 2026-09

Record of running the bundled `/claude-api prompt-audit` (Claude Code 2.1.258) over every skill in this marketplace against Claude Fable 5.1. Written so the unapplied remainder is resumable without re-auditing, so the catalog gaps it exposed are filed, and so the follow-ups ship in the same PR.

## Decay rule

Point-in-time, stamped 2026-09-02. The check is the quoted text, never the status and never the line number. If a finding's quoted source text is still present at or near the cited path, the finding is open. A quote that matches nothing has been applied, superseded, or moved.

## Contents

- [Stated assumptions](#stated-assumptions)
- [Corpus](#corpus)
- [Method](#method)
- [Results by wave](#results-by-wave)
- [Catalog gaps](#catalog-gaps)
- [Withheld findings](#withheld-findings)
- [Follow-ups](#follow-ups)

## Stated assumptions

Per prompt-audit Step 0, established from the request and the repository, not by asking.

- **Scope.** Every markdown file under `plugins/*/skills/` excluding `vendor/` and `evals/`, plus `plugins/*/agents/*.md`. Descriptions and trigger text are in scope under the guide's trigger-versus-behavior split.
- **Target model.** Claude Fable 5.1, named by the operator and the newest model the repository's own docs point at. Where the migration guide carries Opus 5 guidance with no Fable 5.1 counterpart, Opus 5 guidance applies; on conflict Fable 5.1 wins.
- **Labels.** Each finding is labeled `fleet` (reason documented model-agnostically or convergent across current model guides) or `fable-5-1` (reason specific to Claude Fable 5.1). Both are applied at high and medium confidence.
- **Repo conventions are not binding.** ADRs, CI gates, and `check-skill.sh` were updated or removed where they blocked a warranted change; a superseding ADR lists each accepted decision this audit contradicted.

## Corpus

Fresh `origin/main` at e69547e3e (2026-09-02).

| Measure | Count |
|---|---|
| Plugins | 74 |
| Skills (SKILL.md, excluding vendor and eval fixtures) | 241 |
| Skill-owned markdown files in scope | 798 |
| Lines in scope | ~115,000 |
| Agent definitions | 13 |

Greppable signals before the audit: 308 caps-emphasis words (`MUST|NEVER|ALWAYS|CRITICAL|IMPORTANT`), 245 numbered-step headers, 210 bare prohibition bullets, 162 migration-relative phrasings, 285 tracker references, 475 dated stamps, 103 Claude Code version pins, 7 retired-model mentions, 2 numeric output caps, 1 narration suppressor, 0 think-step-by-step scaffolds.

## Method

One fresh-context subagent per plugin reads the prompt-audit guide and the Fable 5.1 migration sections, audits every in-scope file of that plugin, and writes a report with one row per finding (`file:line`, quoted evidence, pattern row, why obsolete for the target, confidence, action, label, catalog row) and one proposed hunk per finding. The main session reviews each report, applies accepted hunks, updates the skill's evals when its body changed, runs `check-skill.sh` on each touched skill, bumps the plugin's patch version with a CHANGELOG line, and commits once per plugin.

Waves, ordered by usage, pipeline centrality, and signal density:

| Wave | Plugins |
|---|---|
| 1 | session-flow, planning, source-control, implementation, plus every `setup` skill as one cross-cutting lane |
| 2 | work-items, review, discovery, verification, toolchain, testing, bugs, debugging, discipline |
| 3a | claude-config, claude-ops, claude-memory, playbooks |
| 3b | skill-quality, plugin-quality, autonomy, instruction-placement, context-budget, context-guard, rate-limit-guard, guardrails, computer-use, overengineering, improvement |
| 4a | docs-hygiene, code-tidying, repo-hygiene, repo-fleet-hygiene, disk-hygiene, codebase-health, ai-slop, provenance |
| 4b | tdd, mutation-testing, event-storming, architecture, coupling, naming, domain-driven-design, mcp-tools, evals, performance, prototype, visualization, wizard, machine-health |
| 5 | knowledge, songwriting, education, adhd, ai-briefing, kindle-dedrm, context7, firecrawl, x, dometrain, miro, playwright, github, playgrounds, desktop-notification, eol-normalizer, actionlint, bash-format, biome-format, go-format, markdown-format, powershell-format, ruff-format, typos-format |

## Results by wave

(filled per wave)

## Catalog gaps

Findings whose pattern has no row in `plugins/claude-config/skills/audit-instructions/reference/criteria.md`.

(filled per wave)

## Withheld findings

Low-confidence and `flag` items, reported but not applied.

(filled per wave)

## Follow-ups

Inventoried here as they arise and shipped in the PR body verbatim.

- F1. Write one superseding ADR covering every accepted ADR decision this audit contradicted (at minimum ADR 0004 D-1 and D-3, ADR 0006's applied-set gate); decide with the operator whether ADR 0005 and ADR 0008 are also retired.
- F2. Audit the out-of-scope prompt surfaces the same way: hooks prompt text, output styles, `.claude/rules`, `CLAUDE.md`, `AGENTS.md`.
- F3. Behavior measurement beyond the wave-1 spot-check: route to `claude-config:unhobble`.
- F4. Graduate `docs/topics/prompt-audit-skills/PLAN.md` into this record and remove it before the PR (contract-slice prune gate).
