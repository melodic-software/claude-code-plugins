#!/bin/sh
# go-format pre-commit format entry: format the staged Go files with the
# goimports adapter, then re-stage them.
#
#   format.sh             the staged changes (git runs it as pre-commit)
#   format.sh --worktree  the uncommitted changes against HEAD, untracked files
#                         included, parsed without rewriting (the opt-in
#                         end-of-turn Stop row)
#   format.sh --resolve [<path>...]  print the format row, or one per path
#                         (resolve-tool.sh rt_print); runs nothing
#
# The command resolves per file through lib/git-hooks/resolve-tool.sh to the
# goimports adapter in adapters.sh: every Go file but a generated one, with no
# config gate, formatting and import ordering only. A .claude/ecosystems/
# record is never run here; /toolchain:lint and /toolchain:check run it. The
# entry fails only when goimports itself errors, which it does for a file it
# cannot parse: each error prints as "<path>:<line>: <message>" on stderr, exit
# 1, wherever the error sits, since a file that does not parse fails whole.
# Pre-commit: a partly staged file is refused before anything is rewritten
# (re-staging a rewrite would stage its unstaged hunks too); the rewritten
# paths print on stdout and are re-staged. A staged file since deleted from the
# work tree is parsed from the index and never rewritten. A missing tool
# follows the check-placement contract: checks.skipmissing, else fail for an
# agent and a notice for a person.
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
[[ "$CHECKS_MODE" == pre-commit ]] || GF_LIST=1

files=()
gone=()
while IFS= read -r -d '' f; do
  rt_wants "$f" || continue
  if [[ -f "$f" && ! -L "$f" ]]; then
    files+=("$f")
  elif checks_staged_gone "$f"; then
    gf_generated <(git show ":$f" 2>/dev/null) && continue
    gone+=("$f")
  fi
done < <(checks_files)
((${#files[@]} + ${#gone[@]})) || exit 0

rt_group format "$PWD" ${files[@]+"${files[@]}"} ${gone[@]+"${gone[@]}"}
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

is_gone() {
  local g
  for g in ${gone[@]+"${gone[@]}"}; do
    [[ "$g" == "$1" ]] && return 0
  done
  return 1
}

if [[ "$CHECKS_MODE" == pre-commit ]]; then
  refused=0
  for ((i = 0; i < RT_GN; i++)); do
    ((runs[i])) || continue
    rt_use "$i"
    for f in "${RT_FILES[@]}"; do
      if ! is_gone "$f" && checks_partly_staged "$f"; then
        printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
        refused=1
      fi
    done
  done
  ((refused)) && exit 1
fi

errs="$CHECKS_TMP/goimports"
: >"$errs"
written=()
for ((i = 0; i < RT_GN; i++)); do
  ((runs[i])) || continue
  rt_use "$i"
  present=()
  for f in "${RT_FILES[@]}"; do
    if is_gone "$f"; then
      # goimports reads stdin when given no file and names it "<standard input>";
      # -w cannot write stdin, so it is dropped and the result discarded.
      git show ":$f" 2>/dev/null |
        (cd "$RT_DIR" && RT_BIN="$RT_BIN" sh -c "${RT_SCRIPT/ -w / }" sh) 2>"$CHECKS_TMP/one" >/dev/null
      escaped="$(printf '%s' "$f" | sed 's/[#&\\]/\\&/g')"
      sed "s#^<standard input>:#$escaped:#" "$CHECKS_TMP/one" >>"$errs"
    else
      present+=("$f")
    fi
  done
  ((${#present[@]})) || continue
  rt_run "${present[@]}" >/dev/null 2>>"$errs" || :
  written+=("${present[@]}")
done
if [[ "$CHECKS_MODE" == pre-commit ]] && ((${#written[@]})); then
  checks_restage "${written[@]}"
fi

if [[ -s "$errs" ]]; then
  # goimports prints "<path>:<line>:<col>: <message>"; the contract line drops
  # the column. Anything else it prints passes through.
  sed -e 's/^\(.*\.go\):\([0-9][0-9]*\):[0-9][0-9]*: /\1:\2: /' "$errs" >&2
  printf 'go-format: goimports could not process the files above.\n' >&2
  exit 1
fi
exit "$tool_failed"
