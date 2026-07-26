#!/usr/bin/env bash
# Black-box contract test for powershell-format.sh (the powershell-format plugin hook).
#
# Proves WIRING: the hook fires on .ps1/.psm1/.psd1, skips otherwise, applies
# PSScriptAnalyzer's formatting (alias expansion), surfaces residual findings via
# additionalContext (advisory, exit 0), honors the kill switch, gates on a
# consumer PSScriptAnalyzerSettings.psd1 (present -> run, absent -> leave bytes
# untouched), trust-gates a CustomRulePath-declaring settings state on explicit
# approval, degrades cleanly when the PSScriptAnalyzer module is unavailable,
# and emits a schema-valid telemetry envelope.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures. The
# hook is invoked from an UNRELATED cwd so any reliance on the caller's working
# directory would surface (settings discovery is file-anchored).
#
# Requires a real pwsh with the PSScriptAnalyzer module. Without pwsh the whole
# suite skips; the pwsh-absent and module-absent GRACEFUL-DEGRADE paths are
# exercised separately by simulating their absence, so they run even where a real
# pwsh + module is present.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/powershell-format.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

# Settings that enable a formatter-applied rule (PSUseCorrectCasing, which
# Invoke-Formatter rewrites in place) and a semantic lint rule (PSAvoidGlobalVars,
# which the formatter never rewrites, so it survives to surface as a finding).
SETTINGS_BODY="@{
    IncludeRules = @('PSUseCorrectCasing','PSAvoidGlobalVars','PSUseConsistentIndentation')
    Rules = @{
        PSUseCorrectCasing = @{ Enable = \$true }
        PSUseConsistentIndentation = @{ Enable = \$true; IndentationSize = 4 }
    }
}"

# new_repo <dir> [NO_SETTINGS] -> init a git repo, writing PSScriptAnalyzerSettings.psd1
# at the root unless the second arg is the literal NO_SETTINGS.
new_repo() {
  local r="$1" mode="${2:-}"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
  if [[ "$mode" != "NO_SETTINGS" ]]; then
    printf '%s\n' "$SETTINGS_BODY" >"$r/PSScriptAnalyzerSettings.psd1"
  fi
}

# Invoke the hook from an unrelated cwd. CLAUDE_PROJECT_DIR is left UNSET so
# read_file_path's membership guard is disabled (not part of the fire gate).
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true bash "$HOOK"
  )
}

# Same as run_hook but with caller-supplied extra env (NAME=VALUE or -u NAME ...).
run_hook_env() {
  local file_path="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK"
  )
}

# make_sink <body> -> path to an executable single-command stub sink running
# <body> (which reads the envelope on stdin). HOOK_TELEMETRY_SINK must be a
# single executable path, not a command-with-args, so tests point it at a stub.
make_sink() {
  local s
  s="$(mktemp -p "$WORK" sink.XXXXXX)"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$1"
  } >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}

# wait_for_sink <file> [tries] -> block until <file> is non-empty (the
# fire-and-forget sink flushed) or the bound elapses, polling in 20ms steps.
wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

# ============================================================================
# GRACEFUL DEGRADE — run regardless of pwsh/module presence
# ============================================================================

# --- pwsh absent -> clean silent skip ----------------------------------------
# Simulate a pwsh-less box by dropping pwsh-containing dirs from PATH while
# retaining jq/git/dirname. Works where pwsh has its own dir (Windows: Program
# Files\PowerShell); on a runner where pwsh shares /usr/bin with coreutils the
# drop would also lose jq, so that case is skipped.
_pwsh_free_usable() {
  PATH="$1" jq --version >/dev/null 2>&1 &&
    PATH="$1" git --version >/dev/null 2>&1 &&
    PATH="$1" dirname / >/dev/null 2>&1 &&
    ! PATH="$1" command -v pwsh >/dev/null 2>&1
}
_filtered=""
IFS=':' read -ra _path_dirs <<<"$PATH"
for _d in "${_path_dirs[@]}"; do
  [[ -x "$_d/pwsh" || -x "$_d/pwsh.exe" ]] && continue
  _filtered="${_filtered:+$_filtered:}$_d"
