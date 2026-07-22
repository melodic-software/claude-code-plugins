#!/usr/bin/env bash
# shellcheck disable=SC2154
# Remove build artifacts for the clean build tier (includes caches when --include-caches).
#
# Default: --dry-run (writes a manifest of planned removals + reclaimable bytes).
# --apply consumes the manifest (re-stat staleness guard) and mutates disk.
# With --include-caches the caches tier shares this one manifest — a single
# pruned walk per tier, no subprocess. Enumeration/manifest/apply engine lives
# in lib/clean-common.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

DRY_RUN=1
INCLUDE_CACHES=0
MANIFEST_ARG=""

usage() {
  cat <<'EOF'
clean-build.sh — remove build artifacts for the clean build tier.

Usage:
  clean-build.sh [--dry-run] [--apply] [--include-caches] [--manifest PATH] [--help]

Default: --dry-run — writes a manifest and prints its path + reclaimable total,
never mutates. --include-caches folds the caches tier into the same manifest.

Manifest flow (single walk paid once):
  --dry-run              writes a manifest, prints `Manifest: <path>` and
                         `Summary: planned=N bytes=K`.
  --apply --manifest P   consumes manifest P (re-stat guard, no re-walk); resume
                         = re-run the same command (already-gone entries skipped).
  --apply                without --manifest builds the manifest then applies it.
  --manifest P           on --dry-run writes to P instead of a mktemp path.

Exit: 0 success; 1 not a git repo OR an apply had rm failures; 2 usage error.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  --apply)
    DRY_RUN=0
    shift
    ;;
  --include-caches)
    INCLUDE_CACHES=1
    shift
    ;;
  --manifest)
    if [[ $# -lt 2 ]]; then
      echo "clean-build.sh: --manifest requires a value" >&2
      exit 2
    fi
    MANIFEST_ARG="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "clean-build.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
done

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "clean-build.sh: not a git repository" >&2
  exit 1
fi

cd "$REPO_ROOT" || exit 1

# No build-system clean driver (e.g. `dotnet clean`): the universal bin/obj/…
# removal below already deletes everything such a driver would, and running one
# first is pure overhead (full MSBuild evaluation, minutes on a large solution)
# that also re-creates obj/ evaluation artifacts. One walk + rm is strictly
# faster and equally complete.

# --apply with a prebuilt manifest: skip enumeration entirely, just consume it.
if [[ "$DRY_RUN" -eq 0 && -n "$MANIFEST_ARG" ]]; then
  if [[ ! -r "$MANIFEST_ARG" ]]; then
    echo "clean-build.sh: manifest not readable: $MANIFEST_ARG" >&2
    exit 1
  fi
  clean_apply_manifest "$REPO_ROOT" "$MANIFEST_ARG" "build caches"
  printf 'Summary: removed=%s failed=%s bytes=%s\n' \
    "$CLEAN_REMOVED_COUNT" "$CLEAN_FAILED_COUNT" "$CLEAN_REMOVED_BYTES"
  [[ "$CLEAN_FAILED_COUNT" -eq 0 ]] || exit 1
  exit 0
fi

MANIFEST="$(clean_manifest_path "$MANIFEST_ARG")" || exit 1

if [[ "$INCLUDE_CACHES" -eq 1 ]]; then
  mapfile -t CACHE_CANDS < <(clean_caches_candidates "$REPO_ROOT")
  clean_add_candidates caches "${CACHE_CANDS[@]}"
fi

mapfile -t BUILD_CANDS < <(clean_build_candidates "$REPO_ROOT")
clean_add_candidates build "${BUILD_CANDS[@]}"

clean_plan "$REPO_ROOT" "$MANIFEST" "$DRY_RUN"

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'Manifest: %s\n' "$MANIFEST"
  printf 'Summary: planned=%s bytes=%s\n' "$CLEAN_PLANNED_COUNT" "$CLEAN_PLANNED_BYTES"
  exit 0
fi

clean_apply_manifest "$REPO_ROOT" "$MANIFEST" "build caches"
printf 'Summary: removed=%s failed=%s bytes=%s\n' \
  "$CLEAN_REMOVED_COUNT" "$CLEAN_FAILED_COUNT" "$CLEAN_REMOVED_BYTES"
[[ "$CLEAN_FAILED_COUNT" -eq 0 ]] || exit 1
exit 0
