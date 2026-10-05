#!/usr/bin/env bash
# Gates for changelog fragments (ADR 0048).
#
#   scripts/check-changelog-fragments.sh --check
#       every file under .changes/ is a valid fragment: .changes/<plugin>/
#       <branch-slug>-<8 hex>.md for a plugin in fragment mode, front matter
#       with one valid `bump`, and a body of known `###` sections (or, for
#       `bump: none`, a non-empty reason)
#   scripts/check-changelog-fragments.sh --check-required <base-ref>
#       a change set that changes a fragment-mode plugin's shipped files adds or
#       modifies a fragment for it; a fragment it adds must not already exist at
#       <base-ref>
#   scripts/check-changelog-fragments.sh --check-release <base-ref>
#       for the release pull request: <base-ref> holds no fragment this release
#       left unconsumed for a plugin whose version it bumps, and no fragment it
#       consumed has changed on <base-ref> since the release was cut. In the
#       merge queue <base-ref> is HEAD^1, the tree the queued commit lands on
#       (main plus every entry ahead of it); a change set that bumps no plugin
#       with pending fragments passes, so the step runs on every queued commit
#
# Shipped files are everything under plugins/<name>/. On the release pull
# request (changelog_fragments::is_release_pr) the root CHANGELOG.md and a
# plugin.json edit to `version` alone are left out: those are what a release
# writes, so it needs no fragment of its own. Any other pull request that edits
# them needs a fragment like any other change, and check-changelog-parity.sh
# --check-bump fails one that bumps the version or adds a CHANGELOG heading.
#
# The diff modes read the change set as check-changelog-parity.sh does: fork
# point to branch tip, with a pull_request merge commit resolved to its branch
# tip.
#
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr. That is
# the check-script family contract stated in README.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/gate-entry.sh
. "$SCRIPT_DIR/lib/gate-entry.sh" || exit 2
# shellcheck source=lib/changelog-fragments.sh
. "$SCRIPT_DIR/lib/changelog-fragments.sh" || exit 2

self="$(basename "$0")"
GE_FLAGS=("--check" "--check-required:ref" "--check-release:ref")
GE_BAD_REF_MSG="$self: base ref '${2-}' is not a resolvable commit."
# shellcheck disable=SC2310  # the non-zero return IS the handled case
if ! gate_entry::classify "$@"; then
  echo "usage: $self [--check | --check-required <base-ref> | --check-release <base-ref>]" >&2
  exit 2
fi
mode="$GE_MODE"
base="$GE_REF"

if [[ "$mode" == --check ]]; then
  fragments=()
  if [[ -d .changes ]]; then
    mapfile -t fragments < <(find .changes -type f | LC_ALL=C sort)
  fi
  invalid=0
  for path in ${fragments[@]+"${fragments[@]}"}; do
    changelog_fragments::validate "$path"
    case $? in
    0) ;;
    1) invalid=$((invalid + 1)) ;;
    *) exit 2 ;;
    esac
  done
  if ((invalid > 0)); then
    echo "$invalid of ${#fragments[@]} changelog fragment(s) are invalid; see docs/adr/0048-release-plugins-from-changelog-fragments-through-a-bot-maintained-release-pr.md for the format." >&2
    gate_entry::finish 1
  fi
  echo "All ${#fragments[@]} changelog fragment(s) under .changes/ are valid."
  gate_entry::finish 0
fi

if ! jq --version >/dev/null 2>&1; then
  echo "$self: jq is required to read manifest versions; refusing to pass without it." >&2
  exit 2
fi

head_commit=HEAD
if git rev-parse -q --verify 'HEAD^2' >/dev/null 2>&1 && git merge-base --is-ancestor 'HEAD^1' "$base" 2>/dev/null; then
  head_commit='HEAD^2'
fi
if ! merge_base="$(git merge-base "$base" "$head_commit")"; then
  echo "$self: 'git merge-base $base $head_commit' failed; refusing to pass without checking." >&2
  exit 2
fi
status_file="$(mktemp)" || exit 2
trap 'rm -f "$status_file"' EXIT
if ! git diff --name-status --no-renames -z "$merge_base" "$head_commit" >"$status_file"; then
  echo "$self: the diff from $merge_base to $head_commit failed; refusing to pass without checking." >&2
  exit 2
fi