done
REPO_ABSENT="$WORK/pwsh-absent"
new_repo "$REPO_ABSENT"
printf "%s\n" "gci -Path '.'" >"$REPO_ABSENT/a.ps1"
BEFORE_ABSENT="$(cat "$REPO_ABSENT/a.ps1")"
if _pwsh_free_usable "$_filtered"; then
  OUT=$(run_hook_env "$REPO_ABSENT/a.ps1" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true PATH="$_filtered")
  RC=$?
  if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "pwsh absent -> exit 0, silent (clean skip)"; else fail "pwsh absent not silent (rc=$RC out=$OUT)"; fi
  if [[ "$(cat "$REPO_ABSENT/a.ps1")" == "$BEFORE_ABSENT" ]]; then ok "pwsh absent -> file left untouched"; else fail "pwsh absent -> file was rewritten"; fi
else
  echo "SKIP: could not assemble a pwsh-free PATH retaining jq/git/dirname"
fi

# --- exit-code mappings via a stub pwsh (module-absent + tool-break) ---------
# The pwsh block signals PSScriptAnalyzer-module-absent as exit 3 and an
# analyzer throw (bad settings, internal error) as exit 4. A real installed
# module cannot be hidden on Windows (PSScriptAnalyzer ships in $PSHOME and
# PSModulePath cannot drop it), so a stub pwsh emitting those exits proves the
# hook's bash-side mapping deterministically — and runs even where no real pwsh
# is present. The stub takes precedence via a prepended PATH entry.
STUB_BIN="$WORK/stub-bin"
mkdir -p "$STUB_BIN"
make_stub_pwsh() {
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$1"
  } >"$STUB_BIN/pwsh"
  chmod +x "$STUB_BIN/pwsh"
}
REPO_STUB="$WORK/stub-repo"
new_repo "$REPO_STUB"
printf "%s\n" "Get-ChildItem -Path '.'" >"$REPO_STUB/s.ps1"
BEFORE_STUB="$(cat "$REPO_STUB/s.ps1")"

# exit 3 -> module absent -> clean silent skip
make_stub_pwsh 'exit 3'
OUT=$(run_hook_env "$REPO_STUB/s.ps1" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true PATH="$STUB_BIN:$PATH")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "module absent (pwsh exit 3) -> exit 0, silent (clean skip)"; else fail "module absent not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_STUB/s.ps1")" == "$BEFORE_STUB" ]]; then ok "module absent -> file left untouched"; else fail "module absent -> file was rewritten"; fi

# exit 4 (+ stderr) -> analyzer threw -> advisory tool-break context, exit 0
make_stub_pwsh 'echo "boom: bad settings" >&2; exit 4'
OUT=$(run_hook_env "$REPO_STUB/s.ps1" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true PATH="$STUB_BIN:$PATH")
RC=$?
if [[ $RC -eq 0 ]]; then ok "tool break (pwsh exit 4) -> exit 0 (advisory)"; else fail "tool break exit $RC (must be advisory)"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -qi 'tool break' && printf '%s' "$CTX" | grep -q 'boom'; then
    ok "tool break -> surfaced as advisory (not a finding)"
  else
    fail "tool break -> not in tool-break branch: $CTX"
  fi
else
  fail "tool break -> no additionalContext JSON: $OUT"
fi
rm -f "$STUB_BIN/pwsh"

