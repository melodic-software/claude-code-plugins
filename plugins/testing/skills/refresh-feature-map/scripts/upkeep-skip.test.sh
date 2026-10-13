#!/usr/bin/env bash
# Tests for upkeep-skip.sh: the check decision against stored state and the
# commit-time window, record then check, argument refusals, and state keying.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP="$SCRIPT_DIR/upkeep-skip.sh"
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.name fixture
git config --global user.email fixture@example.invalid
git config --global init.defaultBranch main

# new_repo <dir> <committer date>: a repository with one commit at that date.
new_repo() {
  git init -q "$1"
  GIT_COMMITTER_DATE="$2" GIT_AUTHOR_DATE="$2" git -C "$1" commit -q --allow-empty -m init
}
# run <args...>: stdout in $out, stderr in $err, exit code in $rc.
run() {
  rc=0
  out="$(bash "$SKIP" "$@" 2>"$T/stderr")" || rc=$?
  err="$(cat "$T/stderr")"
}
# state_files <state dir>: how many state files the script has written.
state_files() { find "$1/feature-map-upkeep" -type f 2>/dev/null | wc -l | tr -d ' '; }

FRESH="$T/fresh"
OLD="$T/old"
new_repo "$FRESH" "$(date -R)"
new_repo "$OLD" "2001-02-03T04:05:06Z"
MAP=.claude/skills/feature-map

# --- check: no state on this host ----------------------------------------------
S="$T/state-none"
run check --repo "$OLD" --map "$MAP" --state-dir "$S" --since 24h
assert_eq "no state, HEAD older than 24h: skip" "0:skip no commit within 24h and no state on this host" "$rc:$out"

run check --repo "$OLD" --map "$MAP" --state-dir "$S"
assert_eq "--since defaults to 24h" "0:skip no commit within 24h and no state on this host" "$rc:$out"

run check --repo "$FRESH" --map "$MAP" --state-dir "$S" --since 24h
assert_eq "no state, fresh commit: run" "0:run" "$rc:${out%% *}"

run check --repo "$OLD" --map "$MAP" --state-dir "$S" --since 99999d
assert_eq "a window wider than HEAD's age: run" "0:run" "$rc:${out%% *}"

# --- check: stored state --------------------------------------------------------
S="$T/state-record"
run record --repo "$OLD" --map "$MAP" --state-dir "$S"
assert_eq "record exits 0" "0" "$rc"
run check --repo "$OLD" --map "$MAP" --state-dir "$S"
assert_eq "record then check: skip" "0:skip unchanged since the last clean pass" "$rc:$out"

key_file="$(find "$S/feature-map-upkeep" -type f)"
assert_eq "the state file holds HEAD" "$(git -C "$OLD" rev-parse HEAD)" "$(cat "$key_file")"

git -C "$OLD" commit -q --allow-empty -m second
run check --repo "$OLD" --map "$MAP" --state-dir "$S"
assert_eq "state SHA differs from HEAD: run" "0:run" "$rc:${out%% *}"

run check --repo "$OLD" --map other/map --state-dir "$S"
assert_eq "a second map does not read the first map's state" "0:run" "$rc:${out%% *}"

# --- keying ---------------------------------------------------------------------
S="$T/state-space"
run record --repo "$FRESH" --map "docs/my feature map" --state-dir "$S"
run check --repo "$FRESH" --map "docs/my feature map" --state-dir "$S"
assert_eq "map path with a space: record then check skips" "0:skip unchanged since the last clean pass" "$rc:$out"
assert_eq "map path with a space keys one state file" "1" "$(state_files "$S")"
name="$(basename "$(find "$S/feature-map-upkeep" -type f)")"
if [[ "$name" =~ ^[0-9a-f]{40,64}$ ]]; then pass "state file name is a hash"; else fail "state file name is a hash" "$name"; fi

S="$T/state-subst"
# shellcheck disable=SC2016 # the command substitution is literal map text
run record --repo "$FRESH" --map 'docs/$(touch '"$T"'/pwned)' --state-dir "$S"
assert_eq "a map path holding \$(...) is data: one state file" "0:1" "$rc:$(state_files "$S")"
if [[ ! -e "$T/pwned" ]]; then pass "no command ran from the map path"; else fail "no command ran from the map path" "pwned exists"; fi

# --- refusals: exit 2, nothing on stdout -----------------------------------------
S="$T/state-refuse"
run check --repo "$FRESH" --map ../x --state-dir "$S"
assert_eq "--map ../x exits 2 with empty stdout" "2:" "$rc:$out"
if [[ -n "$err" ]]; then pass "--map ../x names the problem on stderr"; else fail "--map ../x names the problem on stderr" "stderr empty"; fi
run check --repo "$FRESH" --map /abs --state-dir "$S"
assert_eq "--map /abs exits 2 with empty stdout" "2:" "$rc:$out"
run check --repo "$FRESH" --map "$MAP" --state-dir "$S" --since 0h
assert_eq "--since 0h exits 2 with empty stdout" "2:" "$rc:$out"
run check --repo "$FRESH" --map "$MAP" --state-dir "$S" --since 2w
assert_eq "--since 2w exits 2 with empty stdout" "2:" "$rc:$out"
run check --repo "$T/missing" --map "$MAP" --state-dir "$S"
assert_eq "a missing repository exits 2 with empty stdout" "2:" "$rc:$out"
run record --repo "$T/missing" --map "$MAP" --state-dir "$S"
assert_eq "record on a missing repository exits 2 with empty stdout" "2:" "$rc:$out"
: >"$T/not-a-dir"
run record --repo "$FRESH" --map "$MAP" --state-dir "$T/not-a-dir"
assert_eq "record into a state dir that is a file exits 2" "2:" "$rc:$out"
run frobnicate
assert_eq "an unknown subcommand exits 2" "2:" "$rc:$out"

# --- help -----------------------------------------------------------------------
run --help
assert_eq "--help exits 0" "0" "$rc"
if [[ "$out" == *check* && "$out" == *record* ]]; then pass "--help names both subcommands"; else fail "--help names both subcommands" "$out"; fi

if ((FAILED > 0)); then
  printf '%d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'all cases passed\n'
