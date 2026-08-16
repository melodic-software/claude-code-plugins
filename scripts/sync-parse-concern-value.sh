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
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies this cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-parse-concern-value.sh"
# `src=` and `copies=(` are parsed out of this file by scripts/affected-tests.sh;
# keep both spellings exactly as they are.
src="lib/parse-concern-value.sh"
copies=(
  plugins/claude-memory/skills/audit/scripts/parse-concern-value.sh
  plugins/session-flow/skills/retro/scripts/parse-concern-value.sh
  plugins/docs-hygiene/skills/audit-noise/scripts/lib/parse-concern-value.sh
)
sync_cluster_manifest_strip='/skills/*'
sync_cluster_noun="Lib"
sync_cluster_carrier="consuming"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-parse-concern-value.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
