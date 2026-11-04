#!/usr/bin/env bash
# A git repository with a PowerShell script and no PSScriptAnalyzerSettings.psd1, where this clone has
# declined the pre-commit entry, so bare apply has nothing to do but guide (setup SKILL.md apply).
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
git add .
git commit -q -m "chore: init"
