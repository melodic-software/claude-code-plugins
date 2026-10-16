#!/usr/bin/env bash
# instruction-placement pre-commit check: fail when the generated rules index no
# longer matches .claude/rules/.
#
#   index-check.sh               the staged changes (git runs it as pre-commit)
#   index-check.sh --worktree    the uncommitted changes against HEAD
#
# The check runs only when a changed path is under a .claude/rules/ directory
# (a deletion or rename included) or is the index file itself: the root
# AGENTS.md, else the root CLAUDE.md. It compares that file's index block with a
# fresh render and prints the regenerate command when they differ. A repository
# with no index block has not adopted an index and is never failed. This check
# needs no external tool; render-index.sh and discover.sh sit beside this script
# in an installed copy.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
here="$(cd "$here" && pwd)" || exit 1
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1

renderer="$here/render-index.sh"
[[ -f "$renderer" ]] || renderer="$here/../scripts/render-index.sh"
[[ -f "$renderer" ]] || exit 0

checks_init pre-commit "$@" || exit 0

target=""
for candidate in AGENTS.md CLAUDE.md; do
  if [[ -f "$candidate" ]]; then
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

verdict="$(bash "$renderer" check --file "$PWD/$target" --root "$PWD" 2>/dev/null || true)"
[[ "$verdict" == DRIFTED* ]] || exit 0

printf '%s:1: the rules index no longer matches .claude/rules/. Regenerate it: bash "%s" write --file "%s" --root "%s", then stage %s\n' \
  "$target" "$renderer" "$PWD/$target" "$PWD" "$target" >&2
exit 1
