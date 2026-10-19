---
description: "Read-only check that node resolves for the review connected-page Artifact guard and that the hook is registered. Use when a hook notice says node is missing, or before assuming the guard ran. Does not install."
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(bash ${CLAUDE_SKILL_DIR}/scripts/check.sh:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Report whether node resolves and the connected-page Artifact guard is registered. Never installs.
---

## Purpose

Run the read-only check. Do not install Node.js, do not download anything, and do not edit `hooks/hooks.json`.

This plugin treats a failed row as the guard not running: an Artifact publish of a connected page then reaches claude.ai with nothing stopping it.

## Check

Run `bash ${CLAUDE_SKILL_DIR}/scripts/check.sh` through Bash, with no arguments; it refuses any. It prints one `check<TAB>PASS|FAIL<TAB>detail` row each for:

- **node**: `node` resolves on `PATH`, with its version.
- **registration**: one `PreToolUse` entry in `hooks/hooks.json` matches `Artifact` and runs `node` on `hooks/connected-page-gate.mjs`, and that file exists. Without `node` this row is a text match and says so.
- **hook**: the guard denies a sample Artifact call that publishes a connected page. It runs only when `node` resolves.

Report the rows as a PASS/FAIL table. On a node FAIL, give the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json`. When any row fails, say that the connected-page guard is not running in this session. A `connected_page_guard_enabled` of off also stops the guard; this check does not read it. Stop.

## Next

/review:explain-change

Only when the user was about to publish a change digest. A failing check has no successor in this plugin.

## Gotchas

This skill does not install. A hook notice is not permission to install Node.js or to change the hook registration.
