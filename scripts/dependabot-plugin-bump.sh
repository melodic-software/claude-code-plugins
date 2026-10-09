#!/usr/bin/env bash
# Write plugin.json patch bumps and Keep a Changelog entries for Dependabot PRs
# that touch plugins/**. Does not exempt Dependabot from check-changelog-parity
# --check-bump; it supplies the bump the bot cannot author. A plugin in
# changelog-fragment mode (the base's scripts/fragment-plugins.txt, ADR 0048)
# gets nothing here: scripts/dependabot-fragments.sh writes its fragment, with the
# same entry under `### Changed`, after the pull request merges.
#
# Usage:
#   scripts/dependabot-plugin-bump.sh <base-ref> [--pr <n>] [--title <text>]
#
# Exit: 0 clean (including no-op), 1 gate self-check failed after edits, 2 usage/env.
#
# Sources (verified 2026-09-27):
#   - GitHub Dependabot managing PRs: [dependabot skip] lets Dependabot force-push
#     over bot commits (docs.github.com/.../managing-pull-requests-for-dependency-updates)
#   - Claude Code plugin version delivery (code.claude.com/docs/en/plugins/loading)
#   - scripts/check-changelog-parity.sh --check-bump (never relaxes for bots)
#   - Tracker consensus: keep the gate; generalize dependabot-miro-bundle.yml
#   Recheck when the GitHub page stops naming [dependabot skip] or the Claude
#   Code plugin-loading page stops tying update delivery to the version string.
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer the git checkout root so a copy of this script outside scripts/
# (workflow extracts origin/<base> to /tmp) still edits the PR working tree
# and sources helpers from that checkout.
if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  ROOT="$(cd "$SELF_DIR/.." && pwd)"
fi
cd "$ROOT"

SCRIPTS_DIR="$ROOT/scripts"
if [[ -f "$SELF_DIR/lib/changed-files.sh" ]]; then
  SCRIPTS_DIR="$SELF_DIR"
fi
# shellcheck source=lib/changed-files.sh
. "$SCRIPTS_DIR/lib/changed-files.sh"
# The workflow runs the base branch's copy of this script against the PR
# branch's scripts/; a branch older than the fragment library has no plugin in
# fragment mode.
if [[ -f "$SCRIPTS_DIR/lib/changelog-fragments.sh" ]]; then
  # shellcheck source=lib/changelog-fragments.sh
  . "$SCRIPTS_DIR/lib/changelog-fragments.sh"
else
  changelog_fragments::in_mode() { return 1; }
fi
# The workflow writes the base's copy of this library next to its copy of this
# script, so a branch older than the library still renders the entry.
if [[ -f "$SELF_DIR/lib/dependabot-entry.sh" ]]; then
  # shellcheck source=lib/dependabot-entry.sh
  . "$SELF_DIR/lib/dependabot-entry.sh"
else
  # shellcheck source=lib/dependabot-entry.sh
  . "$SCRIPTS_DIR/lib/dependabot-entry.sh"
fi

