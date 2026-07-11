# claude-config-audit

A Claude Code plugin bundling three audit skills for one cohesive capability: keeping a repo's Claude
Code configuration healthy. Each skill answers a different question about the same surface:

| Skill | Question it answers |
|---|---|
| `/claude-config-audit:settings-audit` | Are the configuration FILES (`settings.json`, `settings.local.json`, `.mcp.json`, hooks, plugins, permissions) correct against upstream truth? |
| `/claude-config-audit:memory-health` | Is the instruction/memory layer (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`, auto-memory) healthy against official-doc criteria? |
| `/claude-config-audit:automation-deep-dive` | Is the configured automation SET the right set — are there genuine gaps, judged against the enforcement hierarchy? |

All three default to report-only; mutations (`--fix`, the `fix` action, `--implement`) require
explicit opt-in and per-item user approval.

## What each skill does

### settings-audit

Five phases: load/parse config files, validate seven categories (schema, permissions, MCP servers,
hooks, plugins, env vars, skill-listing budget), recheck against live official docs and known upstream
issues, report severity-rated findings, and optionally fix. Includes live plugin-drift detection
against each registered marketplace's upstream `marketplace.json` (ORPHAN / NEW / RENAME modes) with an
asymmetric auto-fix policy that never removes a plugin the user explicitly enabled. `settings.local.json`
is inspected structurally (key counts) only — never read or echoed.

```shell
/claude-config-audit:settings-audit              # full report-only audit
/claude-config-audit:settings-audit permissions  # one category
/claude-config-audit:settings-audit --fix        # audit, then apply approved fixes
```

### memory-health

Audits the files you write that shape Claude's behavior against a codified checklist derived from
official Claude Code documentation (line budgets, deletion test, content placement, consistency,
currency, auto-memory index integrity). A deterministic spine (script-backed checks for the MEMORY.md
index and orphan always-loaded rules) yields identical findings on identical repo state; judgment-tier
checks apply fixed criteria with model reading. Reports persist to the plugin's data directory —
they audit contributor-personal auto-memory, so they never land in the repo.

```shell
/claude-config-audit:memory-health          # audit (default)
/claude-config-audit:memory-health fix      # apply findings with per-item approval
/claude-config-audit:memory-health update   # refresh criteria from current official docs
/claude-config-audit:memory-health report   # show the last audit without re-running
```

### automation-deep-dive

Discovers automation-gap candidates (hooks, MCP servers, skills, subagents, scheduled tasks), then
deep-dives each against eight quality gates (already enforced, too slow, not scriptable, zero
incidents, already exists, YAGNI, platform mismatch, premature) with required evidence. Default
verdict is REJECT — a clean bill of health is a valid outcome.

```shell
/claude-config-audit:automation-deep-dive               # evaluate, recommend-only
/claude-config-audit:automation-deep-dive hooks         # one category
/claude-config-audit:automation-deep-dive --implement   # implement user-approved items
```

## Consumer conventions

The skills read the consuming repo's own `CLAUDE.md` / `.claude/rules/` for project-specific policy:
additional required permission patterns, documented reasons for disabled MCP servers, a custom
enforcement hierarchy, instruction-layer conventions or documented exemptions (e.g. a deliberate
CLAUDE.md line-budget overage). Nothing project-specific is baked into the plugin.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install claude-config-audit@melodic-software
```

## Configuration

No `userConfig`. State: memory-health audit reports persist under the plugin's `${CLAUDE_PLUGIN_DATA}`
directory. Network: settings-audit fetches official docs pages and each registered marketplace's
`marketplace.json` from `raw.githubusercontent.com` (read-only; a failed fetch degrades to SKIP).
Scripts require `jq`; the drift check additionally requires `curl`.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
