#!/usr/bin/env bash
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect-ecosystems.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../lib/test-helpers.sh
source "$SCRIPT_DIR/../lib/test-helpers.sh"

mkfixture() {
  local name="$1"
  shift
  local dir="$TEST_TMPDIR/$name"
  mkdir -p "$dir"
  local m
  for m in "$@"; do
    : >"$dir/$m"
  done
  printf '%s\n' "$dir"
}

run_in() {
  local root="$1"
  shift
  (cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$root" bash "$DETECT" "$@" 2>/dev/null)
}

EMPTY="$(mkfixture empty)"
empty_exit=0
empty_out="$(run_in "$EMPTY")" || empty_exit=$?
assert_equals "empty project prints the empty answer" "none detected" "$empty_out"
assert_exit "empty project still exits 0" 0 "$empty_exit"

assert_not_contains "unmatched *.sln does not leak its pattern" "$empty_out" '*.sln'
assert_not_contains "unmatched *.slnx does not leak its pattern" "$empty_out" '*.slnx'

for marker in package.json pyproject.toml Cargo.toml go.mod; do
  one="$(mkfixture "solo-$marker" "$marker")"
  assert_equals "$marker alone is detected" "$marker" "$(run_in "$one")"
done

SLN_ONE="$(mkfixture sln-one MyApp.sln)"
assert_equals "a .sln is detected by glob" "MyApp.sln" "$(run_in "$SLN_ONE")"

SLNX_ONE="$(mkfixture slnx-one MyApp.slnx)"
assert_equals "a .slnx is detected by glob" "MyApp.slnx" "$(run_in "$SLNX_ONE")"

NEARMISS="$(mkfixture near-miss package.json.bak go.mod.orig mypyproject.toml Cargo.toml.lock notes.slnx.txt Makefile Gemfile requirements.txt)"
assert_equals "near-miss filenames detect nothing" "none detected" "$(run_in "$NEARMISS")"

MULTI="$(mkfixture multi package.json pyproject.toml Cargo.toml go.mod App.sln App.slnx)"
multi_out="$(run_in "$MULTI")"
multi_expected="$(printf '%s\n' App.slnx App.sln package.json pyproject.toml Cargo.toml go.mod)"
assert_equals "multi-ecosystem tree reports every marker in glob order" "$multi_expected" "$multi_out"
assert_not_contains "a populated tree never prints the empty answer" "$multi_out" "none detected"

PARTIAL="$(mkfixture partial App.slnx)"
partial_exit=0
partial_out="$(run_in "$PARTIAL")" || partial_exit=$?
assert_equals "a match on the FIRST glob with all later misses still reports" "App.slnx" "$partial_out"
assert_exit "trailing misses under set -e do not abort the script" 0 "$partial_exit"

MANY_SLN="$(mkfixture many-sln Zebra.sln Alpha.sln Middle.slnx)"
many_expected="$(printf '%s\n' Middle.slnx Alpha.sln Zebra.sln)"
assert_equals "every glob match is listed, sorted within its glob" "$many_expected" "$(run_in "$MANY_SLN")"

SPACED="$(mkfixture spaced)"
: >"$SPACED/My Big App.sln"
assert_equals "a space in a glob match survives as one entry" "My Big App.sln" "$(run_in "$SPACED")"

SPACED_MULTI="$(mkfixture spaced-multi go.mod)"
: >"$SPACED_MULTI/My Big App.sln"
spaced_multi_expected="$(printf '%s\n' 'My Big App.sln' go.mod)"
assert_equals "a space-bearing match does not split the rest of the list" \
  "$spaced_multi_expected" "$(run_in "$SPACED_MULTI")"

NESTED="$(mkfixture nested)"
mkdir -p "$NESTED/services/api"
: >"$NESTED/services/api/package.json"
assert_equals "a marker below the root is not detected (no recursion)" \
  "none detected" "$(run_in "$NESTED")"

DIRMARKER="$(mkfixture dir-marker)"
mkdir -p "$DIRMARKER/package.json"
assert_equals "a DIRECTORY named like a marker is detected (-e, not -f)" \
  "package.json" "$(run_in "$DIRMARKER")"

SYMLINKED="$(mkfixture symlinked)"
: >"$TEST_TMPDIR/real-package.json"
ln -s "$TEST_TMPDIR/real-package.json" "$SYMLINKED/package.json"
ln -s "$TEST_TMPDIR/no-such-target" "$SYMLINKED/go.mod"
sym_out="$(run_in "$SYMLINKED")"
assert_contains "a symlink to a live marker is detected" "$sym_out" "package.json"
assert_not_contains "a BROKEN symlink is not detected" "$sym_out" "go.mod"

WINS="$(mkfixture anchor-wins Cargo.toml)"
DECOY="$(mkfixture anchor-decoy package.json)"
anchor_out="$(cd "$DECOY" && CLAUDE_PROJECT_DIR="$WINS" bash "$DETECT" 2>/dev/null)"
assert_equals "CLAUDE_PROJECT_DIR outranks the cwd" "Cargo.toml" "$anchor_out"

blank_out="$(cd "$DECOY" && env CLAUDE_PROJECT_DIR= GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$DETECT" 2>/dev/null)"
assert_equals "an empty CLAUDE_PROJECT_DIR is treated as unset" "package.json" "$blank_out"

