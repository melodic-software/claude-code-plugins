---
description: "Read-only check that node resolves for the multi-agent drift-checker fetch gate hook and that the hook is registered. Use when a hook notice says node is missing, or before assuming the fetch gate ran. Does not install."
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/check.sh:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Report whether node resolves and the drift-checker fetch gate is registered. Never installs.
---

## Purpose

Run the read-only check. Do not install Node.js, do not download anything, and do not edit `hooks/hooks.json`.

Without `node` the fetch gate fails open: the hook cannot start, Claude Code shows a non-blocking hook error notice, and the drift checker's `WebFetch` proceeds, held to first-party docs hosts only by the workflow's source filter and the agent's prompt. **Basis:** [hooks](https://code.claude.com/docs/en/hooks), the exit-code section on a hook that cannot start. **As of:** 2026-10-02. **Recheck:** a Claude Code release changes how a `PreToolUse` hook that cannot start is treated.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation`. **As of:** 2026-10-02. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Run `${CLAUDE_SKILL_DIR}/scripts/check.sh` through Bash. It prints one `check<TAB>PASS|FAIL<TAB>detail` row each for:

- **node**: `node` resolves on `PATH`, with its version.
- **registration**: `hooks/hooks.json` has a `PreToolUse` entry on `WebFetch` that runs `node` on `hooks/drift-checker-fetch-gate.mjs`, and that file exists. This row is read without `node`.
- **gate**: the hook denies a sample drift-checker fetch of an off-host URL. It runs only when `node` resolves.

Report the rows as a PASS/FAIL table. On a node FAIL, give the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json`. When any row fails, say that the fetch gate is not enforcing in this session. Stop.

## Next

/multi-agent:audit-defaults

Only when the user was about to run the drift audit. A failing check has no successor in this plugin.

## Gotchas

This skill does not install. A hook notice is not permission to install Node.js or to change the hook registration.
