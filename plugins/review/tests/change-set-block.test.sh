#!/usr/bin/env bash
# Offline test of the agents' change-set block: extracts the fenced block from
# agents/code-reviewer.md step 2, asserts the other reviewer agents carry the
# same text, and runs it in scratch repos. It proves the block's output only,
# not any model's decline-to-grade behavior.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_CONFIG

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS="$PLUGIN_DIR/agents"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_contains() {
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "expected to contain: $3" ;; esac
}
assert_lacks() {
  case "$2" in *"$3"*) fail "$1" "must not contain: $3" ;; *) pass "$1" ;; esac
}

# The first fenced bash block after the "Identify the change set" step.
extract_block() {
  awk '
    /Identify the change set/ { seen = 1 }
    seen && /^[[:space:]]*```bash[[:space:]]*$/ { inb = 1; next }
    inb && /^[[:space:]]*```[[:space:]]*$/ { exit }
    inb { sub(/^   /, ""); print }
  ' "$1"
}

BLOCK="$(extract_block "$AGENTS/code-reviewer.md")"
if [[ "$BLOCK" == *UNRESOLVED-BASE* ]]; then
  pass "change-set block extracted from code-reviewer.md"
else
  fail "change-set block extracted from code-reviewer.md" "no UNRESOLVED-BASE line in the extracted block"
fi

for agent in security-reviewer architecture-guardian; do
  if [[ "$(extract_block "$AGENTS/$agent.md")" == "$BLOCK" ]]; then
    pass "$agent carries the same change-set block"
  else
    fail "$agent carries the same change-set block" "block differs from code-reviewer.md"
  fi
done

printf '%s\n' "$BLOCK" >"$TMP/block.sh"

# gh fails on PATH so no PR base resolves and no network is used.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 1\n' >"$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

init_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.email "test@example.com"
  git -C "$1" config user.name "test"
  git -C "$1" config core.autocrlf false
}
commit_file() { # <repo> <file> <content> <message>
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit -q -m "$4"
}
run_block() { (cd "$1" && PATH="$TMP/bin:$PATH" bash "$TMP/block.sh" 2>&1); }

# Fixture: a bare "remote" with main and a feature branch two commits ahead.
BARE="$TMP/remote.git"
SEED="$TMP/seed"
init_repo "$SEED"
commit_file "$SEED" base.txt "base-line" "base"
git -C "$SEED" checkout -q -b feature
commit_file "$SEED" one.txt "feature-line-one" "feature one"
commit_file "$SEED" two.txt "feature-line-two" "feature two"
git clone -q --bare "$SEED" "$BARE"
git -C "$BARE" symbolic-ref HEAD refs/heads/main

# (a) no origin remote, clean tree, two commits on a feature branch
A="$TMP/a"
init_repo "$A"
commit_file "$A" base.txt "base-line" "base"
git -C "$A" checkout -q -b feature
commit_file "$A" one.txt "feature-line-one" "feature one"
commit_file "$A" two.txt "feature-line-two" "feature two"
OUT="$(run_block "$A")"
assert_contains "(a) no remote: reports UNRESOLVED-BASE" "$OUT" "UNRESOLVED-BASE"
assert_lacks "(a) no remote: no committed change is emitted as a diff" "$OUT" "feature-line"

# (b) depth-1 single-branch clone, the actions/checkout shape
B="$TMP/b"
git clone -q --depth 1 -b feature "file://$BARE" "$B"
OUT="$(run_block "$B")"
assert_contains "(b) shallow clone: reports UNRESOLVED-BASE" "$OUT" "UNRESOLVED-BASE"
assert_contains "(b) shallow clone: names the clone as shallow" "$OUT" "shallow: true"
assert_lacks "(b) shallow clone: no committed change is emitted as a diff" "$OUT" "feature-line"

# (c) positive: full clone with origin/main present emits the real diff
C="$TMP/c"
git clone -q -b feature "file://$BARE" "$C"
OUT="$(run_block "$C")"
assert_lacks "(c) origin/main present: no UNRESOLVED-BASE" "$OUT" "UNRESOLVED-BASE"
assert_contains "(c) origin/main present: diff has the first commit" "$OUT" "+feature-line-one"
assert_contains "(c) origin/main present: diff has the second commit" "$OUT" "+feature-line-two"

if [[ "$FAILED" -ne 0 ]]; then
  printf '%d case(s) failed\n' "$FAILED" >&2
  exit 1
fi
printf 'all cases passed\n'
