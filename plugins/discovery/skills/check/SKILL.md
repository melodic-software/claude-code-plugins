---
description: "Read-only check that node resolves for the discovery WebFetch truncation hook and that the hook is registered. Use when a hook notice says node is missing, or before assuming the truncation hook ran. Does not install."
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/check.sh:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Report whether node resolves and the WebFetch truncation hook is registered. Never installs.
---

## Purpose

Run the read-only check. Do not install Node.js, do not download anything, and do not edit `hooks/hooks.json`.

This plugin treats a failed row as the truncation hook not running: a truncated WebFetch result then reaches Claude with no added note. How Claude Code handles a hook that cannot start: [hooks](https://code.claude.com/docs/en/hooks), the exit-code section. **As of:** 2026-10-04. **Recheck:** that section changes how a `PostToolUse` hook that cannot start is treated.

## Check

Run `${CLAUDE_SKILL_DIR}/scripts/check.sh` through Bash, with no arguments; it refuses any. It prints one `check<TAB>PASS|FAIL<TAB>detail` row each for:

- **node**: `node` resolves on `PATH`, with its version.
- **registration**: one `PostToolUse` entry in `hooks/hooks.json` matches `WebFetch` and runs `node` on `hooks/webfetch-truncation.mjs`, and that file exists. Without `node` this row is a text match and says so.
- **hook**: the hook flags a sample WebFetch result that ends in a truncation marker. It runs only when `node` resolves.

Report the rows as a PASS/FAIL table. On a node FAIL, give the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json`. When any row fails, say that the truncation hook is not running in this session. Stop.

## Next

/discovery:read-docs

Only when the user was about to read a docs page. A failing check has no successor in this plugin.

## Gotchas

This skill does not install. A hook notice is not permission to install Node.js or to change the hook registration.
