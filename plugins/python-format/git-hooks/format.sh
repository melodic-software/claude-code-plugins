#!/bin/sh
# python-format pre-commit format entry: rewrite the staged Python files with
# the resolved format command, then re-stage them.
#
#   format.sh             the staged changes (git runs it as pre-commit)
#   format.sh --worktree  does nothing: formatting happens at commit
#   format.sh --resolve [<path>...]  print the format row, or one per path
#                         (resolve-tool.sh rt_print);
#                         reads the record, runs nothing
#
# The command resolves per file through lib/git-hooks/resolve-tool.sh: the
# repository's approved python record (fix-cmd), else the Ruff adapter in
# adapters.sh, else nothing. An unapproved record runs nothing; a record the
# reader cannot parse fails the commit. A partly staged file is refused before
# anything is rewritten (re-staging a rewrite would stage its unstaged hunks
# too), and so is a commit whose Ruff config above a file no record binds
# differs between the index and the work tree. A staged file since deleted
# from the work tree is never rewritten. A missing tool follows the
# check-placement contract: checks.skipmissing, else fail for an agent and a
# notice for a person.
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
if [[ -n "$RT_GFAIL" ]]; then
  printf '%s: %s; fix the record, then commit\n' "$RT_PLUGIN" "${RT_GFAIL%$'\n'}" >&2
  exit 1
fi
if [[ -n "${RT_DRIFT_CONFIGS:-}" ]] && ((${#RT_GOTHER[@]})); then
  # shellcheck disable=SC2086 # the config names split on spaces
  checks_refuse_config_drift --if rt_config_counts $RT_DRIFT_CONFIGS -- "${RT_GOTHER[@]}" || exit 1
fi
((RT_GN)) || exit 0

refused=0
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  rt_require
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
exit 0
