#!/usr/bin/env bash
# Sync or verify the plugin copies of the shared hook utility library.
#
#   scripts/sync-hook-utils.sh                     copy the lib into each carrying plugin
#   scripts/sync-hook-utils.sh --check             fail if any plugin copy differs from the source
#   scripts/sync-hook-utils.sh --check-bump <ref>  fail if the lib changed vs <ref> but a carrying
#                                                  plugin's manifest version did not — the plugin
#                                                  version is the update cache key, so an unbumped
#                                                  plugin never delivers the change to consumers
#
# A plugin carries the lib iff plugins/<name>/hooks/hook-utils.sh exists; a new
# plugin opts in by committing an initial copy of the file there.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
src="lib/hook-utils.sh"

copies=(plugins/*/hooks/hook-utils.sh)
if [[ ! -e "${copies[0]}" ]]; then
  echo "error: no plugin copies found under plugins/*/hooks/" >&2
  exit 2
fi

mode="${1:-sync}"
case "$mode" in
sync)
  for copy in "${copies[@]}"; do
    cp "$src" "$copy"
    echo "synced: $copy"
  done
  ;;
--check)
  drifted=0
  for copy in "${copies[@]}"; do
    if ! cmp -s "$src" "$copy"; then
      echo "DRIFT: $copy differs from $src" >&2
      drifted=1
    fi
  done
  if [[ "$drifted" -ne 0 ]]; then
    echo "Run scripts/sync-hook-utils.sh and commit the result." >&2
    exit 1
  fi
  echo "All ${#copies[@]} plugin copies match $src."
  ;;
--check-bump)
  base="${2:?usage: sync-hook-utils.sh --check-bump <base-ref>}"
  if git diff --quiet "$base" -- "$src"; then
    echo "Lib unchanged vs $base; no version bumps required."
    exit 0
  fi
  stale=0
  for copy in "${copies[@]}"; do
    manifest="${copy%/hooks/hook-utils.sh}/.claude-plugin/plugin.json"
    # A plugin absent at the base ref is new in this change set; its initial
    # release already carries the new lib.
    base_version=$(git show "$base:$manifest" 2>/dev/null | jq -r '.version // empty' || true)
    if [[ -z "$base_version" ]]; then
      continue
    fi
    head_version=$(jq -r '.version // empty' "$manifest")
    if [[ "$head_version" == "$base_version" ]]; then
      echo "STALE VERSION: $src changed vs $base but $manifest is still $head_version" >&2
      stale=1
    fi
  done
  if [[ "$stale" -ne 0 ]]; then
    echo "Bump the version of every carrying plugin so consumers receive the lib change." >&2
    exit 1
  fi
  echo "Lib changed vs $base and every carrying plugin bumped its version."
  ;;
*)
  echo "usage: sync-hook-utils.sh [--check | --check-bump <base-ref>]" >&2
  exit 2
  ;;
esac
