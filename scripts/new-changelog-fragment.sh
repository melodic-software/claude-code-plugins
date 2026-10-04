#!/usr/bin/env bash
# Create a changelog fragment for a plugin in fragment mode (ADR 0048).
#
#   scripts/new-changelog-fragment.sh <plugin> <major|minor|patch|none>
#
# Writes .changes/<plugin>/<branch-slug>-<8 hex>.md holding the front matter and
# prints its path. <branch-slug> is the current branch, lowercased, with `/` and
# any other character outside [a-z0-9._-] replaced by `-`;
# the random suffix keeps two branches with one slug apart, so no pull request
# number is needed in advance. Fill in the body afterwards: `### <Section>`
# blocks (Added, Changed, Deprecated, Removed, Fixed, Security), or for `none`
# one line saying why no release is needed. scripts/check-changelog-fragments.sh
# validates it.
#
# Exit: 0 written, 2 usage, a plugin that is not in fragment mode, or no branch.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/changelog-fragments.sh
. "$SCRIPT_DIR/lib/changelog-fragments.sh" || exit 2

self="$(basename "$0")"
if (($# != 2)) || [[ ! "$2" =~ ^(major|minor|patch|none)$ ]]; then
  echo "usage: $self <plugin> <major|minor|patch|none>" >&2
  exit 2
fi
plugin="$1"
bump="$2"

if [[ ! -f "plugins/$plugin/.claude-plugin/plugin.json" ]]; then
  echo "$self: no plugin named '$plugin' (plugins/$plugin/.claude-plugin/plugin.json is missing)." >&2
  exit 2
fi
# shellcheck disable=SC2310  # the non-zero return IS the handled case
if ! changelog_fragments::in_mode "$plugin"; then
  echo "$self: '$plugin' is not in fragment mode ($CF_LIST does not list it); bump its plugin.json and CHANGELOG.md in the pull request instead." >&2
  exit 2
fi
if ! branch="$(git symbolic-ref --quiet --short HEAD)"; then
  echo "$self: HEAD is not on a branch; the fragment name starts with the branch name." >&2
  exit 2
fi
if ! suffix="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')" || [[ ! "$suffix" =~ ^[0-9a-f]{8}$ ]]; then
  echo "$self: could not read 4 random bytes from /dev/urandom." >&2
  exit 2
fi

slug="${branch,,}"
slug="${slug//[^a-z0-9._-]/-}"
path=".changes/$plugin/$slug-$suffix.md"
if [[ -e "$path" ]]; then
  echo "$self: $path already exists; run it again for a new suffix." >&2
  exit 2
fi
mkdir -p ".changes/$plugin" || exit 2
printf -- '---\nbump: %s\n---\n\n' "$bump" >"$path" || exit 2
echo "$path"
