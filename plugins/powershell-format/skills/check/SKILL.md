---
description: "Read-only check that pwsh, the PSScriptAnalyzer module, jq and node resolve for the powershell-format hook. Use when a hook notice says pwsh or jq is missing, or before assuming PowerShell formatting ran. Does not install."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report whether pwsh, PSScriptAnalyzer, jq and node are installed. Never installs.
---

## Purpose

Run the read-only check. Do not run `apply`. Do not install PowerShell, run `Install-Module`, or download anything.

**Claim:** `disable-model-invocation` is a property of the whole skill, so this skill is the model-invocable check while `setup` stays manual. **Basis:** [skills](https://code.claude.com/docs/en/skills), field `disable-model-invocation` ("Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually with `/name`. ... Default: `false`."), fetched 2026-09-28. **As of:** 2026-09-28. **Recheck:** a Claude Code release adds a per-action invocation flag, or that field's description stops applying to the whole skill.

## Check

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md` and follow only its `check` section. Setup's pre-computed rows are not rendered when this skill reads the file, so run every probe (jq, node, pwsh) via Bash. PSScriptAnalyzer is a PowerShell module, not a `PATH` binary, so the `SessionStart` probe cannot see it: probe it with `pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { "present" } else { "absent" }'`, and only when `pwsh` resolved. Report the PASS/FAIL/INFO table and the install route from `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` for a missing `pwsh`. Stop.

## Next

/powershell-format:setup apply

Only when the user explicitly asked for install guidance. A passing check has no successor.

## Gotchas

This skill does not install. A hook notice is not permission to run `apply`.
