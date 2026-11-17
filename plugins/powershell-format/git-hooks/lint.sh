#!/bin/sh
# powershell-format lint entry: report what the PSScriptAnalyzer adapter's
# Invoke-ScriptAnalyzer finds on the lines this change adds. It never rewrites a
# file.
#
#   lint.sh             the staged changes (git runs it as pre-commit)
#   lint.sh --worktree  the uncommitted changes against HEAD, untracked files
#                       included (the opt-in end-of-turn Stop row)
#   lint.sh --resolve [<path>...]  print the lint row, or one per path
#                       (resolve-tool.sh rt_print); runs nothing
#
# The command resolves per file through lib/git-hooks/resolve-tool.sh to the
# adapter in adapters.sh where a PSScriptAnalyzerSettings.psd1 governs the file,
# else to nothing; a .claude/ecosystems/ record is never run here. Findings print
# as "<path>:<line>: [<severity>] <rule>: <message>", repo-relative, and only
# those on added lines block (stderr, exit 1). A run that exits non-zero with no
# parseable finding fails closed. A partly staged file is refused, since the
# analyzer reads the work tree. A staged file gone from the work tree is
# analyzed from the index. A settings state that declares CustomRulePath is
# skipped until the user approves it (adapters.sh). A missing pwsh or
# PSScriptAnalyzer module follows the check-placement contract:
# checks.skipmissing, else fail for an agent and a notice for a person.
#
# POSIX sh until check-lib.sh, sourced first, has it running under bash.
# shellcheck shell=bash
case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
lib="$here/check-lib.sh"
# shellcheck disable=SC2292 # still POSIX sh: no [[ ]]
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail
rt="$here/resolve-tool.sh"
[[ -f "$rt" ]] || rt="$here/../lib/git-hooks/resolve-tool.sh"
# shellcheck source=../../../lib/git-hooks/resolve-tool.sh
. "$rt" || exit 1
# shellcheck source=adapters.sh
. "$here/adapters.sh" || exit 1

resolve=()
if [[ "${1:-}" == --resolve ]]; then
  shift
  for f in "$@"; do
    [[ "$f" == /* ]] || f="$PWD/$f"
    resolve+=("$f")
  done
  set -- --resolve
fi
checks_init pre-commit "$@" || exit 0
if [[ " $CHECKS_ARGS " == *" --resolve "* ]]; then
  rt_print lint "$PWD" ${resolve[@]+"${resolve[@]}"}
  exit 0
fi

candidates=()
while IFS= read -r -d '' f; do
  rt_wants "$f" && candidates+=("$f")
done < <(checks_files)
((${#candidates[@]})) || exit 0

rt_group lint "$PWD" "${candidates[@]}"
checks_refuse_config_drift "$PSF_SETTINGS" -- "${candidates[@]}" || exit 1
((RT_GN)) || exit 0

failed=0
# Every group's tool first: a missing one skips its own group only, and an
# agent's missing tool fails the entry after the other groups have reported.
runs=()
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  rt_require
  case $? in
  0) runs[i]=1 ;;
  2) runs[i]=0 failed=1 ;;
  *) runs[i]=0 ;;
  esac
done

# lint_run <run dir> <files...>: one adapter run for the current group, its
# findings appended to the contract file; 1 stops the entry (a missing module).
lint_run() {
  local rc
  psf_run "$@" >"$out" 2>&1
  rc=$?
  case $rc in
  0 | 1) rt_normalize "$out" "$rc" >>"$contract" || failed=1 ;;
  3)
    psf_module_missing
    (($? == 2)) && failed=1
    return 1
    ;;
  6) [[ "$CHECKS_MODE" == worktree ]] || psf_trust_notice "$out" linting ;;
  *)
    psf_broken "$out" Invoke-ScriptAnalyzer
    failed=1
    ;;
  esac
  return 0
}

psf_init "$PWD"
contract="$CHECKS_TMP/contract"
out="$CHECKS_TMP/pwsh-out"
: >"$contract"
for ((i = 0; i < RT_GN; i++)); do
  ((runs[i])) || continue
  rt_use "$i"
  present=()
  gone=()
  for f in "${RT_FILES[@]}"; do
    if [[ -f "$f" && ! -L "$f" ]]; then
      if [[ "$CHECKS_MODE" == pre-commit ]] && checks_partly_staged "$f"; then
        printf '%s: partly staged; lint checks the work tree, so stage it fully, then commit\n' "$f" >&2
        failed=1
      else
        present+=("$f")
      fi
    elif checks_staged_gone "$f"; then
      gone+=("$f")
    fi
  done
  if ((${#present[@]})); then
    lint_run "$RT_DIR" "${present[@]}" || break
  fi
  if ((${#gone[@]})); then
    # The index copies, written under a mirror of the repository, run from the
    # settings directory's mirror, so the findings name the same repo-relative
    # paths; the settings file is still the work tree's.
    staged=()
    for f in "${gone[@]}"; do
      mkdir -p "$CHECKS_TMP/staged/$(dirname -- "$f")"
      git show ":$f" >"$CHECKS_TMP/staged/$f" 2>/dev/null
      staged+=("$CHECKS_TMP/staged/$f")
    done
    mirror="$CHECKS_TMP/staged${RT_DIR#"$PWD"}"
    mkdir -p "$mirror"
    lint_run "$mirror" "${staged[@]}" || break
  fi
done
if [[ -s "$contract" ]]; then
  checks_changed_lines
  checks_filter_findings <"$contract" >"$CHECKS_TMP/blocking"
  if [[ -s "$CHECKS_TMP/blocking" ]]; then
    cat "$CHECKS_TMP/blocking" >&2
    printf 'powershell-format: fix the findings pwsh reported above, or adjust the repository %s.\n' "$PSF_SETTINGS" >&2
    failed=1
  fi
fi
exit "$failed"
