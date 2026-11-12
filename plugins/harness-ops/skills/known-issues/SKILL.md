---
description: "Lookup and tracking of known Claude product issues: GitHub bug search, service health and model quality checks, and a persistent registry of tracked issues. Use when: 'is this broken', 'any workarounds', 'troubleshoot Claude Code', 'feature behaves unexpectedly', 'scan repo for issues', 'file a bug'. Actions: status (default), search FEATURE, check-all, scan, list, quality, create."
argument-hint: "<status|search|check-all|scan|list|quality|create> [args]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Look up and track known Claude product issues, health, and workarounds
---

**Arguments.** `<status|search|check-all|scan|list|quality|create> [args]`. Full form: <action> [args]. Actions: status (default), search, check-all, scan, list, quality, create. e.g., 'search Stop hook', 'check-all', 'create bug "title"'

## Pre-computed context

Claude Code version: !`claude --version 2>/dev/null || echo "unknown"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Claude Code ships frequently. Features that worked last week may have new bugs today. This skill serves three purposes:

1. **Quick health check**. Snapshot of registry health and model quality (no args needed)
2. **Proactive search**. Find known bugs BEFORE you build on top of a feature
3. **Issue registry**. Maintain single source of truth for the Claude product GitHub issues you track, record what they block, and create follow-up work items when bugs are fixed

## Data Files

The issue registry (`registry.json`) persists in the **registry directory**. By default this is the
plugin's per-machine data directory (`${CLAUDE_PLUGIN_DATA}`, survives plugin updates). A repository
can keep the registry inside itself, git-tracked and team-shared, with `registry_dir` in its
`harness-ops.yaml` team file (convention home, default `docs/conventions`); one person can set it with
the `registry_dir` plugin option or the personal `harness-ops.local.yaml`. The personal file beats the
team file, which beats the option.

**Registry location. Apply to EVERY `registry_manager.py` invocation:** resolve it once per action,
before the first registry call:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/registry-dir.mjs" --project "${CLAUDE_PROJECT_DIR}" --user-registry-dir '${user_config.registry_dir}'
```

It prints JSON: `layer` (`default`, `userConfig`, `team` or `local`), `path` (the file that set it),
`data_dir`, and `errors`.

- `data_dir` is a path → pass `--data-dir "<data_dir>"` exactly as printed. The script has already
  checked containment and that the value holds only letters, digits, `.`, `_`, `-`, `/` and `\`, so
  nothing in it runs in the shell; do not join or normalize it yourself.
- `data_dir` is null → pass `--data-dir "${CLAUDE_PLUGIN_DATA}"`. We never trust an inherited
  `CLAUDE_PLUGIN_DATA` to be this plugin's, so the script uses one only when it names harness-ops.
  Which processes receive the variable is read live from
  [plugins manifest reference: where each variable resolves](https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves).
- `errors` is non-empty → each names a layer, file, key and value that was dropped (an uncontained
  path, a character outside that set, or a value that is not a string). Show every one to the user with the layer that won instead,
  and direct `/harness-ops:setup`. A dropped team or option value resolves to the plugin data
  directory, never to the layer below it.
- The script cannot run (no `node`) → stop the registry action and say so; do not guess a directory.

| File | Purpose | Who edits |
| --- | --- | --- |
| `<registry-dir>/registry.json` | All tracked Claude product GitHub issues with status, category, affected files, and what's blocked | Skill (on search/`scan --add`/check-all), via `scripts/registry_manager.py`. See the registry-location rule above |

Read `context/registry-schema.md` for the full `registry.json` schema and field enums.

## Action Router

The first token of `$ARGUMENTS` is the action:

| Action | Description |
| --- | --- |
| `status` | Registry stats + quality snapshot. Default with no args |
| `search` | Search GitHub Issues for bugs on one feature |
| `check-all` | Check every tracked registry issue; find newly resolved ones, create follow-up TODOs |
| `scan` | Grep the current repo for GitHub issue references and report untracked ones (read-only); `scan --add` also registers them |
| `list` | All tracked issues grouped by status and category |
| `quality` | Benchmarks + status page + recent GitHub degradation reports |
| `create` | Draft and file a GitHub issue on anthropics/claude-code in its template format |

When the first token is not an action, run `search` with the whole argument as the feature name.

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
| Claude Code | `anthropics/claude-code` | Default. Hooks, skills, settings, plugins, tools |
| Python SDK | `anthropics/anthropic-sdk-python` | Python API client issues |
| TypeScript SDK | `anthropics/anthropic-sdk-typescript` | Node.js API client issues |
| C# SDK | `anthropics/anthropic-sdk-csharp` | .NET API client issues |
| MCP Protocol | `modelcontextprotocol/python-sdk` | MCP server/client issues |
| Azure MCP | `microsoft/mcp` | Azure MCP server issues |

## Integration Points

### With your work-item tracker

- `check-all` proposes follow-up work items for resolved issues (file them with whatever
  tracker the consumer project uses, e.g. `gh issue create`, after user confirmation)
- `search` suggests monitoring items for open issues worth watching

### With the consumer project's workarounds docs

If the consumer project documents Claude Code quirks/workarounds (e.g. in `CLAUDE.md` or a
rules file), cross-reference: `search` checks findings against it, `scan` surfaces documented
issues not yet in the registry, and a resolved issue's follow-up TODO includes cleaning up the
now-obsolete workaround. Skip silently when no such doc exists.

### With plan review

When stress-testing a plan that builds on a Claude Code mechanism, run `search` for that
mechanism first. Known bugs reshape plans cheaply before implementation.

### With `/bugs:write` (if installed)

For bugs in YOUR code (not Claude Code itself), use the `bugs` plugin's skill instead;
without it, write up the defect manually. This skill covers Claude product issues only.

## Spoke paths

The `context/` files write this skill's directory as `<skill-dir>`, which is `${CLAUDE_SKILL_DIR}`.
Put that path in place of the placeholder before running a command or writing it into a brief. Those
files arrive through the Read tool as plain bytes, so a `${…}` token in them would reach the Bash
tool unsubstituted, and the Bash tool's environment has no `CLAUDE_SKILL_DIR` to expand it from.
The same table says the Bash tool's environment does not receive `CLAUDE_PLUGIN_DATA`, which the
registry-location rule relies on. Basis: the plugins reference,
<https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>.

## What This Skill Does NOT Do

- **Does not read local telemetry**. OTEL store, collector, hooks, ccusage → invoke `/harness-ops:observability` via the Skill tool
- **Does not fix bugs**. Reports and tracks them
- **Does not test features**. Searches for KNOWN issues
- **Issue creation requires explicit confirmation**. `create` action always shows draft first, never auto-files
- **Does not monitor continuously**. Re-run `check-all` periodically (e.g. from a recurring work item or schedule)
