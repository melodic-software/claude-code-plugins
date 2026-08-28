#!/usr/bin/env bash
# Gate: a change under a plugin's committed vendor/ tree must bump that
# plugin's manifest version in the same change set.
#
#   scripts/check-vendor-version-bump.sh --check-bump <base-ref>
#
# WHY. ADR 0019 ("Intra-plugin sharing") collapses the cross-plugin sync
# machinery when the second consumer is another skill in the SAME plugin: one
# committed copy at the plugin root (vendor/), so nothing can byte-drift and no
# sync-*.sh gate applies. The invariant that REPLACES the byte-drift gate is
# delivery-by-version — editing the shared source obligates a plugin `version`
# bump, because the version is the update cache key and an unbumped plugin
# never delivers the change to consumers. Every cross-plugin cluster gets that
# half enforced by its sync gate's --check-bump; the intra-plugin shape had
# only prose, and two drifts shipped through it: b3445bc2 re-vendored
# knowledge's scene-detect.js with the release note folded into the
# already-released 0.10.9 section and no bump, and b01dace3 edited its
# vtt-parser.js with no bump at all.
#
# WHAT IS CHECKED. For every plugin whose tracked plugins/<name>/vendor/ tree
# differs from <base-ref> — an edit, an addition, or a deletion, since each is
# a source change installed consumers must receive — the plugin's
# .claude-plugin/plugin.json `version` must also differ from <base-ref>.
# General over plugins/*/vendor/ by construction, not a per-plugin list: a
# future plugin adopting the ADR's intra-plugin shape is covered the moment its
# vendor/ directory lands. A plugin absent at the base ref is new in this
# change set; its initial release already carries the vendored source. Whether
# the bump also writes its changelog entry is changelog-parity-gate's half.
#
# Exit: 0 no unbumped vendor change; 1 at least one; 2 usage or a base ref
# git cannot resolve.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

if [[ "${1:-}" != "--check-bump" || -z "${2:-}" || $# -gt 2 ]]; then
  echo "usage: $(basename "$0") --check-bump <base-ref>" >&2
  exit 2
fi
base="$2"

if ! git rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo "$(basename "$0"): cannot resolve base ref: $base" >&2
  exit 2
fi

# One diff over the whole plugins/ tree, filtered structurally in the loop: a
# git pathspec glob ('plugins/*/vendor/') matches `*` across slashes, so it
# could not also hand back the plugin name the manifest lookup needs.
#
# --no-renames is load-bearing. Under rename detection (on by default for
# `git diff`), a file moved plugins/a/vendor/ -> plugins/b/vendor/ collapses to
# one R100 record whose --name-only line is the DESTINATION only, so plugin a's
# vendor deletion — a source change a's installed consumers must receive —
# would never reach the loop and bumping b alone would pass. Disabling
# detection reports the move as a delete plus an add, one path per side, and
# both plugins get checked.
changed_plugins="$(
  git diff --no-renames --name-only "$base" -- plugins/ | while IFS= read -r path; do
    case "$path" in
    plugins/*/vendor/*)
      name="${path#plugins/}"
      name="${name%%/*}"
      # Only a vendor/ directly at the plugin root is the ADR's shape; a
      # vendor/ nested deeper (e.g. a skill-private one) belongs to whatever
      # gate owns that surface.
      [[ "$path" == "plugins/$name/vendor/"* ]] && printf '%s\n' "$name"
      ;;
    *) ;;
    esac
  done | sort -u
)"

if [[ -z "$changed_plugins" ]]; then
  echo "No plugin vendor/ tree changed vs $base; no version bumps required."
  exit 0
fi

stale=0
while IFS= read -r plugin; do
  manifest="plugins/$plugin/.claude-plugin/plugin.json"
  # A plugin absent at the base ref is new in this change set; its initial
  # release already carries the vendored source.
  base_version=$(git show "$base:$manifest" 2>/dev/null | jq -r '.version // empty' || true)
  if [[ -z "$base_version" ]]; then
    continue
  fi
  head_version=$(jq -r '.version // empty' "$manifest" 2>/dev/null || true)
  # A manifest gone (or versionless) at head while vendor/ files still changed
  # is not a bump either; fail rather than skip, so deleting the manifest can
  # never double as this gate's off switch.
  if [[ "$head_version" == "$base_version" || -z "$head_version" ]]; then
    echo "STALE VERSION: plugins/$plugin/vendor/ changed vs $base but $manifest is still ${head_version:-absent}" >&2
    stale=1
  fi
done <<<"$changed_plugins"

if [[ "$stale" -ne 0 ]]; then
  echo "Bump the version of every plugin whose vendor/ source changed — the version is the update cache key, so an unbumped plugin never delivers the change to consumers (ADR 0019, intra-plugin sharing)." >&2
  exit 1
fi

echo "Every plugin with a vendor/ change vs $base bumped its version."
