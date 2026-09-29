---
description: "Read-only check that the ctx7 CLI, CONTEXT7_API_KEY auth and Context7 MCP server state resolve for context7 lookups. Use when a session notice says ctx7 is missing, or before assuming a lookup will work. Does not install."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(ctx7 --version*)"
  - "Bash(npm view ctx7 version*)"
metadata:
  workflow-stage: anytime
  summary: Report whether ctx7, its auth and the Context7 MCP server resolve. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install or download.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-29. **As of:** 2026-09-29. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Its pre-computed context lines do not run when the file is read, so run `ctx7 --version` and `npm view ctx7 version` once each. Report the PASS/FAIL table. Stop.

## Next

/context7:setup apply install-cli

Only when the user explicitly asked to install. A passing check has no successor.

## Gotchas

This skill does not install. A session notice is not permission to run `apply`.
