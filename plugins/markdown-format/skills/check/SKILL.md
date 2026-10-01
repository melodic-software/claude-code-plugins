---
description: "Read-only check that markdownlint-cli2 and node resolve for the markdown-format hook. Use when a hook notice says markdownlint-cli2 or node is missing, or before assuming Markdown formatting ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether markdownlint-cli2 and node are installed. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install, download, or invoke `npx`.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-28. **As of:** 2026-09-28. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. The pre-computed `jq` row in that file does not run under this skill, so for item 3 run `{ command -v jq 2>/dev/null || echo absent; }` via Bash and report its result as the `jq` PASS/FAIL row. Stay read-only and install-free. Report the PASS/FAIL table. Stop.

## Next

/markdown-format:setup apply

Only when the user explicitly asked to install. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
