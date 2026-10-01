---
description: "Read-only check that node and jq resolve for the claude-ops hooks. Use when a hook notice says node or jq is missing, or before assuming claude-ops hooks ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether node and jq resolve for the claude-ops hooks. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install Node.js or jq, and do not download anything.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-30. **As of:** 2026-09-30. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only the node row (7) and the jq row (8) of its `check` section. Its pre-computed context lines do not run when the file is read, so run `command -v node`, `node --version`, `command -v jq` and `jq --version` through Bash. Do not run setup's path-configuration, guard-file or retired-convention steps. Report the PASS/FAIL table with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` for a missing tool. Stop.

## Next

/claude-ops:setup apply

Only when the user explicitly asked for it. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