# --- settings walk-up bounded by CLAUDE_PROJECT_DIR ceiling ------------------
# A settings file ABOVE CLAUDE_PROJECT_DIR (but still inside the git repo) must
# NOT govern an edit inside the project — the walk stops at the project-dir
# ceiling, matching the membership guard hook::read_file_path enforces. Runs
# without pwsh: with no settings found within the ceiling, the skip fires before
# the pwsh call. The git-root-fallback contrast (CLAUDE_PROJECT_DIR unset finds
# the same root settings) is Case 1b below, which needs a real pwsh.
REPO_CEIL="$WORK/ceiling"
new_repo "$REPO_CEIL" # settings at git root
mkdir -p "$REPO_CEIL/proj/sub"
# SC2016: literal PowerShell variable syntax — single quotes are intentional.
# shellcheck disable=SC2016
printf '%s\n' '$global:c = 1' >"$REPO_CEIL/proj/sub/c.ps1"
BEFORE_CEIL="$(cat "$REPO_CEIL/proj/sub/c.ps1")"
OUT=$(
  cd "$UNRELATED" || exit 1
  printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_CEIL/proj/sub/c.ps1" |
    CLAUDE_PROJECT_DIR="$REPO_CEIL/proj" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true bash "$HOOK"
)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "settings above CLAUDE_PROJECT_DIR ceiling -> not found, silent skip"; else fail "ceiling not respected (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_CEIL/proj/sub/c.ps1")" == "$BEFORE_CEIL" ]]; then ok "ceiling -> file left untouched"; else fail "ceiling -> file was rewritten"; fi

# ============================================================================
# Behavioral cases — require a real pwsh + PSScriptAnalyzer module
# ============================================================================
if ! command -v pwsh >/dev/null 2>&1; then
  echo "SKIP: no pwsh on PATH -- powershell-format behavioral tests skipped"
  echo
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
  exit $?
fi
if ! pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { exit 0 } else { exit 1 }' >/dev/null 2>&1; then
  echo "SKIP: PSScriptAnalyzer module not installed -- powershell-format behavioral tests skipped"
  echo
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
  exit $?
fi

# --- Case 1: opt-in gate OFF (no settings) -> file left untouched -------------
REPO_NO="$WORK/no-settings"
new_repo "$REPO_NO" NO_SETTINGS
printf "%s\n" "gci -Path '.'" >"$REPO_NO/nofmt.ps1"
BEFORE_NO="$(cat "$REPO_NO/nofmt.ps1")"
OUT=$(run_hook "$REPO_NO/nofmt.ps1")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "gate OFF (no settings) -> exit 0, silent"; else fail "gate OFF not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_NO/nofmt.ps1")" == "$BEFORE_NO" ]]; then ok "gate OFF -> file left untouched"; else fail "gate OFF -> file was rewritten"; fi

# --- Case 1b: ceiling contrast — CLAUDE_PROJECT_DIR unset finds git-root cfg --
# Reuses the REPO_CEIL tree from the ceiling case above. With CLAUDE_PROJECT_DIR
# unset, run_hook's walk ceiling falls back to the git root, so the root settings
# file IS found and the global-var finding surfaces — proving the ceiling case's
# skip was the bound working, not a missing settings file.
# SC2016: literal PowerShell variable syntax — single quotes are intentional.
# shellcheck disable=SC2016
printf '%s\n' '$global:d = 1' >"$REPO_CEIL/proj/sub/d.ps1"
OUT=$(run_hook "$REPO_CEIL/proj/sub/d.ps1")
if printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q 'PSAvoidGlobalVars'; then
  ok "CLAUDE_PROJECT_DIR unset -> git-root settings found (walk fallback)"
else
  fail "git-root fallback did not find settings: $OUT"
fi

# --- Case 2: gate ON + clean file -> exit 0, empty stdout --------------------
REPO="$WORK/consumer"
new_repo "$REPO"
printf "%s\n" "Get-ChildItem -Path '.'" >"$REPO/clean.ps1"
OUT=$(run_hook "$REPO/clean.ps1")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean .ps1 -> exit 0"; else fail "clean .ps1 exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "clean .ps1 -> empty stdout"; else fail "clean .ps1 stdout not empty: $OUT"; fi

