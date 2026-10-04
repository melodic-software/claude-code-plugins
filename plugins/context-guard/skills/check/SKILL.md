---
description: "Read-only check that node (the PostCompact marker hook and the mod's snapshot writes) and jq (the setup check's zone resolver and zones.json merge) resolve for context-guard, and whether its mod can load (mods off, or Claude Code older than the 2.1.287 floor). Use when a hook notice says node is missing, or before assuming the context-guard mod or marker hook ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether node and jq resolve and whether the context-guard mod can load. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install Node.js or jq, and do not download anything.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-30. **As of:** 2026-09-30. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only the Node.js row and the jq row of its `check` section. Its pre-computed context lines do not run when the file is read, so run `command -v node`, `node --version`, `command -v jq` and `jq --version` through Bash. Do not run setup's other probes or `apply`. Report a PASS/FAIL row for node and for jq, with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` when it is missing. Say what each one is for: without node the PostCompact marker hook does not launch and the mod writes no snapshot, while its zone lines, gate, band row and status tool still run; without jq only setup's zone report and its `zones.json` merge stop, and no hook or mod part depends on it.

Then report a row for the module, from inside this session: the module registers the tool `mcp__context-guard__status` when the session starts, so look for that name in your own tool list, deferred tool names included. Present → PASS "the mod is running in this session". Absent → INFO "mods off in this session, or the status tool was refused by policy" (a refused registration leaves one debug-log line, "context-guard: the status tool could not register"); with mods off there are no zone lines, no gate and no module writes here, and the PostCompact marker hook still runs wherever settings hooks do. Run `claude --version` too: older than 2.1.287 → FAIL "mods off: older than the 2.1.287 floor, unsupported". A separate `claude plugin test` process never sees this session's settings, so use it, if at all, only to say whether mods can load on this build, read against [troubleshoot: check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load) (as of 2026-10-03, Claude Code 2.1.288; recheck when that table changes a message), never as this session's state. Stop.

## Next

/context-guard:setup apply

Only when the user explicitly asked for it. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
