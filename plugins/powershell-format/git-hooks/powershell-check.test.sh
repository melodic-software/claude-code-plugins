#!/usr/bin/env bash
# Contract tests for the powershell-format pre-commit entry
# (git-hooks/powershell-check.sh): staged PowerShell files are rewritten and
# re-staged, a partly staged one is refused untouched, a finding blocks only on a
# line the commit adds, only a file a PSScriptAnalyzerSettings.psd1 governs is
# touched, --worktree reports without rewriting, a missing pwsh or module follows
# the skip-key rule, a CustomRulePath settings state is skipped until approved,
# and the plugin's own vendored installer wires the entry so `git commit` runs it.
# Expected values are PSScriptAnalyzer's documented behavior: PSUseCorrectCasing
# rewrites `get-childitem` to `Get-ChildItem`, and PSAvoidGlobalVars reports a
# `$global:` variable on its own line.
# test-scope: plugins/powershell-format/git-hooks/entries.json plugins/powershell-format/git-hooks/powershell-check.ps1 plugins/powershell-format/lib/git-hooks/check-lib.sh plugins/powershell-format/lib/git-hooks/install.mjs
# shellcheck disable=SC2016  # literal PowerShell variable syntax: single quotes are intentional
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT CLAUDE_PLUGIN_DATA

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/powershell-check.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
if ! command -v pwsh >/dev/null 2>&1 || ! pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { exit 0 } else { exit 1 }' >/dev/null 2>&1; then
  echo "SKIP: pwsh with PSScriptAnalyzer not available -- powershell-check tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Settings that enable a formatter-applied rule (PSUseCorrectCasing) and a
# lint-only rule (PSAvoidGlobalVars) that survives to surface as a finding.
SETTINGS_BODY="@{
    IncludeRules = @('PSUseCorrectCasing', 'PSAvoidGlobalVars')
    Rules = @{ PSUseCorrectCasing = @{ Enable = \$true } }
}"
first_line() { printf '%s' "$1" | head -1 | sed 's/ Found global.*//'; }
HINT='powershell-format: fix the findings above, or adjust the repository PSScriptAnalyzerSettings.psd1.'

n=0
new_repo() { # [NONE for no settings file]
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  if [[ "${1:-}" != NONE ]]; then
    printf '%s\n' "$SETTINGS_BODY" >"$REPO/PSScriptAnalyzerSettings.psd1"
  fi
  printf 'Get-ChildItem .\n' >"$REPO/seed.ps1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m seed --no-verify
}

check() { # <repo> [args...] -> "<rc>|<stdout>|<stderr>"
  local repo="$1" out rc
  shift
  out="$(cd "$repo" && bash "$CHECK" "$@" 2>"$WORK/stderr")"
  rc=$?
  printf '%s|%s|%s' "$rc" "$out" "$(cat "$WORK/stderr")"
}

new_repo
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
expect "a staged miscased file is rewritten, listed on stdout, and exits 0" "0|a.ps1|" "$(check "$REPO")"
expect "the rewrite is in the work tree" "Get-ChildItem ." "$(cat "$REPO/a.ps1")"
expect "the rewrite is re-staged: the index holds the formatted bytes" "Get-ChildItem ." "$(git -C "$REPO" show :a.ps1)"
expect "re-staged: no unstaged change remains" "" "$(git -C "$REPO" diff --name-only)"

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
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
got="$(check "$REPO")"
expect "a finding on an added line blocks, naming that line" "1||a.ps1:2: [Warning] PSAvoidGlobalVars:" "$(first_line "$got")"
expect "the finding is followed by the hint" "$HINT" "$(printf '%s' "$got" | tail -1)"

