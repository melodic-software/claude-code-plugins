#!/usr/bin/env bash
# Regression tests for probe-observability-state.sh.
#
# The script exists to reproduce, from a bundled file, what pre-compute lines
# used to compute inline (#1687). The OTEL cases therefore assert TWO things: the
# script's output against the expected literal, and the script's output against
# the ORIGINAL inline one-liner run in the same environment. The second assertion
# is the byte-for-byte equivalence claim, checked rather than reasoned about.
# The hook-events line has no inline original any more: it reads a whole root
# (sessions/*.jsonl plus the shared file) that the pre-compute line never did,
# so its cases assert the literal alone.
#
# Coverage:
#   --hook-events
#     - present files → `<N> events` summed across sessions/*.jsonl and the
#       shared hook-events.jsonl; nothing → the EMPTY sentence verbatim
#     - path resolves under the git toplevel, and under the working directory
#       when not inside a repo
#     - --root moves the root; an unexpanded `${user_config...}` placeholder and
#       an empty value read as the default; an uncontained root is INVALID
#     - no env override (the line it replaces had none), so CC_OTEL_STORE must
#       not steer it
#   --otel-store
#     - CC_OTEL_STORE used verbatim when set; an EMPTY value falls through
#     - one line per store file, in fixed order, `<name>:<bytes>B` / `<name>:absent`
#     - mixed present/absent across the three files
#   --pipeline
#     - six fixed lines; guard ok / absent / operator-edited / not a checkout;
#       newest session by mtime; shared count; prune-pending age WARN; option
#       defaults for unexpanded placeholders; the probe never writes the guard
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
assert_contains() { if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "contains: $2" "$3"; fi; }

# --- The OTEL pre-compute line this script replaced, verbatim ----------------
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
# WIRED: a checkout whose hook log root holds two session files (2 + 1 lines),
# a shared file (4 lines), a healthy guard, and whose OTEL store holds two of
# three files.
WIRED="$TMP/wired"
mkdir -p "$WIRED/.git" "$WIRED/.observability/claude/sessions" "$WIRED/.claude/observability/otel"
printf '*\n' >"$WIRED/.observability/claude/.gitignore"
printf '{"a":1}\n{"a":2}\n' >"$WIRED/.observability/claude/sessions/s-old.jsonl"
sleep 1
printf '{"a":3}\n' >"$WIRED/.observability/claude/sessions/s-new.jsonl"
printf '{"a":1}\n{"a":2}\n{"a":3}\n{"a":4}\n' >"$WIRED/.observability/claude/hook-events.jsonl"
printf '0123456789' >"$WIRED/.claude/observability/otel/cc-logs.json"
printf '01234' >"$WIRED/.claude/observability/otel/cc-traces.json"

# BARE: a checkout with no observability tree at all.
BARE="$TMP/bare"
mkdir -p "$BARE/.git"

# MOVED: the root configured elsewhere, one session file.
MOVED="$TMP/moved"
mkdir -p "$MOVED/.git" "$MOVED/telemetry/hooks/sessions"
printf '{"a":1}\n{"a":2}\n{"a":3}\n' >"$MOVED/telemetry/hooks/sessions/s1.jsonl"

# ALTSTORE: a store outside any repo, for the CC_OTEL_STORE override.
ALTSTORE="$TMP/altstore"
mkdir -p "$ALTSTORE"
printf 'xy' >"$ALTSTORE/cc-metrics.json"

# Expected byte/line counts come from `wc` itself, not from GNU-shaped literals.
# BSD `wc` left-pads its output (`       10`) where GNU does not, and the script
# must keep emitting whatever the host's `wc` produces.
wc_c() { wc -c <"$1"; }

WIRED_EVENTS="$(cat "$WIRED"/.observability/claude/sessions/*.jsonl "$WIRED/.observability/claude/hook-events.jsonl" | wc -l) events"
MOVED_EVENTS="$(wc -l <"$MOVED/telemetry/hooks/sessions/s1.jsonl") events"
EMPTY_LINE="EMPTY (no hook-event emitter wired, or no hooks fired yet)"
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
assert_eq "hook log present → events summed across session files and the shared file" \
  "$WIRED_EVENTS" "$(bash "$SCRIPT" --hook-events 2>/dev/null)"

export STUB_GIT_TOPLEVEL="$BARE"
assert_eq "hook log absent → EMPTY sentence" "$EMPTY_LINE" "$(bash "$SCRIPT" --hook-events 2>/dev/null)"

export STUB_GIT_TOPLEVEL="$MOVED"
assert_eq "--root moves the root" "$MOVED_EVENTS" \
  "$(bash "$SCRIPT" --hook-events --root telemetry/hooks 2>/dev/null)"
assert_eq "--root with a trailing slash is the same root" "$MOVED_EVENTS" \
  "$(bash "$SCRIPT" --hook-events --root telemetry/hooks/ 2>/dev/null)"
assert_eq "an unexpanded placeholder reads as the default root" "$EMPTY_LINE" \
  "$(bash "$SCRIPT" --hook-events --root '${user_config.session_event_log_dir}' 2>/dev/null)"
assert_eq "an empty --root reads as the default root" "$EMPTY_LINE" \
  "$(bash "$SCRIPT" --hook-events --root '' 2>/dev/null)"
assert_eq "an uncontained root is INVALID, never resolved" \
  "INVALID root (../outside): the hooks write nothing" \
  "$(bash "$SCRIPT" --hook-events --root ../outside 2>/dev/null)"
