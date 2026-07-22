#!/usr/bin/env bash
# Regression tests for scope-report.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/scope-report.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

# Fixture git repos must never inherit an outer hook chain's exported git env.
make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "test@example.com" && git config user.name "test" && git commit -q --allow-empty -m init)
}

# --- Case 1: --help exits 0 with usage ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: inside a git repo, isolated HOME with no memory written ---
# Isolate HOME so the report reads the fixture, never the real user settings/memory.

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
ISO_HOME="$TEST_TMPDIR/home"
mkdir -p "$ISO_HOME/.claude"
printf '{}\n' >"$ISO_HOME/.claude/settings.json"

rc=0
OUT=$(cd "$REPO" && env -u CLAUDE_CODE_DISABLE_AUTO_MEMORY HOME="$ISO_HOME" bash "$SCRIPT") || rc=$?
assert_exit "repo report exits 0" 0 "$rc"
assert_contains "reports settings-scope section" "$OUT" "Settings scopes"
assert_contains "reports user settings PRESENT" "$OUT" "PRESENT"
assert_contains "reports default memory dir section" "$OUT" "Default auto-memory directory"
assert_contains "reports MEMORY.md absent when none written" "$OUT" "MEMORY.md: absent"
assert_contains "env var reported unset when not exported" "$OUT" "unset in OS environment"

# --- Case 3: env var set is reflected ---

OUT=$(cd "$REPO" && CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 HOME="$ISO_HOME" bash "$SCRIPT")
assert_contains "env var reported set when exported" "$OUT" "set in OS environment"

# --- Case 4: MEMORY.md at the resolved default is counted ---
# Derive the default dir from the resolver itself (no slug re-derivation in the test).

RESOLVER="$SCRIPT_DIR/../../audit/scripts/resolve-memory-dir.sh"
MEM_DIR=$(cd "$REPO" && HOME="$ISO_HOME" bash "$RESOLVER" 2>/dev/null | tr -d '\r')
mkdir -p "$MEM_DIR"
printf '# MEMORY\n- one\n- two\n' >"$MEM_DIR/MEMORY.md"
printf '# topic\n' >"$MEM_DIR/debugging.md"

OUT=$(cd "$REPO" && HOME="$ISO_HOME" bash "$SCRIPT")
assert_contains "MEMORY.md present is reported" "$OUT" "MEMORY.md: PRESENT"
assert_contains "topic file count reported" "$OUT" "topic files: 1"

# --- Case 5: outside a git repo, the cwd is the project key (docs: "Outside a git
# repo, the project root is used instead") — resolver and report both resolve, no bail-out ---

NONREPO="$TEST_TMPDIR/plain"
mkdir -p "$NONREPO"
rc=0
RES=$(cd "$NONREPO" && env -u GIT_DIR HOME="$ISO_HOME" bash "$RESOLVER" | tr -d '\r') || rc=$?
assert_exit "resolver exits 0 outside a git repo" 0 "$rc"
assert_contains "resolver derives the memory dir under the config root" "$RES" "$ISO_HOME/.claude/projects/"
assert_contains "resolver slug is cwd-derived" "$RES" "plain"

rc=0
OUT=$(cd "$NONREPO" && env -u GIT_DIR HOME="$ISO_HOME" bash "$SCRIPT") || rc=$?
assert_exit "non-git dir exits 0" 0 "$rc"
assert_contains "non-git dir notes the cwd is the project key" "$OUT" "current directory"
assert_contains "non-git dir reports the resolved memory dir" "$OUT" "$ISO_HOME/.claude/projects/"
assert_contains "non-git dir reports MEMORY.md state" "$OUT" "MEMORY.md: absent"

# --- Case 6: CLAUDE_CONFIG_DIR relocates the config root (user scope + memory tree) ---

CFG="$TEST_TMPDIR/cfg"
mkdir -p "$CFG"
printf '{}\n' >"$CFG/settings.json"
OUT=$(cd "$REPO" && env -u CLAUDE_CODE_DISABLE_AUTO_MEMORY HOME="$ISO_HOME" CLAUDE_CONFIG_DIR="$CFG" bash "$SCRIPT")
assert_contains "reports CLAUDE_CONFIG_DIR when set" "$OUT" "CLAUDE_CONFIG_DIR=$CFG"
assert_contains "user settings resolved under CLAUDE_CONFIG_DIR" "$OUT" "$CFG/settings.json"
assert_contains "memory dir resolved under CLAUDE_CONFIG_DIR" "$OUT" "$CFG/projects/"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
