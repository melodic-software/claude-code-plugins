#!/bin/sh
# javascript-format lint entry: report what the resolved lint command finds on
# the lines this change adds. It never rewrites a file.
#
#   lint.sh             the staged changes (git runs it as pre-commit)
#   lint.sh --worktree  the uncommitted changes against HEAD, untracked files
#                       included (the opt-in end-of-turn Stop row)
#   lint.sh --resolve [<path>...]  print the lint row, or one per path
#                       (resolve-tool.sh rt_print); runs nothing
#
# The command resolves per file through lib/git-hooks/resolve-tool.sh to the
# Biome adapter in adapters.sh where a Biome config governs the file, else to
# nothing; a .claude/ecosystems/ record is never run here. Its output becomes
# "<path>:<line>: <message>" lines, repo-relative, and only those on added
# lines block (stderr, exit 1). A linter that exits non-zero with no parseable
# finding fails closed. A partly staged file is refused, since the linter reads
# the work tree. A staged file gone from the work tree is linted from the index.
# A missing tool follows the check-placement contract: checks.skipmissing,
# else fail for an agent and a notice for a person.
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
if [[ -n "${RT_DRIFT_CONFIGS:-}" ]]; then
  # shellcheck disable=SC2086 # the config names split on spaces
  checks_refuse_config_drift --if rt_config_counts $RT_DRIFT_CONFIGS -- "${candidates[@]}" || exit 1
fi
((RT_GN)) || exit 0

contract="$CHECKS_TMP/contract"
: >"$contract"
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
tool_names=""
for ((i = 0; i < RT_GN; i++)); do
  ((runs[i])) || continue
  rt_use "$i"
  [[ ", $tool_names, " == *", $RT_TOOL, "* ]] || tool_names="${tool_names:+$tool_names, }$RT_TOOL"
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
    rt_lint "${present[@]}" >>"$contract" || failed=1
  fi
  for f in ${gone[@]+"${gone[@]}"}; do
    rt_lint_index "$f" >"$CHECKS_TMP/index" 2>&1
    rt_normalize "$CHECKS_TMP/index" "$?" >>"$contract" || failed=1
  done
done
if [[ -s "$contract" ]]; then
  checks_changed_lines
  checks_filter_findings <"$contract" >"$CHECKS_TMP/blocking"
  if [[ -s "$CHECKS_TMP/blocking" ]]; then
    cat "$CHECKS_TMP/blocking" >&2
    printf '%s: fix the findings %s reported above.\n' "$RT_PLUGIN" "$tool_names" >&2
    failed=1
  fi
fi
exit "$failed"
