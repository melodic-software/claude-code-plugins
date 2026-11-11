#!/usr/bin/env bash
# exec-bit-check.sh — deterministic exec-bit backstop for /source-control:commit.
#
# The skill documents its exec-bit procedure in prose; this script is the same
# rule as a command, so a composing session runs it instead of remembering it.
#
# Reports every path staged at a NEW index entry whose staged blob starts with
# `#!` while its staged mode is 100644. A new entry is not just status `A`: a
# copy destination (`C`) counts, as does a rename destination (`R`) whose source
# was 100755. The candidate-set comment below says why `R` and `C` differ.
#
# Scope limits, matching the skill's reasoning:
#   - Newly-added paths only; a full-repo sweep is not this check's job.
#   - Symlinks (120000) and gitlinks (160000) are skipped before the shebang
#     probe: git tracks a link's own mode, and `git update-index --chmod=+x`
#     fails on a 120000 entry.
#   - The shebang is read from the STAGED BLOB, never the worktree file: the
#     index is what a plain commit records.
#
# --fix sets the WORKTREE bit first, then the index entry. `git update-index
# --chmod=+x` alone is reverted by a later `git add` of the still-0644 worktree
# file, and the pathspec-limited (`--only`) commit records the worktree mode.
# The index write is still required: under `core.filemode=false` (the Windows
# default) git ignores worktree bits, so only update-index yields 100755.
#
# Usage:
#   exec-bit-check.sh [--list | --list0 | --probe | --fix] [--repo-dir <dir>] [--all] [-- <path>...]
#
# Modes (default --list):
#   --list    machine-readable: one offending path per line; empty = nothing to do
#   --list0   NUL-delimited — unambiguous for a pathname containing a newline
#   --probe   one human line for the skill's pre-computed context ("none" when clean)
#   --fix     apply the worktree-then-index fix; requires an explicit scope
#             ('-- <path>...' or --all), since it mutates index entries
#
# Every mode runs from the repository ROOT; caller pathspecs are re-anchored
# from the caller's cwd first.
#
# Exit codes:
#   0  ran successfully (--list/--list0/--probe always exit 0, findings or not;
#      --fix exits 0 when every offending path was fixed)
#   2  usage error
#   3  not a git repository, or git unavailable
#   4  --fix failed on at least one path
set -uo pipefail

PROG=${0##*/}

usage() {
  cat >&2 <<EOF
$PROG — deterministic exec-bit backstop for /source-control:commit.

Usage:
  $PROG [--list | --list0 | --probe | --fix] [--repo-dir <dir>] [--all] [-- <path>...]

Modes (default --list):
  --list             One offending path per line. Empty output = nothing to do.
                     A path containing a newline is shell-quoted (%q) to keep
                     one record per line; use --list0 for full unambiguity.
  --list0            NUL-delimited paths — the unambiguous machine-readable form.
  --probe            Single-line summary for pre-computed skill context.
  --fix              chmod +x the worktree file, then git update-index --chmod=+x.
                     Requires an explicit scope: '-- <path>...' or --all.

Options:
  --repo-dir <dir>   Operate on this repository instead of the current directory.
  --all              Allow --fix to sweep the whole staged set (explicit opt-in).
  -- <path>...       Limit to these pathspecs (default for --list/--probe: whole staged set).
  -h, --help         This help.

Reports paths staged at a NEW index entry whose staged blob starts with '#!' but
whose staged mode is 100644. A new entry is not just status 'A': a copy
destination counts, as does a rename destination whose source was 100755.
Symlinks and already-executable entries are skipped.

Scope note: a rename off a 100644 source is deliberately NOT reported, so for
that one case the answer depends on your diff.renames setting (reported as an
add when off, skipped as a rename when on). Decided trade — see
reference/exec-bit.md.
EOF
}

die() {
  echo "$PROG: $2" >&2
  exit "$1"
}

# Prints a path, %q-quoted when it contains a newline so one path stays one line.
print_path() {
  case "$1" in
  *$'\n'*) printf '%q' "$1" ;;
  *) printf '%s' "$1" ;;
  esac
}

mode=list
repo_dir=""
all=0
paths=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --list | --list0 | --probe | --fix) mode=${1#--} ;;
  --all) all=1 ;;
  --repo-dir)
    [[ "$#" -ge 2 ]] || die 2 "--repo-dir needs a value"
    repo_dir="$2"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    paths+=("$@")
    break
    ;;
  *)
    echo "$PROG: unknown argument '$1'" >&2
    usage
    exit 2
    ;;
  esac
  shift
done

command -v git >/dev/null 2>&1 || die 3 "git not found on PATH"

if [[ -n "$repo_dir" ]]; then
  cd -- "$repo_dir" 2>/dev/null || die 3 "cannot enter --repo-dir '$repo_dir'"
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die 3 "not inside a git work tree"

