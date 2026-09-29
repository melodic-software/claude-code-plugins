#!/usr/bin/env bash
# Write plugin.json patch bumps and Keep a Changelog entries for Dependabot PRs
# that touch plugins/**. Does not exempt Dependabot from check-changelog-parity
# --check-bump; it supplies the bump the bot cannot author.
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

# Parse "Updates \`pkg\` from A to B" lines from Dependabot commits on this branch.
parse_dep_lines() {
  local name=$1
  local msg line pkg from to
  while IFS= read -r msg; do
    [[ -z "$msg" ]] && continue
    while IFS= read -r line; do
      if [[ "$line" =~ Updates\ \`([^\`]+)\`\ from\ ([^[:space:]]+)\ to\ ([^[:space:]]+) ]]; then
        pkg="${BASH_REMATCH[1]}"
        from="${BASH_REMATCH[2]}"
        to="${BASH_REMATCH[3]}"
        printf '%s\t%s\t%s\n' "$pkg" "$from" "$to"
      fi
    done <<<"$msg"
  done < <(git log --format=%B "$merge_base..$head_commit" -- "plugins/$name")
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

    dep_body=""
    while IFS=$'\t' read -r pkg from to; do
      [[ -z "${pkg:-}" ]] && continue
      dep_body+="- \`${pkg}\` ${from}→${to}"$'\n'
    done < <(parse_dep_lines "$name" | sort -u)

    title_line=$pr_title
    title_line="${title_line#build(deps): }"
    title_line="${title_line#chore(deps): }"
    ref=""
    [[ -n "$pr_number" ]] && ref=" (#${pr_number})"

    body_block="- **${title_line}**${ref}."
    if [[ -n "$dep_body" ]]; then
      body_block+=$'\n'"$(printf '%s' "$dep_body" | sed 's/^/  /')"
    fi
    # Process substitution, not a pipe into grep -q: under pipefail a matched
    # grep exits early and SIGPIPEs git (scripts/check-pipefail-grep-q.sh).
    if grep -qE 'dist/|bundle' < <(
      git diff --name-only "$merge_base..$head_commit" -- "plugins/$name"
    ); then
      body_block+=$'\n'"  Committed bundle or dist artifact changed with this update."
    fi

    insert_changelog_entry "$changelog" "$new_ver" "$body_block"
    edited=1
    bumped_names+=("$name")
    echo "dependabot-plugin-bump: $name ${base_ver} -> ${new_ver}"
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
