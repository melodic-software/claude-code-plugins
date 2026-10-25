#!/bin/sh
# instruction-placement pre-commit check: fail when the generated rules index no
# longer matches .claude/rules/.
#
#   index-check.sh               the staged changes (git runs it as pre-commit)
#   index-check.sh --worktree    the uncommitted changes against HEAD
#
# The check runs only when a changed path is under a .claude/rules/ directory
# (a deletion or rename included) or is the index file itself: the root
# AGENTS.md, else the root CLAUDE.md. It compares that file's index block with a
# fresh render (at pre-commit, of the staged copies) and prints the regenerate
# command when they differ. A renderer error blocks. A repository
# with no index block has not adopted an index and is never failed. This check
# needs no external tool; render-index.sh and discover.sh sit beside this script
# in an installed copy.
#
# POSIX sh until check-lib.sh, sourced first, has it running under bash.
# shellcheck shell=bash
case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
here="$(cd "$here" && pwd)" || exit 1
lib="$here/check-lib.sh"
# shellcheck disable=SC2292 # still POSIX sh: no [[ ]]
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail

renderer="$here/render-index.sh"
[[ -f "$renderer" ]] || renderer="$here/../scripts/render-index.sh"
[[ -f "$renderer" ]] || exit 0

checks_init pre-commit "$@" || exit 0

# At pre-commit the verdict is on what the commit holds: the index copies of the
# instruction files and rules, materialized into a scratch tree. --worktree
# judges the work tree.
src="$PWD"
if [[ "$CHECKS_MODE" == pre-commit ]]; then
  src="$CHECKS_TMP/index"
  mkdir -p "$src" || exit 1
  git ls-files -z -- ':(glob)**/AGENTS.md' ':(glob)**/CLAUDE.md' ':(glob)**/.claude/rules/**/*.md' |
    git checkout-index -z --stdin --prefix="$src/" || exit 1
fi

target=""
for candidate in AGENTS.md CLAUDE.md; do
  if [[ -f "$src/$candidate" ]]; then
    target="$candidate"
    break
  fi
done
[[ -n "$target" ]] || exit 0

relevant=0
while IFS= read -r -d '' f; do
  case "$f" in
  .claude/rules/*.md | */.claude/rules/*.md | "$target")
    relevant=1
    break
    ;;
  *) ;;
  esac
done < <(
  checks_diff --name-only --no-renames -z
  [[ "$CHECKS_MODE" == worktree ]] && git ls-files --others --exclude-standard -z
)
((relevant)) || exit 0

# check exits 0 in sync, 1 drifted, 3 with no index block (not adopted); any
# other status is no verdict, and no verdict blocks.
verdict="$(checks_bash_run "$renderer" check --file "$src/$target" --root "$src" 2>"$CHECKS_TMP/render.err")"
rc=$?
((rc == 0 || rc == 3)) && exit 0
if [[ $rc -ne 1 || "$verdict" != DRIFTED* ]]; then
  cat "$CHECKS_TMP/render.err" >&2
  printf 'instruction-placement: render-index.sh check exited %s without a verdict; fix what it reports above.\n' "$rc" >&2
  exit 1
fi

printf '%s:1: the rules index no longer matches .claude/rules/. Regenerate it: bash "%s" write --file "%s" --root "%s", then stage %s\n' \
  "$target" "$renderer" "$PWD/$target" "$PWD" "$target" >&2
exit 1
