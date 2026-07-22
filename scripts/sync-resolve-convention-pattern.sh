#!/usr/bin/env bash
# Sync or verify the plugin copies of the shared commit/PR convention
# ENFORCEMENT-pattern resolver (lib/resolve-convention-pattern.sh).
#
#   scripts/sync-resolve-convention-pattern.sh                     copy the lib into each consuming plugin
#   scripts/sync-resolve-convention-pattern.sh --check             fail if any plugin copy differs from the source
#   scripts/sync-resolve-convention-pattern.sh --check-bump <ref>  fail if the lib changed vs <ref> but a consuming
#                                                                  plugin's manifest version did not — the plugin
#                                                                  version is the update cache key, so an unbumped
#                                                                  plugin never delivers the change to consumers
#
# Like sync-parse-concern-value.sh, the copies are consumed at DIFFERENT paths,
# so the destinations are an explicit list. The list is intentionally EMPTY
# until the first consumer vendors the resolver: the guardrails CC-layer content
# gate (#914) and the opt-in commit-msg hook (#919) each add their copy path here
# and bump the guardrails manifest in the same change. Until then the resolver is
# the seam's source of truth with no cache-isolated copies to keep in step.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
src="lib/resolve-convention-pattern.sh"

copies=(
  # plugins/guardrails/hooks/resolve-convention-pattern.sh   # added by #914
)

mode="${1:-sync}"
case "$mode" in
sync)
  for copy in ${copies[@]+"${copies[@]}"}; do
    cp "$src" "$copy"
    echo "synced: $copy"
  done
  echo "synced ${#copies[@]} copies of $src."
  ;;
--check)
  drifted=0
  for copy in ${copies[@]+"${copies[@]}"}; do
    if ! cmp -s "$src" "$copy"; then
      echo "DRIFT: $copy differs from $src" >&2
      drifted=1
    fi
  done
  if [[ "$drifted" -ne 0 ]]; then
    echo "Run scripts/sync-resolve-convention-pattern.sh and commit the result." >&2
    exit 1
  fi
  echo "All ${#copies[@]} plugin copies match $src."
  ;;
--check-bump)
  base="${2:?usage: sync-resolve-convention-pattern.sh --check-bump <base-ref>}"
  if git diff --quiet "$base" -- "$src"; then
    echo "Lib unchanged vs $base; no version bumps required."
    exit 0
  fi
  stale=0
  for copy in ${copies[@]+"${copies[@]}"}; do
    manifest="${copy%%/hooks/*}/.claude-plugin/plugin.json"
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
  echo "usage: sync-resolve-convention-pattern.sh [--check | --check-bump <base-ref>]" >&2
  exit 2
  ;;
esac
