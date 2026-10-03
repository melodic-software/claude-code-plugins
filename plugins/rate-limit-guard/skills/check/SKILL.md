---
description: "Read-only check that node and jq resolve for the rate-limit-guard hook and statusline tee, and whether its mod can load (mods off, or Claude Code older than the 2.1.287 floor). Use when a hook notice says node or jq is missing, or before assuming rate-limit-guard ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether node and jq resolve and whether the rate-limit-guard mod can load. Never installs.
---

## Purpose

Run the read-only check. Do not install Node.js or jq, and do not download anything.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-10-01. **As of:** 2026-10-01. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Run `command -v node`, `node --version`, `command -v jq` and `jq --version` through Bash. Report a PASS/FAIL row for node and for jq, with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` when it is missing.

Then report a row for the module, which needs Claude Code 2.1.287 or later: run `claude --version`; older → FAIL "mods off: older than the 2.1.287 floor, unsupported". Otherwise run `claude plugin test` from a new empty temporary directory and read its message against the table at [troubleshoot: check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load) (as of 2026-10-03, Claude Code 2.1.288; recheck when that table changes a message): mods can load → PASS; mods turned off → INFO "mods off", with the cause the table names (the StopFailure hook still records rate-limit stops). Stop.

## Next

/rate-limit-guard:setup check

Only when the user asks to verify the statusline wiring and tee freshness.

## Gotchas

This skill does not install. A hook notice is not permission to install Node.js or jq.
