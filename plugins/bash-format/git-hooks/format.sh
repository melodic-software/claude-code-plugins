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
# shellcheck source=shfmt-rewrite.sh
. "$here/shfmt-rewrite.sh" || exit 1
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
  rt_wants "$f" || continue
  [[ -f "$f" && ! -L "$f" ]] && candidates+=("$f")
done < <(checks_files)
((${#candidates[@]})) || exit 0

rt_group format "$PWD" "${candidates[@]}"
checks_refuse_config_drift .editorconfig -- "${candidates[@]}" || exit 1
((RT_GN)) || exit 0

governed=()
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  governed+=("${RT_FILES[@]}")
done
rt_require
case $? in
0) ;;
2) exit 1 ;;
*) exit 0 ;;
esac
(checks_require_tool jq "see https://jqlang.org/download/") || exit 1
command -v jq >/dev/null 2>&1 || exit 0

refused=0
for f in "${governed[@]}"; do
  if checks_partly_staged "$f"; then
    printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
    refused=1
  fi
done
((refused)) && exit 1
for f in "${governed[@]}"; do
  shfmt_rewrite "$f"
done
[[ -z "$SHFMT_NOTE" ]] || printf '%s\n' "$SHFMT_NOTE" >&2
checks_restage "${governed[@]}"
exit 0