manifest_version() { git show "$1:$2" 2>/dev/null | jq -r '.version // empty' 2>/dev/null; }
manifest_sans_version() { git show "$1:$2" 2>/dev/null | jq -cS 'del(.version)' 2>/dev/null; }

release_pr=""
# shellcheck disable=SC2310  # the non-zero return IS the handled case
if changelog_fragments::is_release_pr; then
  release_pr=1
fi
declare -A shipped=() covered=() bumped=() consumed=()
added_fragments=()
while IFS= read -r -d '' status && IFS= read -r -d '' path; do
  case "$path" in
  .changes/*/*)
    rest="${path#.changes/}"
    case "$status" in
    A)
      covered["${rest%%/*}"]=1
      added_fragments+=("$path")
      ;;
    M) covered["${rest%%/*}"]=1 ;;
    D) consumed["$path"]=1 ;;
    *) ;;
    esac
    ;;
  plugins/*/.claude-plugin/plugin.json)
    rest="${path#plugins/}"
    name="${rest%%/*}"
    if [[ "$(manifest_version "$merge_base" "$path")" != "$(manifest_version "$head_commit" "$path")" ]]; then
      bumped["$name"]=1
      [[ -n "$release_pr" ]] || shipped["$name"]=1
    fi
    if [[ "$(manifest_sans_version "$merge_base" "$path")" != "$(manifest_sans_version "$head_commit" "$path")" ]]; then
      shipped["$name"]=1
    fi
    ;;
  plugins/*/*)
    rest="${path#plugins/}"
    name="${rest%%/*}"
    [[ -n "$release_pr" && "$rest" == "$name/CHANGELOG.md" ]] || shipped["$name"]=1
    ;;
  *) ;;
  esac
done <"$status_file"

if [[ "$mode" == --check-required ]]; then
  findings=0
  for path in ${added_fragments[@]+"${added_fragments[@]}"}; do
    if git cat-file -e "$base:$path" 2>/dev/null; then
      echo "FRAGMENT PATH TAKEN: $path already exists at $base; create a new one with scripts/new-changelog-fragment.sh." >&2
      findings=$((findings + 1))
    fi
  done
  checked=0
  for name in "${!shipped[@]}"; do
    changelog_fragments::in_mode "$name"
    case $? in
    0) ;;
    1) continue ;;
    *) exit 2 ;;
    esac
    checked=$((checked + 1))
    [[ -z "${covered[$name]:-}" ]] || continue
    echo "MISSING FRAGMENT: this change set changes files under plugins/$name/ but adds or edits no fragment under .changes/$name/." >&2
    echo "  Run scripts/new-changelog-fragment.sh $name <major|minor|patch|none> and describe the change; use none, with a reason, when it needs no release." >&2
    findings=$((findings + 1))
  done
  if ((findings > 0)); then
    gate_entry::finish 1
  fi
  echo "Every fragment-mode plugin this change set changes ($checked) has a fragment, and no added fragment path exists at $base."
  gate_entry::finish 0
fi

# --check-release
findings=0
for name in "${!bumped[@]}"; do
  if ! pending="$(git ls-tree -r --name-only "$base" -- ".changes/$name/")"; then
    echo "$self: 'git ls-tree $base -- .changes/$name/' failed; refusing to pass without checking." >&2
    exit 2
  fi
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ -n "${consumed[$path]:-}" ]]; then
      # Consumed, but only the content the release was cut from: an edit on the
      # base since then is a change the release never aggregated.
      if ! base_blob="$(git ls-tree "$base" -- "$path")" || ! cut_blob="$(git ls-tree "$merge_base" -- "$path")"; then
        echo "$self: 'git ls-tree' failed reading $path; refusing to pass without checking." >&2
        exit 2
      fi
      [[ "$base_blob" != "$cut_blob" ]] || continue
      echo "EDITED FRAGMENT: $path changed on $base after this release consumed it; rebuild the release from $base." >&2
    else
      echo "UNCONSUMED FRAGMENT: $path is on $base but this release bumps $name without it; rebuild the release from $base." >&2
    fi
    findings=$((findings + 1))
  done <<<"$pending"
done
if ((findings > 0)); then
  gate_entry::finish 1
fi
echo "This release leaves no fragment on $base unconsumed for the ${#bumped[@]} plugin(s) it bumps."
gate_entry::finish 0
