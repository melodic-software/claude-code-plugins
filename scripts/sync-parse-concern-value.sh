#!/usr/bin/env bash
# Sync or verify the plugin copies of the shared topic-docs concern-value parser.
#
#   scripts/sync-parse-concern-value.sh                     copy the lib into each consuming plugin
#   scripts/sync-parse-concern-value.sh --check             fail if any plugin copy differs from the source
#   scripts/sync-parse-concern-value.sh --check-bump <ref>  fail if the lib changed vs <ref> but a consuming
#                                                           plugin's manifest version did not — the plugin
#                                                           version is the update cache key, so an unbumped
#                                                           plugin never delivers the change to consumers
#
# Unlike hooks/hook-utils.sh (same path in every carrying plugin, globbable),
# this helper is consumed by a fixed set of skill scripts at DIFFERENT paths, so
# the destinations are an explicit list. Add a consumer by adding its path here.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
src="lib/parse-concern-value.sh"

copies=(
  plugins/claude-memory/skills/audit/scripts/parse-concern-value.sh
  plugins/session-flow/skills/retro/scripts/parse-concern-value.sh
  plugins/docs-hygiene/skills/audit-noise/scripts/lib/parse-concern-value.sh
)

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
    echo "Run scripts/sync-parse-concern-value.sh and commit the result." >&2
    exit 1
  fi
  echo "All ${#copies[@]} plugin copies match $src."
  ;;
--check-bump)
  base="${2:?usage: sync-parse-concern-value.sh --check-bump <base-ref>}"
  if git diff --quiet "$base" -- "$src"; then
    echo "Lib unchanged vs $base; no version bumps required."
    exit 0
  fi
  stale=0
  for copy in "${copies[@]}"; do
    manifest="${copy%%/skills/*}/.claude-plugin/plugin.json"
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
    echo "Bump the version of every consuming plugin so consumers receive the lib change." >&2
    exit 1
  fi
  echo "Lib changed vs $base and every consuming plugin bumped its version."
  ;;
*)
  echo "usage: sync-parse-concern-value.sh [--check | --check-bump <base-ref>]" >&2
  exit 2
  ;;
esac
