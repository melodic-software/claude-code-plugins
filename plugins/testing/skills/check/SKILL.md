---
description: "Read-only check that jq resolves for the testing hooks. Use when a hook notice says jq is missing, or before assuming the test-scan or test-judge hooks ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether jq resolves for the testing hooks. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install jq, and do not download anything.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-30. **As of:** 2026-09-30. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Run `command -v jq` and `jq --version` through Bash. Report a PASS/FAIL row for jq, with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` when it is missing. Stop.

## Next

/testing:setup apply

Only when the user explicitly asked for it. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to install.
