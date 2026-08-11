#!/usr/bin/env bash
# Regression tests for discover-instruction-surfaces.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/discover-instruction-surfaces.sh"

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
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}

# Every case runs with CLAUDE_CONFIG_DIR pointed at a fixture, so the suite never
# reads — or reports on — the real `~/.claude` on the machine running it.
run_in() {
  # $1 = project dir, $2 = config dir, rest = script args
  local proj="$1" conf="$2"
  shift 2
  (cd "$proj" && CLAUDE_CONFIG_DIR="$conf" bash "$SCRIPT" "$@")
}

# --- fixtures ----------------------------------------------------------------

PROJ="$TEST_TMPDIR/proj"
CONF="$TEST_TMPDIR/conf"
mkdir -p "$PROJ/.claude/rules" "$CONF/rules"

printf '# project memory\n' >"$PROJ/CLAUDE.md"
printf '# personal overrides\n' >"$PROJ/CLAUDE.local.md"
printf '# a project rule\n' >"$PROJ/.claude/rules/project-rule.md"
printf '# nested, out of scope\n' >"$PROJ/.claude/rules/nested-not-a-rule.txt"
mkdir -p "$PROJ/sub"
printf '# subtree memory, out of scope\n' >"$PROJ/sub/CLAUDE.md"

printf '# user memory\n' >"$CONF/CLAUDE.md"
printf '# a user rule\n' >"$CONF/rules/user-rule.md"

# --- the regression this script exists for -----------------------------------
# The old inline `find . -maxdepth 1` discovery could not see either user-scope
# surface. These two assertions fail against that implementation and pass here.

OUT="$(run_in "$PROJ" "$CONF")"
RC=$?

assert_exit "exits 0" 0 "$RC"
assert_contains "user-scope CLAUDE.md is discovered" "$OUT" "$CONF/CLAUDE.md"
assert_contains "user-scope CLAUDE.md carries the user tag" "$OUT" "$(printf 'user\tclaude-md\t%s' "$CONF/CLAUDE.md")"
assert_contains "user-scope rule is discovered" "$OUT" "$CONF/rules/user-rule.md"
assert_contains "user-scope rule carries the user tag" "$OUT" "$(printf 'user\trule\t%s' "$CONF/rules/user-rule.md")"

# --- project scope still works, and is still tagged --------------------------

assert_contains "project CLAUDE.md is tagged project" "$OUT" "$(printf 'project\tclaude-md\tCLAUDE.md')"
assert_contains "CLAUDE.local.md gets its own kind" "$OUT" "$(printf 'project\tclaude-local-md\tCLAUDE.local.md')"
assert_contains "project rule is tagged project" "$OUT" "$(printf 'project\trule\t.claude/rules/project-rule.md')"

# --- scope tagging is what lets C9 skip personal files -----------------------
# C9 is project-scoped. The caller routes on the emitted scope, so a user-scope
# file must never be emitted with a project tag.

assert_not_contains "user CLAUDE.md is never tagged project" "$OUT" "$(printf 'project\tclaude-md\t%s' "$CONF/CLAUDE.md")"

# --- exclusions --------------------------------------------------------------

assert_not_contains "non-.md under rules is not discovered" "$OUT" "nested-not-a-rule.txt"
assert_not_contains "subtree CLAUDE.md is out of scope (depth 1 by design)" "$OUT" "sub/CLAUDE.md"

# --- --scope filter ----------------------------------------------------------

OUT_USER="$(run_in "$PROJ" "$CONF" --scope user)"
assert_contains "--scope user emits user surfaces" "$OUT_USER" "$CONF/CLAUDE.md"
assert_not_contains "--scope user suppresses project surfaces" "$OUT_USER" "$(printf 'project\t')"

OUT_PROJ="$(run_in "$PROJ" "$CONF" --scope project)"
assert_contains "--scope project emits project surfaces" "$OUT_PROJ" "$(printf 'project\tclaude-md\tCLAUDE.md')"
assert_not_contains "--scope project suppresses user surfaces" "$OUT_PROJ" "$(printf 'user\t')"

# --- absent surfaces are absent, not errors ----------------------------------

EMPTY_PROJ="$TEST_TMPDIR/empty-proj"
EMPTY_CONF="$TEST_TMPDIR/empty-conf"
mkdir -p "$EMPTY_PROJ" "$EMPTY_CONF"

OUT_EMPTY="$(run_in "$EMPTY_PROJ" "$EMPTY_CONF")"
RC_EMPTY=$?
assert_exit "exits 0 with nothing to report" 0 "$RC_EMPTY"
if [[ -z "$OUT_EMPTY" ]]; then
  pass "emits nothing when no surface exists"
else
  fail "emits nothing when no surface exists" "got: $OUT_EMPTY"
fi

# A config root that does not exist at all must not crash the run.
OUT_NOCONF="$(run_in "$PROJ" "$TEST_TMPDIR/does-not-exist")"
RC_NOCONF=$?
assert_exit "exits 0 when the config root is absent" 0 "$RC_NOCONF"
assert_contains "still discovers project surfaces without a config root" "$OUT_NOCONF" "$(printf 'project\tclaude-md\tCLAUDE.md')"
assert_not_contains "emits no user rows without a config root" "$OUT_NOCONF" "$(printf 'user\t')"

# --- Git Bash: a Windows-style config root with a drive letter ---------------
# HOME and CLAUDE_CONFIG_DIR are Windows paths on Git Bash. The resolver siblings
# carry explicit workarounds for this; discovery must not regress it.

if command -v cygpath >/dev/null 2>&1; then
  WIN_CONF="$(cygpath -w "$CONF" 2>/dev/null)"
  if [[ -n "$WIN_CONF" ]]; then
    OUT_WIN="$(run_in "$PROJ" "$WIN_CONF" --scope user)"
    assert_contains "discovers user CLAUDE.md under a Windows-form config root" "$OUT_WIN" "CLAUDE.md"
    assert_contains "tags it user under a Windows-form config root" "$OUT_WIN" "$(printf 'user\tclaude-md\t')"
  else
    pass "skipped: cygpath produced no Windows path"
  fi
else
  pass "skipped: cygpath unavailable (not Git Bash)"
fi

# --- unknown argument is advisory, not fatal ---------------------------------

run_in "$PROJ" "$CONF" --nonsense >/dev/null 2>&1
assert_exit "unknown argument still exits 0 (advisory contract)" 0 "$?"

printf '\n%d checks run, %d failed\n' "$CASE_NUM" "$FAILED"
if [[ "$FAILED" -gt 0 ]]; then
  printf 'RESULT: FAIL\n'
  exit 1
fi
printf 'RESULT: PASS — all %d checks passed.\n' "$CASE_NUM"
exit 0
