#!/usr/bin/env bash
# tree-entries.sh <gated-head> <trusted-base-sha>
#
# The tree of the merge commit, as entries for the Git Data API, built from the
# index and never from the working tree: untracked files (claude-code-action's
# .claude-pr/) and unstaged edits never enter it.
#
# Stdout: one line per path the index changes against <gated-head>:
#   <mode> <blob-sha|null> <create-blob|-><TAB><path>
# `null` marks a deletion (the mode is then the gated head's). `create-blob`
# marks a blob neither the gated head nor the trusted base holds at that path,
# so GitHub may not have it yet: the caller uploads only those, which keeps a
# merge that brings thousands of base-side paths to a few blob requests.
#
# Exit: 0; 1 on unmerged entries, a path holding a newline, or git failure.
# shellcheck disable=SC2310  # g wraps one git call, so its status is that call's
set -euo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_LITERAL_PATHSPECS=1
g() { git -c core.hooksPath=/dev/null -c core.fsmonitor= -c diff.external= "$@"; }
die() {
  printf 'tree-entries.sh: %s\n' "$*" >&2
  exit 1
}

(($# == 2)) || die 'usage: tree-entries.sh <gated-head> <trusted-base-sha>'
head=$(g rev-parse -q --verify "$1^{commit}") || die "gated head $1 is not a commit"
base=$(g rev-parse -q --verify "$2^{commit}") || die "trusted base $2 is not a commit"
[[ -z $(g ls-files -u) ]] || die 'the index has unmerged entries'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

g diff --cached --raw --no-renames --no-abbrev --no-ext-diff --no-textconv -z "$head" >"$tmp/raw"

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
