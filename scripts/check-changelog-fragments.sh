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
#       <base-ref>. A Dependabot pull request whose every commit is a verified
#       Dependabot commit needs no fragment: scripts/dependabot-fragments.sh
#       writes it after the merge (changelog_fragments::dependabot_only in
#       scripts/lib/changelog-fragments.sh)
#   scripts/check-changelog-fragments.sh --check-release <base-ref>
#       for the release pull request: no file the release changes (a consumed
#       fragment, a CHANGELOG.md, a plugin.json) has changed on <base-ref> since
#       the release was cut, its build base being the merge base with
#       <base-ref>. A fragment <base-ref> added since then rides the next
#       release. In the merge queue (GITHUB_EVENT_NAME=merge_group) <base-ref>
#       is the group's base commit and the release is CHANGELOG_PR_HEAD, the
#       queued pull request's head; without a readable one it refuses
#
# Shipped files are everything under plugins/<name>/, or docs/conventions/<name>/
# for a listed convention. On the release pull request
# (changelog_fragments::is_release_pr) the root CHANGELOG.md and a plugin.json
# edit to `version` alone are left out: those are what a release writes, so it
# needs no fragment of its own. A convention's release is a new newest
# CHANGELOG heading, so that is what --check-release counts as its bump. Any other pull request that edits
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
# CHECK_DATA_ROOT: the tree to check, when it is not the one holding this
# script (scripts/check-affected.sh sets it; code still loads from SCRIPT_DIR).
cd "${CHECK_DATA_ROOT:-$SCRIPT_DIR/..}" || exit 2
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
if [[ "$mode" == --check-release && "${GITHUB_EVENT_NAME:-}" == merge_group ]]; then
  # The queue checks out the group's squash commit, which has one parent and
  # carries nothing of the release branch, so the release is read from the
  # queued pull request's own head commit.
  # shellcheck disable=SC2310  # the non-zero return IS the handled case
  if [[ -z "${CHANGELOG_PR_HEAD:-}" ]] || ! changed_files::verify_base "$CHANGELOG_PR_HEAD"; then
    echo "$self: in the merge queue --check-release reads the release from CHANGELOG_PR_HEAD, the queued pull request's head commit, which is unset or unreadable; refusing to pass without it." >&2
    exit 2
  fi
  head_commit="$CHANGELOG_PR_HEAD"
elif git rev-parse -q --verify 'HEAD^2' >/dev/null 2>&1 && git merge-base --is-ancestor 'HEAD^1' "$base" 2>/dev/null; then
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
declare -A shipped=() covered=() bumped=()
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
    *) ;;
    esac
    ;;
  plugins/*/.claude-plugin/plugin.json)
    rest="${path#plugins/}"
    name="${rest%%/*}"
    # * matches /, so a nested manifest (an eval fixture) is an ordinary plugin file
    [[ "$rest" == "$name/.claude-plugin/plugin.json" ]] || {
      shipped["$name"]=1
      continue
    }
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
  docs/conventions/*/*)
    rest="${path#docs/conventions/}"
    name="${rest%%/*}"
    # Only a convention no plugin of the same name owns; in_mode below drops
    # an unlisted one.
    [[ "$(changelog_fragments::root_of "$name")" == "docs/conventions/$name" ]] || continue
    if [[ "$rest" == "$name/CHANGELOG.md" ]]; then
      if [[ "$(git show "$merge_base:$path" 2>/dev/null | changelog_fragments::newest_version -)" != "$(git show "$head_commit:$path" 2>/dev/null | changelog_fragments::newest_version -)" ]]; then
        bumped["$name"]=1
      fi
      [[ -z "$release_pr" ]] || continue
    fi
    shipped["$name"]=1
    ;;
  *) ;;
  esac
done <"$status_file"

if [[ "$mode" == --check-required ]]; then
  findings=0
  dependabot=""
  # shellcheck disable=SC2310  # the non-zero return IS the answer
  if changelog_fragments::dependabot_only "$base"; then
    dependabot=1
  fi
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
    root="$(changelog_fragments::root_of "$name")" || root="plugins/$name"
    if [[ -n "$dependabot" ]]; then
      echo "Dependabot-only change to $root/: scripts/dependabot-fragments.sh writes its fragment after the merge."
      continue
    fi
    echo "MISSING FRAGMENT: this change set changes files under $root/ but adds or edits no fragment under .changes/$name/." >&2
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
# The release may merge past fragments the base added after it was cut: they
# ride the next release. It may not merge over a file it changes (a consumed
# fragment, a CHANGELOG.md, a plugin.json) that the base changed since the cut,
# since the release never read that change.
findings=0
while IFS= read -r -d '' status && IFS= read -r -d '' path; do
  if ! base_blob="$(git ls-tree "$base" -- "$path")" || ! cut_blob="$(git ls-tree "$merge_base" -- "$path")"; then
    echo "$self: 'git ls-tree' failed reading $path; refusing to pass without checking." >&2
    exit 2
  fi
  [[ "$base_blob" != "$cut_blob" ]] || continue
  case "$path" in
  .changes/*/*)
    if [[ -n "$base_blob" ]]; then
      echo "EDITED FRAGMENT: $path changed on $base after this release consumed it; rebuild the release from $base." >&2
    else
      echo "REMOVED FRAGMENT: $path was removed on $base after this release consumed it; rebuild the release from $base." >&2
    fi
    ;;
  *) echo "CHANGED ON BASE: $path changed on $base after this release was cut; rebuild the release from $base." >&2 ;;
  esac
  findings=$((findings + 1))
done <"$status_file"
if ((findings > 0)); then
  gate_entry::finish 1
fi
echo "No file this release changes for the ${#bumped[@]} plugin(s) it bumps has changed on $base since it was cut ($merge_base)."
gate_entry::finish 0
