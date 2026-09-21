#!/usr/bin/env bash
# instruction-files.sh: the project-root instruction files the unhobble strip
# moves aside, and the git commands that move them and put them back.
#
# AGENTS.md and .claude/AGENTS.md are on the list unconditionally. Claude Code
# reads them as the project instructions only when no CLAUDE.md name displaces
# them, and the strip removes exactly those CLAUDE.md names, so a file that is
# merely imported by a one-line shim today is read natively the moment the shim
# goes. A baseline that left it in place would declare itself bare while the
# repository's whole instruction surface was still loading. The displacement
# rule and its dated record live in
# plugins/instruction-placement/skills/migrate/reference/sources.md.
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
# experiment normally is the opposite: the surfaces the ledger did not defend
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

# Every name the caller gave, checked against NAMES; `--all` expands to the whole
# list. Sets the global RESOLVED array, deliberately NOT printing into a command
# substitution: a `$(…)` or `< <(…)` runs in a subshell, where this function's
# `exit 2` on a bad name would end only the subshell and let the caller carry on
# with an empty list, turning a rejected typo into a silent no-op.
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
    # A repeat is dropped, not carried. Acting on one twice means a second
    # `git rm` on a file the first already removed, which fails under `set -e`
    # with the tree ALREADY mutated: a command that reports failure after doing
    # half its work is the state this script refuses everywhere else.
    seen=""
    for k in ${RESOLVED[@]+"${RESOLVED[@]}"}; do [[ "$n" == "$k" ]] && seen=1 && break; done
    [[ -n "$seen" ]] || RESOLVED+=("$n")
  done
}

# True when a checkout of this name would have to destroy something first: the
# target occupied by ANY object, or an ancestor inside the root that is not a
# directory. A plain `-f` test misses a directory, a symlink to nowhere, and a
# `.claude` that has become a regular file, and `git checkout` resolves each of
# those by REMOVING it, a nonempty directory included, before writing the
# committed path. Nothing here is recoverable from the ref, so an occupied target
# is treated as already present rather than as free space.
# These PRINT a reason rather than returning a status, so callers read them
# through a command substitution instead of an `if`. A predicate function called
# in a condition suppresses `set -e` for its whole body, which the repo's lint
# configuration flags (SC2310, the check-set-e-suppressed option).
occupied() {
  if [[ -e "$root/$1" || -L "$root/$1" ]]; then
    printf 'occupied'
    return 0
  fi
  # The INDEX counts as occupancy too, and the filesystem alone cannot see it.
  # `git checkout <ref> -- <path>` updates the index AND the worktree, so a name
  # that was recreated, staged, and then deleted from the worktree has content
  # that exists ONLY in the index, invisible to every test above, which this
  # would overwrite with the ref's version and lose. A stripped name has no index
  # entry, so refusing on one costs the ordinary phase-4 restore nothing.
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
  [[ -n "$v" ]] || return 0
  case "${v:0:1}" in
  [a-z] | S) printf 'index-flag' ;;
  *) ;;
  esac
  return 0
}

# The `--all` form of the same question. It differs from `occupied` in one place:
# a PLAIN FILE at the target is not an obstruction there, because overwriting or
# removing the file that belongs at the path is what abandoning does. Anything
# else is, and `-L` is tested BEFORE `-f` because `-f` follows a symlink and
# would call a link to a regular file an ordinary file. The docs recommend an
# `AGENTS.md`-to-`CLAUDE.md` symlink ("Share one file with other coding tools"),
# so a link at one of these paths is a shape a real repository has.
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

