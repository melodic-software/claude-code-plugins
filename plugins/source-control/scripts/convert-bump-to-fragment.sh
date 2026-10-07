#!/usr/bin/env bash
# convert-bump-to-fragment.sh: turn a branch's hand-written plugin version bump
# into a changelog fragment, for each plugin the repository releases from
# fragments (the plugins listed in scripts/fragment-plugins.txt, released by a
# bot-maintained release pull request).
#
#   convert-bump-to-fragment.sh [<base-ref>]
#
# A repository without scripts/fragment-plugins.txt has no fragment-mode plugin,
# so there is nothing to convert.
#
# The base is what the branch's version files are compared against: MERGE_HEAD
# while a merge of the default branch into this branch is in progress (the tip
# the merge brings in), else the merge base of HEAD and <base-ref> (default:
# origin's default branch). For each listed plugin whose working-tree
# plugin.json version differs from the base's:
#   - the bump level is the version delta (major, minor or patch);
#   - every `## [<version>]` section of CHANGELOG.md the base lacks is removed,
#     and its body becomes the fragment body (text before any `###` section
#     goes under `### Changed`);
#   - plugin.json's version returns to the base's; every other edit either
#     file carries stays;
#   - scripts/new-changelog-fragment.sh <plugin> <level> creates the fragment,
#     the body is appended to it, and all three files are staged.
# A plugin whose files are still conflicted, whose version went down, or that
# gained a version but no CHANGELOG heading is left untouched. A plugin whose
# CHANGELOG gained a heading while its version stayed, or whose new fragment
# fails changelog_fragments::validate (scripts/lib/changelog-fragments.sh), is
# named for manual work too.
#
# Exit: 0 every bump converted, or none present; 1 at least one plugin left for
# manual conversion (named on stderr); 2 usage, git failure, or a rebase or
# cherry-pick in progress.
set -uo pipefail

