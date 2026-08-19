#!/usr/bin/env bash
# Sync or verify the cross-plugin lib/state-key.sh cluster.
#
#   scripts/sync-state-key.sh                     copy the canonical file into each carrier
#   scripts/sync-state-key.sh --check             fail if any carrier differs from canonical
#   scripts/sync-state-key.sh --check-bump <ref>  fail if the canonical changed vs <ref> but a
#                                                 carrying plugin's manifest version did not
#
# Canonical copy: plugins/claude-config/lib/state-key.sh (see
# scripts/cross-plugin-source-registry.txt). Tests live beside the canonical copy only.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies the state-key cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-state-key.sh"
# `src=` and `copies=(` are parsed out of this file by scripts/affected-tests.sh;
# keep both spellings exactly as they are.
src="plugins/claude-config/lib/state-key.sh"
copies=(plugins/claude-memory/lib/state-key.sh plugins/claude-ops/lib/state-key.sh plugins/context-budget/lib/state-key.sh plugins/improvement/lib/state-key.sh)
sync_cluster_manifest_strip='/lib/*'
sync_cluster_noun="Canonical"
sync_cluster_carrier="carrying"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-state-key.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
