---
description: "Read-only check that the typos binary resolves for the typos-format hook. Use when a hook notice says typos is missing, or before assuming spell-checking ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether the typos binary is installed. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install typos, download binaries, or run `cargo install`.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-28. **As of:** 2026-09-28. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Setup's pre-computed rows are not rendered when this skill reads the file, so run every probe (jq, node, typos) via Bash. Report the PASS/FAIL table. Stop.

## Next

/typos-format:setup apply

Only when the user explicitly asked for install guidance. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
