#!/usr/bin/env bash
# Sync or verify the cross-plugin lib/managed-scope.sh cluster.
#
#   scripts/sync-managed-scope.sh                      copy the canonical file into each carrier
#   scripts/sync-managed-scope.sh --check              fail if any carrier differs from canonical
#   scripts/sync-managed-scope.sh --check-bump <ref>   fail if the canonical changed vs <ref> but a
#                                                      carrying plugin's manifest version did not
#   scripts/sync-managed-scope.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# Canonical copy: plugins/claude-config/lib/managed-scope.sh (see
# scripts/cross-plugin-source-registry.txt).
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies the managed-scope cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-managed-scope.sh"
src="plugins/claude-config/lib/managed-scope.sh"
copies=(plugins/claude-memory/lib/managed-scope.sh)
sync_cluster_manifest_strip='/lib/*'
sync_cluster_noun="Canonical"
sync_cluster_carrier="carrying"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-managed-scope.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
