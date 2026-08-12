#!/usr/bin/env bash
# Sync or verify the cross-plugin lib/managed-scope.sh cluster.
#
#   scripts/sync-managed-scope.sh                     copy the canonical file into each carrier
#   scripts/sync-managed-scope.sh --check             fail if any carrier differs from canonical
#   scripts/sync-managed-scope.sh --check-bump <ref>  fail if the canonical changed vs <ref> but a
#                                                     carrying plugin's manifest version did not
#
# Canonical copy: plugins/claude-config/lib/managed-scope.sh (see
# scripts/cross-plugin-source-registry.txt).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
src="plugins/claude-config/lib/managed-scope.sh"

copies=(plugins/claude-memory/lib/managed-scope.sh)

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
    echo "Run scripts/sync-managed-scope.sh and commit the result." >&2
    exit 1
  fi
  echo "All ${#copies[@]} plugin copies match $src."
  ;;
--check-bump)
  base="${2:?usage: sync-managed-scope.sh --check-bump <base-ref>}"
  if git diff --quiet "$base" -- "$src"; then
    echo "Canonical unchanged vs $base; no version bumps required."
    exit 0
  fi
  stale=0
  for copy in "${copies[@]}"; do
    manifest="${copy%/lib/managed-scope.sh}/.claude-plugin/plugin.json"
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
  echo "Canonical changed vs $base and every carrying plugin bumped its version."
  ;;
*)
  echo "usage: sync-managed-scope.sh [--check | --check-bump <base-ref>]" >&2
  exit 2
  ;;
esac