usage() {
  echo "usage: $(basename "$0") <base-ref> [--pr <n>] [--title <text>]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
base=$1
shift
pr_number=""
pr_title="Dependabot dependency update"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --pr)
    [[ $# -ge 2 ]] || usage
    pr_number=$2
    shift 2
    ;;
  --title)
    [[ $# -ge 2 ]] || usage
    pr_title=$2
    shift 2
    ;;
  *)
    usage
    ;;
  esac
done

command -v jq >/dev/null || {
  echo "dependabot-plugin-bump: jq is required" >&2
  exit 2
}
# shellcheck disable=SC2310  # verify_base is one git call; its non-zero return is the handled case
changed_files::verify_base "$base" || {
  echo "dependabot-plugin-bump: base-ref '$base' is not a commit" >&2
  exit 2
}
# Fragment mode is the base's list, not the branch's: the gates run on the merge
# with the base, and a branch that predates a plugin's flip still must not bump it.
if git cat-file -e "$base:scripts/fragment-plugins.txt" 2>/dev/null; then
  base_list="$(mktemp)"
  trap 'rm -f "$base_list"' EXIT
  git show "$base:scripts/fragment-plugins.txt" >"$base_list"
  CF_LIST="$base_list"
fi

# Match check-changelog-parity.sh: on a pull_request merge commit, use the PR tip.
head_commit=HEAD
if git rev-parse -q --verify 'HEAD^2' >/dev/null 2>&1 &&
  git merge-base --is-ancestor 'HEAD^1' "$base" 2>/dev/null; then
  head_commit='HEAD^2'
fi
if ! merge_base="$(git merge-base "$base" "$head_commit")"; then
  echo "dependabot-plugin-bump: no merge-base between $base and $head_commit" >&2
  exit 2
fi

diff_paths=()
# shellcheck disable=SC2310  # the non-zero return IS the handled case; the branch exits 2
if ! changed_files::into diff_paths "$merge_base..$head_commit" --include-deleted; then
  echo "dependabot-plugin-bump: diff $merge_base..$head_commit failed" >&2
  exit 2
fi

declare -A shipped_changed=()
for path in ${diff_paths[@]+"${diff_paths[@]}"}; do
  case "$path" in
  plugins/*/.claude-plugin/plugin.json | plugins/*/CHANGELOG.md) ;;
  plugins/*/*)
    rest="${path#plugins/}"
    name="${rest%%/*}"
    # Nested path under a versioned plugin root
    if [[ -f "plugins/$name/.claude-plugin/plugin.json" ]]; then
      shipped_changed["$name"]=1
    fi
    ;;
  *) ;;
  esac
done

version_of() { jq -r '.version // empty' "$1"; }

bump_patch() {
  local ver=$1
  local major minor patch
  IFS=. read -r major minor patch <<<"$ver"
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]] || {
    echo "dependabot-plugin-bump: non-SemVer version '$ver'" >&2
    return 1
  }
  printf '%s.%s.%s' "$major" "$minor" "$((patch + 1))"
}

has_heading() {
  local file=$1 ver=$2
  grep -Eiq "^##[[:space:]]*(\[${ver}\]|${ver}([[:space:]]|-|$))" "$file" 2>/dev/null
}

insert_changelog_entry() {
  local changelog=$1 ver=$2 body=$3
  local date entry tmp
  date="$(date -u +%Y-%m-%d)"
  entry="## [${ver}] - ${date}

### Changed

${body}
"
  tmp="$(mktemp)"
  if grep -qE '^##[[:space:]]*\[' "$changelog"; then
    awk -v entry="$entry" '
      BEGIN { inserted=0 }
      /^##[[:space:]]*\[/ && !inserted { printf "%s\n", entry; inserted=1 }
      { print }
      END { if (!inserted) printf "%s", entry }
    ' "$changelog" >"$tmp"
  else
    # Title-only changelog: append after existing content with a blank line.
    {
      cat "$changelog"
      [[ -n "$(tail -c1 "$changelog" 2>/dev/null || true)" ]] && printf '\n'
      printf '\n%s' "$entry"
    } >"$tmp"
  fi
  mv "$tmp" "$changelog"
}

edited=0
bumped_names=()

# ${!assoc[@]+...} is NOT safe: bash treats ! as indirection on the values.
# Guard length, then iterate keys (bash 4+ associative arrays).
if ((${#shipped_changed[@]} > 0)); then
  for name in "${!shipped_changed[@]}"; do
    manifest="plugins/$name/.claude-plugin/plugin.json"
    changelog="plugins/$name/CHANGELOG.md"
    [[ -f "$manifest" ]] || continue
    if [[ ! -f "$changelog" ]]; then
      echo "dependabot-plugin-bump: $name has no CHANGELOG.md; refusing to invent one" >&2
      exit 1
    fi

    base_manifest="$(git show "$base:$manifest" 2>/dev/null || true)"
    [[ -n "$base_manifest" ]] || continue
    base_ver="$(printf '%s' "$base_manifest" | jq -r '.version // empty')"
    head_ver="$(version_of "$manifest")"
    [[ -n "$base_ver" && -n "$head_ver" ]] || continue

    # A plugin in fragment mode (ADR 0048) gets nothing on the pull request: a
    # commit here would hold every run on it at action_required (#5786).
    # scripts/dependabot-fragments.sh writes its fragment after the merge, and
    # check-changelog-fragments.sh --check-required exempts the pull request.
    mode_rc=0
    # shellcheck disable=SC2310  # the non-zero return IS the answer; rc 2 exits
    changelog_fragments::in_mode "$name" || mode_rc=$?
    ((mode_rc < 2)) || exit 2
    if ((mode_rc == 0)); then
      echo "dependabot-plugin-bump: $name is in fragment mode; its fragment is written after the merge"
      continue
    fi

    # Idempotent: head already above base tip and heading present for head version.
    # shellcheck disable=SC2310  # has_heading's non-zero return IS the "no heading" answer
    if [[ "$head_ver" != "$base_ver" ]] && has_heading "$changelog" "$head_ver"; then
      continue
    fi

    # If head equals base but we touched shipped files, we need a new patch.
    # If head already moved without a heading, keep that number when present.
    if [[ "$head_ver" == "$base_ver" ]]; then
      # shellcheck disable=SC2310  # bump_patch's only failure is its explicit non-SemVer return
      new_ver="$(bump_patch "$base_ver")" || exit 1
    else
      new_ver=$head_ver
      # shellcheck disable=SC2310  # has_heading's non-zero return IS the "no heading" answer
      if has_heading "$changelog" "$new_ver"; then
        continue
      fi
    fi

    if [[ "$new_ver" == "$base_ver" ]]; then
      # shellcheck disable=SC2310  # bump_patch's only failure is its explicit non-SemVer return
      new_ver="$(bump_patch "$base_ver")" || exit 1
    fi

    jq --arg v "$new_ver" '.version = $v' "$manifest" >"${manifest}.tmp"
    mv "${manifest}.tmp" "$manifest"

    # Process substitution, not a pipe into grep -q: under pipefail a matched
    # grep exits early and SIGPIPEs git (scripts/check-pipefail-grep-q.sh).
    # The release workflow rebuilds a bundle in the working tree before this
    # step and commits it after, so uncommitted and untracked files count too.
    bundle=0
    if grep -qE 'dist/|bundle' < <(
      git diff --name-only "$merge_base..$head_commit" -- "plugins/$name"
      git diff --name-only HEAD -- "plugins/$name"
      git ls-files -o --exclude-standard -- "plugins/$name"
    ); then
      bundle=1
    fi
    body_block="$(git log --format=%B "$merge_base..$head_commit" -- "plugins/$name" |
      dependabot_entry::deps | dependabot_entry::item "$pr_title" "$pr_number" "$bundle")"

    insert_changelog_entry "$changelog" "$new_ver" "$body_block"
    echo "dependabot-plugin-bump: $name ${base_ver} -> ${new_ver}"
    edited=1
    bumped_names+=("$name")
  done
fi

if [[ "$edited" -eq 0 ]]; then
  echo "dependabot-plugin-bump: nothing to bump"
  exit 0
fi

# Self-check against the same gate Dependabot must pass.
parity="$SCRIPTS_DIR/check-changelog-parity.sh"
if ! bash "$parity" --check; then
  echo "dependabot-plugin-bump: --check failed after edits" >&2
  exit 1
fi
if ! bash "$parity" --check-bump "$base"; then
  echo "dependabot-plugin-bump: --check-bump failed after edits" >&2
  exit 1
fi
if ! bash "$parity" --check-preserved "$base"; then
  echo "dependabot-plugin-bump: --check-preserved failed after edits" >&2
  exit 1
fi
if ! bash "$parity" --check-order; then
  echo "dependabot-plugin-bump: --check-order failed after edits" >&2
  exit 1
fi

printf 'dependabot-plugin-bump: bumped %s\n' "${bumped_names[*]}"
exit 0
