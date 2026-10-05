#!/usr/bin/env bash
# resolve-version-bump-conflict.sh — resolve the collision two concurrent PRs
# create on one plugin's version bump: <plugin>/.claude-plugin/plugin.json and
# <plugin>/CHANGELOG.md, during a merge of main into the PR branch or a
# rebase/cherry-pick of the PR onto main that stopped on conflicts.
#
# Rule: the new version is main's current version bumped once at the level the
# PR used (major, minor or patch against the merge base), so no version number
# is skipped.
# Main's changelog entries are kept; the PR's one new entry is re-headed under
# the new version and placed above main's newest version heading, so
# check-changelog-parity.sh stays green. Every other edit either side made to
# the two files is three-way merged; when that merge conflicts, or the pair does
# not have that shape, the plugin is left untouched for manual resolution.
#
# A plugin that the default branch's scripts/fragment-plugins.txt lists is in
# changelog-fragment mode, where only the release pull request bumps it: the
# resolution is main's plugin.json and CHANGELOG.md, with the PR's entry moved
# into a changelog fragment (scripts/convert-bump-to-fragment.sh in this plugin,
# once available). This script leaves such a plugin untouched and names it.
#
# Both files are recomputed from the three commits, never from the worktree,
# then written and staged. Other conflicted paths are left alone.
#
# Exit: 0 every plugin pair resolved, or none present; 1 at least one pair left
# for manual resolution (named on stderr); 2 git failure.
set -uo pipefail

conflicted_plugins() {
  git diff --name-only --diff-filter=U |
    sed -n -e 's#/\.claude-plugin/plugin\.json$##p' -e 's#/CHANGELOG\.md$##p' | sort -u
}
# Any other operation (a revert, a merge onto the default branch): name the
# conflicted pairs as left for manual resolution, never report them resolved.
unsupported() {
  local dirs
  dirs=$(conflicted_plugins)
  [[ -z $dirs ]] && exit 0
  while IFS= read -r dir; do echo "left for manual resolution: $dir"; done <<<"$dirs" >&2
  exit 1
}

# ponytail: default branch is origin/HEAD, else "main"; add an argument if a repo needs another.
default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD) default=${default#*/}
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  # The sides are known only for a merge of the default branch INTO the PR.
  [[ $(git branch --show-current) == "${default:-main}" ]] && unsupported
  pr=HEAD main=MERGE_HEAD
  base=$(git merge-base HEAD MERGE_HEAD) || exit 2
elif head=$(git rev-parse -q --verify REBASE_HEAD || git rev-parse -q --verify CHERRY_PICK_HEAD); then
  pr=$head main=HEAD base="$head^"
else
  unsupported
fi

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
status=0

semver() { [[ $1 =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; }
version_at() { git show "$1:$2" 2>/dev/null | jq -r '.version // empty'; }
version_headings() { grep -o '^## \[[0-9][^]]*\]' | sort; }
# Replace the first "version" member's value; the three copies then differ only
# where the sides' other edits do.
set_version() { awk -v v="$1" '!done && sub(/"version"[ \t]*:[ \t]*"[^"]*"/, "\"version\": \"" v "\"") { done = 1 } 1'; }

resolve() {
  local dir=$1 manifest=$1/.claude-plugin/plugin.json changelog=$1/CHANGELOG.md
  local b p m new added side
  b=$(version_at "$base" "$manifest") p=$(version_at "$pr" "$manifest") m=$(version_at "$main" "$manifest")
  semver "$b" || return 1
  local bM=${BASH_REMATCH[1]} bm=${BASH_REMATCH[2]} bp=${BASH_REMATCH[3]}
  semver "$p" || return 1
  local pM=${BASH_REMATCH[1]} pm=${BASH_REMATCH[2]} pp=${BASH_REMATCH[3]}
  semver "$m" || return 1
  local mM=${BASH_REMATCH[1]} mm=${BASH_REMATCH[2]} mp=${BASH_REMATCH[3]}
  if ((pM != bM)); then new="$((mM + 1)).0.0"
  elif ((pm != bm)); then new="$mM.$((mm + 1)).0"
  elif ((pp != bp)); then new="$mM.$mm.$((mp + 1))"
  else return 1; fi

  for side in base pr main; do
    git show "${!side}:$changelog" >"$tmp/cl.$side" 2>/dev/null || return 1
    git show "${!side}:$manifest" | set_version "$new" >"$tmp/pj.$side" || return 1
  done
  added=$(comm -13 <(version_headings <"$tmp/cl.base") <(version_headings <"$tmp/cl.pr"))
  [[ -n $added && $added != *$'\n'* ]] || return 1

  # Split the PR's changelog into its new section and everything else.
  awk -v h="$added" -v sec="$tmp/section" -v rest="$tmp/cl.pr.rest" '
    /^## / { insec = (index($0, h) == 1) }
    insec { print > sec; next }
    { print > rest }' "$tmp/cl.pr"
  git merge-file -p "$tmp/cl.pr.rest" "$tmp/cl.base" "$tmp/cl.main" >"$tmp/cl.merged" || return 1
  git merge-file -p "$tmp/pj.pr" "$tmp/pj.base" "$tmp/pj.main" >"$tmp/pj.merged" || return 1
  awk -v old="$added" -v new="## [$new]" -v sec="$tmp/section" '
    function emit(  line, first) {
      first = 1
      while ((getline line < sec) > 0) {
        if (first) { line = new substr(line, length(old) + 1); first = 0 }
        print line
      }
      done = 1
    }
    !done && /^## \[[0-9]/ { emit() }
    { print }
    END { if (!done) emit() }' "$tmp/cl.merged" >"$tmp/cl.final"

  cp "$tmp/cl.final" "$changelog" && cp "$tmp/pj.merged" "$manifest" &&
    git add -- "$changelog" "$manifest" || return 2
  echo "resolved $dir: $b -> PR $p, main $m -> $new"
}

# Plugin names the default branch lists as in fragment mode, `#` comments dropped.
fragment_mode=" $(git show "$main:scripts/fragment-plugins.txt" 2>/dev/null | sed 's/#.*//' | tr -s ' \t\r\n' ' ') "

while IFS= read -r dir; do
  [[ -n $dir && -f $dir/.claude-plugin/plugin.json && -f $dir/CHANGELOG.md ]] || continue
  if [[ $fragment_mode == *" ${dir##*/} "* ]]; then
    echo "left for manual resolution: $dir is in fragment mode; take main's plugin.json and CHANGELOG.md and move the PR's entry into a changelog fragment" >&2
    status=1
    continue
  fi
  resolve "$dir"
  rc=$?
  ((rc == 0)) && continue
  ((rc == 2)) && exit 2
  echo "left for manual resolution: $dir" >&2
  status=1
done < <(conflicted_plugins)
exit "$status"
