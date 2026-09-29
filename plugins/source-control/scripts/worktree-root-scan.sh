#!/usr/bin/env bash
# worktree-root-scan.sh — classify the directories under the worktree root that
# no given repository registers as a worktree (#5231). Report only: it never
# deletes, moves or repairs anything.
#
# Usage:
#   worktree-root-scan.sh [--root DIR] [--repo-dir REPO]...
#     --root      the worktree root; default: worktree-root-resolve.sh for the
#                 first --repo-dir
#     --repo-dir  a canonical repository; its `git worktree list` paths join the
#                 registered set (repeatable)
#
# Output: one TSV row per unregistered direct child directory of the root:
#   <path><TAB><class><TAB><proposed>
#   symlink   a symlink                                          proposed no
#   live      inside a live work tree (another repo's worktree)  proposed no
#   husk      .git FILE whose gitdir: target does not exist      proposed yes
#   empty     no entries at all                                  proposed yes
#   foreign   content and no .git                                proposed no
#   unknown   .git present, gitdir exists, rev-parse still fails proposed no
# A directory some other repo owns is `live`, so pass every repo whose worktrees
# share the root to keep those out of the proposals.
#
# A root that does not resolve or is not a directory (an unmounted drive) exits 3
# with a message and no rows; it is never read as "everything is an orphan".
#
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

# Physical path when the directory exists, else the input with a CR and trailing
# slashes dropped. Both sides of every comparison go through this, so Git Bash's
# C:/x and /c/x spellings meet.
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

# The ceiling stops discovery at the root, so a child with no .git of its own is
# never read as part of a repository that happens to contain the root.
inside_work_tree() {
  GIT_CEILING_DIRECTORIES="$root" git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

classify() {
  local d="$1" gitfile target
  if [[ -L "$d" ]]; then
    printf 'symlink\tno'
  elif [[ -e "$d/.git" || -L "$d/.git" ]]; then
    # shellcheck disable=SC2310  # pure predicate; both branches are handled
    if inside_work_tree "$d"; then
      printf 'live\tno'
    elif [[ -f "$d/.git" ]] && IFS= read -r gitfile <"$d/.git" && [[ "$gitfile" == "gitdir: "* ]]; then
      target="${gitfile#gitdir: }"
      target="${target%$'\r'}"
      [[ "$target" == /* || "$target" =~ ^[A-Za-z]:[/\\] ]] || target="$d/$target"
      if [[ -e "$target" ]]; then printf 'unknown\tno'; else printf 'husk\tyes'; fi
    else
      printf 'unknown\tno'
    fi
  elif [[ -z "$(ls -A "$d")" ]]; then
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
