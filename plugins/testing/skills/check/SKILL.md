---
description: "Read-only check that node and jq resolve for the testing hooks. Use when a hook notice says node or jq is missing, or before assuming the test-scan or test-judge hooks ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether node and jq resolve for the testing hooks. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install Node.js or jq, and do not download anything.

This skill is the model-invocable check, and `setup` stays manual, because the invocation control is set per skill, not per action. Where that control is defined: [Extend Claude with skills § Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference), the `disable-model-invocation` field. As of 2026-10-11. Recheck when that field gains a per-action form or stops applying to the whole skill.

## Check

Run `command -v node`, `node --version`, `command -v jq` and `jq --version` through Bash. Report a PASS/FAIL row for node and for jq, with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` when it is missing. Stop.

## Next

/testing:setup apply

Only when the user explicitly asked for it. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to install.
