---
name: audit
description: "Audit Claude Code configuration files — settings.json, settings.local.json, .mcp.json, hooks, plugins, permissions, environment variables — for correctness, security, and drift against current official docs. Use when: 'audit settings', 'check config', 'check for config drift', after a Claude Code update, or when permissions, hooks, plugins, or MCP servers may be misconfigured; pass --fix to apply auto-correctable findings with confirmation."
argument-hint: "[--fix] [scope] — scope: permissions|mcp|hooks|plugins|issues|all (default: all)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Claude Code version: !`claude --version 2>/dev/null || echo "unknown"`

## Purpose

Periodic audit of Claude Code configuration files against current official documentation and the
consuming project's own conventions. Answers: "Are our settings correct, secure, complete, and up to
date?"

## Adapting to your environment (graceful degrade)

This skill is self-contained. Where a phase names an adjacent capability — a Claude Code issue-tracking
skill, an environment-bootstrap checker — treat it as optional: if your setup provides an equivalent
skill or tool, use it; otherwise follow the inline guidance here, which stands on its own.
Project-specific conventions (required permission patterns beyond the baseline, documented reasons for
disabled servers, launcher-script wrappers) come from the consuming repo's own `CLAUDE.md` and
`.claude/rules/` — read them when present; this skill does not assume them.

Two adjacent skills cover neighboring questions: the sibling `audit-automation-gaps` skill asks whether the
configured automation SET is the right set (landscape gaps); the `audit` skill in the `claude-memory`
plugin audits the instruction layer (CLAUDE.md / rules / auto-memory). This skill asks whether the
configuration FILES are correct against upstream truth.

## Arguments

Parse `$ARGUMENTS` for:

- **`--fix`**: Apply corrections automatically (with user confirmation per fix). Without this flag, report-only mode
- **Scope filter**: Limit audit to a single category. If omitted, run all categories
  - `permissions` — deny/ask/allow rules, deprecated syntax, security gaps
  - `mcp` — MCP server definitions, commands, env vars, connectivity
  - `hooks` — hook scripts exist, timeouts, matchers
  - `plugins` — enabled/disabled status, marketplace availability
  - `issues` — recheck known GitHub issues only
  - `all` — run everything (default)

## Config Files

| File | How to read | Notes |
| --- | --- | --- |
| `.claude/settings.json` | Read tool or `jq` | Project-level, checked in |
| `.claude/settings.local.json` | `jq` via Bash only | Commonly deny-listed for the Read tool because it holds tokens. Parse structure/key counts only. **Never echo secret values** |
| `.mcp.json` | Read tool or `jq` | Project-level MCP server definitions |
| `~/.claude/settings.json` | Read tool | User-level defaults (optional — check if exists) |

### Reading settings.local.json safely

Even when no deny rule blocks it, treat `settings.local.json` as secret-bearing: run
`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-structure.sh"` for key counts and
validity, never dump its contents. Supplemental jq recipes: [context/procedures.md](context/procedures.md)
"Reading settings.local.json safely".

---

## Track progress

For any full audit run (Phases 1-5), keep a phase checklist and tick each phase as it completes —
either in-response or by copying `${CLAUDE_PLUGIN_ROOT}/skills/audit/templates/checklist.md`
into wherever the consuming repo keeps working task notes. Phase 5 is SKIPPED in default report-only
mode.

---

## Phase 1: Load & Parse

Read all config files and validate basic structure.

Record the installed Claude Code version (`claude --version`) — Phase 3.2 compares issue-fix versions
against it. Then run `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-structure.sh"`
before the table below.

### 1.1 JSON validity

`Valid JSON: no` blocks further analysis.

### 1.2 Structure inventory

Map script output into the summary table:

| File | Valid JSON | Keys | Deny | Ask | Allow | Hooks | MCP Servers | Plugins |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

### 1.3 Baseline snapshot

Record script counts for before/after comparison if `--fix` is used:

- Permission rule counts (deny/ask/allow)
- MCP server count (active vs disabled)
- Hook count by event type
- Plugin count (enabled vs disabled)

---

## Phase 2: Validate

Load the audit checklist: [audit-checklist.md](reference/audit-checklist.md)

Run each category's checks. Record findings with severity ratings.

Seven categories — names + the question each answers below; **full per-check criteria in
[context/validation-categories.md](context/validation-categories.md)** (read it when running Phase 2).

