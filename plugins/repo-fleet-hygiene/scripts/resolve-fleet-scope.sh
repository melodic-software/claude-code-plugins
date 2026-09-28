#!/usr/bin/env bash
# Print repository paths for a fleet verb, one per line.
#
#   resolve-fleet-scope.sh [--repo <dir>]... [--config <file>] [--from-file <file>]
#   resolve-fleet-scope.sh --fallback-only
#
# Rungs, first hit that yields a path wins for that source, and sources add:
#   1. --repo
#   2. fleet.repo / fleet.root in --config (git config)
#   3. --from-file (one path per line)
#   4. ghq roots, when ghq is on PATH (each child that is a work tree)
#   5. the git working tree that contains the cwd
# Exit 0 when at least one path was printed, 3 when none, 2 on usage.
# --fallback-only runs rungs 4 and 5 only. Audit already applied 1-3.
set -uo pipefail

REPOS=()
CONFIG=""
FROM_FILE=""
FALLBACK_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --repo)
    [[ $# -ge 2 ]] || { echo "resolve-fleet-scope.sh: --repo needs a path" >&2; exit 2; }
    REPOS+=("$2")
    shift 2
    ;;
  --config)
    [[ $# -ge 2 ]] || { echo "resolve-fleet-scope.sh: --config needs a path" >&2; exit 2; }
    CONFIG="$2"
    shift 2
    ;;
  --from-file)
    [[ $# -ge 2 ]] || { echo "resolve-fleet-scope.sh: --from-file needs a path" >&2; exit 2; }
    FROM_FILE="$2"
    shift 2
    ;;
  --fallback-only)
    FALLBACK_ONLY=1
    shift
    ;;
  *)
    echo "resolve-fleet-scope.sh: unknown argument $1" >&2
    exit 2
    ;;
  esac
done

paths=()
add_path() {
  local path="$1"
  [[ -n "$path" ]] || return 0
  paths+=("$path")
}

if [[ "$FALLBACK_ONLY" -eq 0 ]]; then
  local_repo=""
  for local_repo in ${REPOS[@]+"${REPOS[@]}"}; do
    add_path "$local_repo"
  done
  if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
    while IFS= read -r value; do
      add_path "$value"
    done < <(git config --file "$CONFIG" --get-all fleet.repo 2>/dev/null || true)
    while IFS= read -r value; do
      add_path "$value"
    done < <(git config --file "$CONFIG" --get-all fleet.root 2>/dev/null || true)
  fi
  if [[ -n "$FROM_FILE" && -f "$FROM_FILE" ]]; then
    while IFS= read -r value; do
      [[ -n "$value" && "$value" != \#* ]] && add_path "$value"
    done <"$FROM_FILE"
  fi
fi

if [[ ${#paths[@]} -eq 0 ]] && command -v ghq >/dev/null 2>&1; then
  while IFS= read -r root; do
    [[ -d "$root" ]] || continue
    while IFS= read -r child; do
      if git -C "$child" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        add_path "$child"
      fi
    done < <(find "$root" -mindepth 1 -maxdepth 2 -type d 2>/dev/null)
  done < <(ghq root 2>/dev/null || true)
fi

if [[ ${#paths[@]} -eq 0 ]]; then
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  top="${top%$'\r'}"
  add_path "$top"
fi

if [[ ${#paths[@]} -eq 0 ]]; then
  exit 3
fi
printf '%s\n' "${paths[@]}"
exit 0
