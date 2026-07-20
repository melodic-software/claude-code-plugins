#!/usr/bin/env bash
# Black-box contract test for goal-condition-length.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir. Fixture
# limits are small, arbitrary numbers — never the documented /goal limit — so
# the tool and its test stay grep-clean of any baked-in doc value.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/goal-condition-length.sh"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Assert an exit code from running the SUT with stdin `input` and given args.
# Usage: expect_exit <label> <want_code> <input> <args...>
expect_exit() {
  local label="$1" want="$2" input="$3"
  shift 3
  local got
  printf '%s' "$input" | bash "$SUT" "$@" >/dev/null 2>&1
  got=$?
  if [[ "$got" -eq "$want" ]]; then pass "$label"; else fail "$label (want exit $want, got $got)"; fi
}

# 1. --help exits 0.
if bash "$SUT" --help >/dev/null 2>&1; then pass "--help exits 0"; else fail "--help should exit 0"; fi

# 2. Under limit -> exit 0.
expect_exit "under limit -> 0" 0 "hello" --limit 50

# 3. Exactly at limit -> exit 0 (inclusive boundary: 'up to N characters').
expect_exit "at limit (boundary) -> 0" 0 "abcde" --limit 5

# 4. Over limit -> exit 1.
expect_exit "over limit -> 1" 1 "abcdef" --limit 5

# 5. Missing --limit -> exit 2.
expect_exit "missing --limit -> 2" 2 "hello"

# 6. Non-integer limit -> exit 2.
expect_exit "non-integer limit -> 2" 2 "hello" --limit abc

# 7. Zero limit -> exit 2.
expect_exit "zero limit -> 2" 2 "hello" --limit 0

# 8. Empty condition -> exit 2.
expect_exit "empty condition -> 2" 2 "" --limit 50

# 9. Trailing newline is stripped (5 chars, not 6) -> at-limit passes.
expect_exit "trailing newline stripped -> 0" 0 $'abcde\n' --limit 5

# 10. Reads condition from --file.
printf 'abcdef' >"$TMP/cond.txt"
bash "$SUT" --limit 5 --file "$TMP/cond.txt" >/dev/null 2>&1
rc=$?
if [[ $rc -eq 1 ]]; then pass "--file over limit -> 1"; else fail "--file over limit -> wrong code ($rc)"; fi

# 11. Missing --file target -> exit 2.
bash "$SUT" --limit 5 --file "$TMP/nope.txt" >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then pass "missing --file -> 2"; else fail "missing --file -> wrong code ($rc)"; fi

# 12. stdout is greppable and reports the count and status.
out="$(printf 'abcdef' | bash "$SUT" --limit 5 2>/dev/null)"
if [[ "$out" == "chars=6 limit=5 status=over" ]]; then pass "stdout reports chars/limit/status"; else fail "stdout wrong: '$out'"; fi

# 13. Multibyte char counts as one code point, not its byte length.
#     Skipped (optional-tool SKIP convention) when perl is absent and `wc -m`
#     would fall back to a byte count in a non-UTF-8 locale.
if command -v perl >/dev/null 2>&1; then
  # 'héllo' = 5 code points; passes a limit of 5.
  expect_exit "multibyte counts as 1 code point -> 0" 0 $'h\xc3\xa9llo' --limit 5
else
  printf 'SKIP - multibyte code-point count (perl absent)\n'
fi

if [[ "$fails" -ne 0 ]]; then
  printf '\n%d test(s) failed.\n' "$fails" >&2
  exit 1
fi
printf '\nAll goal-condition-length.sh tests passed.\n'
