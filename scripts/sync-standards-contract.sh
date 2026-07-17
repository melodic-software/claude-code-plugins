#!/usr/bin/env bash
# Sync or verify the plugin binding copies of the standards concern contract.
#
#   scripts/sync-standards-contract.sh                     copy the canonical contract into each carrying plugin
#   scripts/sync-standards-contract.sh --check             fail if any plugin copy differs from the canonical
#   scripts/sync-standards-contract.sh --check-bump <ref>  fail if the contract changed vs <ref> but
#                                                          (a) a carrying plugin's manifest version did not —
#                                                              the plugin version is the update cache key, or
#                                                          (b) the standards-contract frontmatter semver did
#                                                              not — setup's migration detection reads it;
#                                                              without a bump content drifts under a frozen
#                                                              version forever, or
#                                                          (c) the contract CHANGELOG gained no new "## " entry
#
# A plugin carries the contract iff plugins/<name>/reference/standards-contract.md
# exists; a new plugin opts in by committing an initial copy of the file there.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
src="docs/conventions/standards/README.md"
changelog="docs/conventions/standards/CHANGELOG.md"

copies=(plugins/*/reference/standards-contract.md)
if [[ ! -e "${copies[0]}" ]]; then
  echo "error: no plugin copies found under plugins/*/reference/" >&2
  exit 2
fi

frontmatter_version() {
  awk '/^standards-contract:/ {print $2; exit}' -
}

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
    echo "Run scripts/sync-standards-contract.sh and commit the result." >&2
    exit 1
  fi
  echo "All ${#copies[@]} plugin copies match $src."
  ;;
--check-bump)
  base="${2:?usage: sync-standards-contract.sh --check-bump <base-ref>}"
  if git diff --quiet "$base" -- "$src"; then
    echo "Contract unchanged vs $base; no version bumps required."
    exit 0
  fi
  stale=0

  # (b) the contract's own semver must move with its content.
  base_contract=""
  if base_src=$(git show "$base:$src" 2>/dev/null); then
    base_contract=$(frontmatter_version <<<"$base_src")
  fi
  head_contract=$(frontmatter_version <"$src")
  if [[ -n "$base_contract" && "$head_contract" == "$base_contract" ]]; then
    echo "STALE CONTRACT VERSION: $src changed vs $base but its standards-contract frontmatter is still $head_contract" >&2
    stale=1
  fi

  # (c) the change must land a new changelog entry.
  base_headings=$(git show "$base:$changelog" 2>/dev/null | grep -c '^## ' || true)
  head_headings=$(grep -c '^## ' "$changelog" || true)
  if [[ "${head_headings:-0}" -le "${base_headings:-0}" ]]; then
    echo "STALE CHANGELOG: $src changed vs $base but $changelog gained no new '## ' entry" >&2
    stale=1
  fi

  # (a) every carrying plugin must bump so consumers receive the change.
  for copy in "${copies[@]}"; do
    manifest="${copy%/reference/standards-contract.md}/.claude-plugin/plugin.json"
    # A plugin absent at the base ref is new in this change set; its initial
    # release already carries the new contract.
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
    echo "Bump the standards-contract frontmatter, add a changelog entry, and bump every carrying plugin." >&2
    exit 1
  fi
  echo "Contract changed vs $base with frontmatter, changelog, and every carrying plugin bumped."
  ;;
*)
  echo "usage: sync-standards-contract.sh [--check | --check-bump <base-ref>]" >&2
  exit 2
  ;;
esac