new_repo
mkdir -p "$REPO/scripts"
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/scripts/gone.ps1"
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add scripts/gone.ps1 a.ps1
rm -r "$REPO/scripts"
got="$(check "$REPO")"
expect "staged then deleted from the work tree: the staged finding still blocks; a present file is still rewritten" "1|a.ps1|scripts/gone.ps1:2: [Warning] PSAvoidGlobalVars:" "$(first_line "$got")"
expect "staged then deleted: the file is not recreated" "no" "$([[ -e "$REPO/scripts/gone.ps1" ]] && echo yes || echo no)"
git -C "$REPO" rm -q --cached scripts/gone.ps1
printf 'get-childitem .\n' >"$REPO/gone.ps1"
ln -s missing.ps1 "$REPO/link.ps1"
git -C "$REPO" add gone.ps1 link.ps1
rm "$REPO/gone.ps1" "$REPO/link.ps1"
got="$(check "$REPO")"
expect "staged then deleted: a miscased file is reported, not rewritten; a symlink is not checked" "1||gone.ps1:1: [Information] PSUseCorrectCasing:" "$(first_line "$got" | sed 's/ PSUseCorrectCasing: .*/ PSUseCorrectCasing:/')"
expect "staged then deleted: the index keeps its bytes" "get-childitem ." "$(git -C "$REPO" show :gone.ps1)"

new_repo
printf '$global:foo = 1\n' >"$REPO/seed.ps1"
git -C "$REPO" add seed.ps1
git -C "$REPO" commit -q -m old --no-verify
printf '$global:foo = 1\nGet-Date\n' >"$REPO/seed.ps1"
git -C "$REPO" add seed.ps1
expect "a finding on a line the commit did not add does not block" "0||" "$(check "$REPO")"

new_repo NONE
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
expect "no settings file: the file is not touched and the check passes" "0||" "$(check "$REPO")"
expect "no settings file: bytes are as written" "get-childitem ." "$(cat "$REPO/a.ps1")"

new_repo
mkdir -p "$REPO/src/deep"
printf 'get-childitem .\n' >"$REPO/src/deep/b.psm1"
printf '@{\n    Severity = @("Error")\n}\n' >"$REPO/src/deep/c.psd1"
git -C "$REPO" add src
expect "the settings file above a nested file governs it, for .psm1 and .psd1 too" "0|src/deep/b.psm1|" "$(check "$REPO")"

new_repo
mkdir -p "$REPO/.githooks/powershell-format"
printf 'get-childitem .\n' >"$REPO/.githooks/powershell-format/copy.ps1"
git -C "$REPO" add -f .githooks/powershell-format/copy.ps1
expect "an installed copy under .githooks/ is skipped" "0||" "$(check "$REPO")"

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
printf 'get-childitem .\n$global:foo = 1\n' >"$REPO/a.ps1"
got="$(check "$REPO" --worktree)"
expect "--worktree: an untracked file is checked whole and blocks" "1||a.ps1:2: [Warning] PSAvoidGlobalVars:" "$(first_line "$got")"
expect "--worktree: the file keeps its bytes" "$(printf 'get-childitem .\n$global:foo = 1')" "$(cat "$REPO/a.ps1")"
rm "$REPO/a.ps1"
expect "--worktree: no uncommitted change passes" "0||" "$(check "$REPO" --worktree)"

# A PATH with the tools the script runs, git and no pwsh.
NOPWSH="$WORK/nopwsh"
mkdir -p "$NOPWSH"
for t in git bash sed awk cat mktemp rm dirname grep tr; do
  ln -s "$(command -v "$t")" "$NOPWSH/$t"
done
INSTALL_HINT='see https://learn.microsoft.com/powershell/scripting/install/installing-powershell'
new_repo
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPWSH" bash "$CHECK" 2>&1)"
expect "missing pwsh: an agent fails with the install command and the skip key" \
  "FAIL: pwsh missing. Install: $INSTALL_HINT
To skip only while pwsh is missing: git -c checks.skipmissing=pwsh commit ..." "$out"
out="$(cd "$REPO" && PATH="$NOPWSH" bash "$CHECK" 2>&1)"
expect "missing pwsh: a person gets a notice and exit 0" "0|NOTICE: pwsh missing, so this check did not run. Install: $INSTALL_HINT" "$?|$out"
git -C "$REPO" config checks.skipmissing pwsh
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPWSH" bash "$CHECK" 2>&1)"
expect "missing pwsh named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: pwsh (missing)" "$?|$out"
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPWSH" bash "$CHECK" --worktree 2>&1)"
expect "missing pwsh named in checks.skipmissing, --worktree: skipped with a line" "0|SKIPPED: pwsh (missing)" "$?|$out"
git -C "$REPO" config --unset checks.skipmissing
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$NOPWSH" bash "$CHECK" --worktree 2>&1)"
expect "missing pwsh, --worktree: an agent fails as at commit time" \
  "1|FAIL: pwsh missing. Install: $INSTALL_HINT" "$?|${out%%$'\n'*}"

