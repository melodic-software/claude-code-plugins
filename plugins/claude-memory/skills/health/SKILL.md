---
name: health
description: "Audit the Claude Code instruction/memory layer — CLAUDE.md, CLAUDE.local.md, .claude/rules/, and auto-memory — against a codified checklist derived from official Claude Code documentation. Use when: 'audit CLAUDE.md', 'memory health', 'audit rules', 'is my CLAUDE.md too long', 'prune instructions', after CLAUDE.md/rules changes or a Claude Code upgrade; actions: audit (default), fix, update, report."
argument-hint: "[audit|fix|update|report] — default: audit"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Memory files: !`d=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/health/scripts/resolve-memory-dir.sh" 2>/dev/null); ls "$d"/*.md 2>/dev/null | wc -l | tr -d '\r' || echo "0"`
MEMORY.md lines: !`d=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/health/scripts/resolve-memory-dir.sh" 2>/dev/null); test -f "$d/MEMORY.md" && wc -l < "$d/MEMORY.md" | tr -d '\r' || echo "0"`
Rules files: !`find .claude/rules -name "*.md" 2>/dev/null | wc -l | tr -d '\r' || echo "0"`
CLAUDE.md lines: !`test -f CLAUDE.md && wc -l < CLAUDE.md | tr -d '\r' || echo "0"`
CLAUDE.local.md exists: !`test -f CLAUDE.local.md && echo "yes" || echo "no"`
Orphan always-loaded rules (RD1): !`bash "${CLAUDE_PLUGIN_ROOT}/skills/health/scripts/orphan-rule-check.sh" --count 2>/dev/null || echo "?"`
MEMORY.md index issues (M2): !`bash "${CLAUDE_PLUGIN_ROOT}/skills/health/scripts/memory-index-refs-check.sh" --count 2>/dev/null || echo "?"`

# Memory Health

Deterministic health check for the Claude Code instruction/memory layer. Audits files YOU write that
shape Claude's behavior — not the entire context window (MCP tools, agents, and skills are covered by
the `audit` and `automation-gaps` skills in the `claude-config` plugin).

## Scope

| Entity | Location | Loaded | Audited here |
|--------|----------|--------|-------------|
| Project instructions | `CLAUDE.md` | Every session, full | Yes |
| Local overrides | `CLAUDE.local.md` | Every session, full | Yes |
| Rules | `.claude/rules/**/*.md` | Every session (unconditional) or on-demand (path-scoped) | Yes |
| Auto-memory | `~/.claude/projects/<project>/memory/` | First 200 lines of MEMORY.md | Yes |
| Settings, hooks, MCP, agents, skills | Various | Various | No — use `claude-config`'s `audit` / `automation-gaps` |

## Argument parsing

| Argument | Action |
|----------|--------|
| *(none)* or `audit` | Run the full codified checklist against all instruction/memory files |
| `update` | Research current official docs, refresh criteria and official-guidance reference files |
| `fix` | Apply fixes for audit findings (requires prior audit, asks for approval) |
| `report` | Show last audit results without re-running |

## Determinism contract

The checklist at [reference/criteria.md](reference/criteria.md) is codified, not a subjective rubric.
Its **deterministic spine** (C1 line budget, M1 index size, the script-backed M2 index integrity and
RD1 orphan-rule checks) yields byte-identical findings on the same repo state; its **judgment tier**
(C2-C8, R1-R4, M3-M4) applies fixed criteria with model reading, so findings vary in wording though
not in criteria — label those "judgment candidate" in the report. Criteria derive from official Claude
Code documentation (sourced quotes in [reference/official-guidance.md](reference/official-guidance.md));
refresh both via the `update` action.

## Audit mode (default)

Load [context/audit.md](context/audit.md) for the full audit workflow.

## Update mode

Load [context/update.md](context/update.md) for the research-and-refresh workflow.

## Fix mode

Load [context/fix.md](context/fix.md) for the fix-with-approval workflow.

## Report mode

Read the most recent audit report from `${CLAUDE_PLUGIN_DATA}/health/last-audit.md`. If
missing, inform the user no audit has been run yet and suggest running the audit.

**Audit output is contributor-local by design.** Reports audit a contributor's personal auto-memory
(`~/.claude/projects/<project>/memory/`), which varies per team member — so they persist in the
plugin's own data directory, never in the consuming repo.

## Consumer-convention extension seam

This skill ships the doc-derived checklist only. A consuming repo that layers its own
instruction-hygiene conventions (e.g. a team-shared-first codification policy, an always-loaded
context-budget policy, or an exemption from the 200-line CLAUDE.md target for repos that deliberately
run a large rules layer) declares them in its own `CLAUDE.md` / `.claude/rules/` — read those files
during the audit and apply any additional criteria or documented exemptions they define, reporting
such findings under a `REPO` check-ID so they stay distinct from the doc-derived checks.

## Complementary workflows

If the `claude-md-management` plugin is installed, its `claude-md-improver` skill audits CLAUDE.md
structure and content quality (complementary to this health check — run this audit FIRST to identify
issues), and `revise-claude-md` captures session learnings after a fix pass. Absent that plugin, the
fix mode here stands on its own.
