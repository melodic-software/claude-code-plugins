#!/usr/bin/env bash
# tree-entries.sh <gated-head> <trusted-base-sha> <tree>
#
# The tree of the merge commit, as entries for the Git Data API. <tree> is the
# tree post.sh wrote from the index it validated, so untracked files
# (claude-code-action's .claude-pr/), unstaged edits and anything staged after
# that check never enter it. These checks guard against model mistakes and
# hostile head content, not against a hostile model on the same runner: the
# lane token is model-reachable by design.
#
# Stdout: one line per path <tree> changes against <gated-head>:
#   <mode> <blob-sha|null> <create-blob|-><TAB><path>
# `null` marks a deletion (the mode is then the gated head's). `create-blob`
# marks a blob neither the gated head nor the trusted base holds at that path,
# so GitHub may not have it yet: the caller uploads only those, which keeps a
# merge that brings thousands of base-side paths to a few blob requests.
#
# Every git call reads gitattributes from the trusted base tree
# (GIT_ATTR_SOURCE, git 2.41 or later).
#
# Exit: 0; 1 on an input that is not a full object id of the right type, a
# path holding a newline, or git failure.
# shellcheck disable=SC2310  # g wraps one git call, so its status is that call's
set -euo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_LITERAL_PATHSPECS=1
g() { git -c core.hooksPath=/dev/null -c core.fsmonitor= -c diff.external= "$@"; }
die() {
  printf 'tree-entries.sh: %s\n' "$*" >&2
  exit 1
}
OID_RE='^[0-9a-f]{40,64}$'

(($# == 3)) || die 'usage: tree-entries.sh <gated-head> <trusted-base-sha> <tree>'
head=$1 base=$2 tree=$3
version=$(git version)
version=${version#git version }
IFS=. read -r major minor _ <<<"$version"
if ! [[ $major =~ ^[0-9]+$ && $minor =~ ^[0-9]+$ ]] || ((major < 2 || (major == 2 && minor < 41))); then
  die "git $version cannot read attributes from a tree (GIT_ATTR_SOURCE); git 2.41 or later is required"
fi
[[ $head =~ $OID_RE ]] || die "gated head must be a full object id, got '$head'"
[[ $base =~ $OID_RE ]] || die "trusted base must be a full object id, got '$base'"
[[ $tree =~ $OID_RE ]] || die "tree must be a full object id, got '$tree'"
g cat-file -e "$head^{commit}" 2>/dev/null || die "gated head $head is not a commit"
g cat-file -e "$base^{commit}" 2>/dev/null || die "trusted base $base is not a commit"
[[ $(g cat-file -t "$tree" 2>/dev/null) == tree ]] || die "$tree is not a tree"
export GIT_ATTR_SOURCE=$base

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

g diff-tree -r --raw -z --no-renames --no-abbrev --no-ext-diff --no-textconv "$head" "$tree" >"$tmp/raw"

# Raw -z records: ":<src-mode> <dst-mode> <src-sha> <dst-sha> <status>" NUL
# "<path>" NUL. The base's object at each path comes from one cat-file batch,
# whose line protocol is why a path may not hold a newline.
metas=() paths=()
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
  [[ $path != *$'\n'* ]] || die 'a staged path holds a newline'
  metas+=("$meta") paths+=("$path")
done <"$tmp/raw"
((${#paths[@]})) || exit 0

for p in "${paths[@]}"; do printf '%s:%s\n' "$base" "$p"; done |
  g cat-file --batch-check='%(objectname)' >"$tmp/base-objects"
mapfile -t base_objects <"$tmp/base-objects"
((${#base_objects[@]} == ${#paths[@]})) || die 'cat-file returned the wrong number of lines'

for i in "${!paths[@]}"; do
  read -r src_mode dst_mode src_sha dst_sha _ <<<"${metas[i]#:}"
  if [[ $dst_mode == 000000 ]]; then
    printf '%s null -\t%s\n' "$src_mode" "${paths[i]}"
    continue
  fi
  flag=create-blob
  if [[ $dst_mode == 160000 || $dst_sha == "$src_sha" || $dst_sha == "${base_objects[i]}" ]]; then flag=-; fi
  printf '%s %s %s\t%s\n' "$dst_mode" "$dst_sha" "$flag" "${paths[i]}"
done
