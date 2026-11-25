#!/usr/bin/env bash
# Exit: 0 done, 2 usage, a bad root, or an instruction file git rm would refuse.
set -euo pipefail

NAMES=(CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md AGENTS.md .claude/AGENTS.md)

usage() {
  echo "usage: instruction-files.sh list <root>" >&2
  echo "       instruction-files.sh strip <root> <name>... | --all" >&2
  echo "       instruction-files.sh restore <root> <ref> <name>..." >&2
  echo "       instruction-files.sh restore <root> <ref> --all   (abandon the experiment)" >&2
  echo "names: ${NAMES[*]}" >&2
  exit 2
}

RESOLVED=()
resolve_names() {
  RESOLVED=()
  if [[ "$1" == "--all" ]]; then
    [[ $# -eq 1 ]] || usage
    RESOLVED=("${NAMES[@]}")
    return 0
  fi
  local n k known seen
  for n in "$@"; do
    known=""
    for k in "${NAMES[@]}"; do [[ "$n" == "$k" ]] && known=1 && break; done
    [[ -n "$known" ]] || {
      echo "instruction-files.sh: not an instruction file name: $n" >&2
      echo "names: ${NAMES[*]}" >&2
      exit 2
    }
    seen=""
    for k in ${RESOLVED[@]+"${RESOLVED[@]}"}; do [[ "$n" == "$k" ]] && seen=1 && break; done
    [[ -n "$seen" ]] || RESOLVED+=("$n")
  done
}

occupied() {
  if [[ -e "$root/$1" || -L "$root/$1" ]]; then
    printf 'occupied'
    return 0
  fi
  if git -C "$root" ls-files --error-unmatch -- "$1" >/dev/null 2>&1; then
    printf 'staged-in-index'
    return 0
  fi
  occupied_ancestor "$1"
}

index_flag_hidden() {
  local v
  v="$(git -C "$root" ls-files -v -- "$1" 2>/dev/null | head -n 1)"
  case "${v:0:1}" in
  [a-z] | S) printf 'index-flag' ;;
  *) ;;
  esac
  return 0
}

obstruction() {
  if [[ -L "$root/$1" ]]; then
    printf 'symlink'
    return 0
  fi
  if [[ -e "$root/$1" && ! -f "$root/$1" ]]; then
    printf 'not-a-regular-file'
    return 0
  fi
  occupied_ancestor "$1"
}

