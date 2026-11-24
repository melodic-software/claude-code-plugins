#!/bin/sh
# shellcheck shell=bash
case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
lib="$here/check-lib.sh"
# shellcheck disable=SC2292 # still POSIX sh: no [[ ]]
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail

declined="$(git config --type=bool --get checks.guardrails.pre-push-content.declined 2>/dev/null)"
[[ $? -eq 1 ]] && declined="$(git config --type=bool --get checks.git-hooks.declined 2>/dev/null)"
[[ "$declined" == true ]] && exit 0

# shellcheck source=content-scan.sh
. "$here/content-scan.sh" || exit 1

checks_init pre-push "$@" || exit 0
content_scan_init
blocking="$CHECKS_TMP/blocking"
: >"$blocking"

if [[ "$CHECKS_MODE" == worktree ]]; then
  checks_changed_lines
  content_scan "$blocking"
  content_report "$blocking" 'the change (use a placeholder, an environment variable or a portable path)'
fi

commit_ranges() {
  local c=$1 p first="" k=0
  local -a ids=() parents=()
  read -r -a ids < <(git rev-list --parents -n 1 "$c" -- 2>/dev/null)
  ((${#ids[@]} > 1)) && parents=("${ids[@]:1}")
  ((${#parents[@]})) || parents=("$CHECKS_EMPTY_TREE")
  for p in "${parents[@]}"; do
    printf '%s %s\n' "$p" "$c" >"$CHECKS_TMP/push-ranges"
    : >"$CHECKS_TMP/ranges"
    checks_added_ranges "$CHECKS_TMP/ranges" ACMRT
    if ((k++ == 0)); then
      first="$p"
      mv "$CHECKS_TMP/ranges" "$CHECKS_TMP/ranges.all"
      continue
    fi
    checks_intersect_ranges "$CHECKS_TMP/ranges" "$CHECKS_TMP/ranges.all" >"$CHECKS_TMP/ranges.both" ||
      checks_tool_failed awk "$?" 'listing the lines the merge adds'
    mv "$CHECKS_TMP/ranges.both" "$CHECKS_TMP/ranges.all"
  done
  mv "$CHECKS_TMP/ranges.all" "$CHECKS_TMP/ranges"
  printf '%s %s\n' "$first" "$c" >"$CHECKS_TMP/push-ranges"
  other_parents=("${parents[@]:1}")
}

remote="${CHECKS_ARGS%% *}"
[[ -n "$remote" ]] || remote=origin
mv "$CHECKS_TMP/push-ranges" "$CHECKS_TMP/all-ranges"
seen=" "
while read -r base tip <&3; do
  git rev-list --reverse "$tip" --not "$base" --remotes="$remote" -- >"$CHECKS_TMP/commits" 2>/dev/null
  rc=$?
  if ((rc != 0)); then
    checks_tool_failed git "$rc" "listing the commits pushed to $tip"
    continue
  fi
  while read -r c <&4; do
    [[ "$seen" != *" $c "* ]] || continue
    seen+="$c "
    commit_ranges "$c"
    content_scan "$CHECKS_TMP/commit-findings"
    while IFS= read -r finding; do
      printf '%s (commit %s)\n' "$finding" "${c:0:12}"
    done <"$CHECKS_TMP/commit-findings" >>"$blocking"
  done 4<"$CHECKS_TMP/commits"
done 3<"$CHECKS_TMP/all-ranges"

content_report "$blocking" 'the commits that add them (use a placeholder, an environment variable or a portable path, and rewrite each named commit: a later commit that deletes the text still publishes it)'
