#!/usr/bin/env bash
# A git repository where every check step passes or is INFO on a host with pwsh and PSScriptAnalyzer: a
# plain settings file with no CustomRulePath, and this clone has declined the pre-commit entry, so
# verify reports declined rather than missing (setup SKILL.md check steps 5 and 8).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.powershell-format.powershell-check.declined true
printf 'function Get-Demo {\n    return 1\n}\n' >demo.ps1
printf "@{\n    IncludeRules = @('PSAvoidUsingCmdletAliases')\n}\n" >PSScriptAnalyzerSettings.psd1
git add .
git commit -q -m "chore: init"
