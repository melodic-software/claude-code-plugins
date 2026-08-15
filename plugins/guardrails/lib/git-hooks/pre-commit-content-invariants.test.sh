#!/usr/bin/env bash
# Contract test for lib/git-hooks/pre-commit-content-invariants.sh (guardrails).
#
# Black-box: installs the hook template + pattern libs into an isolated repo's
# .git/hooks, stages fixtures, invokes the hook directly, asserts on exit code
# (1 = rejected, 0 = accepted).

set -uo pipefail

HOOK_DIR_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HOOK_DIR_SRC/../.." && pwd)"
TEMPLATE="$PLUGIN_ROOT/lib/git-hooks/pre-commit-content-invariants.sh"
LIB_SRC="$PLUGIN_ROOT/lib"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

PASS=0
FAIL=0
ok() {
  PASS=$((PASS + 1))
  printf 'ok: %s\n' "$1"
}
bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1" >&2
}
assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then ok "$label (exit $actual)"; else bad "$label: expected exit $expected, got $actual"; fi
}

# Isolated repo with the hook + content-lib installed.
newrepo() {
  local d hooks
  d="$(mktemp -d "$TEST_TMPDIR/repo.XXXXXX")"
  git -C "$d" init -q -b main
  git -C "$d" config user.email "test@example.com"
  git -C "$d" config user.name "Test"
  hooks="$(git -C "$d" rev-parse --absolute-git-dir)/hooks"
  mkdir -p "$hooks/guardrails-content-lib"
  cp "$TEMPLATE" "$hooks/pre-commit"
  cp -a "$LIB_SRC/secret-detection" "$hooks/guardrails-content-lib/"
  cp -a "$LIB_SRC/path-detection" "$hooks/guardrails-content-lib/"
  chmod +x "$hooks/pre-commit"
  # Seed an empty commit so later stages have a HEAD.
  git -C "$d" commit -q --allow-empty -m "seed"
  printf '%s' "$d"
}

# stage_file <repo> <relpath> <content>
stage_file() {
  local repo="$1" rel="$2" content="$3" dir
  dir="$(dirname "$repo/$rel")"
  mkdir -p "$dir"
  printf '%s' "$content" >"$repo/$rel"
  git -C "$repo" add -- "$rel"
}

# run_hook <label> <repo> <expected-exit>
run_hook() {
  local label="$1" repo="$2" expected="$3" rc hooks
  hooks="$(git -C "$repo" rev-parse --absolute-git-dir)/hooks"
  (cd "$repo" && bash "$hooks/pre-commit") >/dev/null 2>&1
  rc=$?
  assert_exit "$label" "$expected" "$rc"
}

# Runtime-assembled machine paths (no contiguous path literal in source).
SL='/'
FAKE_GHP='ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
FAKE_LINUX="${SL}home${SL}alice${SL}projects${SL}demo${SL}src${SL}main.sh"

r="$(newrepo)"
stage_file "$r" "notes.txt" "hello with no secrets or paths"
run_hook "clean staged text accepted" "$r" 0

r="$(newrepo)"
stage_file "$r" "leak.txt" "token=${FAKE_GHP}"
run_hook "staged GitHub PAT rejected" "$r" 1

r="$(newrepo)"
stage_file "$r" "paths.md" "see ${FAKE_LINUX} for details"
run_hook "staged Linux home path rejected" "$r" 1

r="$(newrepo)"
stage_file "$r" "tests/fixtures/sample.env" "token=${FAKE_GHP}"
run_hook "tests/fixtures secret allowlisted" "$r" 0

r="$(newrepo)"
stage_file "$r" "tests/fixtures/path.txt" "see ${FAKE_LINUX} for details"
run_hook "tests/fixtures path still scanned" "$r" 1

r="$(newrepo)"
stage_file "$r" ".env.example" "OPENAI_KEY=sk-AAAAAAAAAAAAAAAAAAAA"
run_hook ".env.example allowlisted" "$r" 0

r="$(newrepo)"
stage_file "$r" "clean.txt" "ok"
# Unstaged working-tree-only secret must NOT be seen.
printf 'token=%s\n' "$FAKE_GHP" >"$r/dirty-only.txt"
run_hook "unstaged secret not scanned" "$r" 0

r="$(newrepo)"
hooks="$(git -C "$r" rev-parse --absolute-git-dir)/hooks"
printf '#!/bin/bash\nexit 1\n' >"$hooks/pre-commit.pre-guardrails"
chmod +x "$hooks/pre-commit.pre-guardrails"
stage_file "$r" "ok.txt" "clean"
run_hook "chained prior hook rejection is final" "$r" 1

r="$(newrepo)"
hooks="$(git -C "$r" rev-parse --absolute-git-dir)/hooks"
printf '#!/bin/bash\nexit 0\n' >"$hooks/pre-commit.pre-guardrails"
chmod +x "$hooks/pre-commit.pre-guardrails"
stage_file "$r" "leak2.txt" "token=${FAKE_GHP}"
run_hook "chained prior hook pass still scans content" "$r" 1

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
((FAIL == 0))
