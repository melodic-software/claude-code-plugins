#!/usr/bin/env bash
# test-scope: plugins/powershell-format/.claude-plugin/plugin.json plugins/powershell-format/git-hooks/lint.sh
# test-scope: plugins/powershell-format/git-hooks/entries.json plugins/powershell-format/git-hooks/psscriptanalyzer.ps1 plugins/powershell-format/git-hooks/adapters.sh
# test-scope: plugins/powershell-format/lib/git-hooks/check-lib.sh plugins/powershell-format/lib/git-hooks/install.mjs plugins/powershell-format/lib/git-hooks/resolve-tool.sh
# shellcheck disable=SC2016  # literal PowerShell variable syntax: single quotes are intentional
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT CLAUDE_PLUGIN_DATA

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/format.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
if ! command -v pwsh >/dev/null 2>&1 || ! pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { exit 0 } else { exit 1 }' >/dev/null 2>&1; then
  echo "SKIP: pwsh with PSScriptAnalyzer not available -- format entry tests skipped"
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

new_repo
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
expect "a staged miscased file is rewritten, listed on stdout, and exits 0" "0|a.ps1|" "$(check "$REPO")"
expect "the rewrite is in the work tree" "Get-ChildItem ." "$(cat "$REPO/a.ps1")"
expect "the rewrite is re-staged: the index holds the formatted bytes" "Get-ChildItem ." "$(git -C "$REPO" show :a.ps1)"
expect "re-staged: no unstaged change remains" "" "$(git -C "$REPO" diff --name-only)"

new_repo
printf 'get-childitem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
expect "formatting only: a lint finding on an added line never blocks the format entry" "0|a.ps1|" "$(check "$REPO")"
expect "formatting only: the lint-only rule rewrites nothing" "$(printf 'Get-ChildItem .\n$global:foo = 1')" "$(cat "$REPO/a.ps1")"

new_repo
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
printf 'get-childitem .\nget-date\n' >"$REPO/a.ps1"
expect "a partly staged file is refused with the contract line" "1||a.ps1: partly staged; format it or stage it fully, then commit" "$(check "$REPO")"
expect "a refused file is left byte for byte" "$(printf 'get-childitem .\nget-date')" "$(cat "$REPO/a.ps1")"
expect "a refused file's index entry is left byte for byte" "get-childitem ." "$(git -C "$REPO" show :a.ps1)"

# The settings file is read from the work tree; the commit holds the index's.
DRIFT='config differs between the index and the work tree; stage it or restore it, then commit'
new_repo
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
rm "$REPO/PSScriptAnalyzerSettings.psd1"
expect "a settings file deleted from the work tree refuses the commit, naming it" "1||PSScriptAnalyzerSettings.psd1: $DRIFT" "$(check "$REPO")"
expect "the refused file is left as it was" "get-childitem ." "$(cat "$REPO/a.ps1")"

new_repo
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
printf '@{}\n' >"$REPO/PSScriptAnalyzerSettings.psd1"
expect "a settings file edited after staging refuses the commit" "1||PSScriptAnalyzerSettings.psd1: $DRIFT" "$(check "$REPO")"

new_repo
printf 'get-childitem .\n' >"$REPO/a.ps1"
printf 'notes\n' >"$REPO/notes.md"
git -C "$REPO" add a.ps1 notes.md
printf 'notes\nmore unstaged\n' >"$REPO/notes.md"
expect "a partly staged file that is not PowerShell does not refuse the commit" "0|a.ps1|" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/scripts"
printf 'get-childitem .\n' >"$REPO/scripts/gone.ps1"
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add scripts/gone.ps1 a.ps1
rm -r "$REPO/scripts"
expect "staged then deleted: the present file is still rewritten" "0|a.ps1|" "$(check "$REPO")"
expect "staged then deleted: the file is not recreated" "no" "$([[ -e "$REPO/scripts/gone.ps1" ]] && echo yes || echo no)"
expect "staged then deleted: the index keeps its bytes" "get-childitem ." "$(git -C "$REPO" show :scripts/gone.ps1)"

new_repo NONE
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
expect "no settings file: the file is not touched and the entry passes" "0||" "$(check "$REPO")"
expect "no settings file: bytes are as written" "get-childitem ." "$(cat "$REPO/a.ps1")"

