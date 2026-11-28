#!/usr/bin/env bash
# Exit: 0 the proof holds (fails at old and passes at new, or fails on
#         with-mistake and passes on without-mistake), 1 the proof fails,
# 2 usage or environment error.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG

usage() {
  printf 'usage: %s --check <command> (--old <ref> | --plant <patch>) [--new <ref>]\n' "${0##*/}" >&2
  printf '       %s --check <command> --fixture <dir>\n' "${0##*/}" >&2
  printf '  --fixture: <dir>/with-mistake/ must fail the check and <dir>/without-mistake/ pass it;\n' >&2
  printf '  the check runs in a copy of each, with its stdin file on standard input when present\n' >&2
}
die() {
  printf '%s: %s\n' "${0##*/}" "$1" >&2
  exit 2
}
usage_error() {
  printf '%s: %s\n' "${0##*/}" "$1" >&2
  usage
  exit 2
}

check=""
old=""
plant=""
fixture=""
new="HEAD"
have_check=0
have_old=0
have_plant=0
have_fixture=0
have_new=0
while (($# > 0)); do
  case "$1" in
  --check | --old | --plant | --fixture | --new)
    if (($# < 2)) || [[ -z "$2" ]]; then
      usage_error "$1 needs a value"
    fi
    case "$1" in
    --check) check="$2" have_check=1 ;;
    --old) old="$2" have_old=1 ;;
    --plant) plant="$2" have_plant=1 ;;
    --fixture) fixture="$2" have_fixture=1 ;;
    --new) new="$2" have_new=1 ;;
    *) ;;
    esac
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage_error "unknown argument: $1"
    ;;
  esac
done
if ((have_check == 0 || have_old + have_plant + have_fixture != 1)); then
  usage_error "--check and exactly one of --old, --plant or --fixture are required"
fi

prove_fixture() {
  local side rc=0 with_rc without_rc
  [[ -d "$fixture" ]] || die "--fixture is not a directory: $fixture"
  fixture="$(cd "$fixture" && pwd)" || die "could not read the fixture directory: $fixture"
  for side in with-mistake without-mistake; do
    [[ -d "$fixture/$side" ]] || die "the fixture has no $side directory: $fixture/$side"
  done
  work="$(mktemp -d)" || exit 2
  trap 'rm -rf "$work"' EXIT

  run_input() {
    local input="$fixture/$1"
    cp -R "$input" "$work/$1" || die "could not copy the fixture input: $input"
    (
      cd "$work/$1" || exit 2
      if [[ -f stdin ]]; then
        bash -c "$check" <stdin >&2
      else
        bash -c "$check" </dev/null >&2
      fi
    )
  }
  run_input with-mistake
  with_rc=$?
  run_input without-mistake
  without_rc=$?

  printf 'with-mistake (%s): exit %d (expected non-zero)\n' "$fixture/with-mistake" "$with_rc"
  printf 'without-mistake (%s): exit %d (expected 0)\n' "$fixture/without-mistake" "$without_rc"
  if ((with_rc == 0)); then
    printf '%s: the check passes on %s, so it does not catch the mistake (expected non-zero, observed 0)\n' \
      "${0##*/}" "$fixture/with-mistake" >&2
    rc=1
  elif ((with_rc == 126 || with_rc == 127)); then
    printf '%s: exit %d on %s usually means the command did not run, not that the check failed\n' \
      "${0##*/}" "$with_rc" "$fixture/with-mistake" >&2
  fi
  if ((without_rc != 0)); then
    printf '%s: the check fails on %s (expected 0, observed %d)\n' \
      "${0##*/}" "$fixture/without-mistake" "$without_rc" >&2
    rc=1
  fi
  exit "$rc"
}
if ((have_fixture == 1)); then
  ((have_new == 0)) || usage_error "--new does not apply to --fixture"
  prove_fixture
fi
if ((have_plant == 1)); then
  [[ -f "$plant" && -r "$plant" ]] || die "--plant is not a readable file: $plant"
  plant="$(cd "$(dirname "$plant")" && pwd)/$(basename "$plant")"
fi

command -v git >/dev/null 2>&1 || die "git is required"
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"

new_sha="$(git -C "$repo" rev-parse --verify --quiet "$new^{commit}")" || die "--new is not a commit: $new"
if ((have_old == 1)); then
  old_sha="$(git -C "$repo" rev-parse --verify --quiet "$old^{commit}")" || die "--old is not a commit: $old"
fi

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

if ((have_plant == 1)); then
  git -C "$repo" worktree add --detach "$work/old" "$new_sha" >/dev/null 2>&1 ||
    die "could not create a worktree at $new_sha"
  git -C "$work/old" apply --index --recount "$plant" >&2 ||
    die "the plant does not apply to $new: $plant"
  git -C "$work/old" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
    -c user.name=prove-check -c user.email=prove-check@invalid \
    commit -q --no-verify -m "prove-check plant" >/dev/null 2>&1 ||
    die "the plant changes nothing: $plant"
  old_sha="$(git -C "$work/old" rev-parse HEAD)" || die "could not read the plant commit"
  old="planted $old_sha"
else
  git -C "$repo" worktree add --detach "$work/old" "$old_sha" >/dev/null 2>&1 ||
    die "could not create a worktree at $old_sha"
fi
git -C "$repo" worktree add --detach "$work/new" "$new_sha" >/dev/null 2>&1 ||
  die "could not create a worktree at $new_sha"

run_check() {
  (
    cd "$1" || exit 2
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
