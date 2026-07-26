#!/usr/bin/env bash
# exec-bit-check.sh — deterministic exec-bit backstop for /source-control:commit.
#
# The skill documents an ordered exec-bit procedure in prose. Prose is the first
# thing a long session stops executing: the motivating failure was four new
# shebang scripts shipped at mode 100644 with only the consuming repo's CI
# catching it. This script is the deterministic tier under that prose — the same
# rule, executable, so a composing session runs a command instead of remembering
# a paragraph.
#
# WHAT IT REPORTS: every path staged as a NEW file (`A`) whose staged blob begins
# with a `#!` shebang while its staged mode is 100644 (non-executable).
#
# Deliberate scope limits, each matching the skill's documented reasoning:
#   - Newly-added paths only. An already-tracked file that was already
#     executable needs no action, and a full-repo sweep is not this check's job.
#   - Symlinks (mode 120000) are skipped before the shebang probe. Git tracks
#     the link's own mode, not its target's; `git update-index --chmod=+x` fails
#     outright on a 120000 entry, and following the link could reach a file
#     outside the repo entirely.
#   - The shebang is read from the STAGED BLOB (`git cat-file blob <sha>`), never
#     from the worktree file. The index is what a plain commit records, and
#     reading the blob also avoids every quoting hazard of a worktree path.
#
# --fix sets the WORKTREE bit first, then the index entry, because that is the
# only order that survives a later `git add`: `git update-index --chmod=+x`
# overrides the index alone, so a re-add re-reads the still-0644 worktree mode
# and silently reverts the index. It also matters for the pathspec-limited
# (`--only`) commit form, which records the WORKTREE mode rather than the index.
#
# WHY THE INDEX WRITE IS NOT OPTIONAL: under `core.filemode=false` — the default
# on Windows/NTFS, and confirmed on the machine this was developed on — git
# ignores worktree permission bits entirely and stages every file 100644. On
# such a repo `chmod +x` alone NEVER reaches the index, so `git update-index
# --chmod=+x` is the only thing that can produce a 100755 entry. Both writes are
# therefore always attempted: the chmod for the file's own sake and for
# filemode=true repos, the update-index for what actually gets committed.
#
# Usage:
#   exec-bit-check.sh [--list | --probe | --fix] [--repo-dir <dir>] [-- <path>...]
#
# Modes (default --list):
#   --list    machine-readable: one offending path per line; empty = nothing to do
#   --probe   one human line for the skill's pre-computed context ("none" when clean)
#   --fix     apply the worktree-then-index fix to every path --list would report
#
# Exit codes:
#   0  ran successfully (--list/--probe always exit 0, findings or not;
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
  $PROG [--list | --probe | --fix] [--repo-dir <dir>] [-- <path>...]

Modes (default --list):
  --list             One offending path per line. Empty output = nothing to do.
  --probe            Single-line summary for pre-computed skill context.
  --fix              chmod +x the worktree file, then git update-index --chmod=+x.

Options:
  --repo-dir <dir>   Operate on this repository instead of the current directory.
  -- <path>...       Limit to these pathspecs (default: the whole staged set).
  -h, --help         This help.

Reports staged NEW files (status A) whose staged blob starts with '#!' but whose
staged mode is 100644. Symlinks and already-executable entries are skipped.
EOF
}

mode=list
repo_dir=""
paths=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
  --list) mode=list ;;
  --probe) mode=probe ;;
  --fix) mode=fix ;;
  --repo-dir)
    [[ "$#" -ge 2 ]] || {
      echo "$PROG: --repo-dir needs a value" >&2
      exit 2
    }
    repo_dir="$2"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    while [[ "$#" -gt 0 ]]; do
      paths+=("$1")
      shift
    done
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

command -v git >/dev/null 2>&1 || {
  echo "$PROG: git not found on PATH" >&2
  exit 3
}

if [[ -n "$repo_dir" ]]; then
  cd -- "$repo_dir" 2>/dev/null || {
    echo "$PROG: cannot enter --repo-dir '$repo_dir'" >&2
    exit 3
  }
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "$PROG: not inside a git work tree" >&2
  exit 3
}

# Collect paths staged as NEW files (status A). -z keeps paths with spaces,
# quotes, or newlines intact; --name-status emits status and path as separate
# NUL-terminated fields, and a rename emits THREE fields (Rxxx, old, new), so
# each status is consumed with its own explicit field reads rather than a
# positional split.
added=()
while IFS= read -r -d '' status; do
  case "$status" in
  R*)
    IFS= read -r -d '' _old || break
    IFS= read -r -d '' _new || break
    ;;
  C*)
    IFS= read -r -d '' _src || break
    IFS= read -r -d '' _dst || break
    ;;
  A)
    IFS= read -r -d '' path || break
    added+=("$path")
    ;;
  *)
    IFS= read -r -d '' _path || break
    ;;
  esac
done < <(git diff --cached --name-status -z -- ${paths[@]+"${paths[@]}"} 2>/dev/null)

offenders=()
for path in ${added+"${added[@]}"}; do
  # `git ls-files --stage` prints: <mode> SP <sha> SP <stage> TAB <path>
  stage_line="$(git ls-files --stage -- "$path" 2>/dev/null | head -n 1)"
  [[ -n "$stage_line" ]] || continue

  entry_mode="${stage_line%% *}"
  # Only regular files carry exec-bit semantics. 120000 is a symlink; 160000 a
  # gitlink (submodule). Both are skipped before the blob is ever read.
  [[ "$entry_mode" == "100644" ]] || continue

  rest="${stage_line#* }"
  blob_sha="${rest%% *}"
  [[ -n "$blob_sha" ]] || continue

  first_two="$(git cat-file blob "$blob_sha" 2>/dev/null | head -c 2)"
  [[ "$first_two" == "#!" ]] || continue

  offenders+=("$path")
done

count=${#offenders[@]}

case "$mode" in
list)
  for path in ${offenders+"${offenders[@]}"}; do
    printf '%s\n' "$path"
  done
  exit 0
  ;;
probe)
  if [[ "$count" -eq 0 ]]; then
    printf 'none\n'
  else
    printf '%s staged shebang file(s) still at mode 100644:' "$count"
    for path in "${offenders[@]}"; do
      printf ' %s' "$path"
    done
    printf '\n'
  fi
  exit 0
  ;;
fix)
  if [[ "$count" -eq 0 ]]; then
    printf 'exec-bit-check: nothing to fix\n'
    exit 0
  fi
  failed=0
  for path in "${offenders[@]}"; do
    # Worktree bit FIRST — see the header. A path staged as A can still be
    # absent from disk (added, then removed without staging the removal); the
    # index fix is still correct and still worth applying, so that case warns
    # rather than aborting.
    if [[ -e "$path" ]]; then
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
  exit 0
  ;;
*)
  echo "$PROG: internal error: unhandled mode '$mode'" >&2
  exit 2
  ;;
esac
