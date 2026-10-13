---
description: "Read-only check that the playwright-cli binary and a resolvable browser are in place for /playwright:playwright. Use when a browser flow reports playwright-cli is missing, when a prerequisites report lists it, or before assuming a browser flow will run. Does not install."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(command -v *)"
  - "Bash(playwright-cli --version*)"
  - "Bash(git check-ignore*)"
metadata:
  workflow-stage: anytime
  summary: Report whether playwright-cli and a browser resolve. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install or download.

Invocation control is set per skill, not per action, so this skill is the model-invocable check while `setup` stays manual.

- **Pointer**: when deciding which actions the model may run on its own, fetch [Skills: Control who invokes a skill](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill) live.
- **As of**: 2026-10-11
- **Recheck trigger**: a Claude Code release adds a per-action invocation flag, or that section stops applying the setting to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Its pre-computed `playwright-cli` row does not run when the file is read, so run `command -v playwright-cli` and, when it resolves, `playwright-cli --version`, once each. For its artifact-directory step run `git check-ignore -q .playwright-cli/`. Report the PASS/FAIL/INFO table. Stop.

## Next

/playwright:setup apply install-cli

Only when the user explicitly asked to install. A passing check has no successor.

## Gotchas

This skill does not install, and does not run `playwright-cli install-browser`. A missing-tool report is not permission to run `apply`.
