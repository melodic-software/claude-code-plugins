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

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-29. **As of:** 2026-09-29. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Its pre-computed `playwright-cli` row does not run when the file is read, so run `command -v playwright-cli` and, when it resolves, `playwright-cli --version`, once each. For its browser step run `command -v` over the usual system Chrome and Chromium binary names, and for its artifact-directory step run `git check-ignore -q .playwright-cli/`. Report the PASS/FAIL/INFO table. Stop.

## Next

/playwright:setup apply install-cli

Only when the user explicitly asked to install. A passing check has no successor.

## Gotchas

This skill does not install, and does not run `playwright-cli install-browser`. A missing-tool report is not permission to run `apply`.
