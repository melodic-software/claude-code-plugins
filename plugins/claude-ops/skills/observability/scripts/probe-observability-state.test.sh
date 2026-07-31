#!/usr/bin/env bash
# Regression tests for probe-observability-state.sh.
#
# The script exists only to reproduce, from a bundled file, what two pre-compute
# lines used to compute inline (#1687). So every case asserts TWO things: the
# script's output against the expected literal, and the script's output against
# the ORIGINAL inline one-liner run in the same environment. The second assertion
# is the byte-for-byte equivalence claim, checked rather than reasoned about.
#
# Coverage:
#   --hook-events
#     - present log → `<N> events`; absent log → the EMPTY sentence verbatim
#     - path resolves under the git toplevel, and under the working directory
#       when not inside a repo
#     - no env override (the line it replaces had none), so CC_OTEL_STORE must
#       not steer it
#   --otel-store
#     - CC_OTEL_STORE used verbatim when set; an EMPTY value falls through
#     - one line per store file, in fixed order, `<name>:<bytes>B` / `<name>:absent`
#     - mixed present/absent across the three files
#   - a CRLF-terminated git toplevel does not leak a stray CR into the path
#   - mode validation: missing, unknown, and conflicting arguments all exit 3
#
# PATH-stubs `git` so no real repository state is touched.
#
# Every case runs in THIS shell, never a `( … )` subshell: an assertion inside a
# subshell increments a copy of the failure counter and the run would report
# green with a failing case in it. Environment scoping is therefore explicit
# set/unset around each case rather than subshell containment.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/probe-observability-state.sh"
START_DIR="$PWD"
TMP="$(mktemp -d)"
trap 'cd "$START_DIR" 2>/dev/null; rm -rf "$TMP"' EXIT

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s\n      expected: %q\n      got:      %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

# --- The pre-compute lines this script replaced, verbatim --------------------
ORIG_HOOK="$TMP/original-hook-events.sh"
cat >"$ORIG_HOOK" <<'ORIG'
f="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/observability/hook-events.jsonl"; if [[ -f "$f" ]]; then echo "$(wc -l < "$f") events"; else echo "EMPTY (no hook-event emitter wired, or no hooks fired yet)"; fi
ORIG

ORIG_OTEL="$TMP/original-otel-store.sh"
cat >"$ORIG_OTEL" <<'ORIG'
d="${CC_OTEL_STORE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/observability/otel}"; for f in cc-logs.json cc-metrics.json cc-traces.json; do if [[ -f "$d/$f" ]]; then echo "$f:$(wc -c < "$d/$f" 2>/dev/null || echo 0)B"; else echo "$f:absent"; fi; done 2>/dev/null || echo "unknown"
ORIG

# --- Stubs -------------------------------------------------------------------
STUB="$TMP/stub"
mkdir -p "$STUB"
cat >"$STUB/git" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--show-toplevel" ]]; then
  if [[ -n "${STUB_GIT_TOPLEVEL:-}" ]]; then
    if [[ -n "${STUB_GIT_CRLF:-}" ]]; then
      printf '%s\r\n' "$STUB_GIT_TOPLEVEL"
    else
      printf '%s\n' "$STUB_GIT_TOPLEVEL"
    fi
    exit 0
  fi
  printf 'fatal: not a git repository\n' >&2
  exit 128
fi
exit 0
SH
chmod +x "$STUB/git"
export PATH="$STUB:$PATH"

# --- Fixtures ----------------------------------------------------------------
# WIRED: a repo whose hook log has 4 lines and whose store holds two of three files.
WIRED="$TMP/wired"
mkdir -p "$WIRED/.claude/observability/otel"
printf '{"a":1}\n{"a":2}\n{"a":3}\n{"a":4}\n' >"$WIRED/.claude/observability/hook-events.jsonl"
printf '0123456789' >"$WIRED/.claude/observability/otel/cc-logs.json"
printf '01234' >"$WIRED/.claude/observability/otel/cc-traces.json"

# BARE: a repo with no observability tree at all.
BARE="$TMP/bare"
mkdir -p "$BARE"

# ALTSTORE: a store outside any repo, for the CC_OTEL_STORE override.
ALTSTORE="$TMP/altstore"
mkdir -p "$ALTSTORE"
printf 'xy' >"$ALTSTORE/cc-metrics.json"

# Expected byte/line counts come from `wc` itself, not from GNU-shaped literals.
# BSD `wc` left-pads its output (`       10`) where GNU does not, and the script
# must keep emitting whatever the host's `wc` produces — that padding is part of
# the output shape the replaced pre-compute line had. Hardcoding `10B` would make
# these cases fail on macOS for a difference the script is required to preserve.
wc_c() { wc -c <"$1"; }
wc_l() { wc -l <"$1"; }

