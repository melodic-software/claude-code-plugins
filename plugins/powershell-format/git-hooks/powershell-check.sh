#!/usr/bin/env bash
# powershell-format pre-commit check: rewrite the staged PowerShell files, then
# report what PSScriptAnalyzer still finds on the lines this commit adds.
#
#   powershell-check.sh               the staged changes (git runs it as pre-commit)
#   powershell-check.sh --worktree    the uncommitted changes against HEAD,
#                                     untracked files included, reported without
#                                     rewriting (the opt-in end-of-turn Stop row)
#
# Pre-commit: a partly staged file is refused before anything is rewritten
# (re-staging a rewrite would stage its unstaged hunks too). Then Invoke-Formatter
# runs over the staged .ps1, .psm1 and .psd1 files, the rewritten paths print on
# stdout and are re-staged, and the findings that remain print as
# "<path>:<line>: [<severity>] <rule>: <message>" on stderr, exit 1, only for
# lines the commit adds.
#
# Only a file that a PSScriptAnalyzerSettings.psd1 governs is touched (the closest
# one at or above the file, up to the repository root), and the settings file
# supplies the rules. Files under .githooks/ are installed copies and are skipped.
# The work happens in powershell-check.ps1, which sits beside this script, once
# per settings file.
#
# A settings file that declares CustomRulePath would make PSScriptAnalyzer run
# repository-supplied rule modules, so that state is skipped until the user
# approves its exact content: a marker directory under powershell-format/ in the
# repository's git common directory, the one store every commit and the Stop row
# read (CLAUDE_PLUGIN_DATA is not used, since an agent's shell can carry another
# plugin's value). An agent commit is told the verdict and never the command
# that grants the approval.
#
# Missing pwsh follows the check-placement contract in every mode:
# checks.skipmissing, else fail for an agent and a notice for a person. A
# missing PSScriptAnalyzer module is handled the same way under the name
# PSScriptAnalyzer.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1

checks_init pre-commit "$@" || exit 0

ps1="$here/powershell-check.ps1"
[[ -f "$ps1" ]] || exit 0

