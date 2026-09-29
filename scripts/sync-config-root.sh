#!/usr/bin/env bash
# Sync or verify the cross-plugin lib/config-root.sh cluster.
#
#   scripts/sync-config-root.sh                      copy the canonical file into each carrier
#   scripts/sync-config-root.sh --check              fail if any carrier differs from canonical
#   scripts/sync-config-root.sh --check-bump <ref>   fail if the canonical changed vs <ref> but a
#                                                    carrying plugin's manifest version did not
#   scripts/sync-config-root.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# Canonical copy: plugins/source-control/lib/config-root.sh (see
# scripts/cross-plugin-source-registry.txt). Its test lives beside it only.
#
# What the cluster buys: every bash reader of a `.claude/<surface>` layer cascade
# classifies the resolved root the same way (config-cascade Resolution algorithm
# step 2), so a session rooted at $HOME or outside a git working tree never reads
# ~/.claude/<surface> as the team layer. Plugins install independently and cannot
# source one another, so the resolver is a byte-identical copy plus this gate.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies the config-root cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-config-root.sh"
src="plugins/source-control/lib/config-root.sh"
copies=(plugins/docs-hygiene/lib/config-root.sh)
sync_cluster_manifest_strip='/lib/*'
sync_cluster_noun="Canonical"
sync_cluster_carrier="carrying"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-config-root.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
