---
description: "Read-only report of external tools the enabled plugin fleet declares, and which of them are missing. Use when a hook says a formatter or CLI is missing, or when asking whether this machine has what the enabled plugins need. Never installs."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: operator
  summary: Report external tools the enabled fleet declares missing. Never installs.
  cadence: weekly
---

## Purpose

Answer "does this host have what the enabled plugins need?" Read `prerequisites.json` in each enabled plugin, probe each declared binary, and print one table. Do not install, download, or run `npx`.

**Claim:** the fleet check lives here, not as a `deps` action on `plugins` and not as a machine-health category. `plugins` brings marketplace versions current and is `disable-model-invocation: true`. This question is read-only and model-invocable. Each plugin that needs a binary declares it in `prerequisites.json` at the plugin root (`name`, optional `local_bin`, `check`, `install`), which this skill and the per-plugin check both read. **Basis:** [skills](https://code.claude.com/docs/en/skills), `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. ... Default: `false`."), fetched 2026-09-28. **As of:** 2026-09-28. **Recheck:** a Claude Code release adds a manifest field for external binaries, or `plugins` becomes model-invocable for a read-only action.

## Run

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-prerequisites.sh"
```

The table columns are tool, plugin, present or missing, the check skill, and the documented install command. `missing=N present=M` is the last line. Exit 1 means at least one tool is missing. Exit 2 means no plugin roots could be read.

With no arguments the script merges `enabledPlugins` from the user settings in `~/.claude` (`CLAUDE_CONFIG_DIR` overrides that directory) and the project's `.claude/settings.json` and `settings.local.json`, then reads each enabled record's `installPath`. Only when none of that state exists does it scan `plugins/*/prerequisites.json` in the current repository; a state with nothing enabled prints an empty table.

## Next

- A tool is missing: the `check` skill that row names
- The fleet's versions, a different question: /claude-ops:plugins audit

The table's `check` column names the skill for that row. Run the named check. Do not install unless the user asked.

## Gotchas

A missing row is a report, not an install. Do not run `npx`, `npm install`, or `go install` from this skill.
