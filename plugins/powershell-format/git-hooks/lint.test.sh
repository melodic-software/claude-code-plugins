#!/usr/bin/env bash
# test-scope: plugins/powershell-format/git-hooks/entries.json plugins/powershell-format/git-hooks/psscriptanalyzer.ps1 plugins/powershell-format/git-hooks/adapters.sh
# test-scope: plugins/powershell-format/lib/git-hooks/check-lib.sh plugins/powershell-format/lib/git-hooks/resolve-tool.sh
# test-scope: plugins/powershell-format/git-hooks/format.sh
# shellcheck disable=SC2016  # literal PowerShell variable syntax: single quotes are intentional
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT CLAUDE_PLUGIN_DATA

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/lint.sh"
if ! command -v pwsh >/dev/null 2>&1 || ! pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { exit 0 } else { exit 1 }' >/dev/null 2>&1; then
  echo "SKIP: pwsh with PSScriptAnalyzer not available -- lint entry tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

# shellcheck source=powershell-format-test-helpers.sh
source "$HERE/powershell-format-test-helpers.sh"

SETTINGS_BODY="@{
    IncludeRules = @('PSUseCorrectCasing', 'PSAvoidGlobalVars')
    Rules = @{ PSUseCorrectCasing = @{ Enable = \$true } }
}"
first_line() { printf '%s' "$1" | head -1 | sed 's/ Found global.*//'; }
HINT='powershell-format: fix the findings pwsh reported above, or adjust the repository PSScriptAnalyzerSettings.psd1.'

new_repo
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
got="$(check "$REPO")"
expect "a finding on an added line blocks, naming that line" "1||a.ps1:2: [Warning] PSAvoidGlobalVars:" "$(first_line "$got")"
expect "the finding is followed by the hint" "$HINT" "$(printf '%s' "$got" | tail -1)"

new_repo
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
got="$(check "$REPO")"
expect "reports only: a miscased line is a finding" "1||a.ps1:1: [Information] PSUseCorrectCasing:" "$(first_line "$got" | sed 's/ PSUseCorrectCasing: .*/ PSUseCorrectCasing:/')"
expect "reports only: the work tree is not rewritten" "get-childitem ." "$(cat "$REPO/a.ps1")"
expect "reports only: the index is not rewritten" "get-childitem ." "$(git -C "$REPO" show :a.ps1)"

new_repo
mkdir -p "$REPO/scripts"
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/scripts/gone.ps1"
git -C "$REPO" add scripts/gone.ps1
rm -r "$REPO/scripts"
got="$(check "$REPO")"
expect "staged then deleted: the staged finding still blocks" "1||scripts/gone.ps1:2: [Warning] PSAvoidGlobalVars:" "$(first_line "$got")"
expect "staged then deleted: the file is not recreated" "no" "$([[ -e "$REPO/scripts/gone.ps1" ]] && echo yes || echo no)"
git -C "$REPO" rm -q --cached scripts/gone.ps1
printf 'get-childitem .\n' >"$REPO/gone.ps1"
ln -s missing.ps1 "$REPO/link.ps1"
git -C "$REPO" add gone.ps1 link.ps1
rm "$REPO/gone.ps1" "$REPO/link.ps1"
got="$(check "$REPO")"
expect "staged then deleted: a miscased file is reported; a symlink is not checked" "1||gone.ps1:1: [Information] PSUseCorrectCasing:" "$(first_line "$got" | sed 's/ PSUseCorrectCasing: .*/ PSUseCorrectCasing:/')"
expect "staged then deleted: the index keeps its bytes" "get-childitem ." "$(git -C "$REPO" show :gone.ps1)"

new_repo
printf '$global:foo = 1\n' >"$REPO/seed.ps1"
git -C "$REPO" add seed.ps1
git -C "$REPO" commit -q -m old --no-verify
printf '$global:foo = 1\nGet-Date\n' >"$REPO/seed.ps1"
git -C "$REPO" add seed.ps1
expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

new_repo NONE
printf '$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
expect "no settings file: nothing is checked and the entry passes" "0||" "$(check "$REPO")"

new_repo
printf 'Get-ChildItem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
expect "a partly staged file is refused, since lint reads the work tree" "1||a.ps1: partly staged; lint checks the work tree, so stage it fully, then commit" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/src/deep"
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/src/deep/b.psm1"
git -C "$REPO" add src
got="$(check "$REPO")"
expect "a nested file's finding names its repo-relative path" "1||src/deep/b.psm1:2: [Warning] PSAvoidGlobalVars:" "$(first_line "$got")"

