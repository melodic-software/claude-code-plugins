#!/usr/bin/env bash
# snapshot-tree.sh: print the git tree id of the current work tree, tracked and untracked files
# included and ignored files excluded, so /review:council can diff what a fix pass changed
# (`git diff <before> <after>`), files it created included.
#
# It builds the tree in a throwaway index kept inside the git directory, outside the work tree,
# seeded from the real index, and deletes it on every exit path. No ref, the real index or a
# work-tree file changes; the blobs it writes stay unreferenced until git's own gc removes them.
#
# Usage (from inside the work tree):
#   bash "${CLAUDE_PLUGIN_ROOT}/skills/council/scripts/snapshot-tree.sh"
#
# Output: one 40- or 64-hex tree id on stdout, exit 0; or one stderr line, exit 1.
set -uo pipefail

die() {
  printf 'snapshot-tree.sh: %s\n' "$1" >&2
  exit 1
}

[[ $# -eq 0 ]] || die "takes no arguments"
top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git work tree"
git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || die "cannot resolve the git directory"
real_index=$(git rev-parse --path-format=absolute --git-path index 2>/dev/null) || die "cannot resolve the index path"

tmp_index="$git_dir/council-snapshot-$$.index"
trap 'rm -f "$tmp_index" "$tmp_index.lock"' EXIT
if [[ -f "$real_index" ]]; then
  cp "$real_index" "$tmp_index" || die "cannot copy the index"
fi

GIT_INDEX_FILE="$tmp_index" git -C "$top" add -A -- . 2>/dev/null || die "git add into the throwaway index failed"
tree=$(GIT_INDEX_FILE="$tmp_index" git -C "$top" write-tree 2>/dev/null) || die "git write-tree failed"
printf '%s\n' "$tree"
