#!/usr/bin/env bash
# Black-box contract test for lane-stop-gate.sh (autonomy Stop hook).
#
# Proves WIRING: default-OFF inertness, the completion-signal matrix (sentinel
# token / marker file), the standalone-token match guard, the one-nudge-then-
# allow+notify loop behavior via stop_hook_active, the Stop-only event guard,
# fail-open on empty stdin and missing jq, and that a legitimate signaled stop is
# allowed silently.
#
# Self-contained: installed plugins are cache-isolated with no shared test lib,
# so this defines its own assertions and builds throwaway inputs with jq. The OS
# toast is never exercised here (notification channels are disabled on the paths
# that would fire one) — lane-notify.test.sh covers the notifier.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/lane-stop-gate.sh"

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

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

# build_input — assemble a Stop payload. Named-arg style via env: TYPE, LAST,
# STOP_ACTIVE, CWD.
build_input() {
  local event="${1:-Stop}" last="${2:-}" stop_active="${3:-false}" cwd="${4:-}"
  MSYS_NO_PATHCONV=1 jq -n \
    --arg e "$event" --arg l "$last" --argjson s "$stop_active" --arg c "$cwd" \
    '{hook_event_name:$e, last_assistant_message:$l, stop_hook_active:$s, cwd:$c, session_id:"test-sess"}'
}

# run <input> [extra env KEY=VAL ...] — invoke the hook from an unrelated cwd
# with a hermetic env (ambient CLAUDE_PLUGIN_OPTION_* cleared), notifications
# muted so no real toast fires, then caller overrides applied last.
run() {
  local input="$1"
  shift
  (cd "$UNRELATED" && printf '%s' "$input" |
    env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
      -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
      CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true \
      CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
      "$@" \
      bash "$HOOK" 2>/dev/null)
}

is_block() { printf '%s' "$1" | jq -e '.decision == "block"' >/dev/null 2>&1; }

# --- Case 1: gate disabled (unset default) → silent exit 0 ------------------
OUT="$(cd "$UNRELATED" && build_input Stop "" false |
  env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED bash "$HOOK" 2>&1)"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "default OFF → silent exit 0 (interactive-safe)"; else fail "default OFF (rc=$RC out=$OUT)"; fi

# --- Case 2: enabled, first stop, no signal → block ------------------------
OUT="$(run "$(build_input Stop "working on it" false)")"
RC=$?
if [[ $RC -eq 0 ]]; then ok "first stop no-signal: exit 0"; else fail "first stop no-signal exit $RC"; fi
if is_block "$OUT"; then ok "first stop no-signal → decision:block"; else fail "first stop no-signal → not blocked: $OUT"; fi
if printf '%s' "$OUT" | jq -re '.reason' | grep -q 'LANE-STOP-OK'; then ok "block reason names the sentinel"; else fail "block reason missing sentinel: $OUT"; fi

# --- Case 3: sentinel alone on its own (final) line → allow (no block) ------
OUT="$(run "$(build_input Stop "All queue items cleared.
LANE-STOP-OK" false)")"
if is_block "$OUT"; then fail "sentinel on its own line → still blocked: $OUT"; else ok "sentinel on its own line → stop allowed (no block)"; fi

# --- Case 4: sentinel only as substring of a longer word → NOT signaled ----
OUT="$(run "$(build_input Stop "status: LANE-STOP-OKAYISH maybe" false)")"
if is_block "$OUT"; then ok "sentinel-as-substring → not a signal, blocked"; else fail "sentinel-as-substring wrongly allowed: $OUT"; fi

