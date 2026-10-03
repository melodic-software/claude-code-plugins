#!/usr/bin/env bash
# Can git's untracked cache work on the volume this repository lives on?
#
# `git update-index --test-untracked-cache` checks that the file system updates
# a directory's mtime when an entry inside it changes, which the untracked cache
# relies on. It tests the directory it runs in and needs a repository there, so
# this runs it inside a fresh repository it creates under a scratch root, never
# in the caller's repository: the caller's index and working tree are not
# touched. The answer only says something about the caller's repository when
# the scratch dir is on the same volume, so a scratch root on another volume is
# refused before anything is created.
#
# Run it from inside the repository's working tree.
#
# Usage:
#   untracked-cache-probe.sh [--scratch-root <dir>]
#
#   --scratch-root <dir>   Where the scratch dir is created. Default: $TMPDIR,
#                          else /tmp. Never `/` or a drive root.
#
# Output, one key=value per line:
#   volume=<repository volume>  scratch_volume=<scratch root volume>
#   result=supported|unsupported|not-checked
#   reason_code=no-data|refused-by-guard and reason=<text>, when not-checked
#   detail=<git's own message>, when git ran
#
# Exit: 0 supported; 1 unsupported; 2 not checked (nothing measured).
set -uo pipefail

# A caller's git environment would point the scratch commands at a real
# repository; discover everything from the working directory instead.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

PREFIX="untracked-cache-probe."
ROOT="${TMPDIR:-/tmp}"
SCRATCH=""

usage() {
  cat <<'USAGE'
untracked-cache-probe.sh [--scratch-root <dir>]

  --scratch-root <dir>   Where the scratch dir is created. Default: $TMPDIR, else /tmp.

Run from inside the repository's working tree.
Exit: 0 supported; 1 unsupported; 2 not checked.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scratch-root)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 2
      }
      ROOT="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

not_checked() { # <reason_code> <reason>
  printf 'result=not-checked\nreason_code=%s\nreason=%s\n' "$1" "$2"
  exit 2
}

# Removes only the dir this run created, by its explicit path under the root.
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() {
  if [[ -n "$SCRATCH" && -n "$ROOT" && "$SCRATCH" == "$ROOT/$PREFIX"* && -d "$SCRATCH" ]]; then
    rm -rf -- "$SCRATCH"
  fi
}
trap cleanup EXIT

volume_of() { # <path>
  df -P "$1" 2>/dev/null | awk 'NR == 2 { print $1 }'
}

while [[ "$ROOT" == */ && "$ROOT" != / ]]; do ROOT="${ROOT%/}"; done
if [[ -z "$ROOT" || "$ROOT" == / || "$ROOT" =~ ^(/[A-Za-z]|[A-Za-z]:[/\\]?)$ ]]; then
  not_checked no-data "scratch root '$ROOT' is empty, / or a drive root; this check applies only when its scratch root (\$TMPDIR, else /tmp) is a directory below a root"
fi
[[ -d "$ROOT" ]] || not_checked no-data "scratch root '$ROOT' is not a directory; this check applies only when its scratch root (\$TMPDIR, else /tmp) is an existing directory"

command -v git >/dev/null 2>&1 || not_checked no-data "git is not on PATH; this check applies only where git runs"
REPO="$(git rev-parse --show-toplevel 2>/dev/null)" ||
  not_checked no-data "not inside a git working tree; run /performance:go-faster from inside the repository's working tree"

REPO_VOLUME="$(volume_of "$REPO")"
SCRATCH_VOLUME="$(volume_of "$ROOT")"
printf 'volume=%s\nscratch_volume=%s\n' "${REPO_VOLUME:-unknown}" "${SCRATCH_VOLUME:-unknown}"
[[ -n "$REPO_VOLUME" && -n "$SCRATCH_VOLUME" ]] ||
  not_checked no-data "could not read the volume of '$REPO' or '$ROOT' with df; this check applies only where df reports both volumes"
[[ "$REPO_VOLUME" == "$SCRATCH_VOLUME" ]] ||
  not_checked no-data "scratch root is on $SCRATCH_VOLUME, the repository on $REPO_VOLUME; this check applies only when its scratch root is on the repository's volume"

if ! SCRATCH="$(mktemp -d "$ROOT/${PREFIX}XXXXXX" 2>&1)"; then
  error="$SCRATCH"
  SCRATCH=""
  not_checked refused-by-guard "could not create a scratch dir under '$ROOT': $error; this check applies only where a scratch dir can be created there; git update-index --test-untracked-cache tests it separately, outside go-faster"
fi

if ! init_out="$(cd "$SCRATCH" && git init -q . 2>&1)"; then
  not_checked no-data "git init in the scratch dir failed: $init_out; this check applies only where git can create a repository in its scratch root"
fi
out="$(cd "$SCRATCH" && git update-index --test-untracked-cache 2>&1)"
rc=$?
printf 'detail=%s\n' "$(tr '\n' ' ' <<<"$out" | sed 's/ *$//')"
case "$rc" in
  0)
    printf 'result=supported\n'
    exit 0
    ;;
  1)
    printf 'result=unsupported\n'
    exit 1
    ;;
  *) not_checked no-data "git update-index --test-untracked-cache exited $rc, which is neither supported (0) nor unsupported (1); this check applies only where git answers one of those" ;;
esac
