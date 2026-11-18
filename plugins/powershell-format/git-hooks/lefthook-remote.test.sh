#!/usr/bin/env bash
# test-scope: plugins/powershell-format/git-hooks/lefthook-remote.yml plugins/powershell-format/git-hooks/entries.json plugins/powershell-format/lib/git-hooks/install.mjs plugins/powershell-format/git-hooks/format.sh plugins/powershell-format/git-hooks/lint.sh .lefthook/*/powershell-format-* .lefthook/remote-entry.sh lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done
lr_require_tools pwsh

printf '%s\n' "@{
    IncludeRules = @('PSUseCorrectCasing', 'PSAvoidGlobalVars')
    Rules = @{ PSUseCorrectCasing = @{ Enable = \$true } }
}" >"$REPO/PSScriptAnalyzerSettings.psd1"
git -C "$REPO" add -A
lr_commit config
lr_expect_pass "a commit of the opting-in config passes"

printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
lr_commit format
lr_expect_pass "format: a staged unformatted file commits"
expect "format: the committed file is the formatted one" $'Get-ChildItem .' "$(git -C "$REPO" show HEAD:a.ps1)"
lr_skip_keeps powershell-format-remote-format b.ps1 $'get-childitem .\n' powershell-format-remote-lint

# shellcheck disable=SC2016 # a PowerShell variable, not a substitution
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/c.ps1"
git -C "$REPO" add c.ps1
lr_commit lint
lr_expect_block "lint: a finding on an added line blocks" powershell-format-remote-lint 'c\.ps1:2: \[Warning\] PSAvoidGlobalVars'
lr_skip pre-commit powershell-format-remote-lint commit

printf 'Get-ChildItem .\n' >"$REPO/d.ps1"
git -C "$REPO" add d.ps1
lr_commit clean
lr_expect_pass "a clean file passes"

lr_done