new_repo
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/-lead.ps1"
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/\$(touch pwned).ps1"
git -C "$REPO" add -- '-lead.ps1' '$(touch pwned).ps1'
got="$(check "$REPO")"
expect "crafted file names are linted as files, repo-relative" "\$(touch pwned).ps1:2: [Warning] PSAvoidGlobalVars:|-lead.ps1:2: [Warning] PSAvoidGlobalVars:" \
  "$(printf '%s' "${got#*|*|}" | grep PSAvoidGlobalVars | sed 's/ Found global.*//' | sort | paste -sd'|' -)"
expect "a crafted file name ran nothing" "no" "$([[ -e "$REPO/pwned" ]] && echo yes || echo no)"

new_repo
printf 'get-childitem .\n$global:foo = 1\n' >"$REPO/a.ps1"
got="$(check "$REPO" --worktree)"
expect "--worktree: an untracked file is checked whole and blocks" "1||a.ps1:2: [Warning] PSAvoidGlobalVars:" "$(first_line "$got")"
expect "--worktree: the file keeps its bytes" "$(printf 'get-childitem .\n$global:foo = 1')" "$(cat "$REPO/a.ps1")"
rm "$REPO/a.ps1"
expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

NOPWSH="$WORK/nopwsh"
mkdir -p "$NOPWSH"
for t in git bash sh sed awk cat mktemp rm dirname grep tr; do
  ln -s "$(command -v "$t")" "$NOPWSH/$t"
done
INSTALL_HINT='see https://learn.microsoft.com/powershell/scripting/install/installing-powershell'
new_repo
printf 'Get-ChildItem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPWSH" bash "$CHECK" 2>&1)"
expect "missing pwsh: an agent fails with the install command and the skip key" \
  "1|FAIL: pwsh missing. Install: $INSTALL_HINT
To skip only while pwsh is missing: git -c checks.skipmissing=pwsh commit ..." "$?|$out"
out="$(cd "$REPO" && PATH="$NOPWSH" bash "$CHECK" 2>&1)"
expect "missing pwsh: a person gets a notice and exit 0" "0|NOTICE: pwsh missing, so this check did not run. Install: $INSTALL_HINT" "$?|$out"
git -C "$REPO" config checks.skipmissing pwsh
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPWSH" bash "$CHECK" --worktree 2>&1)"
expect "missing pwsh named in checks.skipmissing, --worktree: skipped with a line" "0|SKIPPED: pwsh (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPWSH" bash "$CHECK" --worktree 2>&1)"
expect "missing pwsh, --worktree: an agent fails as at commit time" \
  "1|FAIL: pwsh missing. Install: $INSTALL_HINT" "$?|${out%%$'\n'*}"

STUB="$WORK/stub"
mkdir -p "$STUB"
printf '#!/usr/bin/env bash\nexit 3\n' >"$STUB/pwsh"
chmod +x "$STUB/pwsh"
INSTALL_MOD='pwsh -Command Install-Module PSScriptAnalyzer -Scope CurrentUser'
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$STUB:$PATH" bash "$CHECK" 2>&1)"
expect "missing module: an agent fails with the install command" \
  "1|FAIL: PSScriptAnalyzer missing. Install: $INSTALL_MOD
To skip only while PSScriptAnalyzer is missing: git -c checks.skipmissing=PSScriptAnalyzer commit ..." "$?|$out"
out="$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" 2>&1)"
expect "missing module: a person gets a notice and exit 0" "0|NOTICE: PSScriptAnalyzer missing, so this check did not run. Install: $INSTALL_MOD" "$?|$out"
git -C "$REPO" config checks.skipmissing PSScriptAnalyzer
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$STUB:$PATH" bash "$CHECK" 2>&1)"
rc=$?
git -C "$REPO" config --unset checks.skipmissing
expect "missing module named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: PSScriptAnalyzer (missing)" "$rc|$out"

printf '#!/usr/bin/env bash\necho "something broke"\nexit 1\n' >"$STUB/pwsh"
out="$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" 2>&1)"
expect "a non-zero exit with no parsed finding fails closed and shows the output" \
  "1|powershell-format: pwsh exited 1 and reported no <path>:<line> finding, so the change was not checked:
