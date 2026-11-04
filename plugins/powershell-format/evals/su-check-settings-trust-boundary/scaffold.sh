#!/usr/bin/env bash
# A git repository whose settings file declares CustomRulePath, naming a harmless rule module, so the
# trust gate applies (setup SKILL.md check step 5). This clone has declined the pre-commit entry.
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
mkdir -p rules
cat >PSScriptAnalyzerSettings.psd1 <<'EOF'
@{
    CustomRulePath = @('./rules/TeamRules.psm1')
    IncludeDefaultRules = $true
}
EOF
cat >rules/TeamRules.psm1 <<'EOF'
function Measure-Nothing {
    param([System.Management.Automation.Language.ScriptBlockAst] $ScriptBlockAst)
    return @()
}
Export-ModuleMember -Function Measure-Nothing
EOF
git add .
git commit -q -m "chore: init"
