---
description: "Read-only check that the playwright-cli binary and a resolvable browser are in place for /playwright:playwright. Use when a session notice says playwright-cli is missing, or before assuming a browser flow will run. Does not install."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(command -v playwright-cli*)"
  - "Bash(playwright-cli --version*)"
metadata:
  workflow-stage: anytime
  summary: Report whether playwright-cli and a browser resolve. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install or download.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-29. **As of:** 2026-09-29. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Its pre-computed `playwright-cli` row does not run when the file is read, so run `command -v playwright-cli` and, when it resolves, `playwright-cli --version`, once each. Report the PASS/FAIL/INFO table. Stop.

## Next

/playwright:setup apply install-cli

Only when the user explicitly asked to install. A passing check has no successor.

## Gotchas

This skill does not install, and does not run `playwright-cli install-browser`. A session notice is not permission to run `apply`.
