#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/goal-condition-length.sh"

# shellcheck source=../lib/test-pass-fail.sh
source "$SCRIPT_DIR/../lib/test-pass-fail.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

expect_exit() {
  local label="$1" want="$2" input="$3"
  shift 3
  local got
  printf '%s' "$input" | bash "$SUT" "$@" >/dev/null 2>&1
  got=$?
  if [[ "$got" -eq "$want" ]]; then pass "$label"; else fail "$label (want exit $want, got $got)"; fi
}

expect_exit "--help exits 0" 0 "" --help

expect_exit "under limit -> 0" 0 "hello" --limit 50

expect_exit "at limit (boundary) -> 0" 0 "abcde" --limit 5

expect_exit "over limit -> 1" 1 "abcdef" --limit 5

expect_exit "missing --limit -> 2" 2 "hello"

expect_exit "non-integer limit -> 2" 2 "hello" --limit abc

expect_exit "zero limit -> 2" 2 "hello" --limit 0

expect_exit "empty condition -> 2" 2 "" --limit 50

expect_exit "trailing newline stripped -> 0" 0 $'abcde\n' --limit 5

printf 'abcdef' >"$TMP/cond.txt"
expect_exit "--file over limit -> 1" 1 "" --limit 5 --file "$TMP/cond.txt"

expect_exit "missing --file -> 2" 2 "" --limit 5 --file "$TMP/nope.txt"

out="$(printf 'abcdef' | bash "$SUT" --limit 5 2>/dev/null)"
if [[ "$out" == "chars=6 limit=5 status=over" ]]; then pass "stdout reports chars/limit/status"; else fail "stdout wrong: '$out'"; fi

# A multibyte char counts as one code point, not its byte length. Skipped when
# perl is absent and `wc -m` would fall back to a byte count in a non-UTF-8 locale.
if command -v perl >/dev/null 2>&1; then
  expect_exit "multibyte counts as 1 code point -> 0" 0 $'h\xc3\xa9llo' --limit 5
else
  printf 'SKIP - multibyte code-point count (perl absent)\n'
fi

fake_bin="$TMP/fakebin"
mkdir -p "$fake_bin"
for stub in perl wc; do
  printf '#!/usr/bin/env bash\ncat >/dev/null 2>&1\nexit 0\n' >"$fake_bin/$stub"
  chmod +x "$fake_bin/$stub"
done
rc=0
printf 'hello' | PATH="$fake_bin:$PATH" bash "$SUT" --limit 50 >/dev/null 2>&1 || rc=$?
if [[ $rc -eq 2 ]]; then pass "counter failure -> 2 (no false pass)"; else fail "counter failure -> wrong code ($rc)"; fi

if command -v script >/dev/null 2>&1 && script -qec true /dev/null </dev/null >/dev/null 2>&1; then
  out="$(timeout 10 script -qec "bash '$SUT' --limit 5" /dev/null </dev/null 2>&1)"
  rc=$?
  if [[ $rc -eq 2 && "$out" == *"--file"* ]]; then pass "terminal stdin -> 2 with usage hint"; else fail "terminal stdin -> want 2 with hint (got $rc)"; fi
else
  printf 'skip - terminal stdin (no util-linux script)\n'
fi

if [[ "$fails" -ne 0 ]]; then
  printf '\n%d test(s) failed.\n' "$fails" >&2
  exit 1
fi
printf '\nAll goal-condition-length.sh tests passed.\n'
