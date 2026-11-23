#!/bin/sh
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
  [[ ! -L "$f" ]] && rt_wants "$f" && candidates+=("$f")
done < <(checks_files)
((${#candidates[@]})) || exit 0

rt_group lint "$PWD" "${candidates[@]}"
((RT_GN)) || exit 0

contract="$CHECKS_TMP/contract"
: >"$contract"
failed=0
rt_use 0
rt_require
case $? in
0) ;;
2) exit 1 ;;
*) exit 0 ;;
esac
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  whole=()
  for f in "${RT_FILES[@]}"; do
    if [[ -f "$f" && ! -L "$f" ]]; then
      if [[ "$CHECKS_MODE" == pre-commit ]] && checks_partly_staged "$f"; then
        rt_lint_index "$f" >"$CHECKS_TMP/index" 2>&1
        rt_normalize "$CHECKS_TMP/index" "$?" >>"$contract" || failed=1
      else
        whole+=("$f")
      fi
    elif checks_staged_gone "$f"; then
      rt_lint_index "$f" >"$CHECKS_TMP/index" 2>&1
      rt_normalize "$CHECKS_TMP/index" "$?" >>"$contract" || failed=1
    fi
  done
  if ((${#whole[@]})); then
    rt_lint "${whole[@]}" >>"$contract" || failed=1
  fi
done
if [[ -s "$contract" ]]; then
  checks_changed_lines
  sed 's/^\(.*:[0-9][0-9]*: \)error: /\1/' "$contract" | checks_filter_findings >"$CHECKS_TMP/blocking"
  if [[ -s "$CHECKS_TMP/blocking" ]]; then
    cat "$CHECKS_TMP/blocking" >&2
    printf "spelling: fix the words above, allow-list intended ones in the repository typos config (extend-words), or mark generator output with git config --add spelling.generatedHeader '<regex>'.\n" >&2
    failed=1
  fi
fi
exit "$failed"