# A pwsh that reports the module absent (exit 3 from the script).
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
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$STUB:$PATH" bash "$CHECK" --worktree 2>&1)"
expect "missing module, --worktree: an agent fails as at commit time" \
  "1|FAIL: PSScriptAnalyzer missing. Install: $INSTALL_MOD" "$?|${out%%$'\n'*}"
git -C "$REPO" config checks.skipmissing PSScriptAnalyzer
out="$(cd "$REPO" && CLAUDECODE=1 PATH="$STUB:$PATH" bash "$CHECK" 2>&1)"
git -C "$REPO" config --unset checks.skipmissing
expect "missing module named in checks.skipmissing: skipped with a line, exit 0" "0|SKIPPED: PSScriptAnalyzer (missing)" "$?|$out"

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
  "powershell-format trust gate: PSScriptAnalyzer skipped for files under PSScriptAnalyzerSettings.psd1; it loads repository rule modules and is not approved. Approval is the user's." "$out"
out="$(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" bash "$CHECK" 2>&1)"
marker="$(printf '%s' "$out" | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
expect "the approval store is the git directory even when CLAUDE_PLUGIN_DATA names another" "yes" "$([[ -n "$marker" && "$marker" == "$REPO"/.git/powershell-format/trust-approvals/pssa-* ]] && echo yes)"
mkdir -p "$marker"
expect "an approved state is analyzed and rewritten" "0|crp.ps1|" "$(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" bash "$CHECK" 2>"$WORK/stderr" | {
  read -r l
  printf '0|%s|' "$l"
})"
expect "the approved rewrite landed" "Get-ChildItem ." "$(cat "$REPO/crp.ps1")"
printf '# unreviewed revision\n' >>"$REPO/rules/CleanRules.psm1"
printf 'get-childitem .\n' >"$REPO/crp2.ps1"
git -C "$REPO" add crp2.ps1
(cd "$REPO" && CLAUDE_PLUGIN_DATA="$DATA" CLAUDECODE=1 bash "$CHECK" >/dev/null 2>&1)
expect "a changed rule module revokes the approval" "get-childitem ." "$(cat "$REPO/crp2.ps1")"

# Without CLAUDE_PLUGIN_DATA the store is the same git directory.
(cd "$REPO" && bash "$CHECK" >"$WORK/stdout" 2>"$WORK/stderr")
marker="$(sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p" "$WORK/stderr")"
expect "outside a session the approval store is the git directory" "yes" "$([[ "$marker" == "$REPO"/.git/powershell-format/trust-approvals/pssa-* ]] && echo yes)"

# End to end through the plugin's vendored installer and real commits.
new_repo
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
status="$(node "$INSTALL" copy --scope local --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"powershell-check","status":"installed"}]' "$status"
expect "the installed copy carries the stamp on line 2" yes \
  "$(grep -qE '^# powershell-format powershell-check sha256:[0-9a-f]{64}$' < <(sed -n 2p "$REPO/.git/hooks/powershell-format/powershell-check.sh") && echo yes)"
expect "the PowerShell asset is installed beside the script" yes \
  "$([[ -f "$REPO/.git/hooks/powershell-format/powershell-check.ps1" ]] && echo yes)"
printf 'get-childitem .\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
git -C "$REPO" commit -q -m format >/dev/null 2>&1
expect "git commit runs the entry and succeeds" "0" "$?"
expect "the commit holds the formatted bytes" "Get-ChildItem ." "$(git -C "$REPO" show HEAD:a.ps1)"
expect "the work tree matches the commit" "" "$(git -C "$REPO" status --porcelain)"
printf 'Get-ChildItem .\n$global:foo = 1\n' >"$REPO/a.ps1"
git -C "$REPO" add a.ps1
err="$(git -C "$REPO" commit -q -m finding 2>&1)"
expect "git commit fails on a finding on an added line" "1" "$?"
expect "the commit failure names the line" "a.ps1:2: [Warning] PSAvoidGlobalVars:" "$(printf '%s\n' "$err" | head -1 | sed "s/ Found.*//")"
expect "verify reports ok after the install" "ok	powershell-check" "$(node "$INSTALL" verify --repo "$REPO")"

echo "powershell-check: $PASS passed, $FAIL failed"
((FAIL == 0))
