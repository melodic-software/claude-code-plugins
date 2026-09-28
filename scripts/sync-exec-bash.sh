#!/usr/bin/env bash
# Sync or verify the plugin copies of the exec-form bash launcher.
#
#   scripts/sync-exec-bash.sh                      copy the lib into each carrying plugin
#   scripts/sync-exec-bash.sh --check              fail if any plugin copy differs from the source
#   scripts/sync-exec-bash.sh --check-bump <ref>   fail if the lib changed vs <ref> but a carrying
#                                                  plugin's manifest version did not
#   scripts/sync-exec-bash.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# A plugin carries the launcher iff plugins/<name>/hooks/exec-bash.mjs exists.
# A new plugin opts in by committing an initial copy of the file there.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies this cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-exec-bash.sh"
src="lib/exec-bash.mjs"
copies=(plugins/*/hooks/exec-bash.mjs)
sync_cluster_manifest_strip='/hooks/*'
sync_cluster_noun="Launcher"
sync_cluster_carrier="carrying"
sync_cluster_sync_summary=0

if [[ ! -e "${copies[0]}" ]]; then
  echo "error: no plugin copies found under plugins/*/hooks/exec-bash.mjs" >&2
  exit 2
fi

mode="${1:-sync}"
base=""
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-exec-bash.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
