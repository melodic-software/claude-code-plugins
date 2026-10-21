#!/usr/bin/env bash
# Writes everything a read activity changed against the gated head, committed,
# staged, unstaged or untracked, as one `git diff --binary` patch, for the
# patch output mode of pr-run-activity-read.yml. Runs from the checkout after
# the activity, through a temporary index, so the checkout's own index is
# untouched. Ignored files and .lane/ are left out.
#
# Usage: collect-patch.sh <head-sha> <patch-file>
# Prints `state=empty` (no change, no patch file) or `state=written`, then
# `sha256=<hex>` of the patch file (empty when there is none): lines for
# $GITHUB_OUTPUT. Exit 2 for bad arguments, 1 when git fails.
#
# The activity ran in this checkout and could write its .git, so git never
# reads that directory's config, hooks or info files: it runs against a fresh
# repository in a scratch directory that borrows only the checkout's objects,
# with no global or system config. No filter, hook, fsmonitor or include the
# activity planted runs, and every diff option that changes the patch's form
# is passed explicitly. The patch is still the activity's output: its
# consumer validates it.
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
work=$(pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/home"
: >"$scratch/config"
clean=(env -i PATH=/usr/bin:/bin HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/home"
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$scratch/config" GIT_NO_REPLACE_OBJECTS=1)
"${clean[@]}" git init -q --bare --template= "$scratch/git" || fail 'could not make the scratch repository'
printf '%s\n' "$work/.git/objects" >"$scratch/git/objects/info/alternates"
g=("${clean[@]}" GIT_DIR="$scratch/git" GIT_WORK_TREE="$work" GIT_INDEX_FILE="$scratch/index"
  git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.untrackedCache=false)

"${g[@]}" cat-file -e "$head^{commit}" 2>/dev/null || fail "the head $head is not a commit here"

"${g[@]}" read-tree "$head" || fail 'could not read the head into a scratch index'
# .lane/ holds what the runner staged for the skill (pr-run-activity-read.yml),
# never the activity's change.
paths=(':(top)' ':(top,exclude).lane')
"${g[@]}" add -A -- "${paths[@]}" || fail 'could not stage the working tree in the scratch index'
"${g[@]}" diff --cached --binary --full-index --no-color --no-ext-diff --no-textconv \
  --no-renames --no-relative --submodule=short --src-prefix=a/ --dst-prefix=b/ -U3 "$head" -- "${paths[@]}" >"$patch" ||
  fail 'could not write the patch'

if [[ ! -s $patch ]]; then
  rm -f -- "$patch"
  printf 'state=empty\nsha256=\n'
  exit 0
fi
sum=$(sha256sum <"$patch")
printf 'state=written\nsha256=%s\n' "${sum%% *}"