# --- Case 3: gate ON + wrong casing -> formatter fixes it in place ------------
# PSUseCorrectCasing is applied by Invoke-Formatter (unlike alias expansion,
# which is a lint-only rule). The subdir file exercises the settings walk.
mkdir -p "$REPO/src"
printf "%s\n" "get-childitem -Path '.'" >"$REPO/src/fmt.ps1"
OUT=$(run_hook "$REPO/src/fmt.ps1")
RC=$?
if [[ $RC -eq 0 ]]; then ok "format case -> exit 0 (advisory)"; else fail "format case exit $RC"; fi
if grep -q 'Get-ChildItem' "$REPO/src/fmt.ps1"; then
  ok "gate ON (subdir file) -> formatter fixed the casing in place"
else
  fail "gate ON -> casing not fixed: $(cat "$REPO/src/fmt.ps1")"
fi

# --- Case 4: gate ON + lint finding (global var) -> advisory context ---------
mkdir -p "$REPO/lib"
# SC2016: literal PowerShell variable syntax — single quotes are intentional.
# shellcheck disable=SC2016
printf '%s\n' '$global:foo = 1' >"$REPO/lib/lint.ps1"
OUT=$(run_hook "$REPO/lib/lint.ps1")
RC=$?
if [[ $RC -eq 0 ]]; then ok "lint finding -> exit 0 (advisory)"; else fail "lint finding exit $RC (must be advisory)"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -q 'PSAvoidGlobalVars'; then
    ok "lint finding -> surfaced in additionalContext"
  else
    fail "lint ctx missing the finding: $CTX"
  fi
else
  fail "lint finding -> no additionalContext JSON: $OUT"
fi

# --- Case 5: .psm1 and .psd1 extensions match --------------------------------
printf "%s\n%s\n%s\n" "function Get-Foo {" "    Write-Output 'x'" "}" >"$REPO/mod.psm1"
OUT=$(run_hook "$REPO/mod.psm1")
RC=$?
if [[ $RC -eq 0 ]]; then ok ".psm1 -> exit 0 (glob matches)"; else fail ".psm1 exit $RC"; fi
printf "%s\n%s\n%s\n" "@{" "    Severity = @('Error')" "}" >"$REPO/data.psd1"
OUT=$(run_hook "$REPO/data.psd1")
RC=$?
if [[ $RC -eq 0 ]]; then ok ".psd1 -> exit 0 (glob matches)"; else fail ".psd1 exit $RC"; fi

# --- Case 6: non-matching extension -> exit 0 silently -----------------------
echo "console.log('x')" >"$REPO/notes.js"
OUT=$(run_hook "$REPO/notes.js")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "non-matching ext -> exit 0 silent"; else fail "non-matching ext not skipped (rc=$RC out=$OUT)"; fi

# --- Case 7: kill switch bypasses hook ---------------------------------------
printf "%s\n" "gci -Path '.'" >"$REPO/kill.ps1"
BEFORE_K="$(cat "$REPO/kill.ps1")"
OUT=$(run_hook_env "$REPO/kill.ps1" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=false)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch off -> exit 0 silent"; else fail "kill switch failed (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO/kill.ps1")" == "$BEFORE_K" ]]; then ok "kill switch -> file untouched"; else fail "kill switch -> file was modified"; fi

# --- Case 8: UTF-8 BOM survives a reformat (encoding preservation) -----------
# pwsh's Set-Content default (utf8NoBOM) would strip the BOM on the first
# auto-format; the hook must write back with the detected original encoding.
printf '\xEF\xBB\xBFget-childitem -Path '"'"'.'"'"'\n' >"$REPO/bom.ps1"
OUT=$(run_hook "$REPO/bom.ps1")
RC=$?
if [[ $RC -eq 0 ]]; then ok "BOM file -> exit 0"; else fail "BOM file exit $RC"; fi
if grep -q 'Get-ChildItem' "$REPO/bom.ps1"; then ok "BOM file -> casing fixed (formatter ran)"; else fail "BOM file -> casing not fixed: $(cat "$REPO/bom.ps1")"; fi
BOM_HEX=$(head -c 6 "$REPO/bom.ps1" | od -An -tx1 | tr -d ' \n')
if [[ "$BOM_HEX" == "efbbbf476574" ]]; then
  ok "BOM file -> single UTF-8 BOM preserved on write-back"