# Prints a reason when a directory component of the name exists as something
# other than a directory, so the path cannot be written without destroying it.
occupied_ancestor() {
  local p="$1"
  while [[ "$p" == */* ]]; do
    p="${p%/*}"
    # `-L` first, and on its own. `-d` FOLLOWS a symlink, so a `.claude` that is
    # a link to a directory would read as an ordinary directory and pass; git
    # writing a path through it replaces the link with a real directory, losing
    # the link. A DANGLING link fails `-e` and would pass this test the other
    # way, while still blocking the write.
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
      # Under `--all` the set means "every name present", so an absent one is
      # simply not in it. A name the CALLER approved is the opposite: exiting 0
      # having stripped nothing lets the manifest record a bare baseline while
      # the file the plan named still loads, which is this script's whole
      # subject reached through a stale plan instead of a mid-loop abort. The
      # usual cause is exactly that: the plan named `CLAUDE.md` and the surface
      # moved to `.claude/CLAUDE.md` before the strip ran.
      [[ "$1" == "--all" ]] || refused+=("$n (not present under $root; re-run list and re-classify)")
      continue
    fi
    present+=("$n")
    # Resolved outside the conditions below, per SC2310 as elsewhere here.
    hidden="$(index_flag_hidden "$n")"
    if ! git -C "$root" ls-files --error-unmatch -- "$n" >/dev/null 2>&1; then
      # This helper is git-only by construction: git holding the undo is the whole
      # reason it can remove anything. An untracked instruction file has no undo
      # here, so it is not this command's to strip at all. It goes through the
      # SAME backup-to-plugin-state path the manifest already uses for settings
      # and other non-git-tracked surfaces, which is where its restore lives too.
      refused+=("$n (untracked: not this helper's to strip; back it up to the manifest and remove it there, as with settings)")
    elif ! git -C "$root" diff --quiet -- "$n" ||
      ! git -C "$root" diff --cached --quiet HEAD -- "$n"; then
      # `git rm` without -f refuses a file whose content differs from the tip of
      # the branch, in the worktree or staged, exactly as it refuses an untracked
      # one. Catching it here keeps the refusal from landing mid-loop.
      refused+=("$n (modified: commit or stash it before stripping)")
    elif [[ -n "$hidden" ]]; then
      # `assume-unchanged` and `skip-worktree` tell git to STOP COMPARING the
      # worktree copy, so the two `diff --quiet` checks above both report clean
      # on a file that has been edited, and `git rm` then deletes the edit with
      # no refusal and nothing in the ref to recover. Measured on git 2.55: with
      # `--assume-unchanged` set and the file edited, `ls-files -v` prints `h`,
      # both diffs exit 0, and `git rm` succeeds. The flag is the only signal
      # that the clean answer is not trustworthy, so it is a refusal of its own.
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
    # Abandoning. A name the ref has is checked out over whatever is in the
    # worktree now, since a file the experiment recreated or rewrote is the content
    # this path discards. A name the ref does NOT have but git TRACKS is removed,
    # tracked-and-absent-from-the-ref being git's own evidence the experiment added
    # it. A name that is neither in the ref nor tracked is the case this cannot
    # decide: it is named for the operator and LEFT, per the branch below.
    for n in "${NAMES[@]}"; do
      # ONE guard, ahead of every branch, resolved outside the conditions per
      # SC2310. Each branch below runs a command that assumes a plain file or
      # nothing: `git checkout` DELETES a directory or symlink in its way, and
      # `git rm` ABORTS on a non-empty directory, which under `set -e` would end
      # the run part-way with earlier names already restored, the index entry
      # still present and a raw `fatal:` in place of this script's own message.
      # A half-applied abandon is the state this script refuses everywhere else.
      obstructed="$(obstruction "$n")"
      if [[ -n "$obstructed" ]]; then
        echo "instruction-files.sh: left in place, $n is blocked by another object ($obstructed): $root/$n" >&2
        echo "  git would have to destroy it to reach the path; clear it by hand, then re-run." >&2
        # The INDEX half is still safe to finish for a tracked name the ref lacks:
        # `--cached` drops the entry the experiment added without touching the
        # object in the way, so the next commit does not carry it.
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
        # TRACKED and not in the ref: git itself is the evidence the experiment
        # added it, so removing it is provably a return to the pre-strip state.
        # `git rm -f` clears the index entry whether or not the worktree copy is
        # still there, which a worktree test alone would miss: a staged addition
        # whose file was deleted by hand stays indexed, and the next commit would
        # carry the experiment's own instruction file into the abandoned state.
        git -C "$root" rm -q -f --ignore-unmatch -- "$n"
        printf 'removed %s\n' "$n"
      elif [[ -f "$root/$n" ]]; then
        # UNTRACKED and not in the ref: git holds no evidence either way. It may
        # be a file the experiment created, or a file that predated it and was
        # never tracked at all, which is the ordinary case for CLAUDE.local.md and
        # for anything the strip plan classified `policy` or `convention` and kept.
        # The ref cannot tell them apart, because a file that was never tracked is
        # absent from every commit. Deleting it would be unrecoverable, and this
        # script refuses to delete an untracked instruction file anywhere else for
        # the same reason, so it is named for the operator and left alone.
        echo "instruction-files.sh: left in place, untracked and not in $ref: $n" >&2
        echo "  git cannot tell an experiment-created file from one that predated it;" >&2
        echo "  delete it by hand if the experiment created it." >&2
      fi
    done
    exit 0
  fi
  # Named: every refusal is resolved BEFORE anything is checked out, and a name
  # this cannot honour is an error rather than a silent skip. A caller that asked
  # for a file by name and got exit 0 would record it as restored while it stayed
  # deleted, which is the ledger lying about what the experiment put back.
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
      # The reason is already resolved, so name WHICH of the three it is rather
      # than making the operator work out whether the file is there, a link is,
      # or a parent directory has become something else.
      refused+=("$n ($blocked; clear it first, or use --all to abandon the experiment)")
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
