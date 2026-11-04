#!/usr/bin/env bash
# A git repository with a plain settings file and a script, where this clone has declined the pre-commit
# entry, so verify prints declined (setup SKILL.md check step 8).
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