else
  fail "BOM file -> leading bytes changed: $BOM_HEX (expected efbbbf476574)"
fi

# --- Case 9: legacy ANSI (invalid UTF-8) -> skipped byte-identical ------------
# A BOM-less file that is not valid UTF-8 cannot be round-tripped safely; the
# hook must skip it (exit 5 arm) rather than transcode. Wrong casing proves the
# skip: had the formatter run, it would have rewritten it.
printf 'write-output "\xE9"\n' >"$REPO/ansi.ps1"
ANSI_HEX_BEFORE=$(od -An -tx1 <"$REPO/ansi.ps1" | tr -d ' \n')
OUT=$(run_hook "$REPO/ansi.ps1")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "ANSI file -> exit 0 silent skip"; else fail "ANSI file (rc=$RC out=$OUT)"; fi
if [[ "$(od -An -tx1 <"$REPO/ansi.ps1" | tr -d ' \n')" == "$ANSI_HEX_BEFORE" ]]; then
  ok "ANSI file -> byte-identical (never transcoded)"
else
  fail "ANSI file -> bytes changed"
fi

# --- Case 10: CustomRulePath trust gate + relative rule path resolution ------
# A settings file that declares CustomRulePath makes PSScriptAnalyzer load and
# execute repository-supplied rule modules, so the hook must SKIP the run —
# with a visible notice on both channels — until the user approves that exact
# settings-content state; any settings change must revoke the approval. Once
# approved, the run must succeed from an unrelated cwd, proving the hook
# anchors relative CustomRulePath resolution at the settings directory
# (without that anchor this repo's analysis throws -> tool break).
REPO_CRP="$WORK/customrule"
new_repo "$REPO_CRP" NO_SETTINGS
mkdir -p "$REPO_CRP/rules"
cat >"$REPO_CRP/rules/CleanRules.psm1" <<'EOF'
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
cat >"$REPO_CRP/PSScriptAnalyzerSettings.psd1" <<'EOF'
@{
    CustomRulePath = './rules/CleanRules.psm1'
    IncludeRules = @('PSUseCorrectCasing', 'Measure-AlwaysClean')
    Rules = @{
        PSUseCorrectCasing = @{ Enable = $true }
    }
}
EOF
printf "%s\n" "get-childitem -Path '.'" >"$REPO_CRP/crp.ps1"
CRP_DATA="$WORK/crp-plugin-data"

