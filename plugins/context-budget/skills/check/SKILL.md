---
description: "Read-only check that node resolves for the context-budget hooks. Use when a hook notice says node is missing, or before assuming context-budget hooks ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether node resolves for the context-budget hooks. Never installs.
---

## Purpose

Run the read-only check. Do not install Node.js, and do not download anything.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-10-01. **As of:** 2026-10-01. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only the `node` row of its `check` section. Its pre-computed context lines do not run when the file is read, so run `command -v node` and `node --version` through Bash. Skip its Claude Code CLI and Agent SDK rows. Report the PASS/FAIL row with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` when node is missing. Stop.

## Next

/context-budget:setup check

Only when the user asks for the full prerequisite check. A passing check has no other successor.

## Gotchas

This skill does not install. A hook notice is not permission to install Node.js.
