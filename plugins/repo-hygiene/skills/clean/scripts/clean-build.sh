#!/usr/bin/env bash
# shellcheck disable=SC2154
# Remove build artifacts for the clean build tier (includes caches when --include-caches).
#
# Default: --dry-run (writes a manifest of planned removals + reclaimable bytes).
# --apply consumes the manifest (re-stat staleness guard) and mutates disk.
# Optional dotnet clean driver when dotnet available. With --include-caches the
# caches tier shares this one manifest — a single pruned walk per tier, no
# subprocess. Enumeration/manifest/apply engine lives in lib/clean-common.sh.
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
    MANIFEST_ARG="${2:-}"
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

# .NET clean driver — solution/project detected at runtime, never hardcoded.
# Prefer a *.slnx, then *.sln, at the repo root; skip cleanly when none exists
# or dotnet is unavailable (universal bin/obj globs below still remove output).
# Independent of the path manifest (it is an action, not a path): announced on
# dry-run, run on any --apply.
DOTNET_SOLUTION=""
if command -v dotnet >/dev/null 2>&1; then
  for cand in "$REPO_ROOT"/*.slnx "$REPO_ROOT"/*.sln; do
    if [[ -f "$cand" ]]; then
      DOTNET_SOLUTION="$cand"
      break
    fi
  done
fi
if [[ -n "$DOTNET_SOLUTION" ]]; then
  DOTNET_DRIVER="dotnet clean \"$DOTNET_SOLUTION\" -v q"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'Planned: %s\n' "$DOTNET_DRIVER"
  else
    if ! dotnet clean "$DOTNET_SOLUTION" -v q 2>/dev/null; then
      printf 'DRIVER_FAILED: %s\n' "$DOTNET_DRIVER" >&2
    fi
  fi
fi

# --apply with a prebuilt manifest: skip enumeration entirely, just consume it.
if [[ "$DRY_RUN" -eq 0 && -n "$MANIFEST_ARG" ]]; then
  clean_apply_manifest "$REPO_ROOT" "$MANIFEST_ARG"
  printf 'Summary: removed=%s failed=%s bytes=%s\n' \
    "$CLEAN_REMOVED_COUNT" "$CLEAN_FAILED_COUNT" "$CLEAN_REMOVED_BYTES"
  [[ "$CLEAN_FAILED_COUNT" -eq 0 ]] || exit 1
  exit 0
fi

MANIFEST="$(clean_manifest_path "$MANIFEST_ARG")"

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

clean_apply_manifest "$REPO_ROOT" "$MANIFEST"
printf 'Summary: removed=%s failed=%s bytes=%s\n' \
  "$CLEAN_REMOVED_COUNT" "$CLEAN_FAILED_COUNT" "$CLEAN_REMOVED_BYTES"
[[ "$CLEAN_FAILED_COUNT" -eq 0 ]] || exit 1
exit 0
