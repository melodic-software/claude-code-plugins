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

With no arguments and a `claude` executable on PATH, the script reads the enabled set and each `installPath` from `claude plugin list --json`. That output lists installs across every project, so it keeps user and managed rows, and project or local rows only when their `projectPath` is the current project (`CLAUDE_PROJECT_DIR`, else the git toplevel); an id resolves by its most specific scope, so user-enabled and project-disabled is disabled. When `claude` is absent or prints nothing, it merges `enabledPlugins` from the settings files instead: the user settings in `~/.claude` (`CLAUDE_CONFIG_DIR` overrides that directory) and the project's `.claude/settings.json` and `settings.local.json`. A file holding any non-Boolean `enabledPlugins` value contributes none of its keys, and the managed scope is not read there. Output that is not a JSON list stops the run with exit 2 instead. Only when none of that state exists does it scan `plugins/*/prerequisites.json` in the current repository; a state with nothing enabled prints an empty table.

**Claim:** `claude plugin list --json` returns one row per install with `id`, `scope`, `enabled`, `installPath` and, for project and local rows, `projectPath`, and an id's most specific scope decides whether it is enabled. **Basis:** the `plugin list --json` output observed on Claude Code 2.1.284 (user and project rows only; a managed row was not observed), and the `enabledPlugins` precedence managed > `--settings` > local > project > user recorded in [scope-semantics.md](../plugins/context/scope-semantics.md) from the [settings](https://code.claude.com/docs/en/settings) page. **As of:** 2026-09-29. **Recheck:** a release note changes `plugin list --json` fields or its scope values, or the settings page changes the `enabledPlugins` precedence.

## Next

- A formatter or linter binary is missing: /actionlint:check, /bash-format:check, /biome-format:check, /go-format:check, /markdown-format:check, /powershell-format:check, /ruff-format:check or /typos-format:check
- The fleet's versions, a different question: /claude-ops:plugins audit

## Gotchas

A missing row is a report, not an install. Do not run `npx`, `npm install`, or `go install` from this skill.

The table's `check` column names the skill for that row. When that skill is model-invocable, run it. When it is a setup skill (a `:setup check` command), it is human-only, so the model cannot invoke it and can only relay the command: tell the user to type it and show the row's install command. Install nothing unless the user asked.
