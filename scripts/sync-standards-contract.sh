#!/usr/bin/env bash
# Sync or verify the plugin binding copies of the standards concern contract.
#
#   scripts/sync-standards-contract.sh                      copy the canonical contract into each carrying plugin
#   scripts/sync-standards-contract.sh --check              fail if any plugin copy differs from the canonical
#   scripts/sync-standards-contract.sh --print-manifest     emit src and copies as data (for affected-tests)
#   scripts/sync-standards-contract.sh --check-bump <ref>   fail if the contract changed vs <ref> but
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
#
# sync, --check and --print-manifest are the shared engine's, same as the sibling
# sync-*.sh gates. --check-bump stays here: it also gates the contract's own
# frontmatter semver and its CHANGELOG, which no other cluster has. Its
# carrying-plugin manifest walk is still the engine's.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-standards-contract.sh"
sync_cluster_manifest_strip='/reference/standards-contract.md'
sync_cluster_sync_summary=0
src="docs/conventions/standards/README.md"
schema="docs/conventions/standards/standards.schema.json"
changelog="docs/conventions/standards/CHANGELOG.md"

copies=(plugins/*/reference/standards-contract.md)
if [[ ! -e "${copies[0]}" ]]; then
  echo "error: no plugin copies found under plugins/*/reference/" >&2
  exit 2
fi

frontmatter_version() {
  awk '/^standards-contract:/ {print $2; exit}'
}

mode="${1:-sync}"
if [[ "$mode" == "--check-bump" ]]; then
  # Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic
  # with the path and line of the expansion, so the message has to come from the
  # script the user actually ran.
  base="${2:?usage: sync-standards-contract.sh --check-bump <base-ref>}"
  # The schema is contract surface too — a schema-only change still
  # requires the version, changelog, and carrying-plugin bumps.
  if git diff --quiet "$base" -- "$src" "$schema"; then
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

  # (c) the changelog must carry an entry for the contract version the
  # frontmatter now names — a heading count could be satisfied by any
  # unrelated '## ' section.
  head_contract_re=${head_contract//./\\.}
  if ! grep -Eq "^## ${head_contract_re}( |$)" "$changelog" 2>/dev/null; then
    echo "STALE CHANGELOG: $src changed vs $base but $changelog has no '## $head_contract' entry" >&2
    stale=1
  fi

  # (a) every carrying plugin must bump so consumers receive the change. The
  # engine assigns through printf -v, which shellcheck cannot follow; declaring
  # the out-var here is what tells it (SC2154) the name is written.
  manifest_stale=0
  sync_cluster::check_manifest_bumps_to manifest_stale "$base"
  if [[ "$manifest_stale" -ne 0 ]]; then
    stale=1
  fi

  if [[ "$stale" -ne 0 ]]; then
    echo "Bump the standards-contract frontmatter, add a changelog entry, and bump every carrying plugin." >&2
    exit 1
  fi
  echo "Contract changed vs $base with frontmatter, changelog, and every carrying plugin bumped."
else
  # sync, --check, --print-manifest and the usage banner are the engine's.
  sync_cluster::run "$mode"
fi
