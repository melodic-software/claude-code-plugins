---
description: "Read-only check of the disk-hygiene prerequisites: node, bash, the Python 3 interpreter ladder, and the hook launcher registration. Use when a hook notice says Python is missing, when /disk-hygiene:check is named, or before assuming the disk-hygiene guard is enforcing. Installs nothing."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(command -v *)"
  - "Bash(git --version*)"
  - "Bash(grep -m1 *)"
metadata:
  workflow-stage: anytime
  summary: Report whether node, bash and a supported Python resolve for the disk-hygiene guard. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install or download.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-29. **As of:** 2026-09-29. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section, running each probe it names with the Bash tool. Report the PASS/FAIL/INFO table. Stop.

The interpreter probes (alias classification, version floor, kill switch) are not pre-granted: a wildcarded interpreter rule grants nothing in auto mode, so they run under the session's normal permissions.

## Next

/disk-hygiene:setup apply

Only when the user explicitly asked to resolve what the check reported. A passing check has no successor.

## Gotchas

This skill does not install anything. A missing-tool report is not permission to run `apply`, install Node, bash or Python, or change `PATH`.