new_repo
mkdir -p "$REPO/src/deep"
printf 'get-childitem .\n' >"$REPO/src/deep/b.psm1"
printf '@{\n    Severity = @("Error")\n}\n' >"$REPO/src/deep/c.psd1"
git -C "$REPO" add src
expect "the settings file above a nested file governs it, for .psm1 and .psd1 too" "0|src/deep/b.psm1|" "$(check "$REPO")"

new_repo NONE
mkdir -p "$REPO/mod"
printf "@{ IncludeRules = @('PSUseCorrectCasing'); Rules = @{ PSUseCorrectCasing = @{ Enable = \$true } } }\n" >"$REPO/mod/PSScriptAnalyzerSettings.psd1"
git -C "$REPO" add mod
git -C "$REPO" commit -q -m mod --no-verify
printf 'get-childitem .\n' >"$REPO/mod/x.ps1"
printf 'get-childitem .\n' >"$REPO/top.ps1"
git -C "$REPO" add mod/x.ps1 top.ps1
expect "a nested settings file governs only its own subtree" "0|mod/x.ps1|" "$(check "$REPO")"
expect "a file above the nested settings is untouched" "get-childitem ." "$(cat "$REPO/top.ps1")"

new_repo
mkdir -p "$REPO/.githooks/powershell-format"
printf 'get-childitem .\n' >"$REPO/.githooks/powershell-format/copy.ps1"
git -C "$REPO" add -f .githooks/powershell-format/copy.ps1
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"
mkdir -p "$REPO/sub/.githooks"
printf 'get-childitem .\n' >"$REPO/sub/.githooks/nested.ps1"
git -C "$REPO" add -f sub/.githooks/nested.ps1
expect "only the root .githooks/ is skipped: a nested one is formatted" "0|sub/.githooks/nested.ps1|" "$(check "$REPO")"

new_repo
printf '\xEF\xBB\xBFget-childitem .\n' >"$REPO/bom.ps1"
git -C "$REPO" add bom.ps1
check "$REPO" >/dev/null
expect "a UTF-8 BOM survives the rewrite" "efbbbf476574" "$(head -c 6 "$REPO/bom.ps1" | od -An -tx1 | tr -d ' \n')"

new_repo
printf 'write-output "\xE9"\n' >"$REPO/ansi.ps1"
git -C "$REPO" add ansi.ps1
before="$(od -An -tx1 <"$REPO/ansi.ps1" | tr -d ' \n')"
expect "a legacy ANSI file is skipped without a message" "0||" "$(check "$REPO")"
expect "a legacy ANSI file keeps its bytes" "$before" "$(od -An -tx1 <"$REPO/ansi.ps1" | tr -d ' \n')"

new_repo
for name in '-lead.ps1' 'a b.ps1' '$(touch pwned).ps1' 'x;touch pwned2.ps1'; do
  printf 'get-childitem .\n' >"$REPO/$name"
done
git -C "$REPO" add -- '-lead.ps1' 'a b.ps1' '$(touch pwned).ps1' 'x;touch pwned2.ps1'
check "$REPO" >/dev/null
got=""
for name in '-lead.ps1' 'a b.ps1' '$(touch pwned).ps1' 'x;touch pwned2.ps1'; do
  got+="$(cat "$REPO/$name")|"
done
expect "crafted file names are formatted as files" "Get-ChildItem .|Get-ChildItem .|Get-ChildItem .|Get-ChildItem .|" "$got"
expect "a crafted file name ran nothing" "no" "$([[ -e "$REPO/pwned" || -e "$REPO/pwned2.ps1" || -e "$REPO/pwned2" ]] && echo yes || echo no)"

new_repo
printf 'get-childitem .\n' >"$REPO/a.ps1"
expect "--worktree: the format entry does nothing" "0||" "$(check "$REPO" --worktree)"
expect "--worktree: the file keeps its bytes" "get-childitem ." "$(cat "$REPO/a.ps1")"

NOPWSH="$WORK/nopwsh"
mkdir -p "$NOPWSH"
for t in git bash sh sed awk cat mktemp rm dirname grep tr; do
  ln -s "$(command -v "$t")" "$NOPWSH/$t"
