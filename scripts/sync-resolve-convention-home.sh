#!/usr/bin/env bash
# Sync or verify the cross-plugin lib/resolve-convention-home.sh cluster.
#
#   scripts/sync-resolve-convention-home.sh                      copy the canonical file into each carrier
#   scripts/sync-resolve-convention-home.sh --check              fail if any carrier differs from canonical
#   scripts/sync-resolve-convention-home.sh --check-bump <ref>   fail if the canonical changed vs <ref> but a
#                                                                carrying plugin's manifest version did not
#   scripts/sync-resolve-convention-home.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# Canonical copy: plugins/claude-config/lib/resolve-convention-home.sh (see
# scripts/cross-plugin-source-registry.txt). Tests live beside the canonical copy only.
#
# A plugin whose skills resolve the consumer's convention home at runtime
# (config-cascade expression doctrine) enrolls a copy here; plugin-quality
# (the ADR 0018 pilot) is the first carrier.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies the resolve-convention-home cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-resolve-convention-home.sh"
src="plugins/claude-config/lib/resolve-convention-home.sh"
copies=(plugins/plugin-quality/lib/resolve-convention-home.sh)
sync_cluster_manifest_strip='/lib/*'
sync_cluster_noun="Canonical"
sync_cluster_carrier="carrying"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-resolve-convention-home.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
