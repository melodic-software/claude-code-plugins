---
description: "Read-only check of the disk-hygiene prerequisites: node, bash, the Python 3 interpreter ladder, and the hook launcher registration. Use when a hook notice says Python is missing, when /disk-hygiene:check is named, or before assuming the disk-hygiene guard is enforcing. Installs nothing."
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(command -v *)"
  - "Bash(grep -m1 '^MIN_PYTHON' *)"
metadata:
  workflow-stage: anytime
  summary: Report whether node, bash and a supported Python resolve for the disk-hygiene guard. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install or download.

This skill is the model-invocable check while `setup` stays manual; why they are split: the pointer below.

- **Pointer**: when checking what `disable-model-invocation` controls, fetch [Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference) live. **As of**: 2026-10-11. **Recheck trigger**: a Claude Code release adds a per-action invocation flag, or that field stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section, running each probe it names with the Bash tool. Report the PASS/FAIL/INFO table. Stop.

The interpreter probes (alias classification, version floor, kill switch) are not pre-granted; they run under the session's normal permissions, not a wildcarded interpreter allow rule.

- **Pointer**: when checking which allow rules auto mode drops, fetch [How auto mode evaluates actions](https://code.claude.com/docs/en/permission-modes#how-auto-mode-evaluates-actions) live. **As of**: 2026-10-11. **Recheck trigger**: that section changes which allow rules it drops.

## Next

/disk-hygiene:setup apply

Only when the user explicitly asked to resolve what the check reported. A passing check has no successor.

## Gotchas

This skill does not install anything. A missing-tool report is not permission to run `apply`, install Node, bash or Python, or change `PATH`.
