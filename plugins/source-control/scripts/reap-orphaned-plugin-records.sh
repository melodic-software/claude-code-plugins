#!/usr/bin/env bash
# Exit codes:
#   0  every path was reaped and its directory removed
#   1  a path failed; the path and step are named, later paths are not touched
#   2  usage error (no path given, or an unknown flag)

set -uo pipefail

PROG=${0##*/}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/reap-project-plugin-records.sh"

usage() {
  cat <<'EOF'
reap-orphaned-plugin-records.sh: reap project-scope plugin records for paths a person confirmed as dead worktrees.

Usage:
  reap-orphaned-plugin-records.sh <path> [<path> ...]

  <path>  a confirmed dead worktree path; it must not exist

Exit codes:
  0  every path was reaped and its directory removed
  1  a path failed; the path and step are named, later paths are not touched
  2  usage error (no path given, or an unknown flag)
EOF
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

windows_shell=false
case "$(uname -s 2>/dev/null)" in
MINGW* | MSYS* | CYGWIN*) windows_shell=true ;;
*) ;;
esac

strip_trailing_separators() {
  local p="$1"
  if [[ "$windows_shell" == "true" ]]; then
    while [[ "$p" == */ || "$p" == *\\ ]] && [[ ${#p} -gt 1 ]]; do p="${p%?}"; done
  else
    while [[ "$p" == */ && ${#p} -gt 1 ]]; do p="${p%?}"; done
  fi
  printf '%s' "$p"
}

total=${#paths[@]}
index=0
start_dir="$PWD"

fail_path() {
  printf 'error: [%s/%s] %s: failed at %s — %s\n' "$index" "$total" "$1" "$2" "$3"
  printf 'error: stopped; %s later path(s) were not touched.\n' "$((total - index))"
}

indent() { sed 's/^/    /'; }

one_line() { printf '%s' "$1" | tr '\r\n' '  '; }

run_helper() {
  local step="$1" out rc
  shift
  out="$(bash "$HELPER" --worktree-path "$path" "$@" 2>&1)"
  rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf '%s\n' "$out" | indent
    fail_path "$path" "$step" "helper exited $rc; the directory is left in place"
    exit 1
  fi
  printf '  %s: ok\n' "$step"
  printf '%s\n' "$out" | indent
}

for raw in "${paths[@]}"; do
  index=$((index + 1))
  path="$(strip_trailing_separators "$raw")"
  if [[ -z "$path" ]]; then
    fail_path "$raw" "validate" "empty path"
    exit 1
  fi
  case "$path" in
  /* | [A-Za-z]:[/\\]*) ;;
  *) path="$start_dir/$path" ;;
  esac
  printf '[%s/%s] %s\n' "$index" "$total" "$path"

  if ! mkerr="$(mkdir -- "$path" 2>&1)"; then
    detail="$(one_line "$mkerr")"
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

  if ! cd -- "$path"; then
    fail_path "$path" "cd" "could not enter the directory it just created"
    exit 1
  fi

  run_helper "reap --dry-run" --dry-run
  run_helper "reap"

  if ! rm -rf -- "$path/.claude"; then
    fail_path "$path" "rm .claude" "could not remove $path/.claude; the directory is left in place"
    exit 1
  fi

  if ! cd -- "$(dirname -- "$path")"; then
    fail_path "$path" "cd .." "could not leave the directory; it is left in place"
    exit 1
  fi
  if ! rmerr="$(rmdir -- "$path" 2>&1)"; then
    fail_path "$path" "rmdir" "$(one_line "$rmerr")"
    exit 1
  fi
  printf '  rmdir: removed\n'
  printf 'ok: [%s/%s] %s reaped\n' "$index" "$total" "$path"
done

printf 'ok: %s path(s) reaped.\n' "$total"
exit 0