assert_eq "an absolute root is INVALID" \
  "INVALID root (/tmp/x): the hooks write nothing" \
  "$(bash "$SCRIPT" --hook-events --root /tmp/x 2>/dev/null)"

unset STUB_GIT_TOPLEVEL
cd "$WIRED" || exit 1
assert_eq "not in a repo → hook log resolves under the working directory" \
  "$WIRED_EVENTS" "$(bash "$SCRIPT" --hook-events 2>/dev/null)"
cd "$START_DIR" || exit 1

export STUB_GIT_TOPLEVEL="$WIRED" STUB_GIT_CRLF=1
assert_eq "CRLF toplevel is stripped (--hook-events)" "$WIRED_EVENTS" \
  "$(bash "$SCRIPT" --hook-events 2>/dev/null)"
unset STUB_GIT_CRLF

# The replaced line had no env override; CC_OTEL_STORE must not steer this mode.
export CC_OTEL_STORE="$ALTSTORE"
assert_eq "CC_OTEL_STORE does not steer --hook-events" "$WIRED_EVENTS" \
  "$(bash "$SCRIPT" --hook-events 2>/dev/null)"
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

# --- --pipeline ---------------------------------------------------------------
export STUB_GIT_TOPLEVEL="$WIRED"
P_OUT="$(bash "$SCRIPT" --pipeline --enabled true --keep-sessions 5 2>/dev/null)"
assert_eq "pipeline: six lines" "6" "$(printf '%s\n' "$P_OUT" | wc -l | tr -d ' ')"
assert_contains "pipeline: default root named as default" "root: .observability/claude (default)" "$P_OUT"
assert_contains "pipeline: guard ok" "guard: ok" "$P_OUT"
assert_contains "pipeline: session count and newest by mtime" "sessions: 2 file(s), newest s-new" "$P_OUT"
assert_contains "pipeline: shared file count" "shared: 4 event(s) in hook-events.jsonl" "$P_OUT"
assert_contains "pipeline: no pending prune" "prune-pending: none" "$P_OUT"
assert_contains "pipeline: options rendered with defaults filled in" \
  "logging: on; categories: all; keep: 5 sessions or 14 days; pre-prune: none" "$P_OUT"

P_OUT="$(bash "$SCRIPT" --pipeline --enabled '${user_config.session_event_log_enabled}' \
  --categories '${user_config.session_event_log_categories}' --keep-days '${user_config.session_log_keep_days}' \
  --pre-prune-command 'archive.sh' 2>/dev/null)"
assert_contains "pipeline: unexpanded placeholders read as the manifest defaults" \
  "logging: off; categories: all; keep: 30 sessions or 14 days; pre-prune: set (runs detached at SessionEnd)" "$P_OUT"
if [[ "$P_OUT" != *"archive.sh"* ]]; then
  pass "pipeline: the pre-prune command text is never echoed"
else
  fail "pipeline: the pre-prune command text is never echoed" "no archive.sh" "$P_OUT"
fi

export STUB_GIT_TOPLEVEL="$BARE"
P_OUT="$(bash "$SCRIPT" --pipeline 2>/dev/null)"
assert_contains "pipeline: absent guard is reported as healed on first write" \
  "guard: absent (the first write heals it)" "$P_OUT"
assert_contains "pipeline: no sessions" "sessions: none" "$P_OUT"
assert_contains "pipeline: no shared file" "shared: absent" "$P_OUT"
if [[ ! -e "$BARE/.observability" ]]; then
  pass "pipeline: the probe never creates the root or the guard"
else
  fail "pipeline: the probe never creates the root or the guard" "no .observability" "created"
fi

EDITED="$TMP/edited"
mkdir -p "$EDITED/.git" "$EDITED/.observability/claude/prune-pending/1000-1" "$EDITED/.observability/claude/prune-pending/2000-2"
printf '# mine\nsessions/\n' >"$EDITED/.observability/claude/.gitignore"
touch -t 202601010000 "$EDITED/.observability/claude/prune-pending/1000-1"
export STUB_GIT_TOPLEVEL="$EDITED"
P_OUT="$(bash "$SCRIPT" --pipeline 2>/dev/null)"
assert_contains "pipeline: an operator-edited guard is named" "guard: operator-edited (writes refused)" "$P_OUT"
assert_contains "pipeline: stale pending prune WARNs" \
  "prune-pending: 2 dir(s), 1 older than 24 h WARN: an archiver is not finishing" "$P_OUT"
assert_eq "pipeline: the operator's guard is left alone" "# mine" "$(head -1 "$EDITED/.observability/claude/.gitignore")"

NOGIT="$TMP/nogit"
mkdir -p "$NOGIT"
export STUB_GIT_TOPLEVEL="$NOGIT"
P_OUT="$(bash "$SCRIPT" --pipeline 2>/dev/null)"
assert_contains "pipeline: outside a checkout no guard is needed" "guard: not needed (not a git checkout)" "$P_OUT"

P_OUT="$(bash "$SCRIPT" --pipeline --root ../escape 2>/dev/null)"
assert_contains "pipeline: an uncontained root is INVALID" "root: ../escape INVALID (uncontained; the hooks write nothing)" "$P_OUT"
assert_contains "pipeline: guard is n/a on an invalid root" "guard: n/a (root invalid)" "$P_OUT"
unset STUB_GIT_TOPLEVEL

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

bash "$SCRIPT" --hook-events --root >/dev/null 2>&1
assert_eq "a flag without its value exits 3" "3" "$?"

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
