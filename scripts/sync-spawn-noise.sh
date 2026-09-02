#!/usr/bin/env bash
# Sync or verify the cross-plugin lib/spawn_noise.py cluster.
#
#   scripts/sync-spawn-noise.sh                      copy the canonical file into each carrier
#   scripts/sync-spawn-noise.sh --check              fail if any carrier differs from canonical
#   scripts/sync-spawn-noise.sh --check-bump <ref>   fail if the canonical changed vs <ref> but a
#                                                    carrying plugin's manifest version did not
#   scripts/sync-spawn-noise.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# Canonical copy: plugins/claude-ops/lib/spawn_noise.py (see
# scripts/cross-plugin-source-registry.txt). Tests live beside the canonical copy only.
#
# What the cluster buys: `claude-ops:audit-performance` and `performance` must not
# disagree about what counts as an unmeasurable host. Plugins install independently,
# so neither can import the other at runtime; a byte-identical copy plus this gate is
# how the bimodal threshold keeps exactly one home. Two plugins quietly holding
# different values for BIMODAL_SPREAD_RATIO is worse than either value.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies the spawn-noise cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-spawn-noise.sh"
src="plugins/claude-ops/lib/spawn_noise.py"
copies=(plugins/performance/lib/spawn_noise.py)
sync_cluster_manifest_strip='/lib/*'
sync_cluster_noun="Canonical"
sync_cluster_carrier="carrying"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-spawn-noise.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
