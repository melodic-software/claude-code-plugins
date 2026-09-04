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
# Exit: 0 no unbumped vendor change; 1 at least one; 2 usage, a base ref git
# cannot resolve, a failed diff, missing tooling, or a base manifest that
# exists but cannot be read as a version (failed git show, malformed JSON, no
# `version` key) — a gate that cannot see must refuse to pass, never report
# "nothing changed", and never mistake "could not read" for the new-plugin
# carve-out.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2

if [[ "${1:-}" != "--check-bump" || -z "${2:-}" || $# -gt 2 ]]; then
  echo "usage: $(basename "$0") --check-bump <base-ref>" >&2
  exit 2
fi
base="$2"

# jq is how every manifest version is read below; without it the per-plugin
# reads all come back empty, which the loop would misread as "new plugin,
# exempt" for every plugin — a full-open gate. Assert it up front so absent
# tooling is its own loud exit, distinct from "nothing changed".
if ! jq --version >/dev/null 2>&1; then
  echo "$(basename "$0"): jq is required to read manifest versions; refusing to pass without it" >&2
  exit 2
fi

if ! changed_files::verify_base "$base"; then
  echo "$(basename "$0"): cannot resolve base ref: $base" >&2
  exit 2
fi

# One diff over the whole plugins/ tree, filtered structurally in the loop: a
# git pathspec glob ('plugins/*/vendor/') matches `*` across slashes, so it
# could not also hand back the plugin name the manifest lookup needs. The walk
# itself is the shared resolver's, not a hand-rolled pipeline, and each of its
# arguments is load-bearing:
#
#   --include-deleted — a deletion is a source change installed consumers must
#   receive, so the scanner default of dropping deleted paths is wrong here.
#
#   --no-renames — under rename detection (on by default for `git diff`), a
#   file moved plugins/a/vendor/ -> plugins/b/vendor/ collapses to one R100
#   record whose --name-only line is the DESTINATION only, so plugin a's
#   vendor deletion — a source change a's installed consumers must receive —
#   would never reach the loop and bumping b alone would pass. Disabling
#   detection reports the move as a delete plus an add, one path per side, and
#   both plugins get checked.
#
# The resolver also carries the fail-closed mechanics: a failed git diff (or
# a failure staging/sorting its output) is its own non-zero return rather
# than an empty list that reads as "nothing changed", and paths arrive
# NUL-delimited so a name git would
# C-quote under the default core.quotePath (non-ASCII bytes, a literal quote)
# reaches the structural filter verbatim instead of wrapped in quotes that
# match no pattern.
changed_paths=()
if ! changed_files::into changed_paths "$base" --include-deleted --no-renames -- plugins/; then
  echo "$(basename "$0"): git diff failed against $base (or staging its output did); refusing to pass on a change set this gate could not read" >&2
  exit 2
fi

changed_plugins=()
declare -A seen_plugins=()
for path in ${changed_paths[@]+"${changed_paths[@]}"}; do
  case "$path" in
  plugins/*/vendor/*)
    name="${path#plugins/}"
    name="${name%%/*}"
    # Only a vendor/ directly at the plugin root is the ADR's shape; a
    # vendor/ nested deeper (e.g. a skill-private one) belongs to whatever
    # gate owns that surface.
    [[ "$path" == "plugins/$name/vendor/"* ]] || continue
    [[ -z "${seen_plugins[$name]:-}" ]] || continue
    seen_plugins["$name"]=1
    changed_plugins+=("$name")
    ;;
  *) ;;
  esac
done

if [[ ${#changed_plugins[@]} -eq 0 ]]; then
  echo "No plugin vendor/ tree changed vs $base; no version bumps required."
  exit 0
fi

# Base manifests are staged through a file rather than a command substitution.
# `$(git show ...)` is not a faithful read: Bash silently DROPS any raw NUL
# byte from the captured output, so a base manifest corrupted by an embedded
# NUL -- which is never valid JSON -- reaches jq already repaired, parses
# clean, and yields a version the gate then trusts. The same read from a file
# hands jq the bytes git actually stored, so a corrupt base manifest is the
# exit 2 the header promises rather than a silent version.
base_manifest_file="$(mktemp)" || {
  echo "$(basename "$0"): mktemp failed; refusing to pass without a place to stage base manifests" >&2
  exit 2
}
trap 'rm -f "$base_manifest_file"' EXIT

stale=0
for plugin in "${changed_plugins[@]}"; do
  manifest="plugins/$plugin/.claude-plugin/plugin.json"
  # A plugin absent at the base ref is new in this change set; its initial
  # release already carries the vendored source. But "absent" must be an
  # observation, never a fallback: the old single-pipeline read collapsed a
  # failed `git show`, a malformed base manifest, and a version-less one into
  # the same empty string this carve-out keys on, silently exempting each.
  # So existence is probed on its own (ls-tree exits 0 with empty output for
  # a path the base tree lacks, non-zero only when git itself failed), and
  # once the manifest is known to exist every later step must succeed: a base
  # version this gate cannot read is not a bump exemption.
  if ! base_manifest_entry="$(git ls-tree --name-only "$base" -- "$manifest")"; then
    echo "$(basename "$0"): git ls-tree failed reading $base; refusing to pass on a base this gate could not read" >&2
    exit 2
  fi
  if [[ -z "$base_manifest_entry" ]]; then
    continue
  fi
  if ! git show "$base:$manifest" >"$base_manifest_file"; then
    echo "$(basename "$0"): git show failed reading $manifest at $base; refusing to pass on a manifest this gate could not read" >&2
    exit 2
  fi
  if ! base_version="$(jq -r '.version // empty' "$base_manifest_file")"; then
    echo "$(basename "$0"): $manifest at $base is not valid JSON; refusing to treat an unreadable base version as a bump exemption" >&2
    exit 2
  fi
  if [[ -z "$base_version" ]]; then
    echo "$(basename "$0"): $manifest at $base has no version; refusing to treat a version-less base manifest as a bump exemption" >&2
    exit 2
  fi
  head_version=$(jq -r '.version // empty' "$manifest" 2>/dev/null || true)
  # A manifest gone (or versionless) at head while vendor/ files still changed
  # is not a bump either; fail rather than skip, so deleting the manifest can
  # never double as this gate's off switch.
  if [[ "$head_version" == "$base_version" || -z "$head_version" ]]; then
    echo "STALE VERSION: plugins/$plugin/vendor/ changed vs $base but $manifest is still ${head_version:-absent}" >&2
    stale=1
  fi
done

if [[ "$stale" -ne 0 ]]; then
  echo "Bump the version of every plugin whose vendor/ source changed — the version is the update cache key, so an unbumped plugin never delivers the change to consumers (ADR 0019, intra-plugin sharing)." >&2
  exit 1
fi

echo "Every plugin with a vendor/ change vs $base bumped its version."