done
INSTALL_HINT='see https://learn.microsoft.com/powershell/scripting/install/installing-powershell'
new_repo
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPWSH" bash "$CHECK" 2>&1)"
expect "missing pwsh: an agent fails with the install command and the skip key" \
  "1|FAIL: pwsh missing. Install: $INSTALL_HINT
To skip only while pwsh is missing: git -c checks.skipmissing=pwsh commit ..." "$?|$out"
out="$(cd "$REPO" && PATH="$NOPWSH" bash "$CHECK" 2>&1)"
expect "missing pwsh: a person gets a notice and exit 0" "0|NOTICE: pwsh missing, so this check did not run. Install: $INSTALL_HINT" "$?|$out"
git -C "$REPO" config checks.skipmissing pwsh
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPWSH" bash "$CHECK" 2>&1)"
rc=$?
git -C "$REPO" config --unset checks.skipmissing
expect "missing pwsh named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: pwsh (missing)" "$rc|$out"

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
expect "missing module: the file is untouched" "get-childitem ." "$(cat "$REPO/a.ps1")"

printf '#!/usr/bin/env bash\necho "PSSA_ERROR a.ps1: boom"\nexit 4\n' >"$STUB/pwsh"
out="$(cd "$REPO" && PATH="$STUB:$PATH" bash "$CHECK" 2>&1)"
expect "a formatter error fails the entry and shows the error" "1|powershell-format: Invoke-Formatter failed under PSScriptAnalyzerSettings.psd1:
a.ps1: boom" "$?|$out"

# CustomRulePath: skipped until the exact content state is approved.
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
    IncludeRules = @('PSUseCorrectCasing', 'Measure-AlwaysClean')
    Rules = @{ PSUseCorrectCasing = @{ Enable = $true } }
}
EOF
git -C "$REPO" add -A
git -C "$REPO" commit -q -m rules --no-verify
DATA="$WORK/plugin-data"
printf 'get-childitem .\n' >"$REPO/crp.ps1"
git -C "$REPO" add crp.ps1
out="$(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" CLAUDECODE=1 bash "$CHECK" 2>&1)"
expect "unapproved CustomRulePath, agent commit: skipped with the verdict" "0" "$?"
expect "unapproved CustomRulePath: the file is untouched" "get-childitem ." "$(cat "$REPO/crp.ps1")"
expect "an agent is told the verdict and never the approval command" \
  "powershell-format trust gate: formatting skipped for files under PSScriptAnalyzerSettings.psd1; it loads repository rule modules and is not approved. Approval is the user's." "$out"
out="$(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" bash "$CHECK" 2>&1)"
marker="$(printf '%s' "$out" | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
expect "the approval store is the git directory even when CLAUDE_PLUGIN_DATA names another" "yes" "$([[ -n "$marker" && "$marker" == "$REPO"/.git/powershell-format/trust-approvals/pssa-* ]] && echo yes)"
hash() { sha256sum "$1" | cut -d' ' -f1 | tr a-f A-F; }
sig="$(printf '%s\n%s\t%s\n%s\t%s\n' "$REPO" "$REPO/PSScriptAnalyzerSettings.psd1" "$(hash "$REPO/PSScriptAnalyzerSettings.psd1")" \
  "$REPO/rules/CleanRules.psm1" "$(hash "$REPO/rules/CleanRules.psm1")" | sha256sum | cut -d' ' -f1)"
expect "the approval marker is unchanged from the earlier entry's" "$REPO/.git/powershell-format/trust-approvals/pssa-$sig" "$marker"
mkdir -p "$marker"
expect "an approved state is rewritten" "0|crp.ps1|" "$(check "$REPO")"
expect "the approved rewrite landed" "Get-ChildItem ." "$(cat "$REPO/crp.ps1")"
printf '# unreviewed revision\n' >>"$REPO/rules/CleanRules.psm1"
printf 'get-childitem .\n' >"$REPO/crp2.ps1"
git -C "$REPO" add crp2.ps1
(cd "$REPO" && CLAUDECODE=1 bash "$CHECK" >/dev/null 2>&1)
expect "a changed rule module revokes the approval" "get-childitem ." "$(cat "$REPO/crp2.ps1")"