occupied_ancestor() {
  local p="$1"
  while [[ "$p" == */* ]]; do
    p="${p%/*}"
    if [[ -L "$root/$p" ]]; then
      printf 'symlinked-ancestor'
      return 0
    fi
    if [[ -e "$root/$p" && ! -d "$root/$p" ]]; then
      printf 'blocked-ancestor'
      return 0
    fi
  done
  return 0
}

cmd="${1:-}"
root="${2:-}"
[[ -n "$cmd" && -n "$root" ]] || usage
[[ -d "$root" ]] || {
  echo "instruction-files.sh: not a directory: $root" >&2
  exit 2
}

case "$cmd" in
list)
  for n in "${NAMES[@]}"; do
    if [[ -f "$root/$n" ]]; then printf '%s\n' "$n"; fi
  done
  ;;
strip)
  [[ $# -ge 3 ]] || usage
  shift 2
  resolve_names "$@"
  refused=()
  present=()
  for n in "${RESOLVED[@]}"; do
    if [[ ! -f "$root/$n" ]]; then
      [[ "$1" == "--all" ]] || refused+=("$n (not present under $root; re-run list and re-classify)")
      continue
    fi
    present+=("$n")
    hidden="$(index_flag_hidden "$n")"
    if ! git -C "$root" ls-files --error-unmatch -- "$n" >/dev/null 2>&1; then
      refused+=("$n (untracked: not this helper's to strip; back it up to the manifest and remove it there, as with settings)")
    elif ! git -C "$root" diff --quiet -- "$n" ||
      ! git -C "$root" diff --cached --quiet HEAD -- "$n"; then
      refused+=("$n (modified: commit or stash it before stripping)")
    elif [[ -n "$hidden" ]]; then
      refused+=("$n (assume-unchanged or skip-worktree is set, so git cannot see local edits; clear the bit with git update-index --no-assume-unchanged / --no-skip-worktree, then re-check)")
    fi
  done
  if [[ ${#refused[@]} -gt 0 ]]; then
    echo "instruction-files.sh: git rm would refuse these, so nothing was stripped:" >&2
    printf '  %s\n' "${refused[@]}" >&2
    exit 2
  fi
  for n in ${present[@]+"${present[@]}"}; do
    git -C "$root" rm -q -- "$n"
    printf '%s\n' "$n"
  done
  ;;
restore)
  ref="${3:-}"
  [[ -n "$ref" && $# -ge 4 ]] || usage
  shift 3
  git -C "$root" rev-parse --verify --quiet "$ref^{commit}" >/dev/null || {
    echo "instruction-files.sh: not a commit in $root: $ref" >&2
    exit 2
  }
  if [[ "$1" == "--all" ]]; then
    [[ $# -eq 1 ]] || usage
    for n in "${NAMES[@]}"; do
      obstructed="$(obstruction "$n")"
      if [[ -n "$obstructed" ]]; then
        echo "instruction-files.sh: left in place, $n is blocked by another object ($obstructed): $root/$n" >&2
        echo "  git would have to destroy it to reach the path; clear it by hand, then re-run." >&2
        if ! git -C "$root" cat-file -e "$ref:$n" 2>/dev/null &&
          git -C "$root" ls-files --error-unmatch -- "$n" >/dev/null 2>&1; then
          git -C "$root" rm -q --cached --ignore-unmatch -- "$n"
          echo "  its index entry was dropped; only the worktree object remains." >&2
        fi
        continue
      fi
      if git -C "$root" cat-file -e "$ref:$n" 2>/dev/null; then
        git -C "$root" checkout "$ref" -- "$n"
        printf '%s\n' "$n"
      elif git -C "$root" ls-files --error-unmatch -- "$n" >/dev/null 2>&1; then
        git -C "$root" rm -q -f --ignore-unmatch -- "$n"
        printf 'removed %s\n' "$n"
      elif [[ -f "$root/$n" ]]; then
        echo "instruction-files.sh: left in place, untracked and not in $ref: $n" >&2
        echo "  git cannot tell an experiment-created file from one that predated it;" >&2
        echo "  delete it by hand if the experiment created it." >&2
      fi
    done
    exit 0
  fi
  refused=()
  for n in "$@"; do
    known=""
    for k in "${NAMES[@]}"; do [[ "$n" == "$k" ]] && known=1 && break; done
    blocked="$(occupied "$n")"
    if [[ -z "$known" ]]; then
      refused+=("$n (not an instruction file name; names: ${NAMES[*]})")
    elif [[ -n "$blocked" ]]; then
      case "$blocked" in
      staged-in-index)
        refused+=("$n (staged-in-index: content exists only in the index; commit or stash it to keep it, or 'git rm --cached -- $n' to discard it, then re-run)")
        ;;
      *)
        refused+=("$n ($blocked; clear it first, or use --all to abandon the experiment)")
        ;;
      esac
    elif ! git -C "$root" cat-file -e "$ref:$n" 2>/dev/null; then
      refused+=("$n (not in $ref; nothing to restore it from)")
    fi
  done
  if [[ ${#refused[@]} -gt 0 ]]; then
    echo "instruction-files.sh: nothing was restored:" >&2
    printf '  %s\n' "${refused[@]}" >&2
    exit 2
  fi
  for n in "$@"; do
    git -C "$root" checkout "$ref" -- "$n"
    printf '%s\n' "$n"
  done
  ;;
*)
  usage
  ;;
esac