OUT_GATE_1=$(run_hook_env "$REPO_CRP/crp.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
RC_GATE_1=$?
if [[ $RC_GATE_1 -eq 0 ]]; then ok "unapproved CustomRulePath -> exit 0 (advisory)"; else fail "unapproved CustomRulePath exit $RC_GATE_1"; fi
if printf '%s' "$OUT_GATE_1" | jq -e '(.hookSpecificOutput.additionalContext | contains("trust gate") and contains("CustomRulePath")) and (.systemMessage | contains("trust gate"))' >/dev/null 2>&1; then
  ok "unapproved CustomRulePath -> trust-gate notice on both channels"
else
  fail "trust-gate notice absent: $OUT_GATE_1"
fi
if grep -q 'get-childitem' "$REPO_CRP/crp.ps1"; then
  ok "unapproved CustomRulePath -> analyzer blocked (file untouched)"
else
  fail "unapproved CustomRulePath still ran the analyzer: $(cat "$REPO_CRP/crp.ps1")"
fi

# Same state, same session: the notice dedupes, but the run stays blocked.
OUT_GATE_2=$(run_hook_env "$REPO_CRP/crp.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
if [[ -z "$OUT_GATE_2" ]] && grep -q 'get-childitem' "$REPO_CRP/crp.ps1"; then
  ok "unchanged unapproved state notices once, stays blocked"
else
  fail "unchanged unapproved state (out=$OUT_GATE_2 file=$(cat "$REPO_CRP/crp.ps1"))"
fi

# The notice's approval instruction must name a marker under this plugin-data
# store; creating that marker is the explicit opt-in that enables the run.
CRP_MARKER="$(printf '%s' "$OUT_GATE_1" | jq -r '.systemMessage' | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
if [[ -n "$CRP_MARKER" && "$CRP_MARKER" == "$CRP_DATA"/* ]]; then
  ok "trust-gate notice carries an approval marker under CLAUDE_PLUGIN_DATA"
else
  fail "trust-gate approval marker missing or misplaced: $OUT_GATE_1"
fi
mkdir -p "$CRP_MARKER"
OUT_GATE_3=$(run_hook_env "$REPO_CRP/crp.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
RC_GATE_3=$?
if [[ $RC_GATE_3 -eq 0 && -z "$OUT_GATE_3" ]]; then ok "approved CustomRulePath -> exit 0, no tool break, no notice"; else fail "approved CustomRulePath (rc=$RC_GATE_3 out=$OUT_GATE_3)"; fi
if grep -q 'Get-ChildItem' "$REPO_CRP/crp.ps1"; then
  ok "approved CustomRulePath -> relative rule path resolved, formatter ran"
else
  fail "approved CustomRulePath -> formatter did not run: $(cat "$REPO_CRP/crp.ps1")"
fi

# A settings-content change produces a new state signature: the approval is
# revoked, and the gate blocks — and notices, despite the same session — again.
printf '%s\n' '# unreviewed settings revision' >>"$REPO_CRP/PSScriptAnalyzerSettings.psd1"
printf "%s\n" "get-childitem -Path '.'" >"$REPO_CRP/crp2.ps1"
OUT_GATE_4=$(run_hook_env "$REPO_CRP/crp2.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
if printf '%s' "$OUT_GATE_4" | jq -e '.hookSpecificOutput.additionalContext | contains("trust gate")' >/dev/null 2>&1 &&
  grep -q 'get-childitem' "$REPO_CRP/crp2.ps1"; then
  ok "changed settings state revokes approval and blocks again"
else
  fail "changed settings state was not re-gated: $OUT_GATE_4"
fi

# The approval signature must cover the rule-module content, not only the
# settings text: after approving a settings state, changing a referenced rule
# module (settings untouched) must revoke the approval — e.g. a branch switch
# swapping the module bytes under an unchanged settings file.
CRP_MARKER_2="$(printf '%s' "$OUT_GATE_4" | jq -r '.systemMessage' | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
mkdir -p "$CRP_MARKER_2"
printf "%s\n" "get-childitem -Path '.'" >"$REPO_CRP/crp2b.ps1"
OUT_GATE_M1=$(run_hook_env "$REPO_CRP/crp2b.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
if [[ -z "$OUT_GATE_M1" ]] && grep -q 'Get-ChildItem' "$REPO_CRP/crp2b.ps1"; then
  ok "re-approved settings+module state analyzes again"
else
  fail "re-approved settings+module state did not analyze: $OUT_GATE_M1 $(cat "$REPO_CRP/crp2b.ps1")"
fi
printf '%s\n' '# unreviewed rule-module revision' >>"$REPO_CRP/rules/CleanRules.psm1"
printf "%s\n" "get-childitem -Path '.'" >"$REPO_CRP/crp3.ps1"
OUT_GATE_M2=$(run_hook_env "$REPO_CRP/crp3.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
if printf '%s' "$OUT_GATE_M2" | jq -e '.hookSpecificOutput.additionalContext | contains("trust gate")' >/dev/null 2>&1 &&
  grep -q 'get-childitem' "$REPO_CRP/crp3.ps1"; then
  ok "changed rule module revokes approval and blocks again"
else
  fail "changed rule module was not re-gated: $OUT_GATE_M2 $(cat "$REPO_CRP/crp3.ps1")"
fi

# Transitive dependency: a file the rule module references by string literal is
# part of the code that runs, so it is pinned too — changing ONLY that file
# (settings and declared module untouched) must revoke the approval.
cat >>"$REPO_CRP/rules/CleanRules.psm1" <<'EOF'
$rulesHelper = './helper.ps1'
EOF
printf '%s\n' '# helper v1' >"$REPO_CRP/rules/helper.ps1"
printf "%s\n" "get-childitem -Path '.'" >"$REPO_CRP/crp4.ps1"
OUT_GATE_T1=$(run_hook_env "$REPO_CRP/crp4.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
T_MARKER="$(printf '%s' "$OUT_GATE_T1" | jq -r '.systemMessage' | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
mkdir -p "$T_MARKER"
OUT_GATE_T2=$(run_hook_env "$REPO_CRP/crp4.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
if [[ -n "$T_MARKER" && -z "$OUT_GATE_T2" ]] && grep -q 'Get-ChildItem' "$REPO_CRP/crp4.ps1"; then
  ok "approved state including transitive helper analyzes"
else
  fail "approved transitive state did not analyze: m=$T_MARKER out=$OUT_GATE_T2 $(cat "$REPO_CRP/crp4.ps1")"
fi
printf '%s\n' '# unreviewed helper revision' >>"$REPO_CRP/rules/helper.ps1"
printf "%s\n" "get-childitem -Path '.'" >"$REPO_CRP/crp5.ps1"
OUT_GATE_T3=$(run_hook_env "$REPO_CRP/crp5.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
if printf '%s' "$OUT_GATE_T3" | jq -e '.hookSpecificOutput.additionalContext | contains("trust gate")' >/dev/null 2>&1 &&
  grep -q 'get-childitem' "$REPO_CRP/crp5.ps1"; then
  ok "changed transitive helper revokes approval and blocks again"
else
  fail "changed transitive helper was not re-gated: $OUT_GATE_T3 $(cat "$REPO_CRP/crp5.ps1")"
fi

# The standard self-relative dependency form `. "$PSScriptRoot/x.ps1"` resolves
# against the module's own directory, so the scan must pin it there: changing
# only that helper must revoke the approval.
cat >>"$REPO_CRP/rules/CleanRules.psm1" <<'EOF'
. "$PSScriptRoot/helper2.ps1"
EOF
printf '%s\n' 'function Get-CrpHelperTwo { return 2 }' >"$REPO_CRP/rules/helper2.ps1"
printf "%s\n" "get-childitem -Path '.'" >"$REPO_CRP/crp6.ps1"
OUT_GATE_P1=$(run_hook_env "$REPO_CRP/crp6.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
P_MARKER="$(printf '%s' "$OUT_GATE_P1" | jq -r '.systemMessage' | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
mkdir -p "$P_MARKER"
OUT_GATE_P2=$(run_hook_env "$REPO_CRP/crp6.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
if [[ -n "$P_MARKER" && -z "$OUT_GATE_P2" ]] && grep -q 'Get-ChildItem' "$REPO_CRP/crp6.ps1"; then
  ok "approved state including PSScriptRoot-relative helper analyzes"
else
  fail "approved PSScriptRoot-relative state did not analyze: m=$P_MARKER out=$OUT_GATE_P2 $(cat "$REPO_CRP/crp6.ps1")"
fi
printf '%s\n' '# unreviewed helper2 revision' >>"$REPO_CRP/rules/helper2.ps1"
printf "%s\n" "get-childitem -Path '.'" >"$REPO_CRP/crp7.ps1"
OUT_GATE_P3=$(run_hook_env "$REPO_CRP/crp7.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
if printf '%s' "$OUT_GATE_P3" | jq -e '.hookSpecificOutput.additionalContext | contains("trust gate")' >/dev/null 2>&1 &&
  grep -q 'get-childitem' "$REPO_CRP/crp7.ps1"; then
  ok "changed PSScriptRoot-relative helper revokes approval and blocks again"
else
  fail "changed PSScriptRoot-relative helper was not re-gated: $OUT_GATE_P3 $(cat "$REPO_CRP/crp7.ps1")"
fi

# Fail closed: with no CLAUDE_PLUGIN_DATA an approval can be neither recorded
# nor verified, so a CustomRulePath settings state must still skip the run (and
# notice every time — the once-per-session gate fails open toward visibility
# when it has no marker store).
OUT_GATE_5=$(run_hook_env "$REPO_CRP/crp2.ps1" -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
if printf '%s' "$OUT_GATE_5" | jq -e '.systemMessage | contains("trust gate")' >/dev/null 2>&1 &&
  grep -q 'get-childitem' "$REPO_CRP/crp2.ps1"; then
  ok "CustomRulePath without a plugin-data store fails closed"
else
  fail "CustomRulePath without a plugin-data store did not fail closed: $OUT_GATE_5"
fi

# Textual-scan evasion: key detection uses PowerShell's restricted data-file
# parser, so a backtick-escaped double-quoted key ("CustomRule`Path" evaluates
# to CustomRulePath) must still gate — a grep for the literal key would miss it.
REPO_ESC="$WORK/customrule-escaped"
new_repo "$REPO_ESC" NO_SETTINGS
cat >"$REPO_ESC/PSScriptAnalyzerSettings.psd1" <<'EOF'
@{
    "CustomRule`Path" = './rules/CleanRules.psm1'
    IncludeRules = @('PSUseCorrectCasing')
}
EOF
printf "%s\n" "get-childitem -Path '.'" >"$REPO_ESC/esc.ps1"
OUT_GATE_6=$(run_hook_env "$REPO_ESC/esc.ps1" CLAUDE_PLUGIN_DATA="$CRP_DATA" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
if printf '%s' "$OUT_GATE_6" | jq -e '.systemMessage | contains("trust gate")' >/dev/null 2>&1 &&
  grep -q 'get-childitem' "$REPO_ESC/esc.ps1"; then
  ok "escaped CustomRulePath key still gates (restricted-parser detection)"
else
  fail "escaped CustomRulePath key evaded the gate: $OUT_GATE_6"
fi

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) -----------------------------
OUT_NS=$(run_hook_env "$REPO/clean.ps1" -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true)
RC_NS=$?
if [[ $RC_NS -eq 0 && -z "$OUT_NS" ]]; then
  ok "telemetry/sink-unset: exit 0, empty stdout (parity)"
else
  fail "telemetry/sink-unset: rc=$RC_NS out=$OUT_NS"
fi

# --- Stub sink + lint finding -> envelope status ok with findings ------------
# SC2016: literal PowerShell variable syntax — single quotes are intentional.
# shellcheck disable=SC2016
printf '%s\n' '$global:tel = 1' >"$REPO/tel.ps1"
TEL="$(mktemp)"
SINK="$(make_sink "cat >\"$TEL\"")"
run_hook_env "$REPO/tel.ps1" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
wait_for_sink "$TEL"
if [[ -s "$TEL" ]]; then
  ok "telemetry/stub-sink: envelope received"
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    if jq -e "has(\"$field\")" "$TEL" >/dev/null 2>&1; then
      ok "envelope: $field present"
    else
      fail "envelope: $field missing ($(cat "$TEL"))"
    fi
  done
  if [[ "$(jq -r '.hook' "$TEL")" == "powershell-format" ]]; then ok "envelope: hook is powershell-format"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.0" ]]; then ok "envelope: schema_version 1.0"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

# --- Stub sink + gate OFF (no settings) -> status skipped --------------------
printf "%s\n" "gci -Path '.'" >"$REPO_NO/tel2.ps1"
TELS="$(mktemp)"
SINKS="$(make_sink "cat >\"$TELS\"")"
run_hook_env "$REPO_NO/tel2.ps1" CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKS" >/dev/null
wait_for_sink "$TELS"
if [[ -s "$TELS" ]]; then
  if [[ "$(jq -r '.status' "$TELS")" == "skipped" ]]; then ok "telemetry/gate-off: status skipped"; else fail "telemetry/gate-off: status=$(jq -r '.status' "$TELS")"; fi
  if [[ "$(jq '.data.findings | length' "$TELS")" -eq 0 ]]; then ok "telemetry/gate-off: findings empty array"; else fail "telemetry/gate-off: findings not empty"; fi
else
  fail "telemetry/gate-off: no envelope written"
fi
rm -f "$TELS"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