something broke" "$?|$out"
printf '#!/usr/bin/env bash\necho "PSSA_ERROR a.ps1: boom"\nexit 4\n' >"$STUB/pwsh"
out="$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" 2>&1)"
expect "an analyzer error fails the entry and shows the error" "1|powershell-format: Invoke-ScriptAnalyzer failed under PSScriptAnalyzerSettings.psd1:
a.ps1: boom" "$?|$out"

new_repo NONE
mkdir -p "$REPO/rules"
cat >"$REPO/rules/CleanRules.psm1" <<'EOF'
function Measure-AlwaysClean {
    [CmdletBinding()]
    [OutputType('Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]')]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst
    )
    return
}
Export-ModuleMember -Function Measure-AlwaysClean
EOF
cat >"$REPO/PSScriptAnalyzerSettings.psd1" <<'EOF'
@{
    CustomRulePath = './rules/CleanRules.psm1'
    IncludeDefaultRules = $true
    IncludeRules = @('PSAvoidGlobalVars', 'Measure-AlwaysClean')
}
EOF
git -C "$REPO" add -A
git -C "$REPO" commit -q -m rules --no-verify
printf '$global:foo = 1\n' >"$REPO/crp.ps1"
git -C "$REPO" add crp.ps1
out="$(cd "$REPO" && CLAUDECODE=1 bash "$CHECK" 2>&1)"
expect "unapproved CustomRulePath, agent commit: skipped with the verdict, exit 0" \
  "0|powershell-format trust gate: linting skipped for files under PSScriptAnalyzerSettings.psd1; it loads repository rule modules and is not approved. Approval is the user's." "$?|$out"
expect "unapproved CustomRulePath, --worktree: silent" "0||" "$(check "$REPO" --worktree)"
out="$(cd "$REPO" && bash "$CHECK" 2>&1)"
marker="$(printf '%s' "$out" | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
hash() { sha256sum "$1" | cut -d' ' -f1 | tr a-f A-F; }
sig="$(printf '%s\n%s\t%s\n%s\t%s\n' "$REPO" "$REPO/PSScriptAnalyzerSettings.psd1" "$(hash "$REPO/PSScriptAnalyzerSettings.psd1")" \
  "$REPO/rules/CleanRules.psm1" "$(hash "$REPO/rules/CleanRules.psm1")" | sha256sum | cut -d' ' -f1)"
expect "a person is told the approval command, under the earlier entry's marker" "$REPO/.git/powershell-format/trust-approvals/pssa-$sig" "$marker"
mkdir -p "$marker"
got="$(check "$REPO")"
expect "an approved state is analyzed" "1||crp.ps1:1: [Warning] PSAvoidGlobalVars:" "$(first_line "$got")"

new_repo
expect "--resolve: the repository row names the adapter, its tool and the settings file" \
  "powershell-format	lint	adapter:psscriptanalyzer	pwsh	yes	config PSScriptAnalyzerSettings.psd1; binary pwsh on PATH" \
  "$(cd "$REPO" && sh "$CHECK" --resolve)"
expect "--resolve: pwsh off PATH is found no" \
  "powershell-format	lint	adapter:psscriptanalyzer	pwsh	no	config PSScriptAnalyzerSettings.psd1; binary pwsh on PATH" \
  "$(cd "$REPO" && PATH="$NOPWSH" sh "$CHECK" --resolve)"

FORMAT="$HERE/format.sh"
mkdir -p "$WORK/stub"
printf '#!/bin/sh\n: >"%s/stub-ran"\nexit 99\n' "$WORK" >"$WORK/stub/pwsh"
chmod +x "$WORK/stub/pwsh"
lint_with_stub() {
  rm -f "$WORK/stub-ran"
  local out rc
  out="$(cd "$1" && PATH="$WORK/stub:$PATH" bash "$CHECK" 2>&1)"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$([[ -e "$WORK/stub-ran" ]] && echo pwsh-started || echo no-pwsh)"
}
cached() { find "$1/.git/powershell-format-lint" -type f 2>/dev/null | wc -l | tr -d ' '; }

new_repo
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
want="$(cd "$REPO" && bash "$CHECK" 2>&1)"
want="$?|$want|no-pwsh"
new_repo
printf 'get-childitem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
(cd "$REPO" && bash "$FORMAT" >/dev/null 2>&1)
expect "shared run: after format, lint reports what a lint-only run reports, with no pwsh start of its own" \
  "$want" "$(lint_with_stub "$REPO")"
