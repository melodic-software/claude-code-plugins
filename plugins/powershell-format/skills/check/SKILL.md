---
description: "Read-only check that pwsh, the PSScriptAnalyzer module and node resolve for the powershell-format hooks and git pre-commit entry. Use when a hook notice says pwsh or node is missing, or before assuming PowerShell formatting ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether pwsh, PSScriptAnalyzer and node are installed. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install PowerShell, run `Install-Module`, or download anything.

The read-only check is its own skill so the model can invoke it while `setup` stays manual.

- **Pointer**: when deciding what `disable-model-invocation` governs, fetch [skills: Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference) live. **As of**: 2026-10-11. **Recheck trigger**: that section adds per-action invocation control, or changes what `disable-model-invocation` governs.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Run every probe (node, pwsh) via Bash. PSScriptAnalyzer is a PowerShell module, not a `PATH` binary, so the `SessionStart` probe cannot see it: probe it with `pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { "present" } else { "absent" }'`, and only when `pwsh` resolved. Report the PASS/FAIL/INFO table and the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` for a missing `pwsh`. Stop.

## Next

/powershell-format:setup apply

Only when the user explicitly asked for install guidance. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
