#!/usr/bin/env bash
# Unit tests for hook-utils.sh: sourced-lib tests for hook::emit_telemetry.
#
# Tests source hook-utils.sh directly and drive hook::emit_telemetry in
# isolation. No subprocess invocation of markdown-format.sh — black-box
# integration tests live in markdown-format.test.sh.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# --- Source the lib under test -----------------------------------------------
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

# make_sink <outfile> → prints the path to a single-executable stub sink that
# copies its stdin to <outfile>. The contract requires HOOK_TELEMETRY_SINK to be
# a single executable path (not a command-with-args), so tests point it at a
# stub script rather than `tee FILE`.
make_sink() {
  local s
  s="$(mktemp)"
  cat >"$s" <<EOF
#!/usr/bin/env bash
cat >"$1"
EOF
  chmod +x "$s"
  printf '%s' "$s"
}

# wait_for_sink <file> [max_polls] → block until <file> is non-empty (the
# fire-and-forget sink has flushed) or the bound elapses. Polls in 20ms steps so
# the assertion fires as soon as the write lands instead of racing a fixed sleep
# (sink dispatch is a freshly-spawned process; spawn latency varies, especially
# on Windows Git Bash). Returns non-zero on timeout so negative cases can assert.
wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while (( tries-- > 0 )); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

# --- Test 1: HOOK_TELEMETRY_SINK unset → returns 0, no output ----------------
unset HOOK_TELEMETRY_SINK 2>/dev/null || true
out=$(hook::emit_telemetry "markdown-format" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"foo.md","findings":[]}' 2>/dev/null)
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "sink unset: returns 0"
else
  fail "sink unset: expected 0, got $rc"
fi
if [[ -z "$out" ]]; then
  ok "sink unset: no output"
else
  fail "sink unset: unexpected output: $out"
fi

# --- Test 2: jq absent → fail-open (returns 0, no output) -------------------
# Make `command -v jq` genuinely fail by running with a PATH that contains no
# jq. A shell-function shadow does NOT exercise the guard: `command -v jq`
# reports a defined function as present, so the absence branch is never taken.
# emit_telemetry uses only shell builtins until its jq calls, so an empty PATH
# is sufficient. Scoped to the command so PATH/sink never leak into the suite.
EMPTY_BIN="$(mktemp -d)"
# shellcheck disable=SC2030,SC2031
out_nojq=$(
  export HOOK_TELEMETRY_SINK="cat"
  PATH="$EMPTY_BIN" hook::emit_telemetry "markdown-format" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"foo.md","findings":[]}' 2>/dev/null
)
rc_nojq=$?
rmdir "$EMPTY_BIN" 2>/dev/null || true
if [[ $rc_nojq -eq 0 ]]; then
  ok "jq absent: returns 0"
else
  fail "jq absent: expected 0, got $rc_nojq"
fi
if [[ -z "$out_nojq" ]]; then
  ok "jq absent: no output"
else
  fail "jq absent: unexpected output: $out_nojq"
fi

# --- Test 3: envelope shape matches schema (7 required common fields + data) --
SINK_FILE="$(mktemp)"
cleanup_t3() { rm -f "$SINK_FILE"; }
trap cleanup_t3 EXIT

# Use a file-writing sink to capture the envelope.
# shellcheck disable=SC2031  # prior subshell export is intentionally scoped there
HOOK_TELEMETRY_SINK="$(make_sink "$SINK_FILE")"
export HOOK_TELEMETRY_SINK
data_json='{"tool":"Write","file":"docs/foo.md","findings":["docs/foo.md:12 MD013/line-length"]}'
start=$EPOCHREALTIME
hook::emit_telemetry "markdown-format" "PostToolUse" "ok" "$start" "$data_json" 2>/dev/null
wait_for_sink "$SINK_FILE"
unset HOOK_TELEMETRY_SINK

