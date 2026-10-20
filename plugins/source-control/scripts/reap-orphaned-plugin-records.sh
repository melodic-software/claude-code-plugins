#!/usr/bin/env bash
# reap-orphaned-plugin-records.sh — run the worktree audit Step 2b remedy over
# the paths a person individually confirmed as dead worktrees.
#
# WHY THIS EXISTS. `claude plugin uninstall <id> -s project` has no path flag, so
# the only route to a project-scope record whose path no longer exists is to
# recreate the path, reap from inside it, and remove it again. This script does
# that for each confirmed dead path.
#
# PER PATH, IN ORDER, STOPPING AT THE FIRST FAILURE:
#   1. mkdir <path>             plain `mkdir`, never `-p`: it FAILS when the path
#                               exists, so a live directory is never reaped. A
#                               path whose parent is missing fails here too.
#   2. cd <path>
#   3. reap --dry-run           reap-project-plugin-records.sh --worktree-path
#   4. reap                     the helper's own cwd-only check still applies
#   5. rm -rf <path>/.claude    the settings file the uninstall CLI rewrites
#   6. cd .. && rmdir <path>    removes only the directory step 1 created
# A failure in steps 3-4 leaves the directory in place, because deleting it
# would put surviving records back out of reach.
#
# The caller must confirm each path is a dead worktree first (not another
# repository's live worktree, not an unmounted share, not a detached volume).
# This script does no classification of its own.
#
# Usage:
#   reap-orphaned-plugin-records.sh <path> [<path> ...]
#
# Output: `[n/total] <path>: <step> ...` lines, the helper's own lines indented
# under the step that ran them, and a closing `ok:` or `error:` line.
# Exit codes:
#   0  every path was reaped and its directory removed
#   1  a path failed; the path and step are named, later paths are not touched
#   2  usage error (no path given, or an unknown flag)

set -uo pipefail

PROG=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/reap-project-plugin-records.sh"

# Print the header block with its comment markers stripped; derived, not a
# hardcoded line range, so it cannot truncate as the header grows.
usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
    "${BASH_SOURCE[0]}"
}

paths=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    paths+=("$@")
    break
    ;;
  -*)
    printf '%s: unknown argument: %s\n' "$PROG" "$1" >&2
    exit 2
    ;;
  *)
    paths+=("$1")
    shift
    ;;
  esac
done

if [[ ${#paths[@]} -eq 0 ]]; then
  printf '%s: at least one path is required\n' "$PROG" >&2
  exit 2
fi

# strip_trailing_separators <path> — every trailing separator the platform
# recognizes. Off Windows a trailing backslash is a legal filename byte and must
# survive, or the chain would act on a different sibling path.
strip_trailing_separators() {
  local p="$1"
  case "$(uname -s 2>/dev/null)" in
  MINGW* | MSYS* | CYGWIN*)
    while [[ "$p" == */ || "$p" == *\\ ]] && [[ ${#p} -gt 1 ]]; do p="${p%?}"; done
    ;;
  *)
    while [[ "$p" == */ && ${#p} -gt 1 ]]; do p="${p%?}"; done
    ;;
  esac
  printf '%s' "$p"
}

total=${#paths[@]}
index=0
start_dir="$PWD"

# fail_path <path> <step> <detail> — name the path and step, then stop.
fail_path() {
  printf 'error: [%s/%s] %s: failed at %s — %s\n' "$index" "$total" "$1" "$2" "$3"
  printf 'error: stopped; %s later path(s) were not touched.\n' "$((total - index))"
}

# indent — prefix the helper's output so it reads as part of its step.
indent() { sed 's/^/    /'; }

for raw in "${paths[@]}"; do
  index=$((index + 1))
  path="$(strip_trailing_separators "$raw")"
  if [[ -z "$path" ]]; then
    fail_path "$raw" "validate" "empty path"
    exit 1
  fi
  # The chain changes directory, so a relative path is anchored to where the
  # script started; the helper compares --worktree-path against its own cwd.
  case "$path" in
  /* | [A-Za-z]:[/\\]*) ;;
  *) path="$start_dir/$path" ;;
  esac
  printf '[%s/%s] %s\n' "$index" "$total" "$path"

  # Plain mkdir, never `mkdir -p`: it fails on an existing directory.
  if ! mkerr="$(mkdir -- "$path" 2>&1)"; then
    detail="$(printf '%s' "$mkerr" | tr '\r\n' '  ')"
    if [[ ! -e "$path" && ! -L "$path" ]]; then
      parent="$(dirname -- "$path")"
      if [[ ! -d "$parent" ]]; then
        detail="$detail (parent directory $parent is missing; see #7461)"
      fi
    else
      detail="$detail (the path exists, so it is not reaped)"
    fi
    fail_path "$path" "mkdir" "$detail"
    exit 1
  fi
  printf '  mkdir: created\n'

  # From here on the directory exists and was created by this script. Every
  # later failure leaves it in place.
  if ! cd -- "$path"; then
    fail_path "$path" "cd" "could not enter the directory it just created"
    exit 1
  fi

  out="$(bash "$HELPER" --worktree-path "$path" --dry-run 2>&1)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf '%s\n' "$out" | indent
    fail_path "$path" "reap --dry-run" "helper exited $rc; the directory is left in place"
    exit 1
  fi
  printf '  reap --dry-run: ok\n'
  printf '%s\n' "$out" | indent

  out="$(bash "$HELPER" --worktree-path "$path" 2>&1)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf '%s\n' "$out" | indent
    fail_path "$path" "reap" "helper exited $rc; the directory is left in place"
    exit 1
  fi
  printf '  reap: ok\n'
  printf '%s\n' "$out" | indent

  if ! rm -rf -- "$path/.claude"; then
    fail_path "$path" "rm .claude" "could not remove $path/.claude; the directory is left in place"
    exit 1
  fi

  if ! cd -- "$(dirname -- "$path")"; then
    fail_path "$path" "cd .." "could not leave the directory; it is left in place"
    exit 1
  fi
  if ! rmerr="$(rmdir -- "$path" 2>&1)"; then
    fail_path "$path" "rmdir" "$(printf '%s' "$rmerr" | tr '\r\n' '  ')"
    exit 1
  fi
  printf '  rmdir: removed\n'
  printf 'ok: [%s/%s] %s reaped\n' "$index" "$total" "$path"
done

printf 'ok: %s path(s) reaped.\n' "$total"
exit 0