# `git diff --cached --raw` prints root-relative paths but a `git ls-files`
# pathspec is cwd-relative, so from a subdirectory every lookup would miss and
# the check would fail open. Re-anchor caller pathspecs with `--show-prefix`
# (absolute and `:`-magic pathspecs are left alone), then cd to the root.
repo_prefix="$(git rev-parse --show-prefix 2>/dev/null)"
repo_top="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -n "$repo_prefix" ]] && [[ "${#paths[@]}" -gt 0 ]]; then
  for i in "${!paths[@]}"; do
    case "${paths[i]}" in
    /* | :*) ;;
    *) paths[i]="$repo_prefix${paths[i]}" ;;
    esac
  done
fi
if [[ -n "$repo_top" ]]; then
  cd -- "$repo_top" 2>/dev/null || die 3 "cannot enter repository root '$repo_top'"
fi

# --fix mutates index entries, and the whole staged set can hold another
# session's work, so it refuses an unscoped run; --all is the explicit opt-in.
if [[ "$mode" == "fix" ]] && [[ "$all" -eq 0 ]] && [[ "${#paths[@]}" -eq 0 ]]; then
  echo "$PROG: --fix needs an explicit scope: pass '-- <path>...' for this commit's paths," >&2
  echo "       or --all to deliberately sweep the whole staged set." >&2
  exit 2
fi

# Candidate set: every path staged at a NEW index entry. Rename detection (on
# by default via `diff.renames`) and copy detection (`diff.renames=copies`) turn
# the same staged file from `A <path>` into `R<score> <old> <new>` or
# `C<score> <src> <dst>`, so keying on `A` alone would fail open on the
# consumer's diff config. `--raw -z` gives the source mode a rename needs; a
# pair record carries two path fields, and each pair arm must read both or the
# NUL stream desynchronizes. `R` and `C` do not share a predicate (#2118):
#
#   C -- the destination did not exist before, so it is newly added whatever
#        the source mode, and is judged like `A`.
#   R -- the destination is the same tracked file at a new path, reported only
#        when its source was 100755 (the move dropped the bit). Moving a
#        deliberately non-executable 100644 file must not flip its mode.
#        The cost: `git mv` of a 100644 shebang file is reported under
#        `diff.renames=false` (as `A`) but not under the default `true` (as
#        `R`). That disagreement is a decided trade (#2141), pinned by `repo19`
#        in exec-bit-check.test.sh; reopen #2141 before "repairing" this arm.
#
# A destination that kept 100755 is dropped by the 100644 filter below.
added=()
while IFS= read -r -d '' info; do
  info="${info#:}"
  src_mode="${info%% *}"
  status="${info##* }"
  case "$status" in
  R*)
    IFS= read -r -d '' _source || break
    IFS= read -r -d '' path || break
    [[ "$src_mode" == "100755" ]] && added+=("$path")
    ;;
  C*)
    IFS= read -r -d '' _source || break
    IFS= read -r -d '' path || break
    added+=("$path")
    ;;
  A)
    IFS= read -r -d '' path || break
    added+=("$path")
    ;;
  *)
    IFS= read -r -d '' _path || break
    ;;
  esac
done < <(git diff --cached --raw -z -- ${paths[@]+"${paths[@]}"} 2>/dev/null)

offenders=()
for path in ${added+"${added[@]}"}; do
  # `git ls-files --stage` prints: <mode> SP <sha> SP <stage> TAB <path>
  read -r entry_mode blob_sha _ < <(git ls-files --stage -- "$path" 2>/dev/null | head -n 1) || continue
  # Only regular files carry exec-bit semantics; symlinks and gitlinks drop here.
  [[ "$entry_mode" == "100644" ]] || continue
  [[ "$(git cat-file blob "$blob_sha" 2>/dev/null | head -c 2)" == "#!" ]] || continue
  offenders+=("$path")
done

count=${#offenders[@]}

case "$mode" in
list)
  # %q keeps a newline-bearing path on one line; --list0 is the unambiguous form.
  for path in ${offenders+"${offenders[@]}"}; do
    print_path "$path"
    printf '\n'
  done
  ;;
list0)
  # NUL is the one byte a git pathname cannot contain. Pair with `read -r -d ''`.
  for path in ${offenders+"${offenders[@]}"}; do
    printf '%s\0' "$path"
  done
  ;;
probe)
  if [[ "$count" -eq 0 ]]; then
    printf 'none\n'
  else
    # One line: it is injected into skill context, so %q any newline.
    printf '%s staged shebang file(s) still at mode 100644:' "$count"
    for path in "${offenders[@]}"; do
      printf ' '
      print_path "$path"
    done
    printf '\n'
  fi
  ;;
fix)
  if [[ "$count" -eq 0 ]]; then
    printf 'exec-bit-check: nothing to fix\n'
    exit 0
  fi
  failed=0
  for path in "${offenders[@]}"; do
    # Worktree bit first (see the header). -L is tested before -e because -e
    # follows a symlink: a path staged as a regular file but a symlink in the
    # worktree would otherwise make the link's target, possibly outside the
    # repository, executable. A path staged but absent from disk still gets
    # its index fix, with a warning.
    if [[ -L "$path" ]]; then
      echo "$PROG: refusing '$path': staged as a regular file but the worktree entry is a symlink" >&2
      failed=1
      continue
    elif [[ -e "$path" ]]; then
      chmod +x -- "$path" 2>/dev/null || {
        echo "$PROG: chmod +x failed for '$path'" >&2
        failed=1
        continue
      }
    else
      echo "$PROG: warning: '$path' is staged but absent from the worktree; fixing the index entry only" >&2
    fi
    git update-index --chmod=+x -- "$path" 2>/dev/null || {
      echo "$PROG: git update-index --chmod=+x failed for '$path'" >&2
      failed=1
      continue
    }
    printf 'exec-bit-check: fixed %s\n' "$path"
  done
  [[ "$failed" -eq 0 ]] || exit 4
  ;;
*) die 2 "internal error: unhandled mode '$mode'" ;;
esac
exit 0