if [[ -s "$SINK_FILE" ]]; then
  ok "envelope shape: sink received data"
  # Validate all 7 required common fields
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    if jq -e "has(\"$field\")" "$SINK_FILE" >/dev/null 2>&1; then
      ok "envelope shape: field '$field' present"
    else
      fail "envelope shape: field '$field' missing. envelope=$(cat "$SINK_FILE")"
    fi
  done
  # Validate data sub-fields
  for subfield in tool file findings; do
    if jq -e ".data | has(\"$subfield\")" "$SINK_FILE" >/dev/null 2>&1; then
      ok "envelope shape: data.$subfield present"
    else
      fail "envelope shape: data.$subfield missing. data=$(jq .data "$SINK_FILE")"
    fi
  done
  # Validate schema_version
  sv=$(jq -r '.schema_version' "$SINK_FILE")
  if [[ "$sv" == "1.0" ]]; then
    ok "envelope: schema_version is 1.0"
  else
    fail "envelope: schema_version expected 1.0, got $sv"
  fi
  # Validate hook id
  hook_val=$(jq -r '.hook' "$SINK_FILE")
  if [[ "$hook_val" == "markdown-format" ]]; then
    ok "envelope: hook is markdown-format"
  else
    fail "envelope: hook expected markdown-format, got $hook_val"
  fi
  # Validate hook_event
  he=$(jq -r '.hook_event' "$SINK_FILE")
  if [[ "$he" == "PostToolUse" ]]; then
    ok "envelope: hook_event is PostToolUse"
  else
    fail "envelope: hook_event expected PostToolUse, got $he"
  fi
  # Validate status
  st=$(jq -r '.status' "$SINK_FILE")
  if [[ "$st" == "ok" ]]; then
    ok "envelope: status is ok"
  else
    fail "envelope: status expected ok, got $st"
  fi
else
  fail "envelope shape: sink file empty — emit did not fire or sink did not write"
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    fail "envelope shape: field '$field' not verifiable (no envelope)"
  done
  for subfield in tool file findings; do
    fail "envelope shape: data.$subfield not verifiable (no envelope)"
  done
fi

