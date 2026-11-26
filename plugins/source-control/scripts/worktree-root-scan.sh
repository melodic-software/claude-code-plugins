#!/usr/bin/env bash
# Exit codes:
#   0  scan complete (zero or more rows)
#   2  usage
#   3  root unresolved or missing
#   5  a --repo-dir is not a repository, or git is older than the -z floor

set -euo pipefail

PROG=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-facts.sh
source "$SCRIPT_DIR/lib/worktree-facts.sh"

usage() {
  printf 'Usage: %s [--root DIR] [--repo-dir REPO]...\n' "$PROG" >&2
  exit 2
}

root=""
repos=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    [[ $# -ge 2 ]] || usage
    root="$2"
    shift 2
    ;;
  --repo-dir)
    [[ $# -ge 2 ]] || usage
    repos+=("$2")
    shift 2
    ;;
  *) usage ;;
  esac
done
[[ -n "$root" || ${#repos[@]} -gt 0 ]] || usage

phys() {
  local p="${1%$'\r'}" out
  while [[ ${#p} -gt 1 && "$p" == */ ]]; do p="${p%/}"; done
  if [[ -d "$p" ]] && out="$(cd "$p" && pwd -P 2>/dev/null)"; then
    printf '%s' "$out"
  else
    printf '%s' "$p"
  fi
}

if [[ -z "$root" ]]; then
  root="$(bash "$SCRIPT_DIR/worktree-root-resolve.sh" --repo-dir "${repos[0]}")"
fi
if [[ -z "$root" ]]; then
  printf '%s: no worktree root resolved; pass --root\n' "$PROG" >&2
  exit 3
fi
if [[ ! -d "$root" ]]; then
  printf '%s: worktree root is not a directory (unmounted?): %s\n' "$PROG" "$root" >&2
  exit 3
fi
root="$(phys "$root")"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

registered=()
for repo in ${repos[@]+"${repos[@]}"}; do
  if ! git -C "$repo" worktree list --porcelain -z >"$tmp" 2>/dev/null; then
    printf '%s: cannot list worktrees of %s; %s\n' "$PROG" "$repo" "$(worktree_list_z_floor_note)" >&2
    exit 5
  fi
  worktree_facts_parse_z "$tmp"
  for p in ${WT_FACT_PATH[@]+"${WT_FACT_PATH[@]}"}; do
    registered+=("$(phys "$p")")
  done
done

is_registered() {
  local r
  for r in ${registered[@]+"${registered[@]}"}; do
    [[ "$r" == "$1" ]] && return 0
  done
  return 1
}

inside_work_tree() {
  GIT_CEILING_DIRECTORIES="$root" git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

classify() {
  local d="$1" gitfile target common entries
  if [[ -L "$d" ]]; then
    printf 'symlink\tno'
  elif ! entries="$(ls -A "$d" 2>/dev/null)"; then
    printf 'unknown\tno'
  elif [[ -e "$d/.git" || -L "$d/.git" ]]; then
    # shellcheck disable=SC2310  # pure predicate; both branches are handled
    if inside_work_tree "$d"; then
      printf 'live\tno'
    elif [[ -f "$d/.git" && ! -L "$d/.git" ]] && IFS= read -r gitfile <"$d/.git" && [[ "$gitfile" == "gitdir: "* ]]; then
      target="${gitfile#gitdir: }"
      target="${target%$'\r'}"
      [[ "$target" == /* || "$target" =~ ^[A-Za-z]:[/\\] ]] || target="$d/$target"
      common="${target%/worktrees/*}"
      if [[ ! -e "$target" && "$target" == */worktrees/* && -f "$common/HEAD" && -d "$common/objects" ]]; then
        if [[ "$entries" == .git ]]; then printf 'husk\tyes'; else printf 'husk\tno'; fi
      else
        printf 'unknown\tno'
      fi
    else
      printf 'unknown\tno'
    fi
  elif [[ -z "$entries" ]]; then
    printf 'empty\tyes'
  else
    printf 'foreign\tno'
  fi
}

rows=""
for d in "$root"/* "$root"/.[!.]* "$root"/..?*; do
  [[ -L "$d" || -d "$d" ]] || continue
  # shellcheck disable=SC2310  # pure predicates; both branches are handled
  is_registered "$(phys "$d")" && continue
  rows+="$d"$'\t'"$(classify "$d")"$'\n'
done
printf '%s' "$rows"
