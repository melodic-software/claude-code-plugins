#!/bin/sh
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

if [[ "${1:-}" == --resolve ]]; then
  shift
  resolve=()
  for f in "$@"; do
    [[ "$f" == /* ]] || f="$PWD/$f"
    resolve+=("$f")
  done
  checks_init pre-commit --resolve || exit 0
  rt_print lint "$PWD" ${resolve[@]+"${resolve[@]}"}
  exit 0
fi
if [[ "${1:-}" == --base ]]; then
  base_ref="${2:-}"
  shift 2 2>/dev/null || shift
  if [[ -z "$base_ref" ]]; then
    printf '%s\n' 'lint-full.sh: --base needs a ref' >&2
    exit 2
  fi
  checks_init pre-push "$@" </dev/null || exit 0
  if ! fork="$(git merge-base "$base_ref" HEAD 2>/dev/null)"; then
    printf 'lint-full.sh: no merge-base of HEAD and %s, so nothing was checked\n' "$base_ref" >&2
    exit 1
  fi
  printf '%s %s\n' "$fork" "$(git rev-parse HEAD)" >"$CHECKS_TMP/push-ranges"
else
  checks_init pre-push "$@" || exit 0
fi

candidates=()
while IFS= read -r -d '' f; do
  rt_wants "$f" && candidates+=("$f")
done < <(checks_files)
((${#candidates[@]})) || exit 0
rt_group lint "$PWD" "${candidates[@]}"
((RT_GN)) || exit 0

roots=()
targets=()
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  for f in "${RT_FILES[@]}"; do
    tip=""
    if [[ "$CHECKS_MODE" == pre-push ]]; then
      tip="$(checks_range_tip "$f")" || continue
    fi
    checks_file_text --tip "$tip" "$f" >"$CHECKS_TMP/text" || continue
    (($(bf_lines <"$CHECKS_TMP/text") > BF_SC_LARGE_LINES)) || continue
    if [[ -z "$tip" || ("$(git hash-object --no-filters -- "$f" 2>/dev/null)" == "$(git hash-object --no-filters -- "$CHECKS_TMP/text")" && ! -L "$f") ]]; then
      roots+=("$PWD")
      targets+=("$f")
      continue
    fi
    tree="$CHECKS_TMP/tip.$tip"
    if [[ ! -d "$tree" ]] && ! (export GIT_INDEX_FILE="$CHECKS_TMP/index.$tip" &&
      git read-tree "$tip" && git checkout-index -a --prefix="$tree/"); then
      checks_tool_failed git 1 "checking out $tip to lint $f"
      rm -rf "${tree:?}"
      continue
    fi
    roots+=("$tree")
    targets+=("$tree/$f")
  done
done
((${#targets[@]})) || exit 0
rt_require
case $? in
0) ;;
2) exit 1 ;;
*) exit 0 ;;
esac
bf_large "$((BF_SC_LARGE_LINES + 1))" || exit 0

out="$CHECKS_TMP/shellcheck"
: >"$out"
rc=0
top="$RT_DIR"
done_roots=" "
for root in "${roots[@]}"; do
  [[ "$done_roots" == *" $root "* ]] && continue
  done_roots+="$root "
  batch=()
  for k in "${!roots[@]}"; do
    [[ "${roots[k]}" == "$root" ]] && batch+=("${targets[k]}")
  done
  RT_DIR="$root"
  if [[ "$root" == "$top" ]]; then
    bf_lint_once "$out" 1 "${batch[@]}"
  else
    bf_lint "$out" 1 "${batch[@]}"
  fi
  r=$?
  ((r > rc)) && rc=$r
done
RT_DIR="$top"
checks_changed_lines
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
