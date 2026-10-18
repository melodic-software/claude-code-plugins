#!/usr/bin/env bash
# Writes everything a read activity changed against the gated head, committed,
# staged, unstaged or untracked, as one `git diff --binary` patch, for the
# patch output mode of pr-run-activity-read.yml. Runs from the checkout after
# the activity, through a temporary index, so the checkout's own index is
# untouched. Ignored files are left out.
#
# Usage: collect-patch.sh <head-sha> <patch-file>
# Prints `state=empty` (no change, no patch file) or `state=written`, then
# `sha256=<hex>` of the patch file (empty when there is none): lines for
# $GITHUB_OUTPUT. Exit 2 for bad arguments, 1 when git fails.
#
# The activity ran in this checkout and could have changed its git config, so
# every diff option that changes the patch's form is passed explicitly. The
# patch is still the activity's output: its consumer validates it.
# Contract: docs/conventions/pr-pipeline/pr-run-activity.md, patch output mode.
set -euo pipefail

usage() {
  echo 'usage: collect-patch.sh <40-hex head SHA> <patch file>' >&2
  exit 2
}
fail() {
  echo "collect-patch.sh: $1" >&2
  exit 1
}

[[ $# -eq 2 && -n $2 ]] || usage
head=$1
patch=$2
[[ $head =~ ^[0-9a-f]{40}$ ]] || usage

rm -f -- "$patch"
git cat-file -e "$head^{commit}" 2>/dev/null || fail "the head $head is not a commit here"

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
export GIT_INDEX_FILE="$scratch/index"
g=(git -c core.fsmonitor=false -c core.untrackedCache=false)

"${g[@]}" read-tree "$head" || fail 'could not read the head into a scratch index'
"${g[@]}" add -A || fail 'could not stage the working tree in the scratch index'
"${g[@]}" diff --cached --binary --full-index --no-color --no-ext-diff --no-textconv \
  --no-renames --no-relative --submodule=short --src-prefix=a/ --dst-prefix=b/ -U3 "$head" -- >"$patch" ||
  fail 'could not write the patch'

if [[ ! -s $patch ]]; then
  rm -f -- "$patch"
  printf 'state=empty\nsha256=\n'
  exit 0
fi
sum=$(sha256sum <"$patch")
printf 'state=written\nsha256=%s\n' "${sum%% *}"
