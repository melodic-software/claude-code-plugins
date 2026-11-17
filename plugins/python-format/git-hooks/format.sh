#!/bin/sh
# python-format pre-commit format entry: rewrite the staged Python files with
# the resolved format command, then re-stage them.
#
#   format.sh             the staged changes (git runs it as pre-commit)
#   format.sh --worktree  does nothing: formatting happens at commit
#   format.sh --resolve [<path>...]  print the format row, or one per path
#                         (resolve-tool.sh rt_print);
#                         runs nothing
#
# The command resolves per file through lib/git-hooks/resolve-tool.sh to the
# Ruff adapter in adapters.sh where a Ruff config governs the file, else to
# nothing; a .claude/ecosystems/ record is never run here. A partly staged file
# is refused before anything is rewritten (re-staging a rewrite would stage its
# unstaged hunks too), and so is a commit whose Ruff config above a staged file
# differs between the index and the work tree. A staged file since deleted from
# the work tree is never rewritten. A missing tool follows the check-placement
# contract: checks.skipmissing, else fail for an agent and a notice for a
# person.
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
  rt_print format "$PWD" ${resolve[@]+"${resolve[@]}"}
  exit 0
fi
[[ "$CHECKS_MODE" == pre-commit ]] || exit 0

candidates=()
while IFS= read -r -d '' f; do
  rt_wants "$f" && candidates+=("$f")
done < <(checks_files)
((${#candidates[@]})) || exit 0

rt_group format "$PWD" "${candidates[@]}"
if [[ -n "${RT_DRIFT_CONFIGS:-}" ]]; then
  # shellcheck disable=SC2086 # the config names split on spaces
  checks_refuse_config_drift --if rt_config_counts $RT_DRIFT_CONFIGS -- "${candidates[@]}" || exit 1
fi
((RT_GN)) || exit 0

# Every group's tool first: a missing one skips its own group only, and an
# agent's missing tool fails the entry once the other groups have run.
runs=()
tool_failed=0
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  rt_require
  case $? in
  0) runs[i]=1 ;;
  2) runs[i]=0 tool_failed=1 ;;
  *) runs[i]=0 ;;
  esac
done

refused=0
for ((i = 0; i < RT_GN; i++)); do
  ((runs[i])) || continue
  rt_use "$i"
  for f in "${RT_FILES[@]}"; do
    if [[ -f "$f" && ! -L "$f" ]] && checks_partly_staged "$f"; then
      printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
      refused=1
    fi
  done
done
((refused)) && exit 1

written=()
for ((i = 0; i < RT_GN; i++)); do
  ((runs[i])) || continue
  rt_use "$i"
  present=()
  for f in "${RT_FILES[@]}"; do
    [[ -f "$f" && ! -L "$f" ]] && present+=("$f")
  done
  ((${#present[@]})) || continue
  rt_run "${present[@]}" >/dev/null 2>&1 || :
  written+=("${present[@]}")
done
((${#written[@]})) && checks_restage "${written[@]}"
exit "$tool_failed"
