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

# Every main-case invocation runs through this so an ambient CLAUDE_CONFIG_DIR from the
# caller's environment can never relocate the config root out of the isolated HOME:
# Case 4 resolves a dir and then WRITES to it, so a leaked config root would write into
# the live user config tree. GIT_DIR and CLAUDE_CODE_DISABLE_AUTO_MEMORY are dropped for
# the same reason. Case 6 sets CLAUDE_CONFIG_DIR deliberately and calls `env` directly.
iso_env() {
  env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_DISABLE_AUTO_MEMORY -u GIT_DIR HOME="$ISO_HOME" "$@"
}

# Fixture git repos must never inherit an outer hook chain's exported git env.
make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG
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
OUT=$(cd "$REPO" && iso_env bash "$SCRIPT") || rc=$?
assert_exit "repo report exits 0" 0 "$rc"
assert_contains "reports settings-scope section" "$OUT" "Settings scopes"
assert_contains "reports user settings PRESENT" "$OUT" "PRESENT"
assert_contains "reports default memory dir section" "$OUT" "Default auto-memory directory"
assert_contains "reports MEMORY.md absent when none written" "$OUT" "MEMORY.md: absent"
assert_contains "env var reported unset when not exported" "$OUT" "unset in OS environment"

# --- Case 3: env var set is reflected ---

OUT=$(cd "$REPO" && iso_env env CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 bash "$SCRIPT")
assert_contains "env var reported set when exported" "$OUT" "set in OS environment"

# --- Case 4: MEMORY.md at the resolved default is counted ---
# Derive the default dir from the resolver itself (no slug re-derivation in the test).

RESOLVER="$SCRIPT_DIR/../../audit/scripts/resolve-memory-dir.sh"
MEM_DIR=$(cd "$REPO" && iso_env bash "$RESOLVER" 2>/dev/null | tr -d '\r')

# Hard stop before any mkdir/write: a resolved dir outside the suite temp tree means
# isolation failed and the next two lines would write into a real config tree.
if [[ "$MEM_DIR" != "$TEST_TMPDIR"/* ]]; then
  printf 'ABORT: resolved memory dir escaped the test tmpdir: %s (expected under %s)\n' "$MEM_DIR" "$TEST_TMPDIR" >&2
  exit 1
fi
pass "resolved memory dir stays under the test tmpdir"

mkdir -p "$MEM_DIR"
printf '# MEMORY\n- one\n- two\n' >"$MEM_DIR/MEMORY.md"
printf '# topic\n' >"$MEM_DIR/debugging.md"

OUT=$(cd "$REPO" && iso_env bash "$SCRIPT")
assert_contains "MEMORY.md present is reported" "$OUT" "MEMORY.md: PRESENT"
assert_contains "topic file count reported" "$OUT" "topic files: 1"

# --- Case 4b: a topic filename with an embedded newline counts once ---
# Regression for the wc -l over-count on newline-delimited find output.

printf '# topic\n' >"$MEM_DIR/oops"$'\n'"weird.md"

OUT=$(cd "$REPO" && iso_env bash "$SCRIPT")
assert_contains "newline-named topic file counted once, not twice" "$OUT" "topic files: 2"

rm -f "$MEM_DIR/oops"$'\n'"weird.md"

# --- Case 5: outside a git repo, the cwd is the project key (docs: "Outside a git
# repo, the project root is used instead") — resolver and report both resolve, no bail-out ---

NONREPO="$TEST_TMPDIR/plain"
mkdir -p "$NONREPO"
rc=0
RES=$(cd "$NONREPO" && iso_env bash "$RESOLVER" | tr -d '\r') || rc=$?
assert_exit "resolver exits 0 outside a git repo" 0 "$rc"
assert_contains "resolver derives the memory dir under the config root" "$RES" "$ISO_HOME/.claude/projects/"
assert_contains "resolver slug is cwd-derived" "$RES" "plain"

rc=0
OUT=$(cd "$NONREPO" && iso_env bash "$SCRIPT") || rc=$?
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

# --- Case 7: an ambient CLAUDE_CONFIG_DIR never leaks into the isolated cases ---
# Simulates a developer (or hook chain) running this suite with CLAUDE_CONFIG_DIR
# already exported. The sentinel lives under the suite tmpdir so the check itself stays
# hermetic; on a real machine the same leak would land in the live config tree.

AMBIENT="$TEST_TMPDIR/ambient-config"
mkdir -p "$AMBIENT"
export CLAUDE_CONFIG_DIR="$AMBIENT"

LEAK_REPO="$TEST_TMPDIR/leak-repo"
make_repo "$LEAK_REPO"

LEAK_DIR=$(cd "$LEAK_REPO" && iso_env bash "$RESOLVER" 2>/dev/null | tr -d '\r')
assert_contains "ambient CLAUDE_CONFIG_DIR does not move the resolved memory dir" "$LEAK_DIR" "$ISO_HOME/.claude/projects/"

mkdir -p "$LEAK_DIR"
printf '# MEMORY\n' >"$LEAK_DIR/MEMORY.md"
OUT=$(cd "$LEAK_REPO" && iso_env bash "$SCRIPT")
assert_contains "report under ambient CLAUDE_CONFIG_DIR reads the isolated home" "$OUT" "$ISO_HOME/.claude/projects/"

LEAKED=$(find "$AMBIENT" -mindepth 1 -print 2>/dev/null)
if [[ -z "$LEAKED" ]]; then
  pass "nothing written to the ambient CLAUDE_CONFIG_DIR"
else
  fail "nothing written to the ambient CLAUDE_CONFIG_DIR" "created: $(printf '%s' "$LEAKED" | tr '\n' ' ')"
fi

unset CLAUDE_CONFIG_DIR

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
