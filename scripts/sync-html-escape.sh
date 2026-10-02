#!/usr/bin/env bash
# Sync or verify the rendered-views HTML escape helper.
#
#   scripts/sync-html-escape.sh                      copy the canonical file into each adopting plugin
#   scripts/sync-html-escape.sh --check              fail if any adopting copy differs from canonical
#   scripts/sync-html-escape.sh --check-bump <ref>   fail if the canonical changed vs <ref> but an
#                                                    adopting plugin's manifest version did not
#   scripts/sync-html-escape.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# Canonical copy: lib/html-escape.mjs. Each adopting plugin carries the same
# path within its own root (lib/html-escape.mjs) because a plugin cache cannot
# see the repo-root canonical. The adopters are review and education. The
# path-within-plugin and arrow lines in scripts/cross-plugin-source-registry.txt
# are the duplication audit's cluster. This script is the dedicated drift check.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies the escape-helper cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-html-escape.sh"
src="lib/html-escape.mjs"
copies=(plugins/education/lib/html-escape.mjs plugins/review/lib/html-escape.mjs)
sync_cluster_manifest_strip='/lib/*'
sync_cluster_noun="Canonical"
sync_cluster_carrier="adopting"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-html-escape.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
