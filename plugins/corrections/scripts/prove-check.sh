#!/usr/bin/env bash
# Prove a proposed check fails on the old code and passes on the current code.
#
#   prove-check.sh --check '<command>' --old <ref> [--new <ref>]
#
# Runs <command> (through `bash -c`) in a temporary worktree at <old>, which
# must exit non-zero, and in a temporary worktree at <new> (default HEAD),
# which must exit 0. Run it from inside the repository the refs belong to.
# Prints both exit codes on stdout; the check's own output goes to stderr.
# Both worktrees are removed on every exit path.
#
# Exit: 0 the proof holds (fails at old, passes at new), 1 the proof fails,
# 2 usage or environment error.
set -uo pipefail
# A caller's git environment (a hook sets these) would point every git call
# below at the caller's repository instead of the one in the working directory.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG

usage() {
  printf 'usage: %s --check <command> --old <ref> [--new <ref>]\n' "${0##*/}" >&2
}

check=""
old=""
new="HEAD"
have_check=0
have_old=0
while (($# > 0)); do
  case "$1" in
  --check | --old | --new)
    if (($# < 2)) || [[ -z "$2" ]]; then
      printf '%s: %s needs a value\n' "${0##*/}" "$1" >&2
      usage
      exit 2
    fi
    case "$1" in
    --check) check="$2" have_check=1 ;;
    --old) old="$2" have_old=1 ;;
    --new) new="$2" ;;
    *) ;;
    esac
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf '%s: unknown argument: %s\n' "${0##*/}" "$1" >&2
    usage
    exit 2
    ;;
  esac
done
if ((have_check == 0 || have_old == 0)); then
  printf '%s: --check and --old are required\n' "${0##*/}" >&2
  usage
  exit 2
fi

if ! command -v git >/dev/null 2>&1; then
  printf '%s: git is required\n' "${0##*/}" >&2
  exit 2
fi
if ! repo="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  printf '%s: not inside a git repository\n' "${0##*/}" >&2
  exit 2
fi

old_sha="$(git -C "$repo" rev-parse --verify --quiet "$old^{commit}")" || {
  printf '%s: --old is not a commit: %s\n' "${0##*/}" "$old" >&2
  exit 2
}
new_sha="$(git -C "$repo" rev-parse --verify --quiet "$new^{commit}")" || {
  printf '%s: --new is not a commit: %s\n' "${0##*/}" "$new" >&2
  exit 2
}

work="$(mktemp -d)" || exit 2
# shellcheck disable=SC2329  # invoked through the EXIT trap below
cleanup() {
  local d
  for d in "$work/old" "$work/new"; do
    [[ -e "$d" ]] && git -C "$repo" worktree remove --force "$d" >/dev/null 2>&1
  done
  rm -rf "$work"
  git -C "$repo" worktree prune >/dev/null 2>&1
}
trap cleanup EXIT

for side in old new; do
  sha="$old_sha"
  [[ "$side" == new ]] && sha="$new_sha"
  if ! git -C "$repo" worktree add --detach "$work/$side" "$sha" >/dev/null 2>&1; then
    printf '%s: could not create a worktree at %s\n' "${0##*/}" "$sha" >&2
    exit 2
  fi
done

# run_check <dir>: run the command with the caller's git environment cleared,
# so a check that calls git sees the worktree and not the caller's repository.
run_check() {
  (
    cd "$1" || exit 2
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CONFIG \
      bash -c "$check" >&2
  )
}

run_check "$work/old"
old_rc=$?
run_check "$work/new"
new_rc=$?

printf 'old (%s): exit %d (expected non-zero)\n' "$old" "$old_rc"
printf 'new (%s): exit %d (expected 0)\n' "$new" "$new_rc"

rc=0
if ((old_rc == 0)); then
  printf '%s: the check passes on the old ref, so it does not catch the mistake\n' "${0##*/}" >&2
  rc=1
elif ((old_rc == 126 || old_rc == 127)); then
  printf '%s: exit %d on the old ref usually means the command did not run, not that the check failed\n' "${0##*/}" "$old_rc" >&2
fi
if ((new_rc != 0)); then
  printf '%s: the check fails on the new ref\n' "${0##*/}" >&2
  rc=1
fi
exit "$rc"
