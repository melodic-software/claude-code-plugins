#!/usr/bin/env bash
set -uo pipefail

self="$(basename "$0")"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

usage() {
  echo "usage: $self [-C <dir>] [--stdin] [--carriers-of <canonical>]... [<plugin>...] <major|minor|patch|none>" >&2
  exit 2
}

if [[ "${1:-}" == -C ]]; then
  (($# >= 2)) || usage
  dir="$2"
  shift 2
  if [[ "${1:-}" == -C ]]; then
    echo "$self: -C may be given only once." >&2
    exit 2
  fi
  if [[ "$dir" == - ]] || ! CDPATH='' cd -P -- "$dir" >/dev/null; then
    echo "$self: -C: cannot change to '$dir'." >&2
    exit 2
  fi
fi
if ! root="$(git rev-parse --show-toplevel 2>/dev/null)" || ! cd "$root"; then
  echo "$self: run it inside a git work tree; the fragment goes under its .changes/." >&2
  exit 2
fi
# shellcheck source=lib/changelog-fragments.sh
. "$SCRIPT_DIR/lib/changelog-fragments.sh" || exit 2

stdin=0 names=() manifest=""
while (($#)); do
  case "$1" in
  --stdin)
    stdin=1
    shift
    ;;
  --carriers-of)
    (($# >= 2)) || usage
    if [[ -z "$manifest" ]] && ! manifest="$(bash "$SCRIPT_DIR/sync-shared-copies.sh" --print-manifest)"; then
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
  if [[ ! "$plugin" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "$self: '$plugin' is not a plugin name (lowercase letters, digits and -)." >&2
    exit 2
  fi
  if ! changelog_fragments::root_of "$plugin" >/dev/null; then
    echo "$self: no plugin named '$plugin' (plugins/$plugin/.claude-plugin/plugin.json is missing) and no convention docs/contracts/$plugin/CHANGELOG.md or docs/conventions/$plugin/CHANGELOG.md." >&2
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
  branch="${CHANGELOG_FRAGMENT_BRANCH:-}"
  if [[ -z "$branch" ]]; then
    echo "$self: HEAD is not on a branch; the fragment name starts with the branch name." >&2
    exit 2
  fi
  if [[ ! "$branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$ ]] || ! git check-ref-format "refs/heads/$branch"; then
    echo "$self: CHANGELOG_FRAGMENT_BRANCH '$branch' is not a branch name." >&2
    exit 2
  fi
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

written=()
trap 'rm -f "${written[@]}"' EXIT
trap 'exit 2' INT TERM HUP
discard() { exit 2; }
for plugin in "${plugins[@]}"; do
  for ((try = 0; try < 64; try++)); do
    if ! suffix="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')" || [[ ! "$suffix" =~ ^[0-9a-f]{8}$ ]]; then
      echo "$self: could not read 4 random bytes from /dev/urandom." >&2
      discard
    fi
    [[ "$suffix" =~ [a-f]{2} ]] || break
  done
  if [[ "$suffix" =~ [a-f]{2} ]]; then
    echo "$self: drew no suffix without two letters in a row in 64 tries." >&2
    discard
  fi
  path=".changes/$plugin/$slug-$suffix.md"
  if [[ -L .changes || -L ".changes/$plugin" ]]; then
    echo "$self: .changes or .changes/$plugin is a symbolic link; wrote nothing." >&2
    discard
  fi
  if [[ -e "$path" || -L "$path" ]]; then
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
