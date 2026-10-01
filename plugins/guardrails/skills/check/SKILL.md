---
description: "Read-only check that node and jq resolve for the guardrails hooks. Use when a hook notice says node or jq is missing, or before assuming the guards ran. Does not install."
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Report whether node and jq resolve for the guardrails hooks. Never installs.
---

## Pre-computed context

The probes ran at load time, outside the Bash tool, so they still report when a missing `jq` makes the guards deny every Bash call. Each row shows the tool's path, or `absent` when missing:

- `jq`: !`{ command -v jq 2>/dev/null || echo "absent"; }`
- `node`: !`{ command -v node 2>/dev/null || echo "absent"; }`

A row reading `[shell command execution disabled by policy]` carries no result: run that tool's `command -v` probe via Bash instead.

## Purpose

Run the read-only check of the two prerequisites. The guard toggle report belongs to `/guardrails:setup check`, not to this skill. Do not run `apply`, `apply install-commit-msg` or `apply install-pre-commit-content`. Do not install Node.js or jq, and do not download anything.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-30. **As of:** 2026-09-30. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only the `jq` and `node` items of its read-only `check` section, using the pre-computed rows above. Report the PASS/FAIL table with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` for a missing tool. Stop.

## Next

/guardrails:setup apply

Only when the user explicitly asked for it. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