# find_settings <path>: set SETTINGS to the closest PSScriptAnalyzerSettings.psd1
# at or above the path's directory, up to the repository root; 1 when none.
find_settings() {
  local dir="${1%/*}"
  [[ "$dir" == "$1" ]] && dir=.
  while :; do
    if [[ -f "$dir/PSScriptAnalyzerSettings.psd1" ]]; then
      SETTINGS="$dir/PSScriptAnalyzerSettings.psd1"
      [[ "$dir" == . ]] && SETTINGS=PSScriptAnalyzerSettings.psd1
      return 0
    fi
    [[ "$dir" == . ]] && return 1
    case "$dir" in
      */*) dir="${dir%/*}" ;;
      *) dir=. ;;
    esac
  done
}

files=()
sets=()
SETTINGS=""
while IFS= read -r -d '' f; do
  case "$f" in
    .githooks/*) continue ;;
    *$'\n'*) continue ;;
    *.ps1 | *.psm1 | *.psd1) ;;
    *) continue ;;
  esac
  [[ -f "$f" && ! -L "$f" ]] || continue
  find_settings "$f" || continue
  files+=("$f")
  sets+=("$SETTINGS")
done < <(checks_files)
((${#files[@]})) || exit 0

checks_require_tool pwsh "see https://learn.microsoft.com/powershell/scripting/install/installing-powershell"

if [[ "$CHECKS_MODE" == pre-commit ]]; then
  # Only the PowerShell files are refused, not every staged path, which is what
  # checks_refuse_partly_staged would walk.
  refused=0
  for f in "${files[@]}"; do
    if checks_partly_staged "$f"; then
      printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
      refused=1
    fi
  done
  ((refused)) && exit 1
fi

# to_pwsh_path <path>: PowerShell on Windows does not understand MSYS mount
# paths (/d/...), so a Windows bash with cygpath passes the drive-letter form.
to_pwsh_path() {
  case "${OSTYPE:-}" in
    msys* | cygwin* | win32)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
        return
      fi
      ;;
    *) ;;
  esac
  printf '%s' "$1"
}

state_base=""
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
[[ -z "$common" ]] || state_base="$common/powershell-format"
if [[ "$state_base" == [A-Za-z]:\\* ]] && command -v cygpath >/dev/null 2>&1; then
  state_base="$(cygpath -u "$state_base" 2>/dev/null || printf '%s' "$state_base")"
fi
state_arg=""
[[ -z "$state_base" ]] || state_arg="$(to_pwsh_path "$state_base")"

# trust_notice <pwsh output> <settings>: say why PSScriptAnalyzer was skipped for
# a settings file whose CustomRulePath state is not approved.
trust_notice() {
  local line verdict="" marker="" msg
  while IFS= read -r line; do
    case "$line" in
      "PSSA_TRUST GATE "*)
        verdict=GATE
        marker="${line#PSSA_TRUST GATE }"
        ;;
      "PSSA_TRUST NOSTORE") verdict=NOSTORE ;;
      "PSSA_TRUST UNVERIFIABLE") verdict=UNVERIFIABLE ;;
      "PSSA_TRUST UNPINNABLE") verdict=UNPINNABLE ;;
      *) ;;
    esac
  done <"$1"
  msg="powershell-format trust gate: PSScriptAnalyzer skipped for files under $2;"
  case "$verdict" in
    GATE)
      msg="$msg it loads repository rule modules and is not approved. Approval is the user's."
      if ! checks_is_agent && [[ -n "$state_base" && -n "$marker" ]]; then
        msg="$msg Review that file and every rule module it references, then run: mkdir -p '${state_base%/}/trust-approvals/$marker' (any change to them revokes the approval)."
      fi
      ;;
    UNVERIFIABLE) msg="$msg it cannot be verified free of repository rule modules, so lint stays off." ;;
    UNPINNABLE) msg="$msg a rule module it references loads code no approval can pin, so lint stays off." ;;
    *) msg="$msg it loads repository rule modules and there is no approval store, so lint stays off." ;;
  esac
  printf '%s\n' "$msg" >&2
}

# One PSScriptAnalyzer process per settings file, over all the files it governs.
mode=both
[[ "$CHECKS_MODE" == worktree ]] && mode=analyze
root_arg="$(to_pwsh_path "$PWD")"
ps1_arg="$(to_pwsh_path "$ps1")"
findings="$CHECKS_TMP/findings"
: >"$findings"
broken=0
done_sets=$'\n'
for i in "${!sets[@]}"; do
  set_file="${sets[i]}"
  [[ "$done_sets" != *$'\n'"$set_file"$'\n'* ]] || continue
  done_sets+="$set_file"$'\n'
  list="$CHECKS_TMP/list"
  : >"$list"
  for j in "${!sets[@]}"; do
    [[ "${sets[j]}" == "$set_file" ]] && printf '%s\n' "${files[j]}" >>"$list"
  done
  out="$CHECKS_TMP/pwsh-out"
  PSSA_SETTINGS="$(to_pwsh_path "$PWD/$set_file")" PSSA_ROOT="$root_arg" PSSA_REPO_ROOT="$root_arg" \
  PSSA_LIST="$(to_pwsh_path "$list")" PSSA_MODE="$mode" PSSA_STATE_BASE="$state_arg" \
    pwsh -NoProfile -NonInteractive -File "$ps1_arg" >"$out" 2>&1
  rc=$?
  case $rc in
    0 | 1) { grep -v '^PSSA_' "$out" || :; } | tr -d '\r' >>"$findings" ;;
    3)
      if checks_skip_listed PSScriptAnalyzer; then
        printf 'SKIPPED: PSScriptAnalyzer (missing)\n' >&2
        exit 0
      fi
      if checks_is_agent; then
        printf 'FAIL: PSScriptAnalyzer missing. Install: pwsh -Command Install-Module PSScriptAnalyzer -Scope CurrentUser\n' >&2
        printf 'To skip only while PSScriptAnalyzer is missing: git -c checks.skipmissing=PSScriptAnalyzer %s ...\n' "$(checks_git_verb)" >&2
        exit 1
      fi
      printf 'NOTICE: PSScriptAnalyzer missing, so this check did not run. Install: pwsh -Command Install-Module PSScriptAnalyzer -Scope CurrentUser\n' >&2
      exit 0
      ;;
    6) [[ "$CHECKS_MODE" == worktree ]] || trust_notice "$out" "$set_file" ;;
    *)
      broken=1
      printf 'powershell-format: PSScriptAnalyzer failed under %s:\n' "$set_file" >&2
      sed -e 's/^PSSA_ERROR //' "$out" >&2
      ;;
  esac
done

if [[ "$CHECKS_MODE" == pre-commit ]]; then
  rewritten=()
  while IFS= read -r -d '' f; do
    rewritten+=("$f")
  done < <(git diff --name-only -z -- "${files[@]}")
  if ((${#rewritten[@]})); then
    printf '%s\n' "${rewritten[@]}"
    git add -- "${rewritten[@]}"
  fi
fi

((broken)) && exit 1

checks_changed_lines
checks_filter_findings <"$findings" >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'powershell-format: fix the findings above, or adjust the repository PSScriptAnalyzerSettings.psd1.\n' >&2
exit 1