GITREPO="$TEST_TMPDIR/gitrepo"
mkdir -p "$GITREPO/deep/nested"
git -C "$GITREPO" init -q
: >"$GITREPO/Cargo.toml"
: >"$GITREPO/deep/nested/package.json"
git_out="$(cd "$GITREPO/deep/nested" && env -u CLAUDE_PROJECT_DIR bash "$DETECT" 2>/dev/null)"
assert_equals "without CLAUDE_PROJECT_DIR the git toplevel is the root" "Cargo.toml" "$git_out"
assert_not_contains "the cwd's own marker is not reported from a subdirectory" "$git_out" "package.json"

NOGIT="$(mkfixture nogit pyproject.toml)"
nogit_out="$(cd "$NOGIT" && env -u CLAUDE_PROJECT_DIR GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$DETECT" 2>/dev/null)"
assert_equals "outside a repo and with no override, the cwd is the root" "pyproject.toml" "$nogit_out"

GHOST="$(mkfixture ghost-cwd go.mod)"
ghost_exit=0
ghost_out="$(cd "$GHOST" && CLAUDE_PROJECT_DIR="$TEST_TMPDIR/does-not-exist" bash "$DETECT" 2>/dev/null)" || ghost_exit=$?
assert_equals "a nonexistent CLAUDE_PROJECT_DIR degrades to the cwd" "go.mod" "$ghost_out"
assert_exit "a nonexistent CLAUDE_PROJECT_DIR does not abort" 0 "$ghost_exit"

ghost_err="$(cd "$GHOST" && CLAUDE_PROJECT_DIR="$TEST_TMPDIR/does-not-exist" bash "$DETECT" 2>&1 >/dev/null)"
assert_equals "the failed cd prints nothing on stderr" "" "$ghost_err"

args_exit=0
args_out="$(run_in "$MULTI" --bogus extra)" || args_exit=$?
assert_equals "unread arguments do not change the answer" "$multi_expected" "$args_out"
assert_exit "unread arguments do not fail the script" 0 "$args_exit"

raw="$(run_in "$SLN_ONE" | od -c | tr -s ' ')"
assert_contains "output is newline-terminated" "$raw" 'M y A p p . s l n \n'

line_count="$(run_in "$MULTI" | wc -l | tr -d ' ')"
assert_equals "six markers print on exactly six lines" "6" "$line_count"

clean_err="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$MULTI" bash "$DETECT" 2>&1 >/dev/null)"
assert_equals "a normal run prints nothing on stderr" "" "$clean_err"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
echo "All detect-ecosystems.sh checks passed."