# --- Test 4: timestamp is UTC RFC3339 with Z suffix --------------------------
if [[ -s "$SINK_FILE" ]]; then
  ts=$(jq -r '.timestamp' "$SINK_FILE")
  if [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    ok "timestamp: matches RFC3339 UTC pattern"
  else
    fail "timestamp: does not match pattern: $ts"
  fi
  # Verify it is genuinely UTC: timestamp hour must align with UTC hour (±1 for boundary)
  # We verify by checking the TZ=UTC prefix actually produces UTC
  utc_h=$(TZ=UTC date +%H)
  ts_h="${ts:11:2}"
  # Circular ±1h tolerance to absorb an hour-boundary straddle between the emit
  # and this check — including the 23→00 midnight wrap, where a linear distance
  # would read 23 and false-fail once per day. (#0 strips the leading zero so
  # 00–09 are not misread as octal inside (( )).)
  h_diff=$(( ( ${ts_h#0} - ${utc_h#0} + 24 ) % 24 ))
  if [[ $h_diff -le 1 || $h_diff -ge 23 ]]; then
    ok "timestamp: UTC hour aligns with system UTC"
  else
    fail "timestamp: hour drift vs UTC: ts_h=$ts_h utc_h=$utc_h diff=$h_diff"
  fi
else
  fail "timestamp: no envelope to check"
  fail "timestamp: UTC alignment not verifiable"
fi

# --- Test 5: duration_ms is a non-negative integer ---------------------------
if [[ -s "$SINK_FILE" ]]; then
  dur=$(jq '.duration_ms' "$SINK_FILE")
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$SINK_FILE" >/dev/null 2>&1; then
    ok "duration_ms: is non-negative integer (value=$dur)"
  else
    fail "duration_ms: not a non-negative integer: $dur"
  fi
else
  fail "duration_ms: no envelope to check"
fi

rm -f "$SINK_FILE"
trap - EXIT

# --- Test 6: status "skipped" passes through ---------------------------------
SINK_FILE2="$(mktemp)"
HOOK_TELEMETRY_SINK="$(make_sink "$SINK_FILE2")"
export HOOK_TELEMETRY_SINK
hook::emit_telemetry "markdown-format" "PostToolUse" "skipped" "$EPOCHREALTIME" '{"tool":"","file":"","findings":[]}' 2>/dev/null
wait_for_sink "$SINK_FILE2"
unset HOOK_TELEMETRY_SINK

if [[ -s "$SINK_FILE2" ]]; then
  st2=$(jq -r '.status' "$SINK_FILE2")
  if [[ "$st2" == "skipped" ]]; then
    ok "status skipped: correctly emitted"
  else
    fail "status skipped: got $st2"
  fi
else
  fail "status skipped: no envelope written"
fi
rm -f "$SINK_FILE2"

# --- Test 7: RELATIVE sink resolves against the passed repo_root (6th arg) ----
# This is the portable/tracked-wiring path: a relative HOOK_TELEMETRY_SINK joined
# onto the consuming repo root the caller passes.
ROOT7="$(mktemp -d)"
mkdir -p "$ROOT7/.claude/hooks"
REL7=".claude/hooks/sink.sh"
OUT7="$(mktemp)"
cat >"$ROOT7/$REL7" <<EOF
#!/usr/bin/env bash
cat >"$OUT7"
EOF
chmod +x "$ROOT7/$REL7"
export HOOK_TELEMETRY_SINK="$REL7"
hook::emit_telemetry "markdown-format" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"x.md","findings":[]}' "$ROOT7" 2>/dev/null
wait_for_sink "$OUT7"
unset HOOK_TELEMETRY_SINK
if [[ -s "$OUT7" ]] && [[ "$(jq -r '.hook' "$OUT7")" == "markdown-format" ]]; then
  ok "relative sink: resolved against repo_root arg, envelope delivered"
else
  fail "relative sink: not resolved against repo_root arg (out empty or wrong)"
fi
rm -rf "$ROOT7" "$OUT7"

# --- Test 8: RELATIVE sink resolves against CLAUDE_PROJECT_DIR when no root arg --
ROOT8="$(mktemp -d)"
mkdir -p "$ROOT8/.claude/hooks"
OUT8="$(mktemp)"
cat >"$ROOT8/.claude/hooks/sink.sh" <<EOF
#!/usr/bin/env bash
cat >"$OUT8"
EOF
chmod +x "$ROOT8/.claude/hooks/sink.sh"
export HOOK_TELEMETRY_SINK=".claude/hooks/sink.sh"
CLAUDE_PROJECT_DIR="$ROOT8" hook::emit_telemetry "markdown-format" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"x.md","findings":[]}' 2>/dev/null
wait_for_sink "$OUT8"
unset HOOK_TELEMETRY_SINK
if [[ -s "$OUT8" ]]; then
  ok "relative sink: resolved against CLAUDE_PROJECT_DIR fallback"
else
  fail "relative sink: CLAUDE_PROJECT_DIR fallback did not resolve"
fi
rm -rf "$ROOT8" "$OUT8"

# --- Test 9: RELATIVE sink with NO anchor → fail-open skip (return 0, no write) --
OUT9="$(mktemp)"
rm -f "$OUT9" # ensure absent
export HOOK_TELEMETRY_SINK="relative/no/anchor/sink.sh"
(
  unset CLAUDE_PROJECT_DIR 2>/dev/null || true
  hook::emit_telemetry "markdown-format" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"x.md","findings":[]}' 2>/dev/null
)
rc9=$?
sleep 0.2
unset HOOK_TELEMETRY_SINK
if [[ $rc9 -eq 0 ]] && [[ ! -s "$OUT9" ]]; then
  ok "relative sink, no anchor: fail-open skip (rc 0, no write)"
else
  fail "relative sink, no anchor: expected skip (rc=$rc9, out exists=$([[ -s "$OUT9" ]] && echo y || echo n))"
fi
rm -f "$OUT9"

# --- Test 10: ABSOLUTE sink passes through unchanged --------------------------
OUT10="$(mktemp)"
ABS10="$(make_sink "$OUT10")" # mktemp path is absolute
export HOOK_TELEMETRY_SINK="$ABS10"
hook::emit_telemetry "markdown-format" "PostToolUse" "ok" "$EPOCHREALTIME" '{"tool":"Write","file":"x.md","findings":[]}' "/some/ignored/root" 2>/dev/null
wait_for_sink "$OUT10"
unset HOOK_TELEMETRY_SINK
if [[ -s "$OUT10" ]] && [[ "$(jq -r '.hook' "$OUT10")" == "markdown-format" ]]; then
  ok "absolute sink: passes through unchanged (repo_root ignored)"
else
  fail "absolute sink: did not pass through"
fi
rm -f "$ABS10" "$OUT10"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
