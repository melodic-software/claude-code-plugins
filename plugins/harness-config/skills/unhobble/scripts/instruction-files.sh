#!/usr/bin/env bash
# instruction-files.sh: the project-root instruction files the unhobble strip
# moves aside, and the git commands that move them and put them back.
#
# AGENTS.md and .claude/AGENTS.md are on the list unconditionally. Claude Code
# reads them as the project instructions only when no CLAUDE.md name displaces
# them, and the strip removes exactly those CLAUDE.md names, so a file that is
# merely imported by a one-line shim today is read natively the moment the shim
# goes. A baseline that left it in place would declare itself bare while the
# repository's whole instruction surface was still loading. Whether a session
# reads one at all, and which files the instruction-files mode loads, carry their
# dated records in this plugin's reference/agents-md-liveness.md. The caller
# decides candidacy from those; this script only moves the names it is given.
#
#   instruction-files.sh list <root>                     print the files present under <root>
#   instruction-files.sh strip <root> <name>...          git rm each NAMED file
#   instruction-files.sh strip <root> --all              git rm every name present
#   instruction-files.sh restore <root> <ref> <name>...  git checkout <ref> -- each NAMED file
#   instruction-files.sh restore <root> <ref> --all      ABANDON the experiment: the
#                                                        pre-strip state of every name
#
# <root> is always an explicit argument. This script never falls back to the
# working directory: a strip that resolved its own target would run against
# whatever repository the operator happened to be standing in rather than the
# checkout they named.
#
# BOTH DIRECTIONS NAME WHAT THEY TOUCH. The strip plan classifies per file, so a
# repository can hold a behavioral CLAUDE.md beside an AGENTS.md the operator
# classified `policy` or `convention` and chose to keep; a strip that took the
# whole list would delete the surface the plan said to retain. Phase 4 is the
# mirror: it re-adds only the instructions the stumble ledger defended, so a
# restore of everything would hand back the ones it did not and undo the result.
# `list` reports the candidates; the caller classifies them and names its choice.
# `--all` exists on both verbs for the cases where the whole set IS the decision,
# and is a separate word because taking the set is never the default.
#
# `restore --all` IS THE ABANDON PATH, NOT THE CLOSE PATH. It is for walking the
# whole experiment back to its pre-strip state, discarding the result. Closing an
# experiment normally is the opposite: the editorial surfaces the ledger did not defend
# STAY retired, which is the finding the experiment was run to produce, so a
# close never calls it. Reaching the pre-strip state means both halves: a name the
# ref has is checked out over whatever is on disk, since a file the experiment
# recreated or rewrote is exactly what an abandon discards, and a name the ref
# does NOT have but git TRACKS is removed, since being tracked and absent from
# the ref is git's own evidence the experiment added it. A name the ref does not
# have and git does not track is the one case this cannot decide: a file that was
# never tracked is absent from every commit, so a `CLAUDE.local.md` that predated
# the experiment looks exactly like one the experiment wrote. It is named for the
# operator and left in place; an unrecoverable delete is the worse error.
#
# `strip` checks every present file is tracked AND clean BEFORE it removes any of
# them, and exits 2 naming the offenders with the tree untouched. `git rm` refuses
# both an untracked file (the ordinary case for CLAUDE.local.md) and a tracked one
# whose content differs from the tip of the branch, and either refusal mid-loop
# leaves the files ahead of it gone while the ones behind it stay loaded, which is
# the half-stripped baseline this whole change exists to prevent. Back an untracked
# file up through the manifest, and commit or stash a dirty one, then strip.
#
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

# Prints a reason when the index carries a bit that makes git stop comparing the
# worktree copy, so a "clean" answer from `git diff` cannot be trusted for it.
# `ls-files -v` marks these: a LOWERCASE status letter means assume-unchanged,
# and `S` means skip-worktree.
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
    # Resolved outside the conditions below, per SC2310 as elsewhere here.
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
    # Resolved outside the condition below: a function called inside one
    # suppresses `set -e` for its body (SC2310).
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