if (($# > 1)); then
  echo "usage: ${0##*/} [<base-ref>]" >&2
  exit 2
fi
root=$(git rev-parse --show-toplevel) || exit 2
cd "$root" || exit 2

list=scripts/fragment-plugins.txt
if [[ ! -f $list ]]; then
  echo "No $list here: no plugin releases from fragments, nothing to convert."
  exit 0
fi
# shellcheck source=/dev/null  # the repository's own fragment library
. scripts/lib/changelog-fragments.sh || exit 2
if [[ -d $(git rev-parse --git-path rebase-merge) || -d $(git rev-parse --git-path rebase-apply) ]] ||
  git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null; then
  echo "A rebase or cherry-pick is in progress; finish it, then run this again." >&2
  exit 2
fi
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  base=MERGE_HEAD
else
  ref=${1:-}
  if [[ -z $ref ]]; then
    ref=$(git symbolic-ref -q --short refs/remotes/origin/HEAD) || ref=origin/main
  fi
  base=$(git merge-base HEAD "$ref") || {
    echo "No merge base between HEAD and $ref." >&2
    exit 2
  }
fi

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
status=0

semver() { [[ $1 =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; }
version_headings() { grep -o '^## \[[0-9][^]]*\]' | sort -u; }
set_version() { awk -v v="$1" '!done && sub(/"version"[ \t]*:[ \t]*"[^"]*"/, "\"version\": \"" v "\"") { done = 1 } 1'; }
left() {
  echo "left for manual conversion: plugins/$1 ($2)" >&2
  status=1
}

convert() {
  local name=$1 manifest=plugins/$1/.claude-plugin/plugin.json changelog=plugins/$1/CHANGELOG.md
  local b w level path
  [[ -f $manifest ]] || return 0
  b=$(git show "$base:$manifest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)
  [[ -n $b ]] || return 0
  if [[ -n $(git ls-files -u -- "$manifest" "$changelog") ]]; then
    left "$name" "plugin.json or CHANGELOG.md is still conflicted"
    return
  fi
  w=$(jq -r '.version // empty' "$manifest" 2>/dev/null) || {
    left "$name" "plugin.json does not parse"
    return
  }
  git show "$base:$changelog" 2>/dev/null | version_headings >"$tmp/base.h" || :
  version_headings <"$changelog" >"$tmp/work.h" 2>/dev/null || :
  comm -13 "$tmp/base.h" "$tmp/work.h" >"$tmp/added.h"
  if [[ $w == "$b" ]]; then
    [[ ! -s $tmp/added.h ]] || left "$name" "CHANGELOG.md gained a version heading but plugin.json stayed at $b"
    return 0
  fi
  semver "$b" || {
    left "$name" "base version $b is not semver"
    return
  }
  local bM=${BASH_REMATCH[1]} bm=${BASH_REMATCH[2]} bp=${BASH_REMATCH[3]}
  semver "$w" || {
    left "$name" "version $w is not semver"
    return
  }
  local wM=${BASH_REMATCH[1]} wm=${BASH_REMATCH[2]} wp=${BASH_REMATCH[3]}
  if ((wM > bM)); then
    level="major"
  elif ((wM == bM && wm > bm)); then
    level="minor"
  elif ((wM == bM && wm == bm && wp > bp)); then
    level="patch"
  else
    left "$name" "version went from $b to $w"
    return
  fi

  if [[ ! -s $tmp/added.h ]]; then
    left "$name" "version moved $b -> $w but CHANGELOG.md gained no heading"
    return
  fi
  # Split the changelog into the added sections' bodies and everything else;
  # an added section's text ahead of its first ### section goes under Changed.
  # A ## line inside a code fence is text, not a section boundary.
  awk -v heads="$tmp/added.h" -v body="$tmp/body.raw" -v rest="$tmp/cl.rest" '
    BEGIN { while ((getline h < heads) > 0) added[h] = 1; printf "" > body }
    /^[ \t]*(```|~~~)/ { fence = !fence }
    !fence && /^## / { key = $0; sub(/\].*/, "]", key); insec = (key in added); started = 0; if (insec) next }
    insec {
      sub(/\r$/, "")
      if (!started) {
        if ($0 !~ /[^ \t]/) next
        started = 1
        if ($0 !~ /^### /) print "### Changed\n" > body
      }
      print > body
      next
    }
    { print > rest }' "$changelog"
  # Trim blank edges.
  awk '{ line[NR] = $0; if ($0 ~ /[^ \t]/) { if (!first) first = NR; last = NR } }
    END { for (i = first; first && i <= last; i++) print line[i] }' "$tmp/body.raw" >"$tmp/body"
  if [[ ! -s $tmp/body ]]; then
    left "$name" "the added CHANGELOG section is empty"
    return
  fi
  path=$(scripts/new-changelog-fragment.sh "$name" "$level") || {
    left "$name" "scripts/new-changelog-fragment.sh $name $level failed"
    return
  }
  cat "$tmp/body" >>"$path" || return 2
  set_version "$b" <"$manifest" >"$tmp/pj" || return 2
  # All three files change together or not at all: on any failure, put the
  # manifest and changelog back and drop the fragment, so a re-run sees the bump.
  cp "$manifest" "$tmp/pj.orig" && cp "$changelog" "$tmp/cl.orig" || return 2
  if ! { cp "$tmp/pj" "$manifest" && cp "$tmp/cl.rest" "$changelog" &&
    git add -- "$manifest" "$changelog" "$path"; }; then
    cp "$tmp/pj.orig" "$manifest"
    cp "$tmp/cl.orig" "$changelog"
    git rm -q --cached --ignore-unmatch -- "$path" >/dev/null 2>&1
    rm -f -- "$path"
    echo "Staging the conversion of plugins/$name failed; restored its files." >&2
    return 2
  fi
  echo "converted plugins/$name: $b -> $w becomes $path (bump: $level)"
  changelog_fragments::validate "$path" || left "$name" "edit $path until scripts/check-changelog-fragments.sh --check passes"
}

while IFS= read -r name; do
  [[ -n $name ]] || continue
  convert "$name"
  (($? == 2)) && exit 2
done < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$list")
exit "$status"
