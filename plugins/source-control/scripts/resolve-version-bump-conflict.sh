#!/usr/bin/env bash
# resolve-version-bump-conflict.sh — resolve the collision two concurrent PRs
# create on one plugin's version bump: <plugin>/.claude-plugin/plugin.json and
# <plugin>/CHANGELOG.md, during a merge of main into the PR branch or a
# rebase/cherry-pick of the PR onto main that stopped on conflicts.
#
# Rule: the new version is the higher of main's and the PR's version, bumped
# once at the level the PR used (major, minor or patch against the merge base).
# Main's changelog entries are kept; the PR's one new entry is re-headed under
# the new version and placed above main's newest version heading, so
# check-changelog-parity.sh stays green. Every other edit either side made to
# the two files is three-way merged; when that merge conflicts, or the pair does
# not have that shape, the plugin is left untouched for manual resolution.
#
# Both files are recomputed from the three commits, never from the worktree,
# then written and staged. Other conflicted paths are left alone.
#
# Exit: 0 every plugin pair resolved, or none present; 1 at least one pair left
# for manual resolution (named on stderr); 2 git failure.
set -uo pipefail

if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  pr=HEAD main=MERGE_HEAD
  base=$(git merge-base HEAD MERGE_HEAD) || exit 2
elif head=$(git rev-parse -q --verify REBASE_HEAD || git rev-parse -q --verify CHERRY_PICK_HEAD); then
  pr=$head main=HEAD base="$head^"
else
  exit 0
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
  local b p m hM hm hp new added side
  b=$(version_at "$base" "$manifest") p=$(version_at "$pr" "$manifest") m=$(version_at "$main" "$manifest")
  semver "$b" || return 1
  local bM=${BASH_REMATCH[1]} bm=${BASH_REMATCH[2]} bp=${BASH_REMATCH[3]}
  semver "$p" || return 1
  local pM=${BASH_REMATCH[1]} pm=${BASH_REMATCH[2]} pp=${BASH_REMATCH[3]}
  semver "$m" || return 1
  local mM=${BASH_REMATCH[1]} mm=${BASH_REMATCH[2]} mp=${BASH_REMATCH[3]}
  if ((mM > pM || (mM == pM && (mm > pm || (mm == pm && mp >= pp))))); then
    hM=$mM hm=$mm hp=$mp
  else
    hM=$pM hm=$pm hp=$pp
  fi
  if ((pM != bM)); then new="$((hM + 1)).0.0"
  elif ((pm != bm)); then new="$hM.$((hm + 1)).0"
  elif ((pp != bp)); then new="$hM.$hm.$((hp + 1))"
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

while IFS= read -r dir; do
  [[ -n $dir && -f $dir/.claude-plugin/plugin.json && -f $dir/CHANGELOG.md ]] || continue
  resolve "$dir"
  rc=$?
  ((rc == 0)) && continue
  ((rc == 2)) && exit 2
  echo "left for manual resolution: $dir" >&2
  status=1
done < <(git diff --name-only --diff-filter=U |
  sed -n -e 's#/\.claude-plugin/plugin\.json$##p' -e 's#/CHANGELOG\.md$##p' | sort -u)
exit "$status"
