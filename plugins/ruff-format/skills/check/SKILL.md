---
description: "Read-only check that ruff and node resolve for the ruff-format hook. Use when a hook notice says ruff or node is missing, or before assuming Ruff formatting ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether ruff and node are installed. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install, download, or invoke `uvx` or `pipx run`.

The read-only check is its own skill so the model can invoke it while `setup` stays manual.

- **Pointer**: when deciding what `disable-model-invocation` governs, fetch [skills: Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference) live. **As of**: 2026-10-11. **Recheck trigger**: that section adds per-action invocation control, or changes what `disable-model-invocation` governs.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Setup's pre-computed rows are not rendered when this skill reads the file, so run every probe (jq, node, ruff) via Bash. The SessionStart probe looks for `ruff` on PATH and at `.venv/bin/ruff` under the working directory or up to seven of its ancestors, while the edit hook also accepts `.venv/Scripts/ruff.exe` and walks up from the edited file. So also look for `.venv/bin/ruff` and `.venv/Scripts/ruff.exe` under the repository root, and report a `.venv` ruff as found even when PATH has none. Report the PASS/FAIL table. Stop.

## Next

/ruff-format:setup apply

Only when the user explicitly asked to install. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
