#!/bin/sh
# guardrails pre-push check: secrets and machine-specific paths in the lines
# each pushed commit adds.
#
#   pre-push-content.sh <remote> <url>   the pushed commits, refs on stdin (git
#                                        runs it as pre-push)
#   pre-push-content.sh --worktree       the uncommitted changes against HEAD,
#                                        untracked files included
#
# pre-commit-content judges a commit as it is made; a push also carries
# commits that check never judged: made before the hooks were installed, by a
# tool or clone without them, or rebased or cherry-picked in. This entry runs
# the same scan (content-scan.sh, installed beside it as an asset with the
# pattern libraries) on every pushed ref, whatever its name.
#
# The pushed ranges come from the check lib: one per pushed ref, a new branch
# from its merge-base with the remote's default branch, a deletion skipped.
# Each commit in a range is judged on its own, on the lines it adds to its
# parent (commit_ranges), so a secret one commit adds and a later commit of the
# same push removes still blocks: the push would publish it in history. A merge
# is judged on the lines it adds against every parent, which are its conflict
# resolution. A commit one of the remote's tracking refs holds is on the remote
# already and is not judged again.
#
# Findings print as "<path>:<line>: <message> (commit <id>)" on stderr and
# exit 1; the fix is to rewrite the named commit. A text tool or git command
# that fails mid-scan also exits 1, since the scan is incomplete.
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
# shellcheck source=../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail

# A declined entry checks nothing, whichever path registered it: a lefthook
# remote runs this script from the fetched copy, where no installer removed it.
# The keys read as install.mjs reads them: the entry's key at git's precedence,
# unset falling back to the master key, a non-boolean value not declining.
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

# commit_ranges <commit>: $CHECKS_TMP/ranges holds the lines <commit> adds
# against every parent (a root commit, against the empty tree), push-ranges
# names its first parent, so content_scan reads the files it changes from
# there, and other_parents names the rest, so a file a merge takes whole from
# another parent (one judged whole, past the ranges) is not judged again. A
# file any parent holds as a symlink or a submodule counts every line as added
# against it (T); content_scan judges only a regular file, so a file turned
# into a symlink is not read. The ranges keep a binary file's rows, unread:
# content_scan judges a file holding a NUL byte whole before it reads any range.
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
    # Keep only the lines this parent's diff adds too.
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