expect "shared run: lint consumes the result format left" "0" "$(cached "$REPO")"

new_repo
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
(cd "$REPO" && bash "$FORMAT" >/dev/null 2>&1)
printf 'Get-ChildItem .\nGet-Date\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
expect "shared run: a file changed after format makes lint start pwsh itself" "pwsh-started" \
  "$(lint_with_stub "$REPO" | sed 's/.*|//')"

new_repo
git -C "$REPO" config checks.powershell-format.lint.declined true
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
(cd "$REPO" && bash "$FORMAT" >/dev/null 2>&1)
expect "shared run: a declined lint entry makes format lint nothing" "0" "$(cached "$REPO")"
git -C "$REPO" config checks.powershell-format.lint.declined false
(cd "$REPO" && bash "$FORMAT" >/dev/null 2>&1)
expect "shared run: a lint entry opted back in is linted by format again" "2" "$(cached "$REPO")"

skip_job() {
  printf 'pre-commit:\n  jobs:\n    - name: powershell-format-remote\n      group:\n        jobs:\n%s\n' "$1"
}
for shape in \
  "name first|          - name: powershell-format-remote-lint
            skip: true" \
  "capitalized boolean|          - name: powershell-format-remote-lint
            skip: True" \
  "skip first, with a comment|          - skip: true # disabled locally
            name: powershell-format-remote-lint" \
  "quoted name, a comment on its own line|          - name: 'powershell-format-remote-lint' # broken here
            # kept for now
            skip: true"; do
  new_repo
  skip_job "${shape#*|}" >"$REPO/lefthook-local.yml"
  printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
  git -C "$REPO" add a.ps1
  (cd "$REPO" && bash "$FORMAT" >/dev/null 2>&1)
  expect "shared run: a lint job skipped in lefthook-local.yml (${shape%%|*}) makes format lint nothing" "0" "$(cached "$REPO")"
done
new_repo
skip_job "          - name: powershell-format-remote-format
            skip: true
          - name: powershell-format-remote-lint" >"$REPO/lefthook-local.yml"
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
(cd "$REPO" && bash "$FORMAT" >/dev/null 2>&1)
expect "shared run: a skip on the format job alone still lets format lint" "2" "$(cached "$REPO")"

new_repo NONE
mkdir -p "$REPO/rules"
printf '@{\n    CustomRulePath = %s\n    IncludeRules = @(%s, %s)\n    Rules = @{ PSUseCorrectCasing = @{ Enable = $true } }\n}\n' \
  "'./rules'" "'PSUseCorrectCasing'" "'PSAvoidGlobalVars'" >"$REPO/PSScriptAnalyzerSettings.psd1"
printf 'function Measure-R {\n    param($ScriptBlockAst)\n    Write-Verbose %s\n}\nExport-ModuleMember -Function Measure-R\n' "'r'" >"$REPO/rules/R.psm1"
git -C "$REPO" add -A
git -C "$REPO" commit -q -m rules --no-verify
printf 'function Measure-R {\n    param($ScriptBlockAst)\n    write-verbose %s\n}\nExport-ModuleMember -Function Measure-R\n' "'r'" >"$REPO/rules/R.psm1"
printf 'Get-ChildItem .\n' >"$REPO/a.ps1"
git -C "$REPO" add -A
marker="$(cd "$REPO" && bash "$CHECK" 2>&1 | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
mkdir -p "$marker"
(cd "$REPO" && bash "$FORMAT" >/dev/null 2>&1)
expect "shared run: format rewrote the approved, staged rule module" "    Write-Verbose 'r'" "$(sed -n 3p "$REPO/rules/R.psm1")"
expect "shared run: with CustomRulePath declared, format lints nothing, so no rule module runs unsigned" "0" "$(cached "$REPO")"
expect "shared run: a rule module format rewrote stops lint at the trust gate, as lint's own start does" yes \
  "$(grep -q 'trust gate: linting skipped' < <(cd "$REPO" && bash "$CHECK" 2>&1) && echo yes || echo no)"

new_repo
printf '%s\n' "$SETTINGS_BODY" '# staged edit' >"$REPO/PSScriptAnalyzerSettings.psd1"
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add -A
(cd "$REPO" && bash "$FORMAT" >/dev/null 2>&1)
expect "shared run: a staged settings file format may rewrite makes format lint nothing" "0" "$(cached "$REPO")"

echo "lint: $PASS passed, $FAIL failed"
((FAIL == 0))