- **A — Schema & Structure**: `$schema` present, no unknown keys, `mcpServers` not in `settings.local.json`
- **B — Permissions**: baseline deny/ask patterns present (list in [reference/required-permissions.md](reference/required-permissions.md), plus any additional patterns the consuming repo's own rules declare as required), no deprecated `:*`, deny-rules-in-`settings.json`-only (bug #8961)
- **C — MCP Servers**: commands resolve, `${VAR}` syntax, `disabledMcpjsonServers` match, documented disable reasons
- **D — Hooks**: paths resolve + readable, sane timeouts, valid matchers, quoted `$CLAUDE_PROJECT_DIR`, no duplicates, valid events
- **E — Plugins**: static checks (marketplace membership) + live upstream drift detection (`scripts/check-plugin-drift.sh` — ORPHAN/NEW/RENAME modes, auto-fix policy table in the context file)
- **F — Environment Variables**: documented/justified vars, secrets in `settings.local.json` only, forward-slash paths
- **G — Skill-listing budget**: `/doctor` overflow check and trim levers (description trimming, `skillOverrides`, budget settings)

---

## Phase 3: Research & Recheck

External verification against current documentation.

### 3.1 Official docs check

Fetch [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings) and compare:

- Are there new settings the project should consider adopting?
- Have any settings in use been deprecated or renamed?
- Has permission rule syntax changed?

### 3.2 GitHub issue recheck

For each issue in [known-issues.md](reference/known-issues.md), check live status
(`gh issue view <number> -R anthropics/claude-code --json state,title` — or the consuming repo's own
Claude Code issue-tracking skill if it has one). For any issue whose upstream fix has shipped at or
below the installed Claude Code version, confirm the settings-specific workaround is still needed and
recommend retiring it if not.

### 3.3 Permission syntax verification

Fetch [code.claude.com/docs/en/permissions](https://code.claude.com/docs/en/permissions) and verify:

- The project's permission patterns match current documented syntax
- No new permission types added (e.g., new tool types)
- Wildcard behavior unchanged

---

## Phase 4: Report

Present all findings as a severity-rated GFM table:

| # | Category | Severity | Finding | Current | Recommended |
| --- | --- | --- | --- | --- | --- |

### Severity guide

| Severity | Criteria |
| --- | --- |
| error | Security gap, broken config, or enforcement bypass |
| warning | Deprecated syntax, missing best practice, stale issue status |
| info | Enhancement opportunity, new feature available |

### Interactive checkpoint

**If `--fix` flag is set:** Present findings table, then ask user which items to fix. Do NOT proceed without their response.

**If report-only (no `--fix`):** Present findings table and summary. Note which items could be auto-fixed.

> "Which findings would you like me to fix? Reply with numbers, 'all', or 'skip'."

---

## Phase 5: Fix (only with `--fix` flag)

For each user-approved fix:

1. Make the edit
2. Validate JSON with `jq` after each edit
3. Report what changed

After all fixes:

- Present before/after comparison (rule counts, server counts, etc.)
- Verify all config files are still valid JSON

### Fixes the skill can apply

Auto-fixable (add `$schema`, fix `:*` syntax, add/move deny rules, plugin orphan-removal +
new-as-`false` via `scripts/fix-plugin-drift.sh --yes`) vs judgment-required (new settings from docs,
permission restructure, MCP config, orphan-`true` removal, heuristic rename) — full matrix in
[context/procedures.md](context/procedures.md) "Phase 5 — fixes the skill can apply".

---

## Required permission patterns

Category B (Phase 2) checks that the project's `.claude/settings.json` contains a security baseline of
deny/ask patterns: secret-file Read denies, destructive-git Bash denies, and a `git push` ask-gate. The
concrete list is in [reference/required-permissions.md](reference/required-permissions.md). Projects
with a stricter posture declare their additional required patterns in their own rules files — when the
consuming repo documents such a list, include it in the Category B check.

CC settings schema, MCP server shape, hook event names, and permission glob syntax are upstream
invariants documented at [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings)
and audited via the Phase 3 live doc fetch rather than asserted as fixed patterns here.

## Post-Audit

### Consumer workaround inventory

When a settings-affecting upstream issue drives a project-specific workaround (or one becomes
obsolete), record that in the consuming repo's own conventions/rules files — the plugin's bundled
[known-issues.md](reference/known-issues.md) tracks only broadly-applicable upstream issues and is
refreshed via plugin updates, not per-consumer edits.

### Suggest frequency

Based on findings count:

- 0 findings: "Config is clean. Recheck after next Claude Code major update."
- 1-3 findings: "Minor drift. Monthly recheck recommended."
- 4+ findings: "Significant drift detected. Consider running after every CC update."
