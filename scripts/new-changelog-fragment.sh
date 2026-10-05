#!/usr/bin/env bash
# Create changelog fragments for plugins in fragment mode (ADR 0048).
#
#   scripts/new-changelog-fragment.sh [--stdin] [--carriers-of <canonical>]... [<plugin>...] <major|minor|patch|none>
#
# Writes one .changes/<plugin>/<branch-slug>-<8 hex>.md per named plugin, holding
# the front matter, and prints each path. --carriers-of adds every plugin that
# carries a copy of <canonical> in scripts/shared-copies.txt, so one edit to a
# shared library takes one command. A plugin named twice gets one fragment. A
# plugin not in fragment mode is skipped with a note on stderr: bump its
# plugin.json and CHANGELOG.md in the pull request instead.
#
# <branch-slug> is the current branch, lowercased, with `/` and any other
# character outside [a-z0-9._-] replaced by `-`; the random suffix keeps two
# branches with one slug apart, so no pull request number is needed in advance.
#
# Without --stdin, fill in the body afterwards. With --stdin, the body is read
# from stdin and written into every fragment, and each fragment must then pass
# scripts/check-changelog-fragments.sh's validation, or none is kept. The body is
# `### <Section>` blocks (Added, Changed, Deprecated, Removed, Fixed, Security),
# or for `none` one line saying why no release is needed.
#
# Exit: 0 written; 2 usage, an unknown plugin or canonical, no plugin in
# fragment mode, an invalid --stdin body, or no branch.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/changelog-fragments.sh
. "$SCRIPT_DIR/lib/changelog-fragments.sh" || exit 2

self="$(basename "$0")"
usage() {
  echo "usage: $self [--stdin] [--carriers-of <canonical>]... [<plugin>...] <major|minor|patch|none>" >&2
  exit 2
}

stdin=0 names=() manifest=""
while (($#)); do
  case "$1" in
  --stdin)
    stdin=1
    shift
    ;;
  --carriers-of)
    (($# >= 2)) || usage
    if [[ -z "$manifest" ]] && ! manifest="$(bash scripts/sync-shared-copies.sh --print-manifest)"; then
      echo "$self: could not read scripts/shared-copies.txt." >&2
      exit 2
    fi
    carriers="$(awk -F'\t' -v src="$2" '
      $1 == "src" { cur = $2; next }
      $1 == "copy" && cur == src { sub(/^plugins\//, "", $2); sub(/\/.*/, "", $2); print $2 }
    ' <<<"$manifest")"
    if [[ -z "$carriers" ]]; then
      echo "$self: '$2' is not a canonical in scripts/shared-copies.txt." >&2
      exit 2
    fi
    mapfile -t -O "${#names[@]}" names <<<"$carriers"
    shift 2
    ;;
  -*) usage ;;
  *)
    names+=("$1")
    shift
    ;;
  esac
done
((${#names[@]} >= 2)) || usage
bump="${names[-1]}"
unset 'names[-1]'
[[ "$bump" =~ ^(major|minor|patch|none)$ ]] || usage

plugins=()
declare -A seen=()
for plugin in "${names[@]}"; do
  [[ -z "${seen[$plugin]:-}" ]] || continue
  seen["$plugin"]=1
  if [[ ! -f "plugins/$plugin/.claude-plugin/plugin.json" ]]; then
    echo "$self: no plugin named '$plugin' (plugins/$plugin/.claude-plugin/plugin.json is missing)." >&2
    exit 2
  fi
  changelog_fragments::in_mode "$plugin"
  case $? in
  0) plugins+=("$plugin") ;;
  1) echo "$self: skipped '$plugin': not in fragment mode ($CF_LIST does not list it); bump its plugin.json and CHANGELOG.md in the pull request instead." >&2 ;;
  *) exit 2 ;;
  esac
done
if ((${#plugins[@]} == 0)); then
  echo "$self: no named plugin is in fragment mode; wrote nothing." >&2
  exit 2
fi
if ! branch="$(git symbolic-ref --quiet --short HEAD)"; then
  echo "$self: HEAD is not on a branch; the fragment name starts with the branch name." >&2
  exit 2
fi
slug="${branch,,}"
slug="${slug//[^a-z0-9._-]/-}"
slug="${slug#"${slug%%[a-z0-9]*}"}"
if [[ -z "$slug" ]]; then
  echo "$self: branch '$branch' has no letter or digit to name the fragment after." >&2
  exit 2
fi
body=""
if ((stdin)); then
  body="$(cat)" || exit 2
  if [[ -z "${body//[[:space:]]/}" ]]; then
    echo "$self: --stdin read an empty body." >&2
    exit 2
  fi
fi

# Until every fragment is written and valid, any exit, an interrupt included,
# removes the ones already written: a partial set would record a shared change
# for only some of its carriers.
written=()
trap 'rm -f "${written[@]}"' EXIT
trap 'exit 2' INT TERM HUP
discard() { exit 2; }
for plugin in "${plugins[@]}"; do
  if ! suffix="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')" || [[ ! "$suffix" =~ ^[0-9a-f]{8}$ ]]; then
    echo "$self: could not read 4 random bytes from /dev/urandom." >&2
    discard
  fi
  path=".changes/$plugin/$slug-$suffix.md"
  if [[ -e "$path" ]]; then
    echo "$self: $path already exists; run it again for a new suffix." >&2
    discard
  fi
  mkdir -p ".changes/$plugin" || discard
  if ((stdin)); then
    printf -- '---\nbump: %s\n---\n\n%s\n' "$bump" "$body" >"$path" || discard
  else
    printf -- '---\nbump: %s\n---\n\n' "$bump" >"$path" || discard
  fi
  written+=("$path")
done
if ((stdin)); then
  invalid=0
  for path in "${written[@]}"; do
    changelog_fragments::validate "$path" || invalid=1
  done
  if ((invalid)); then
    echo "$self: the body from stdin does not make a valid fragment; wrote nothing." >&2
    discard
  fi
fi
trap - EXIT INT TERM HUP
printf '%s\n' "${written[@]}"