WIRED_EVENTS="$(wc_l "$WIRED/.claude/observability/hook-events.jsonl") events"
WIRED_STORE_LINES="$(printf 'cc-logs.json:%sB\ncc-metrics.json:absent\ncc-traces.json:%sB' \
  "$(wc_c "$WIRED/.claude/observability/otel/cc-logs.json")" \
  "$(wc_c "$WIRED/.claude/observability/otel/cc-traces.json")")"
EMPTY_STORE_LINES="$(printf 'cc-logs.json:absent\ncc-metrics.json:absent\ncc-traces.json:absent')"
ALT_STORE_LINES="$(printf 'cc-logs.json:absent\ncc-metrics.json:%sB\ncc-traces.json:absent' \
  "$(wc_c "$ALTSTORE/cc-metrics.json")")"

# run_both <label> <mode> <original-script> <expected-literal>
run_both() {
  local label="$1" mode="$2" original="$3" expected="$4" got orig
  got="$(bash "$SCRIPT" "$mode" 2>/dev/null)"
  orig="$(bash "$original" 2>/dev/null)"
  assert_eq "$label" "$expected" "$got"
  assert_eq "$label (matches the original inline line byte-for-byte)" "$orig" "$got"
}

# --- --hook-events ------------------------------------------------------------
export STUB_GIT_TOPLEVEL="$WIRED"
run_both "hook log present → line count" --hook-events "$ORIG_HOOK" "$WIRED_EVENTS"

export STUB_GIT_TOPLEVEL="$BARE"
run_both "hook log absent → EMPTY sentence" --hook-events "$ORIG_HOOK" \
  "EMPTY (no hook-event emitter wired, or no hooks fired yet)"

unset STUB_GIT_TOPLEVEL
cd "$WIRED" || exit 1
run_both "not in a repo → hook log resolves under the working directory" \
  --hook-events "$ORIG_HOOK" "$WIRED_EVENTS"
cd "$START_DIR" || exit 1

export STUB_GIT_TOPLEVEL="$WIRED" STUB_GIT_CRLF=1
assert_eq "CRLF toplevel is stripped (--hook-events)" "$WIRED_EVENTS" \
  "$(bash "$SCRIPT" --hook-events 2>/dev/null)"
unset STUB_GIT_CRLF

# The replaced line had no env override; CC_OTEL_STORE must not steer this mode.
export CC_OTEL_STORE="$ALTSTORE"
run_both "CC_OTEL_STORE does not steer --hook-events" --hook-events "$ORIG_HOOK" "$WIRED_EVENTS"
unset CC_OTEL_STORE

# --- --otel-store -------------------------------------------------------------
run_both "store under the git toplevel: mixed present/absent, fixed order" \
  --otel-store "$ORIG_OTEL" "$WIRED_STORE_LINES"

export STUB_GIT_TOPLEVEL="$BARE"
run_both "store absent → every file reported absent" \
  --otel-store "$ORIG_OTEL" "$EMPTY_STORE_LINES"

export STUB_GIT_TOPLEVEL="$WIRED" CC_OTEL_STORE="$ALTSTORE"
run_both "CC_OTEL_STORE is used verbatim" --otel-store "$ORIG_OTEL" "$ALT_STORE_LINES"

export CC_OTEL_STORE=""
run_both "empty CC_OTEL_STORE falls through to the repo default" \
  --otel-store "$ORIG_OTEL" "$WIRED_STORE_LINES"
unset CC_OTEL_STORE

unset STUB_GIT_TOPLEVEL
cd "$WIRED" || exit 1
run_both "not in a repo → store resolves under the working directory" \
  --otel-store "$ORIG_OTEL" "$WIRED_STORE_LINES"
cd "$START_DIR" || exit 1

export STUB_GIT_TOPLEVEL="$WIRED" STUB_GIT_CRLF=1
assert_eq "CRLF toplevel is stripped (--otel-store)" "$WIRED_STORE_LINES" \
  "$(bash "$SCRIPT" --otel-store 2>/dev/null)"
unset STUB_GIT_CRLF

# --- Mode validation ----------------------------------------------------------
out="$(bash "$SCRIPT" 2>&1)"
rc=$?
assert_eq "no mode exits 3" "3" "$rc"
case "$out" in
*"a mode is required"*) pass "no mode names the requirement on stderr" ;;
*) fail "no mode names the requirement on stderr" "a mode is required" "$out" ;;
esac

bash "$SCRIPT" --bogus >/dev/null 2>&1
assert_eq "unknown argument exits 3" "3" "$?"

out="$(bash "$SCRIPT" --hook-events --otel-store 2>&1)"
rc=$?
assert_eq "conflicting modes exit 3" "3" "$rc"
case "$out" in
*"mutually exclusive"*) pass "conflicting modes are named on stderr" ;;
*) fail "conflicting modes are named on stderr" "mutually exclusive" "$out" ;;
esac

bash "$SCRIPT" --help >/dev/null 2>&1
assert_eq "--help exits 0" "0" "$?"

if [[ $FAILED -eq 0 ]]; then
  printf '\nAll %d cases passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d of %d cases FAILED.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
