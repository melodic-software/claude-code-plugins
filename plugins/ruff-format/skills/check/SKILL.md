---
description: "Read-only check that the ruff binary resolves for the ruff-format hook. Use when a hook notice says ruff is missing, or before assuming Ruff formatting ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether the ruff binary is installed. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install, download, or invoke `uvx` or `pipx run`.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-28. **As of:** 2026-09-28. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Setup's pre-computed rows are not rendered when this skill reads the file, so run every probe (jq, node, ruff) via Bash. The SessionStart probe looks for `ruff` on PATH and at `.venv/bin/ruff` under the working directory or up to seven of its ancestors, while the edit hook also accepts `.venv/Scripts/ruff.exe` and walks up from the edited file. So also look for `.venv/bin/ruff` and `.venv/Scripts/ruff.exe` under the repository root, and report a `.venv` ruff as found even when PATH has none. Report the PASS/FAIL table. Stop.

## Next

/ruff-format:setup apply

Only when the user explicitly asked to install. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
