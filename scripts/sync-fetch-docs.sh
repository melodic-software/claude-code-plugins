#!/usr/bin/env bash
# Sync or verify the plugin copies of the shared upstream docs fetcher.
#
#   scripts/sync-fetch-docs.sh                      copy the canonical file into each carrying plugin
#   scripts/sync-fetch-docs.sh --check              fail if any plugin copy differs from canonical
#   scripts/sync-fetch-docs.sh --check-bump <ref>   fail if the canonical changed vs <ref> but a carrying
#                                                   plugin's manifest version did not
#   scripts/sync-fetch-docs.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# Canonical copy: lib/fetch-docs.sh. Each carrying plugin runs its own copy at
# scripts/fetch-docs.sh because a plugin cache cannot see the repo-root
# canonical. Add a carrier by adding its path to the copies list.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies the fetcher cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-fetch-docs.sh"
src="lib/fetch-docs.sh"
copies=(
  plugins/claude-config/scripts/fetch-docs.sh
  plugins/claude-ops/scripts/fetch-docs.sh
)
sync_cluster_manifest_strip='/scripts/*'
sync_cluster_noun="Canonical"
sync_cluster_carrier="carrying"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-fetch-docs.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
