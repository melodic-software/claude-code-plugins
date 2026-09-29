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
SKIPPED=0
pass() { printf 'PASS: %s\n' "$1"; }
# A case whose subject this host cannot build is neither a pass nor a failure:
# it prints its own visible line and never routes through pass().
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
}
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
printf 'l\n' >"$REPO/loose.md"

# Drive-root slash preservation is a string contract, not a host contract: the
# suite does not need Windows.
assert_eq "ordinary trailing slash is stripped" "$(normalize_dir_target "docs/")" "docs"
assert_eq "nested trailing slash is stripped" "$(normalize_dir_target "C:/tmp/")" "C:/tmp"
assert_eq "unix root keeps its slash" "$(normalize_dir_target "/")" "/"
assert_eq "windows drive root keeps its slash" "$(normalize_dir_target "C:/")" "C:/"
assert_eq "lowercase windows drive root keeps its slash" "$(normalize_dir_target "d:/")" "d:/"
assert_eq "windows drive-root backslash is unchanged" "$(normalize_dir_target "C:\\")" "C:\\"
assert_eq "already-drive-relative spelling is left alone" "$(normalize_dir_target "C:")" "C:"
assert_eq "ordinary path without a slash is unchanged" "$(normalize_dir_target "docs")" "docs"

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
assert_eq "untracked markdown is not in the bare list" "$(printf '%s\n' "${bare[@]}" | grep -c 'loose.md' || true)" "0"

# The bare list is REPO_ROOT-prefixed, so it cannot depend on the CWD: a wrong
# prefix leaves paths the existence filter drops.
declare -a bare_away=()
away_text="$(cd "$TEST_TMPDIR" && resolve_targets bare_away "$REPO" "" 0 0 0 && join_lines bare_away)"
assert_eq "a bare invocation from outside the checkout lists the same paths" "$away_text" "$bare_text"

# A directory inside a checkout that holds only untracked markdown expands to
# nothing; the walk is reserved for a directory outside one.
mkdir -p "$REPO/untrackedonly"
printf 'u\n' >"$REPO/untrackedonly/loose.md"
declare -a untracked_only=()
resolve_targets untracked_only "$REPO" "" 0 0 0 "$REPO/untrackedonly" 2>"$TEST_TMPDIR/untracked-only.err"
assert_eq "a directory with no tracked markdown expands to nothing" "$(join_lines untracked_only)" ""
assert_eq "a directory with no tracked markdown does not name a walk" "$(cat "$TEST_TMPDIR/untracked-only.err")" ""

declare -a win_bare=() win_dir=()
resolve_targets win_bare "$REPO" "" 1 1 0
resolve_targets win_dir "$REPO" "" 1 1 0 "$REPO"
assert_eq "offset/limit windows the bare list and a directory the same way" "$(join_lines win_dir)" "$(join_lines win_bare)"
assert_eq "the window is the second sorted path" "$(join_lines win_bare)" "$REPO/nested/notes-é.md"

# A failing ls-files must say so, and git's own stderr must survive: swallowed,
# it is an empty list indistinguishable from a checkout with no tracked
# markdown. The stub fails only ls-files, so the branch under test is the
# listing and not work-tree detection.
BADLS_BIN="$TEST_TMPDIR/bin-badls"
mkdir -p "$BADLS_BIN"
REAL_GIT="$(command -v git)"
cat >"$BADLS_BIN/git" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == "ls-files" ]]; then
    echo "fatal: stubbed ls-files failure" >&2
    exit 128
  fi
done
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$BADLS_BIN/git"
declare -a badls_bare=() badls_dir=()
PATH="$BADLS_BIN:$PATH" resolve_targets badls_bare "$REPO" "" 0 0 0 2>"$TEST_TMPDIR/badls-bare.err"
assert_eq "a failing listing on a bare invocation names the status and keeps git's stderr" \
  "$(cat "$TEST_TMPDIR/badls-bare.err")" \
  "fatal: stubbed ls-files failure
detect.sh: git ls-files failed in $REPO (exit 128); nothing was scanned"
assert_eq "a failing listing on a bare invocation is an empty list" "$(join_lines badls_bare)" ""
PATH="$BADLS_BIN:$PATH" resolve_targets badls_dir "$REPO" "" 0 0 0 "$REPO/nested" 2>"$TEST_TMPDIR/badls-dir.err"
assert_eq "a failing listing on a directory names the status and keeps git's stderr" \
  "$(cat "$TEST_TMPDIR/badls-dir.err")" \
  "fatal: stubbed ls-files failure
detect.sh: git ls-files failed under $REPO/nested (exit 128); that directory expanded to nothing"
assert_eq "a failing listing on a directory is an empty list" "$(join_lines badls_dir)" ""

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

# Outside a checkout a bare invocation has nothing tracked to list, which is a
# reportable state rather than a clean audit of an empty set.
declare -a outside_bare=()
resolve_targets outside_bare "$OUTSIDE" "" 0 0 0 2>"$TEST_TMPDIR/outside-bare.err"
assert_eq "a bare invocation outside a checkout says so" "$(cat "$TEST_TMPDIR/outside-bare.err")" \
  "detect.sh: git could not confirm a work tree at $OUTSIDE; a bare invocation has no tracked markdown to list (pass paths explicitly)"
assert_eq "a bare invocation outside a checkout is an empty list" "$(join_lines outside_bare)" ""

# silent-skip-ok: routed to skip(), a visible SKIP line counted apart from PASS
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
  for name in \
    "bare invocation without git reports it and lists nothing" \
    "bare invocation without git is an empty list" \
    "a directory without git reports the walk" \
    "a directory without git lists the walked markdown"; do
    skip "$name" 'ln -s copies here, so a git-less PATH cannot be built out of the real binaries'
  done
fi

if [[ "$FAILED" -ne 0 ]]; then
  printf 'Result: %s failed, %s host skip(s)\n' "$FAILED" "$SKIPPED" >&2
  exit 1
fi
printf 'Result: all passed, %s host skip(s)\n' "$SKIPPED"