# --- Case 5: marker file exists → allow ------------------------------------
MARK="$WORK/done.marker"
: >"$MARK"
OUT="$(run "$(build_input Stop "no token here" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$MARK")"
if is_block "$OUT"; then fail "marker present → still blocked: $OUT"; else ok "marker file present → stop allowed"; fi
rm -f "$MARK"

# --- Case 6: marker absent → block -----------------------------------------
OUT="$(run "$(build_input Stop "no token here" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$WORK/never.marker")"
if is_block "$OUT"; then ok "marker absent → blocked"; else fail "marker absent wrongly allowed: $OUT"; fi

# --- Case 7: relative marker resolves against payload cwd → allow ----------
REPO="$WORK/lane"
mkdir -p "$REPO"
: >"$REPO/complete"
OUT="$(run "$(build_input Stop "" false "$REPO")" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="complete")"
if is_block "$OUT"; then fail "relative marker under cwd → still blocked: $OUT"; else ok "relative marker resolves against cwd → allowed"; fi
rm -rf "$REPO"

# --- Case 8: stop_hook_active=true, no signal → allow + no block (notify path)
OUT="$(run "$(build_input Stop "still no token" true)")"
RC=$?
if [[ $RC -eq 0 ]]; then ok "post-nudge stop: exit 0"; else fail "post-nudge stop exit $RC"; fi
if is_block "$OUT"; then fail "post-nudge stop → blocked again (would risk runaway): $OUT"; else ok "post-nudge stop → allowed (no second block)"; fi

# --- Case 9: non-Stop event (SubagentStop) → allow even when unsatisfied ----
OUT="$(run "$(build_input SubagentStop "no token" false)")"
if is_block "$OUT"; then fail "SubagentStop → blocked (must not gate subagents): $OUT"; else ok "SubagentStop event → not gated"; fi

# --- Case 10: empty stdin → silent exit 0 ----------------------------------
OUT="$(cd "$UNRELATED" && env CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true bash "$HOOK" </dev/null 2>&1)"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "empty stdin → silent exit 0 (fail-open)"; else fail "empty stdin (rc=$RC out=$OUT)"; fi

# --- Case 11: custom sentinel via env → allow ------------------------------
OUT="$(run "$(build_input Stop "queue empty
DONE-ROTATE" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="DONE-ROTATE")"
if is_block "$OUT"; then fail "custom sentinel → still blocked: $OUT"; else ok "custom sentinel honored → allowed"; fi

# --- Case 12: jq absent → visible systemMessage notice + exit 0 (fail-open) --
FAKEBIN="$(mktemp -d -p "$WORK" fakebin.XXXXXX)"
for t in bash dirname cat env printf mktemp mkdir find tr grep sed uname sleep git awk; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
JQ_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
OUT_NOJQ="$(cd "$UNRELATED" && printf '{"session_id":"nojq-1","hook_event_name":"Stop","stop_hook_active":false}' |
  env -i PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA" \
    CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true bash "$HOOK" 2>/dev/null)"
RC=$?
if [[ $RC -eq 0 && "$OUT_NOJQ" == *'"systemMessage"'* && "$OUT_NOJQ" == *jq* ]]; then
  ok "jq-absent → exit 0 with visible systemMessage notice (fail-open)"
else
  fail "jq-absent (rc=$RC out=$OUT_NOJQ)"
fi

# --- Case 13: sentinel mentioned/negated inline (not alone on a line) → block
# Regression: after the nudge reveals the token, a premature turn that merely
# discusses or negates it must NOT satisfy the gate.
OUT="$(run "$(build_input Stop "I should not emit LANE-STOP-OK yet" false)")"
if is_block "$OUT"; then ok "inline mention/negation of sentinel → not a signal, blocked"; else fail "inline sentinel mention wrongly allowed: $OUT"; fi

# --- Case 14: sentinel alone on its line amid other lines, indented → allow --
# Leading/trailing whitespace around the dedicated line is tolerated.
OUT="$(run "$(build_input Stop "Goal verified, tests green.
  LANE-STOP-OK
(stopping now)" false)")"
if is_block "$OUT"; then fail "sentinel alone on its line (indented) → wrongly blocked: $OUT"; else ok "sentinel alone on its own line (whitespace ok) → stop allowed"; fi

# --- Case 15: early sentinel in a very long message → allow (SIGPIPE guard) --
# Regression: `printf | grep -q` under pipefail loses an early match when the
# message overruns the pipe buffer (grep exits, printf takes SIGPIPE, the
# pipeline reads false). The sentinel first + ~120KB of trailing text must
# still be recognized as a signal. The message is fed to jq via --rawfile, not
# --arg: a 120KB argv element overruns OS argv limits, and a failed build would
# silently degrade this case to the empty-stdin fail-open path.
build_big_input() { # <file-with-message> — message rides stdin (-Rs), not a
  # path argument: a native jq binary cannot open an MSYS-style temp path.
  jq -Rs \
    '{hook_event_name:"Stop", last_assistant_message:., stop_hook_active:false, cwd:"", session_id:"test-sess"}' \
    <"$1"
}
BIGFILE="$WORK/bigmsg.txt"
{
  printf 'LANE-STOP-OK\n'
  head -c 120000 /dev/zero | tr '\0' 'x'
} >"$BIGFILE"
# Control first — the same long tail WITHOUT the sentinel must block, proving
# the long payload is actually built and evaluated (not lost to fail-open).
# The stdin read timeout is raised for both invocations: the hook's default 2s
# bounded read can time out on a 120KB payload on a slow-pipe host (Windows),
# and this case tests the sentinel match, not stdin timing.
head -c 120000 /dev/zero | tr '\0' 'x' >"$BIGFILE.nosig"
OUT="$(run "$(build_big_input "$BIGFILE.nosig")" CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=30)"
if is_block "$OUT"; then ok "~120KB message without sentinel → blocked (long payload really evaluated)"; else fail "long-message control not blocked — long payload not reaching the gate: $OUT"; fi
OUT="$(run "$(build_big_input "$BIGFILE")" CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=30)"
if is_block "$OUT"; then fail "early sentinel in long message → wrongly blocked (pipefail/SIGPIPE): $OUT"; else ok "early sentinel in ~120KB message → stop allowed (no SIGPIPE loss)"; fi

# --- Telemetry (hook-telemetry convention): sink helpers ---------------------
# make_sink <file> → executable that appends stdin to <file>; wait_sink <file>
# polls until the fire-and-forget background write lands (or ~3s elapses).
make_sink() {
  local s="$WORK/sink.sh"
  printf '#!/usr/bin/env bash\ncat >>"%s"\n' "$1" >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}
wait_sink() {
  local f="$1" tries=150
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

# --- Case 16: telemetry on block → status=blocked, outcome=nudged, no token --
TEL="$WORK/tel-block.jsonl"
SINK="$(make_sink "$TEL")"
OUT="$(run "$(build_input Stop "no token" false)" HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$WORK")"
if is_block "$OUT"; then ok "telemetry block case still blocks"; else fail "telemetry block case not blocked: $OUT"; fi
if wait_sink "$TEL"; then
  if jq -e '.hook=="lane-stop-gate" and .status=="blocked" and .data.outcome=="nudged" and .data.signal=="none" and (.duration_ms|type)=="number"' "$TEL" >/dev/null 2>&1; then
    ok "telemetry on block: envelope hook/status/outcome/signal/duration correct"
  else
    fail "telemetry on block: bad envelope: $(cat "$TEL")"
  fi
  if grep -q "LANE-STOP-OK" "$TEL"; then fail "telemetry envelope leaks the sentinel token"; else ok "telemetry envelope carries no sentinel token"; fi
else
  fail "telemetry on block: no envelope written"
fi

# --- Case 17: telemetry on signaled allow → status=ok, signal=sentinel -------
TEL="$WORK/tel-ok.jsonl"
SINK="$(make_sink "$TEL")"
OUT="$(run "$(build_input Stop "LANE-STOP-OK" false)" HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$WORK")"
if is_block "$OUT"; then fail "telemetry signaled case wrongly blocked: $OUT"; fi
if wait_sink "$TEL" && jq -e '.status=="ok" and .data.outcome=="completion-signaled" and .data.signal=="sentinel"' "$TEL" >/dev/null 2>&1; then
  ok "telemetry on signaled allow: ok/completion-signaled/sentinel"
else
  fail "telemetry on signaled allow: bad or missing envelope: $(cat "$TEL" 2>/dev/null)"
fi

# --- Case 18: telemetry on post-nudge allow → ok, outcome=stopped-after-nudge
TEL="$WORK/tel-nudge.jsonl"
SINK="$(make_sink "$TEL")"
OUT="$(run "$(build_input Stop "still no token" true)" HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$WORK")"
if is_block "$OUT"; then fail "telemetry post-nudge case wrongly blocked: $OUT"; fi
if wait_sink "$TEL" && jq -e '.status=="ok" and .data.outcome=="stopped-after-nudge" and .data.signal=="none"' "$TEL" >/dev/null 2>&1; then
  ok "telemetry on post-nudge allow: ok/stopped-after-nudge/none"
else
  fail "telemetry on post-nudge allow: bad or missing envelope: $(cat "$TEL" 2>/dev/null)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
