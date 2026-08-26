---
description: "Audit the Claude Code instruction/memory layer covering CLAUDE.md, CLAUDE.local.md, .claude/rules/, and auto-memory against a codified checklist derived from official Claude Code documentation. Use when: 'audit CLAUDE.md', 'memory health', 'audit rules', 'is my CLAUDE.md too long', 'prune instructions', after CLAUDE.md/rules changes or a Claude Code upgrade; actions: audit (default), fix, update, report."
argument-hint: "[audit|fix|update|report]. Default: audit"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Audit CLAUDE.md, rules, and auto-memory against the official-docs checklist
---

## Pre-computed context

Memory files: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/memory-dir-stats.sh" --md-count 2>/dev/null || echo "0"`
MEMORY.md loaded lines (200 cap): !`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/memory-dir-stats.sh" --memory-lines 2>/dev/null || echo "0"`
MEMORY.md loaded bytes (25KB cap): !`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/memory-dir-stats.sh" --memory-bytes 2>/dev/null || echo "0"`
Rules files: !`find .claude/rules -name "*.md" 2>/dev/null | wc -l | tr -d '\r' || echo "0"`
CLAUDE.md lines: !`test -f CLAUDE.md && wc -l < CLAUDE.md | tr -d '\r' || echo "0"`
CLAUDE.local.md exists: !`test -f CLAUDE.local.md && echo "yes" || echo "no"`
Orphan always-loaded rules (RD1): !`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/orphan-rule-check.sh" --count 2>/dev/null || echo "?"`
MEMORY.md index issues (M2): !`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/memory-index-refs-check.sh" --count 2>/dev/null || echo "?"`

# Memory Health

Deterministic health check for the Claude Code instruction/memory layer. Audits files YOU write that
shape Claude's behavior, not the entire context window (MCP tools, agents, and skills are covered by
the `audit` and `automation-gaps` skills in the `claude-config` plugin).

## Scope

| Entity | Location | Loaded | Audited here |
|--------|----------|--------|-------------|
| Project instructions | `CLAUDE.md` | Every session, full | Yes |
| Local overrides | `CLAUDE.local.md` | Every session, full | Yes |
| Rules | `.claude/rules/**/*.md` | Every session (unconditional) or on-demand (path-scoped) | Yes |
| **User instructions** | `${CLAUDE_CONFIG_DIR:-~/.claude}/CLAUDE.md` | Every session, full, in **every** project | Yes |
| **User rules** | `${CLAUDE_CONFIG_DIR:-~/.claude}/rules/**/*.md` | Same as project rules, in every project | Yes |
| Auto-memory | `~/.claude/projects/<project>/memory/` | First 200 lines / 25KB of MEMORY.md | Yes |
| Settings, hooks, MCP, agents, skills | Various | Various | No. Use `claude-config`'s `audit` / `automation-gaps` |

Auto memory's effective enabled/disabled state must be resolved before auditing it, not assumed
from a single scope: [`${CLAUDE_PLUGIN_ROOT}/skills/stateless/context/status.md`](../stateless/context/status.md),
"Resolve the effective state".

The two user-scope rows are in scope because they load in every session regardless of where it starts.
Discovery tags every file with its scope so project-scoped criteria (C9) skip personal files rather
than reporting a repo-scoped finding against one. **C6 Consistency** owns instruction-content
conflicts across that discover-instruction-surfaces population, including **user↔project** pairs.
`claude-config:audit-instructions` I15 owns memory-layer precedence adjudication and every conflict
pair with an anchor outside that population (nested `CLAUDE.md`, auto-memory, settings, hooks,
skills, agents, output styles).

## Scope boundary (route out)

This audit owns instruction-layer **health**: structure, size, placement, and index integrity of
the memory files against the codified checklist. Whether an instruction's *content* is still
needed by the current model is the model-era fit question, owned by the `claude-config` plugin's
`audit-instructions` skill. Prior-model workarounds, over-prescriptive scaffolding, bare
prohibitions without rationale, reasoning-echo directives, and stale example scaffolding fall
there. When
that plugin is installed, route such findings to `/claude-config:audit-instructions`, invoked via
the Skill tool, rather than
judging them against this checklist; when it is not installed, keep each as a criteria-free
observation in this audit's report (never a checklist finding, never silently dropped) so the
operator can weigh it against current official prompting guidance.

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
(C2-C9, R1-R4, M3-M4) applies fixed criteria with model reading, so findings vary in wording though
not in criteria. Label those "judgment candidate" in the report. Criteria derive from official Claude
Code documentation (sourced quotes in [reference/official-guidance.md](reference/official-guidance.md));
refresh both via the `update` action.

