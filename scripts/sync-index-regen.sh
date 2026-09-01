#!/usr/bin/env bash
# Sync or verify the plugin copies of the shared slice-index regeneration script.
#
#   scripts/sync-index-regen.sh                      copy the lib into each consuming plugin
#   scripts/sync-index-regen.sh --check              fail if any plugin copy differs from the source
#   scripts/sync-index-regen.sh --check-bump <ref>   fail if the lib changed vs <ref> but a consuming
#                                                    plugin's manifest version did not — the plugin
#                                                    version is the update cache key, so an unbumped
#                                                    plugin never delivers the change to consumers
#   scripts/sync-index-regen.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# Like sync-parse-concern-value.sh, the destinations are an explicit list of
# consuming-plugin paths. discovery (the orchestrating plugin) is the first
# consumer; add another by adding its path here. Tests live beside the
# canonical lib only (lib/index-regen.test.sh).
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies this cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-index-regen.sh"
src="lib/index-regen.sh"
copies=(
  plugins/discovery/scripts/index-regen.sh
)
sync_cluster_manifest_strip='/scripts/*'
sync_cluster_noun="Lib"
sync_cluster_carrier="consuming"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-index-regen.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
