#!/usr/bin/env bash
# One suite for every target-resolution entry form. Assertion helpers are local.
# shellcheck disable=SC2154,SC2034
set -uo pipefail
export LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/resolve-targets.sh
source "$SCRIPT_DIR/lib/resolve-targets.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}

join_lines() {
  local -n arr="$1"
  if [[ ${#arr[@]} -eq 0 ]]; then
    printf ''
    return 0
  fi
  printf '%s\n' "${arr[@]}"
}

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO/nested"
printf 'a\n' >"$REPO/a.md"
printf 'e\n' >"$REPO/nested/notes-é.md"
git -C "$REPO" init -q
git -C "$REPO" add a.md "nested/notes-é.md"
git -C "$REPO" -c user.email=t@example.com -c user.name=t commit -q -m init

declare -a bare=() explicit=() directory=() from_file=()
resolve_targets bare "$REPO" "" 0 0 0
resolve_targets explicit "$REPO" "" 0 0 0 "$REPO/a.md" "$REPO/nested/notes-é.md"
resolve_targets directory "$REPO" "" 0 0 0 "$REPO"
pf="$TEST_TMPDIR/paths"
printf '%s\n' "$REPO/a.md" $'key\t'"$REPO/nested/notes-é.md" >"$pf"
resolve_targets from_file "$REPO" "$pf" 0 0 0

bare_text="$(join_lines bare)"
assert_eq "explicit files match the bare list" "$(join_lines explicit)" "$bare_text"
assert_eq "a directory matches the bare list" "$(join_lines directory)" "$bare_text"
assert_eq "a paths file matches the bare list" "$(join_lines from_file)" "$bare_text"
assert_eq "the non-ASCII tracked name is in the bare list" "$(printf '%s\n' "${bare[@]}" | grep -c 'notes-é.md' || true)" "1"

declare -a win_bare=() win_dir=()
resolve_targets win_bare "$REPO" "" 1 1 0
resolve_targets win_dir "$REPO" "" 1 1 0 "$REPO"
assert_eq "offset/limit windows the bare list and a directory the same way" "$(join_lines win_dir)" "$(join_lines win_bare)"
assert_eq "the window is the second sorted path" "$(join_lines win_bare)" "$REPO/nested/notes-é.md"

OUTSIDE="$TEST_TMPDIR/outside"
mkdir -p "$OUTSIDE/sub"
printf 'x\n' >"$OUTSIDE/one.md"
printf 'y\n' >"$OUTSIDE/sub/two.md"
declare -a outside=()
resolve_targets outside "$REPO" "" 0 0 0 "$OUTSIDE" 2>"$TEST_TMPDIR/outside.err"
err="$(cat "$TEST_TMPDIR/outside.err")"
assert_eq "a directory outside a checkout names the filesystem walk" "$err" \
  "detect.sh: git could not confirm a work tree under $OUTSIDE (exit 128); expanding via filesystem walk"
mapfile -t expected_walk < <(find "$OUTSIDE" -name '*.md' -type f | sort -u)
assert_eq "a directory outside a checkout lists the walked markdown" "$(join_lines outside)" "$(join_lines expected_walk)"

if ln -s /dev/null "$TEST_TMPDIR/link-probe" 2>/dev/null && [[ -L "$TEST_TMPDIR/link-probe" ]]; then
  NOGIT="$TEST_TMPDIR/nogit"
  mkdir -p "$NOGIT"
  for cmd in find sort awk; do
    ln -s "$(command -v "$cmd")" "$NOGIT/$cmd"
  done
  declare -a absent_bare=() absent_dir=()
  PATH="$NOGIT" resolve_targets absent_bare "$REPO" "" 0 0 0 2>"$TEST_TMPDIR/absent-bare.err"
  err="$(cat "$TEST_TMPDIR/absent-bare.err")"
  assert_eq "bare invocation without git reports it and lists nothing" "$err" \
    "detect.sh: git is not on PATH; a bare invocation has no tracked markdown to list (pass paths explicitly)"
  assert_eq "bare invocation without git is an empty list" "$(join_lines absent_bare)" ""
  PATH="$NOGIT" resolve_targets absent_dir "$REPO" "" 0 0 0 "$OUTSIDE" 2>"$TEST_TMPDIR/absent-dir.err"
  err="$(cat "$TEST_TMPDIR/absent-dir.err")"
  assert_eq "a directory without git reports the walk" "$err" \
    "detect.sh: git is not on PATH; directory $OUTSIDE expanded via filesystem walk (tracked-files-only is not achievable)"
  assert_eq "a directory without git lists the walked markdown" "$(join_lines absent_dir)" "$(join_lines expected_walk)"
else
  printf 'SKIP: this host copies symlinks, so a git-less PATH cannot be built\n'
fi

if [[ "$FAILED" -ne 0 ]]; then
  printf 'Result: %s failed\n' "$FAILED" >&2
  exit 1
fi
printf 'Result: all passed\n'