## Audit mode (default)

Load [context/audit.md](context/audit.md) for the full audit workflow.

## Update mode

Load [context/update.md](context/update.md) for the research-and-refresh workflow.

## Fix mode

Load [context/fix.md](context/fix.md) for the fix-with-approval workflow.

## Derive the report location before writing or reading

Every action that touches the report uses **one** path, resolved here: `audit` writes it, `report`
serves it, `fix` acts on it.

```
${CLAUDE_PLUGIN_DATA}/audit/<state-key>/last-audit.md
```

**Derive `<state-key>` by running this, in the project being audited:**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/lib/state-key.sh"
```

It prints `<repo-identity>/<worktree-discriminator>`, the scheme `claude-config:audit-pass` defines
and `audit-prompting-postures` already uses, adopted here rather than reinvented. Run it and use the
result: the key comes from a command this run actually executes, not from a token read out of a file.
Pass `--explain` when the report should say which rung produced its key.

**Why the key exists.** `${CLAUDE_PLUGIN_DATA}` resolves to `~/.claude/plugins/data/{id}/`, keyed to
the plugin identifier and nothing else. No project, checkout, worktree, or session segment
([plugins reference](https://code.claude.com/docs/en/plugins-reference), § Persistent data directory).
A fixed `audit/last-audit.md` is therefore **one file per machine**. Losing reports is the smaller
half; the larger half is the read. `report` mode would serve whatever that file currently holds and
`fix` mode would act on it, so on a machine with two repositories, project B can be shown project A's
findings and offered edits derived from another repository's memory layer. That is a wrong answer
served, not merely an artifact lost, which is why an append-only history does not close it and the
*path* has to carry project identity.

**Never serve a report you cannot attribute.** If nothing exists at the derived path, say that no
audit has been run **for this project** and suggest running one. Do not fall back to an unkeyed
location.

**The pre-rename `health/` directory and any unkeyed `audit/last-audit.md` are unattributable.** This
skill was once named `health`, and both older layouts wrote a machine-global file with no project
segment, so nothing records which repository produced it. It cannot be adopted into a project's key
without inventing that attribution, and inventing it is exactly the defect the key exists to remove.
Where such a file is present, name its path to the user as a leftover they may delete, and run the
audit rather than reading it.

**Audit output is contributor-local by design.** Reports audit a contributor's personal auto-memory
(`~/.claude/projects/<project>/memory/`), which varies per team member, so they persist in the
plugin's own data directory, never in the consuming repo.

**A rolling latest is a separate decision from keying, and this skill keeps one on purpose.**
`last-audit.md` is replaced by the next run *of the same project*; the report is a working artifact,
not a trend series. That is only safe because the key makes "the same project" mean something. See
[`docs/conventions/plugin-data-report-keying/`](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-data-report-keying/README.md)
for when a writer owes a per-run history instead.

## Report mode

Read the report at the derived path above and present it. When it is absent, apply the
never-serve-what-you-cannot-attribute rule above rather than reaching for another file.

## Consumer-convention extension seam

This skill ships the doc-derived checklist only. A consuming repo that layers its own
instruction-hygiene conventions (e.g. a team-shared-first codification policy, an always-loaded
context-budget policy, or an exemption from the 200-line CLAUDE.md target for repos that deliberately
run a large rules layer) declares them in its own `CLAUDE.md` / `.claude/rules/`. Read those files
during the audit and apply any additional criteria or documented exemptions they define, reporting
such findings under a `REPO` check-ID so they stay distinct from the doc-derived checks.

## Complementary workflows

If the `claude-md-management` plugin is installed, its `claude-md-improver` skill audits CLAUDE.md
structure and content quality, complementary to this health check. Run this audit FIRST to identify
issues. `revise-claude-md` captures session learnings after a fix pass. Absent that plugin, the
fix mode here stands on its own.
