#!/usr/bin/env bash
# Sync or verify the cross-plugin skills/setup/reference/legacy-statusline-detect.md cluster.
#
#   scripts/sync-legacy-statusline-detect.sh                      copy the canonical file into each carrier
#   scripts/sync-legacy-statusline-detect.sh --check              fail if any carrier differs from canonical
#   scripts/sync-legacy-statusline-detect.sh --check-bump <ref>   fail if the canonical changed vs <ref> but a
#                                                                 carrying plugin's manifest version did not
#   scripts/sync-legacy-statusline-detect.sh --print-manifest     emit src and copies as data (for affected-tests)
#
# Canonical copy: plugins/context-guard/skills/setup/reference/legacy-statusline-detect.md (see
# scripts/cross-plugin-source-registry.txt). The twin statusline guard plugins carry the shared,
# plugin-name-free half of their legacy-statusline detection here; the surfaces it classifies are
# machine-scope (~/.claude/), so ADR 0018 decision 6 fixes their twin drift with this sync gate
# rather than the repo-scope retirement schema.
#
# The three modes live in scripts/lib/sync-cluster.sh, shared with the sibling
# sync-*.sh gates; this file supplies the legacy-statusline-detect cluster's parameters.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/sync-cluster.sh
. "$script_dir/lib/sync-cluster.sh"

sync_cluster_script="sync-legacy-statusline-detect.sh"
src="plugins/context-guard/skills/setup/reference/legacy-statusline-detect.md"
copies=(plugins/rate-limit-guard/skills/setup/reference/legacy-statusline-detect.md)
sync_cluster_manifest_strip='/skills/*'
sync_cluster_noun="Canonical"
sync_cluster_carrier="carrying"
sync_cluster_sync_summary=0

mode="${1:-sync}"
base=""
# Raised here, not in the shared engine: bash prefixes a ${var:?} diagnostic with
# the path and line of the expansion, so the message has to come from the script
# the user actually ran.
[[ "$mode" == "--check-bump" ]] && base="${2:?usage: sync-legacy-statusline-detect.sh --check-bump <base-ref>}"

sync_cluster::run "$mode" "$base"
