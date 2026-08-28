#!/usr/bin/env bash
# Sync or verify the plugin copies of the content-mutation disclosure guard.
#
#   scripts/sync-rewrite-guard.sh                      copy the lib into each carrying plugin
#   scripts/sync-rewrite-guard.sh --check              fail if any plugin copy differs from the source
#   scripts/sync-rewrite-guard.sh --check-bump <ref>   fail if the lib changed vs <ref> but a carrying
#                                                      plugin's manifest version did not — the plugin
#                                                      version is the update cache key, so an unbumped
#                                                      plugin never delivers the change to consumers
#   scripts/sync-rewrite-guard.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# A plugin carries the lib iff plugins/<name>/hooks/rewrite-guard.sh exists; a
# new plugin opts in by committing an initial copy of the file there.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies the rewrite-guard cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-rewrite-guard.sh"
src="lib/rewrite-guard.sh"
copies=(plugins/*/hooks/rewrite-guard.sh)
sync_cluster_manifest_strip='/hooks/*'
sync_cluster_noun="Lib"
sync_cluster_carrier="carrying"
sync_cluster_sync_summary=0

if [[ ! -e "${copies[0]}" ]]; then
  echo "error: no plugin copies found under plugins/*/hooks/" >&2
  exit 2
fi

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-rewrite-guard.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
