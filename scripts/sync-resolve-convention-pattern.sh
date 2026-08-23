#!/usr/bin/env bash
# Sync or verify the plugin copies of the shared commit/PR convention
# ENFORCEMENT-pattern resolver (lib/resolve-convention-pattern.sh).
#
#   scripts/sync-resolve-convention-pattern.sh                      copy the lib into each consuming plugin
#   scripts/sync-resolve-convention-pattern.sh --check              fail if any plugin copy differs from the source
#   scripts/sync-resolve-convention-pattern.sh --check-bump <ref>   fail if the lib changed vs <ref> but a consuming
#                                                                   plugin's manifest version did not — the plugin
#                                                                   version is the update cache key, so an unbumped
#                                                                   plugin never delivers the change to consumers
#   scripts/sync-resolve-convention-pattern.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# Like sync-parse-concern-value.sh, the copies are consumed at DIFFERENT paths,
# so the destinations are an explicit list. The list started EMPTY and grows as
# each consumer vendors the resolver: the guardrails CC-layer content gate (#914)
# added the copy below, and the opt-in commit-msg hook (#919) adds its own copy
# path here and bumps the guardrails manifest in the same change.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies this cluster's parameters. The list having
# started empty is why this one still prints a copy-count summary after a sync.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-resolve-convention-pattern.sh"
src="lib/resolve-convention-pattern.sh"
copies=(
  plugins/guardrails/hooks/resolve-convention-pattern.sh # CC-layer content gate (block-convention-violation.sh)
)
sync_cluster_manifest_strip='/hooks/*'
sync_cluster_noun="Lib"
sync_cluster_carrier="consuming"
sync_cluster_sync_summary=1

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-resolve-convention-pattern.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
