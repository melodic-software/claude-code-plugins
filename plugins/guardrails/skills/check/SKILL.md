---
description: "Read-only check that node and jq resolve for the guardrails hooks, and which guard toggles are on. Use when a hook notice says node or jq is missing, or before assuming the guards ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether node and jq resolve for the guardrails hooks and the guard toggles. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`, `apply install-commit-msg` or `apply install-pre-commit-content`. Do not install Node.js or jq, and do not download anything.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-30. **As of:** 2026-09-30. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its read-only `check` section: the `jq` and `node` rows and the per-guard toggle-state report. Its pre-computed context lines do not run when the file is read, so run `command -v jq` and `command -v node` through Bash. Report the PASS/FAIL table with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` for a missing tool. Stop.

## Next

/guardrails:setup apply

Only when the user explicitly asked for it. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
