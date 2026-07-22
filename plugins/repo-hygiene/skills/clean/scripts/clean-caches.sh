#!/usr/bin/env bash
# shellcheck disable=SC2154
# Remove tool/linter caches for the clean caches tier.
#
# Default: --dry-run (writes a manifest of planned removals + reclaimable bytes).
# --apply consumes the manifest (re-stat staleness guard) and mutates disk.
# Respects protected paths and git-tracked files. Enumeration/manifest/apply
# engine is shared with clean-build.sh in lib/clean-common.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"

DRY_RUN=1
MANIFEST_ARG=""

usage() {
  cat <<'EOF'
clean-caches.sh — remove tool/linter caches for the clean caches tier.

Usage:
  clean-caches.sh [--dry-run] [--apply] [--manifest PATH] [--help]

Default: --dry-run — writes a manifest and prints its path + reclaimable total,
never mutates. --apply performs rm -rf on eligible targets.

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
  --manifest)
    if [[ $# -lt 2 ]]; then
      echo "clean-caches.sh: --manifest requires a value" >&2
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
    echo "clean-caches.sh: unknown arg '$1'" >&2
    exit 2
    ;;
  esac
done

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "clean-caches.sh: not a git repository" >&2
  exit 1
fi

cd "$REPO_ROOT" || exit 1

# --apply with a prebuilt manifest: skip enumeration entirely, just consume it.
if [[ "$DRY_RUN" -eq 0 && -n "$MANIFEST_ARG" ]]; then
  if [[ ! -r "$MANIFEST_ARG" ]]; then
    echo "clean-caches.sh: manifest not readable: $MANIFEST_ARG" >&2
    exit 1
  fi
  clean_apply_manifest "$REPO_ROOT" "$MANIFEST_ARG" "caches"
  printf 'Summary: removed=%s failed=%s bytes=%s\n' \
    "$CLEAN_REMOVED_COUNT" "$CLEAN_FAILED_COUNT" "$CLEAN_REMOVED_BYTES"
  [[ "$CLEAN_FAILED_COUNT" -eq 0 ]] || exit 1
  exit 0
fi

MANIFEST="$(clean_manifest_path "$MANIFEST_ARG")" || exit 1

mapfile -t CACHE_CANDS < <(clean_caches_candidates "$REPO_ROOT")
clean_add_candidates caches "${CACHE_CANDS[@]}"
clean_plan "$REPO_ROOT" "$MANIFEST" "$DRY_RUN"

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'Manifest: %s\n' "$MANIFEST"
  printf 'Summary: planned=%s bytes=%s\n' "$CLEAN_PLANNED_COUNT" "$CLEAN_PLANNED_BYTES"
  exit 0
fi

clean_apply_manifest "$REPO_ROOT" "$MANIFEST" "caches"
printf 'Summary: removed=%s failed=%s bytes=%s\n' \
  "$CLEAN_REMOVED_COUNT" "$CLEAN_FAILED_COUNT" "$CLEAN_REMOVED_BYTES"
[[ "$CLEAN_FAILED_COUNT" -eq 0 ]] || exit 1
exit 0
