#!/usr/bin/env bash
# Sync or verify the cross-plugin scripts/context-zone.sh cluster.
#
#   scripts/sync-context-zone.sh                      copy the canonical file into each carrier
#   scripts/sync-context-zone.sh --check              fail if any carrier differs from canonical
#   scripts/sync-context-zone.sh --check-bump <ref>   fail if the canonical changed vs <ref> but a
#                                                     carrying plugin's manifest version did not
#   scripts/sync-context-zone.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# Canonical copy: plugins/context-guard/scripts/context-zone.sh (see
# scripts/cross-plugin-source-registry.txt). context-guard owns the zone
# vocabulary, the bands, the staleness window, the token-shape version floor and
# the combination rule, all recorded in
# plugins/context-guard/reference/reader-contract.md, which both plugins cite.
#
# Why a copy rather than a call: plugin caches are per-plugin isolated, so the
# plugin-quality audit skill cannot invoke context-guard's script from the
# cache. The reader contract's resolver-invocation block is scoped to
# "same-plugin or path-provisioned callers", and carrying a synced copy is how
# plugin-quality becomes a same-plugin caller. The copy's test travels with it
# and is registered in the same file, enforced by
# scripts/check-cross-plugin-source-drift.sh --check.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies the context-zone cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-context-zone.sh"
src="plugins/context-guard/scripts/context-zone.sh"
copies=(plugins/plugin-quality/scripts/context-zone.sh)
sync_cluster_manifest_strip='/scripts/*'
sync_cluster_noun="Canonical"
sync_cluster_carrier="carrying"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-context-zone.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
