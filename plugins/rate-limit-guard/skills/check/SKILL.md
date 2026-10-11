---
description: "Read-only check that node resolves for the rate-limit-guard StopFailure hook and snapshot writes, and whether its mod can load (mods off, or Claude Code older than the mods floor). Use when a hook notice says node is missing, or before assuming rate-limit-guard ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether node resolves and whether the rate-limit-guard mod can load. Never installs.
---

## Purpose

Run the read-only check. Do not install Node.js, and do not download anything.

This skill is the model-invocable check and `setup` stays manual, because the invocation switch applies to a whole skill, never to one action. **Pointer:** when deciding what `disable-model-invocation` covers, fetch [skills: frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference) live. **As of:** 2026-10-11. **Recheck trigger:** a Claude Code release adds a per-action invocation flag, or that field stops applying to the whole skill.

## Check

Run `command -v node` and `node --version` through Bash. Report a PASS/FAIL row for node, with the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` when it is missing. Without node the StopFailure hook does not launch and the module cannot write the snapshot file.

Then report a row for the module, which needs the mods floor: `detect.version.min` of the entry with `"id": "claude"` in `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` (the README's "Requirements" points at where it comes from). Run `claude --version`; older → FAIL "mods off: older than the mods floor `<min>`, unsupported". Otherwise decide this session's state from inside this session: at `session.start` the module registers its pull tool, which Claude sees as `mcp__rate-limit-guard__status` ([api: add a tool](https://code.claude.com/docs/en/plugins/mods/api#add-a-tool), as of 2026-10-03, Claude Code 2.1.288; recheck when the full tool name form changes). Look for that name in your own tool list, counting a name listed only as a deferred tool, and do not call it. Present → PASS "mod running in this session". Absent → INFO "mods off in this session, or the status tool's registration was refused": state both causes without picking one, either mods are off here (the README's "Where mods are off" points at what turns them off) or the organization's policy refused the tool, which the module logs as one line in the debug log. The StopFailure hook still records rate-limit stops either way. A `claude plugin test` run is a separate process that never sees this session's flags or settings overlay; when you run it, label its result machine-level (whether mods can load on this build, read against [troubleshoot: check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load), as of 2026-10-03, Claude Code 2.1.288; recheck when that table changes a message), never as this session's state. Stop.

## Next

/rate-limit-guard:setup check

Only when the user asks to verify the snapshot file's freshness, or the options in effect.

## Gotchas

This skill does not install. A hook notice is not permission to install Node.js.
