---
description: "Read-only check that jq resolves for the session-flow observer hook. Use when the observer does not arm at session start, or before assuming it did. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether jq resolves for the session-flow observer hook. Never installs.
---

## Purpose

Run the read-only check. Do not install jq, and do not download anything.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-30. **As of:** 2026-09-30. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `jq` item. Run `command -v jq` and `jq --version` through Bash. Do not run setup's other probes. Report a PASS/FAIL row for jq, with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` when it is missing. Stop.

## Gotchas

This skill does not install. The observer hook skips arming silently when jq is absent, so no notice announces it.
