---
name: known-issues
description: "Looks up and tracks known Claude product issues — searches known GitHub bugs, checks service health and model quality, and maintains a persistent registry of tracked issues. Use when: 'is this broken', 'known CC bugs', 'troubleshoot Claude Code', 'any workarounds', 'feature behaves unexpectedly', 'scan repo for issues', 'file a bug' — actions: status (default), search <feature>, check-all, scan, list, quality, create."
argument-hint: "<action> [args] — actions: status (default), search, check-all, scan, list, quality, create. e.g., 'search Stop hook', 'check-all', 'create bug \"title\"'"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Claude Code version: !`claude --version 2>/dev/null || echo "unknown"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Claude Code ships frequently. Features that worked last week may have new bugs today. This skill serves three purposes:

1. **Quick health check** — snapshot of registry health and model quality (no args needed)
2. **Proactive search** — find known bugs BEFORE you build on top of a feature
3. **Issue registry** — maintain single source of truth for the Claude product GitHub issues you track, record what they block, and create follow-up work items when bugs are fixed

## Data Files

The issue registry (`registry.json`) persists in the **registry directory**. By default this is the
plugin's per-machine data directory (`${CLAUDE_PLUGIN_DATA}`, survives plugin updates). A consumer can
instead keep the registry inside their repository — git-tracked and team-shared — by setting the
`registry_dir` plugin option (personal user configuration).

**Registry location — apply to EVERY `registry_manager.py` invocation:** the configured value is
`${user_config.registry_dir}`; the project root is `${CLAUDE_PROJECT_DIR}`.

- If `${user_config.registry_dir}` is a non-empty path → first require a contained
  project-relative value. Reject POSIX/rooted paths, Windows drive-qualified or drive-relative
  paths, UNC paths, any `..` segment with either separator, and any existing symlink path that
  resolves outside `${CLAUDE_PROJECT_DIR}`. If invalid, stop the registry action, report the
  configuration problem visibly, and direct `/claude-ops:setup`; do not join, normalize, create,
  or use the destination. If valid, pass
  `--data-dir "${CLAUDE_PROJECT_DIR}/${user_config.registry_dir}"`.
- If it is empty or still shows an unexpanded `${user_config.registry_dir}` token (option unset) → OMIT `--data-dir`; the script falls back to `${CLAUDE_PLUGIN_DATA}`.

| File | Purpose | Who edits |
| --- | --- | --- |
| `<registry-dir>/registry.json` | All tracked Claude product GitHub issues with status, category, affected files, and what's blocked | Skill (on search/scan/check-all), via `scripts/registry_manager.py` — see the registry-location rule above |

Read `context/registry-schema.md` for the full `registry.json` schema and field enums.

## Action Router

Parse `$ARGUMENTS` to extract action (first token) and remaining arguments.

| Action | Description |
| --- | --- |
| `status` | Quick health summary — registry stats + quality snapshot (DEFAULT when no args) |
| `search` | Search GitHub Issues for bugs on a specific feature (default when args look like a feature name) |
| `check-all` | Check ALL tracked registry issues — find newly resolved ones, create follow-up TODOs |
| `scan` | Grep the current repo for GitHub issue references and add missing ones to registry |
| `list` | Show all tracked issues grouped by status and category |
| `quality` | Full quality check — benchmarks + status page + recent GitHub degradation reports |
| `create` | Draft and file GitHub issue on anthropics/claude-code using their template format |

**Smart routing:**

- No `$ARGUMENTS` → `status`
- `$ARGUMENTS` starts with action keyword → that action
- `$ARGUMENTS` doesn't start with action keyword → `search` with entire argument as feature name

---

## Action: `status`

Read `context/action-status.md` for full status process and output format. DEFAULT action when no args.

---

## Action: `search`

Read `context/action-search.md` for full search process, flags, and output format.

---

## Action: `check-all`

Read `context/action-check-all.md` for full check-all process and output format.

---

## Action: `scan`

Read `context/action-scan.md` for full scan process and output format.

---

## Action: `quality`

Read `context/action-quality.md` for full quality check process, sources, and output format.

---

## Action: `list`

Read `context/action-list.md` for full list process and output format.

---

## Action: `create`

Read `context/action-create.md` for full issue creation process, mandatory gates, and safety rules.

---

## Repos Reference

| Product | Repo | When to search |
|---------|------|----------------|
| Claude Code | `anthropics/claude-code` | Default — hooks, skills, settings, plugins, tools |
| Python SDK | `anthropics/anthropic-sdk-python` | Python API client issues |
| TypeScript SDK | `anthropics/anthropic-sdk-typescript` | Node.js API client issues |
| C# SDK | `anthropics/anthropic-sdk-csharp` | .NET API client issues |
| MCP Protocol | `modelcontextprotocol/python-sdk` | MCP server/client issues |
| Azure MCP | `microsoft/mcp` | Azure MCP server issues |

## Integration Points

### With your work-item tracker

- `check-all` proposes follow-up work items for resolved issues (file them with whatever
  tracker the consumer project uses — e.g. `gh issue create` — after user confirmation)
- `search` suggests monitoring items for open issues worth watching

### With the consumer project's workarounds docs

If the consumer project documents Claude Code quirks/workarounds (e.g. in `CLAUDE.md` or a
rules file), cross-reference: `search` checks findings against it, `scan` surfaces documented
issues not yet in the registry, and a resolved issue's follow-up TODO includes cleaning up the
now-obsolete workaround. Skip silently when no such doc exists.

### With plan review

When stress-testing a plan that builds on a Claude Code mechanism, run `search` for that
mechanism first — known bugs reshape plans cheaply before implementation.

### With `/bug-report:write` (if installed)

For bugs in YOUR code (not Claude Code itself), use the `bug-report` plugin's skill instead;
without it, write up the defect manually. This skill covers Claude product issues only.

## What This Skill Does NOT Do

- **Does not read local telemetry** — OTEL store, collector, hooks, ccusage → `/observability`
- **Does not fix bugs** — reports and tracks them
- **Does not test features** — searches for KNOWN issues
- **Issue creation requires explicit confirmation** — `create` action always shows draft first, never auto-files
- **Does not monitor continuously** — re-run `check-all` periodically (e.g. from a recurring work item or schedule)
