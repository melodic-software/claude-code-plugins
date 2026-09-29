---
description: "Read-only check that markdownlint-cli2 resolves for the markdown-format hook. Use when a hook notice says markdownlint-cli2 is missing, or before assuming Markdown formatting ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether markdownlint-cli2 is installed. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install, download, or invoke `npx`.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-28. **As of:** 2026-09-28. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Report the PASS/FAIL table. Stop.

## Next

/markdown-format:setup apply

Only when the user explicitly asked to install. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
