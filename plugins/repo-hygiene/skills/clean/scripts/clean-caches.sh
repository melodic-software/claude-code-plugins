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

# die <message> <exit-code>
die() {
  echo "clean-caches.sh: $1" >&2
  exit "$2"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=1 ;;
  --apply) DRY_RUN=0 ;;
  --manifest)
    [[ $# -ge 2 ]] || die "--manifest requires a value" 2
    MANIFEST_ARG="$2"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown arg '$1'" 2 ;;
  esac
  shift
done

REPO_ROOT="$(clean_repo_root)"
[[ -n "$REPO_ROOT" ]] || die "not a git repository" 1
cd "$REPO_ROOT" || exit 1

if [[ "$DRY_RUN" -eq 0 && -n "$MANIFEST_ARG" ]]; then
  # --apply with a prebuilt manifest: skip enumeration entirely, just consume it.
  [[ -r "$MANIFEST_ARG" ]] || die "manifest not readable: $MANIFEST_ARG" 1
  MANIFEST="$MANIFEST_ARG"
else
  MANIFEST="$(clean_manifest_path "$MANIFEST_ARG")" || exit 1
  mapfile -t CACHE_CANDS < <(clean_caches_candidates "$REPO_ROOT")
  clean_add_candidates caches "${CACHE_CANDS[@]}"
  clean_plan "$REPO_ROOT" "$MANIFEST" "$DRY_RUN"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'Manifest: %s\n' "$MANIFEST"
    printf 'Summary: planned=%s bytes=%s\n' "$CLEAN_PLANNED_COUNT" "$CLEAN_PLANNED_BYTES"
    exit 0
  fi
fi

clean_apply_and_report "$REPO_ROOT" "$MANIFEST" "caches" || exit 1
exit 0