new_repo
expect "--resolve: the repository row names the adapter, its tool and the settings file" \
  "powershell-format	format	adapter:psscriptanalyzer	pwsh	yes	config PSScriptAnalyzerSettings.psd1; binary pwsh on PATH" \
  "$(cd "$REPO" && sh "$CHECK" --resolve)"
new_repo NONE
mkdir -p "$REPO/mod" "$REPO/.claude/ecosystems"
printf '@{}\n' >"$REPO/mod/PSScriptAnalyzerSettings.psd1"
git -C "$REPO" add mod
expect "--resolve <path>: one row per file, naming the settings file that governs it or why none does" \
  "powershell-format	format	adapter:psscriptanalyzer	pwsh	yes	config mod/PSScriptAnalyzerSettings.psd1; binary pwsh on PATH
powershell-format	format	none		n/a	" \
  "$(cd "$REPO" && sh "$CHECK" --resolve mod/x.ps1 top.ps1)"
expect "--resolve: a tracked nested settings file is the repository row" \
  "powershell-format	format	adapter:psscriptanalyzer	pwsh	yes	config mod/PSScriptAnalyzerSettings.psd1; binary pwsh on PATH" \
  "$(cd "$REPO" && sh "$CHECK" --resolve)"
new_repo NONE
mkdir -p "$REPO/.claude/ecosystems"
printf 'globs: ["*.ps1"]\nfix-cmd: "touch ran-record <files>"\n' >"$REPO/.claude/ecosystems/powershell.yaml"
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
expect "--resolve: no settings file, and a record the hooks never run" \
  "powershell-format	format	none		n/a	no PSScriptAnalyzerSettings.psd1; the powershell record is not run by hooks; /toolchain:lint and /toolchain:check run it" \
  "$(cd "$REPO" && sh "$CHECK" --resolve)"
expect "a record with no settings file runs nothing at commit" "0||" "$(check "$REPO")"
expect "the record's command never ran" "no" "$([[ -e "$REPO/ran-record" ]] && echo yes || echo no)"

new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs both entries" '[{"entry":"format","status":"installed"},{"entry":"lint","status":"installed"}]' "$status"
expect "the installed format copy carries the stamp on line 2" yes \
  "$(grep -qE '^# powershell-format format sha256:[0-9a-f]{64}$' < <(sed -n 2p "$REPO/.git/hooks/powershell-format/format.sh") && echo yes)"
expect "the adapter assets are installed beside the scripts" yes \
  "$([[ -f "$REPO/.git/hooks/powershell-format/psscriptanalyzer.ps1" && -f "$REPO/.git/hooks/powershell-format/adapters.sh" && -f "$REPO/.git/hooks/powershell-format/resolve-tool.sh" ]] && echo yes)"
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entries and succeeds" "0" "$?"
expect "the commit holds the formatted bytes" "Get-ChildItem ." "$(git -C "$REPO" show HEAD:a.ps1)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
err="$(git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "a.ps1:2: [Warning] PSAvoidGlobalVars:" "$(printf '%s\n' "$err" | head -1 | sed "s/ Found.*//")"
expect "verify reports both entries ok after the install" "ok	format
ok	lint" "$(node "$INSTALL" verify --repo "$REPO")"

new_repo
git -C "$REPO" config checks.powershell-format.powershell-check.declined true
expect "a powershell-check decline carries to format and lint" "declined,declined" \
  "$(node "$INSTALL" verify --repo "$REPO" | cut -f1 | paste -sd, -)"

printf 'C:\\134 %s 9p rw 0 0\n/dev/sdc / ext4 rw 0 0\n' "$WORK/win" >"$WORK/mounts"
pwshdir="$(dirname "$(command -v pwsh)")"
expect "pwsh runs without PATH entries on a 9p mount" "$WORK/ext:$WORK/winx:$pwshdir|$(command -v pwsh)" \
  "$(PATH="$WORK/win/bin:$WORK/ext:$WORK/win:$WORK/winx:$pwshdir" PSF_MOUNTS="$WORK/mounts" RT_BIN=pwsh "$BASH" -c \
    '. "$1/adapters.sh"; psf__path_without_9p; printf "%s|%s" "$PSF_PATH" "$PSF_BIN"' _ "$HERE")"

echo "format: $PASS passed, $FAIL failed"
((FAIL == 0))
