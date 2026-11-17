#!/usr/bin/env bash
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.powershell-format.format.declined true
git config --local checks.powershell-format.lint.declined true
mkdir -p .claude/ecosystems scripts
printf 'globs: ["**/*.ps1"]\nfix-cmd: "pwsh -NoProfile -File scripts/format.ps1 <files>"\nlint-cmd: "pwsh -NoProfile -File scripts/lint.ps1 <files>"\n' >.claude/ecosystems/powershell.yaml
printf 'Write-Output formatted\n' >scripts/format.ps1
printf 'Write-Output linted\n' >scripts/lint.ps1
printf 'function Get-Demo {\n    return 1\n}\n' >demo.ps1
git add .
git commit -q -m "chore: init"
