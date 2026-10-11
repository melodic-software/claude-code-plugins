---
description: "Read-only check that node and jq resolve for the autonomy hooks. Use when a hook notice says node or jq is missing, or before assuming the lane-stop gate ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether node and jq resolve for the autonomy hooks. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install Node.js or jq, and do not download anything.

This skill is the model-invocable check, kept apart from `setup` so `setup` can stay manual.

- **Pointer**: when deciding whether one skill could carry both postures, fetch <https://code.claude.com/docs/en/skills#control-who-invokes-a-skill> live. **As of**: 2026-10-11. **Recheck trigger**: a Claude Code release adds per-action invocation control, or that section is renamed or removed.

## Check

Run `command -v node`, `node --version`, `command -v jq` and `jq --version` through Bash. Report a PASS/FAIL row for node and for jq, with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` when it is missing. Stop.

## Next

/autonomy:setup apply

Only when the user explicitly asked for it. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to install.
