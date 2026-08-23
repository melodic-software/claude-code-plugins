# shellcheck shell=bash
# Shared base-ref validation and changed-file resolution. Sourced, never executed.
#
# Seven checkers under scripts/ each answered the same two questions for
# themselves -- "is this base ref real?" and "what changed against it?" -- and
# the copies drifted. The divergence was live when this file was extracted
# (#2914, finding 1): check-shell-portability.sh and check-skill-portability.sh
# carried the NUL-delimited (-z) read that keeps a C-quoted pathname intact,
# while check-changed-skills.sh and check-docs-only.sh still read
# `git diff --name-only` line-wise and silently dropped such a path. One
# definition here means the next fix to the walk lands in every gate at once.
#
# A caller sources this file and uses:
#
#   changed_files::verify_base <ref>
#       0 when <ref> resolves to a commit, 1 otherwise. Prints nothing: the
#       callers do NOT share an error policy (the portability gates exit 2, and
#       check-docs-only.sh deliberately falls back to "run the full suite"), so
#       the diagnostic and the exit stay at the call site.
#
#   changed_files::resolve_base <out-var>
#       Assigns the first of origin/main, origin/master, main, master that
#       resolves to a commit. Returns 1 and leaves <out-var> untouched when none
#       do. This is the FALLBACK ladder only: a caller with an explicitly
#       supplied ref (scripts/affected-tests.sh's --base) verifies that ref
#       itself, because a ref the user typed and got wrong has to be an error
#       naming it rather than a silent fall-through to origin/main.
#
#   changed_files::into <out-array> <base> [--include-deleted] [-- <pathspec>...]
#       Fills <out-array> with the paths changed against <base>, sorted and
#       de-duplicated.
#
# WHY `into` TAKES A NAMEREF INSTEAD OF PRINTING. Two reasons, both load-bearing:
#
#   1. The paths are read NUL-delimited, and a NUL cannot survive a command
#      substitution -- bash truncates the value there. An array assigned in the
#      caller's own scope is the only shape that carries such a path back intact.
#   2. Running in the CURRENT shell propagates failure. The pattern being
#      replaced was `while read; do ...; done < <(git diff ... | sort -z -u)`,
#      where a git failure is invisible: the process substitution's status is
#      discarded and the loop simply sees no paths, so a blown-up diff and a
#      genuinely empty change set are indistinguishable and both report "nothing
#      in scope, exit 0" -- the fail-open these gates exist to refuse. Here the
#      git failure is the function's own non-zero return, which the caller can
#      (and does) treat as fatal.
#
# `--include-deleted` IS A PER-CALLER DECISION, NOT A DEFAULT TO COPY. Omitting
# it passes `--diff-filter=d`, dropping paths the commit deleted; that is right
# for a scanner, which needs a file on disk to open, and wrong for a classifier,
# which must still see that a non-docs file was deleted. Making it an explicit
# argument is the point of the extraction: the two behaviours stay different on
# purpose and each call site says which it wants.

# changed_files::verify_base <ref>
changed_files::verify_base() {
  git rev-parse --verify --quiet "${1}^{commit}" >/dev/null 2>&1
}

# changed_files::resolve_base <out-var>
changed_files::resolve_base() {
  local -n _cf_base_out="$1"
  local candidate
  for candidate in origin/main origin/master main master; do
    if changed_files::verify_base "$candidate"; then
      _cf_base_out="$candidate"
      return 0
    fi
  done
  return 1
}

# changed_files::into <out-array> <base> [--include-deleted] [-- <pathspec>...]
changed_files::into() {
  local -n _cf_paths_out="$1"
  local base="$2"
  shift 2

  local -a filter=(--diff-filter=d)
  while (($# > 0)); do
    case "$1" in
    --include-deleted)
      filter=()
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      printf 'changed-files: unknown option %s\n' "$1" >&2
      return 2
      ;;
    esac
  done

  _cf_paths_out=()

  # Staged through a temp file rather than read straight off a pipe, and this is
  # the mechanism the docstring's point 2 rests on. `while read; done < <(git
  # ... | sort)` discards both commands' exit status, so the only way to notice
  # a failed diff is to give git a destination whose status is checked in this
  # shell -- and then feed the loop from a PLAIN redirect, which (unlike a
  # process substitution) also keeps the array assignment out of a subshell.
  local tmp
  tmp="$(mktemp)" || {
    printf 'changed-files: mktemp failed\n' >&2
    return 1
  }

  # NUL-delimited (-z) so a pathname Git would C-quote -- non-ASCII bytes under
  # the default core.quotePath, or a literal quote or backslash -- arrives
  # verbatim. A quoted `"plugins/..."` misses every suffix and prefix test the
  # callers apply and is silently dropped, the exact silent exclusion the gates
  # forbid.
  if ! git diff --name-only ${filter[@]+"${filter[@]}"} -z "$base" -- "$@" >"$tmp"; then
    rm -f "$tmp"
    printf 'changed-files: git diff against %s failed; refusing to report an empty change set\n' "$base" >&2
    return 1
  fi
  if ! sort -z -u "$tmp" -o "$tmp"; then
    rm -f "$tmp"
    printf 'changed-files: sorting the change set for %s failed\n' "$base" >&2
    return 1
  fi

  local path
  while IFS= read -r -d '' path; do
    _cf_paths_out+=("$path")
  done <"$tmp"
  rm -f "$tmp"
  return 0
}
