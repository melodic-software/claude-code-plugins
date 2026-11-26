#!/usr/bin/env bash
set -uo pipefail

conflicted_plugins() {
  git diff --name-only --diff-filter=U |
    sed -n -e 's#/\.claude-plugin/plugin\.json$##p' -e 's#/CHANGELOG\.md$##p' | sort -u
}
unsupported() {
  local dirs
  dirs=$(conflicted_plugins)
  [[ -z $dirs ]] && exit 0
  while IFS= read -r dir; do echo "left for manual resolution: $dir"; done <<<"$dirs" >&2
  exit 1
}

default=$(git symbolic-ref -q --short refs/remotes/origin/HEAD) default=${default#*/}
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
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
set_version() { awk -v v="$1" '!done && sub(/"version"[ \t]*:[ \t]*"[^"]*"/, "\"version\": \"" v "\"") { done = 1 } 1'; }

linked() { [[ -L $1/CHANGELOG.md || -L $1/.claude-plugin/plugin.json ]]; }

resolve() {
  local dir=$1 manifest=$1/.claude-plugin/plugin.json changelog=$1/CHANGELOG.md
  local b p m new added side
  linked "$dir" && return 1
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

fragment_mode=" $(git show "$main:scripts/fragment-plugins.txt" 2>/dev/null | sed 's/#.*//' | tr -s ' \t\r\n' ' ') "

while IFS= read -r dir; do
  [[ -n $dir ]] || continue
  linked "$dir" || [[ -f $dir/.claude-plugin/plugin.json && -f $dir/CHANGELOG.md ]] || continue
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
