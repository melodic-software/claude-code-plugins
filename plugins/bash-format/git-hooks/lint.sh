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
  rt_wants "$f" && candidates+=("$f")
done < <(checks_files)
((${#candidates[@]})) || exit 0

rt_group lint "$PWD" "${candidates[@]}"
checks_refuse_config_drift .shellcheckrc shellcheckrc -- "${candidates[@]}" || exit 1
((RT_GN)) || exit 0

files=()
indexed=()
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  for f in "${RT_FILES[@]}"; do
    if [[ -f "$f" && ! -L "$f" ]]; then
      if [[ "$CHECKS_MODE" == pre-commit ]] && checks_partly_staged "$f"; then
        indexed+=("$f")
      else
        files+=("$f")
      fi
    elif checks_staged_gone "$f"; then
      indexed+=("$f")
    fi
  done
done
((${#files[@]} + ${#indexed[@]})) || exit 0
rt_require
case $? in
0) ;;
2) exit 1 ;;
*) exit 0 ;;
esac

checks_changed_lines

out="$CHECKS_TMP/shellcheck"
: >"$out"
rc=0

if ((${#files[@]})); then
  bf_lint_once "$out" 0 "${files[@]}"
  rc=$?
fi
for f in ${indexed[@]+"${indexed[@]}"}; do
  opts=()
  bf_large "$(git show ":$f" 2>/dev/null | bf_lines)" && opts=(--extended-analysis=false)
  git show ":$f" 2>/dev/null | "$RT_BIN" "${BF_SC_ARGS[@]}" ${opts[@]+"${opts[@]}"} - >"$CHECKS_TMP/one" 2>&1
  one=${PIPESTATUS[1]}
  ((one > rc)) && rc=$one
  escaped="$(printf '%s' "$f" | sed 's/[#&\\]/\\&/g')"
  sed "s#^-:#$escaped:#" "$CHECKS_TMP/one" >>"$out"
done
rt_normalize "$out" "$((rc == 1))" >"$CHECKS_TMP/contract" || exit 1
checks_filter_findings <"$CHECKS_TMP/contract" >"$CHECKS_TMP/blocking"
if [[ -s "$CHECKS_TMP/blocking" ]]; then
  cat "$CHECKS_TMP/blocking" >&2
  printf 'bash-format: fix the findings above, or adjust the repository .shellcheckrc.\n' >&2
  exit 1
fi
if ((rc > 1)); then
  printf 'bash-format: shellcheck failed:\n' >&2
  cat "$out" >&2
  exit 1
fi
exit 0
