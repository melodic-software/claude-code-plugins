#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/scope-report.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

iso_env() {
  env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_DISABLE_AUTO_MEMORY -u GIT_DIR HOME="$ISO_HOME" "$@"
}


rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"


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


OUT=$(cd "$REPO" && iso_env env CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 bash "$SCRIPT")
assert_contains "env var reported set when exported" "$OUT" "set in OS environment"


RESOLVER="$SCRIPT_DIR/../../audit/scripts/resolve-memory-dir.sh"
MEM_DIR=$(cd "$REPO" && iso_env bash "$RESOLVER" 2>/dev/null | tr -d '\r')

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


printf '# topic\n' >"$MEM_DIR/oops"$'\n'"weird.md"

OUT=$(cd "$REPO" && iso_env bash "$SCRIPT")
assert_contains "newline-named topic file counted once, not twice" "$OUT" "topic files: 2"

rm -f "$MEM_DIR/oops"$'\n'"weird.md"


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


CFG="$TEST_TMPDIR/cfg"
mkdir -p "$CFG"
printf '{}\n' >"$CFG/settings.json"
OUT=$(cd "$REPO" && env -u CLAUDE_CODE_DISABLE_AUTO_MEMORY HOME="$ISO_HOME" CLAUDE_CONFIG_DIR="$CFG" bash "$SCRIPT")
assert_contains "reports CLAUDE_CONFIG_DIR when set" "$OUT" "CLAUDE_CONFIG_DIR=$CFG"
assert_contains "user settings resolved under CLAUDE_CONFIG_DIR" "$OUT" "$CFG/settings.json"
assert_contains "memory dir resolved under CLAUDE_CONFIG_DIR" "$OUT" "$CFG/projects/"


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

report_and_exit
