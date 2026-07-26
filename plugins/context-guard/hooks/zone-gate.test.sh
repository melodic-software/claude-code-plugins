#!/usr/bin/env bash
# Contract test for zone-gate.sh (PreToolUse, blocking mode only).
#
# Contract: inert in advisory mode (the default) and when disabled; in
# blocking mode it denies matched calls ONLY on a fresh dumb-zone snapshot
# past the grace budget, with handoff-path writes exempt; fail-open on
# unknown, on smart/acceptable (which also reset the counter), on missing
# stdin, and on hostile ids. Exit 0 always.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/zone-gate.sh"

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

command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq not installed"
  exit 0
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

CTX_REL=".claude/context-guard/context"

write_snapshot() { # <home> <sid> <used_percentage>
  local home="$1" sid="$2" used="$3"
  mkdir -p "$home/$CTX_REL"
  printf '{"captured_at":"%s","session_id":"%s","context_window":{"used_percentage":%s,"remaining_percentage":50,"current_usage":{"input_tokens":100}}}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$sid" "$used" >"$home/$CTX_REL/$sid.json"
}

# run <home> <data> <sid> <payload-extra-json> [<mode>] [<grace>]
OUT=""
RC=0
run() {
  local home="$1" data="$2" sid="$3" extra="$4" mode="${5:-blocking}" grace="${6:-}"
  local env_grace=()
  [[ -n "$grace" ]] && env_grace=(CLAUDE_PLUGIN_OPTION_ZONE_GATE_GRACE_CALLS="$grace")
  OUT=$(printf '{"session_id":"%s","hook_event_name":"PreToolUse","tool_name":"Write"%s}' "$sid" "$extra" |
    HOME="$home" CLAUDE_PLUGIN_DATA="$data" HOOK_TELEMETRY_SINK="" \
      CLAUDE_PLUGIN_OPTION_ZONE_HOOK_MODE="$mode" env "${env_grace[@]}" bash "$HOOK" 2>/dev/null)
  RC=$?
}

H="$WORK/home"
D="$WORK/data"

# 1. Advisory mode (default) is inert even on dumb.
write_snapshot "$H" s1 95
OUT=$(printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Write"}' |
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" bash "$HOOK" 2>/dev/null)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "advisory default is inert"; else fail "advisory: rc=$RC out=$OUT"; fi

# 2. Blocking + dumb within grace → allowed, counter counts.
run "$H" "$D" s1 '' blocking 2
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "blocking within grace allows (call 1)"; else fail "grace call 1: rc=$RC out=$OUT"; fi
run "$H" "$D" s1 '' blocking 2
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "blocking within grace allows (call 2)"; else fail "grace call 2: rc=$RC out=$OUT"; fi

# 3. Grace exhausted → deny with permissionDecision.
run "$H" "$D" s1 '' blocking 2
if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$OUT" >/dev/null 2>&1; then
  ok "grace exhausted denies"
else
  fail "grace exhausted: rc=$RC out=$OUT"
fi
if [[ "$OUT" == *handoff* ]]; then ok "deny reason routes to a handoff"; else fail "deny reason lacks handoff routing: $OUT"; fi

# 4. Handoff-path write exempt even past grace.
run "$H" "$D" s1 ',"tool_input":{"file_path":"/work/.work/handoffs/20260726-handoff-x.md"}' blocking 2
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "handoff-path write exempt"; else fail "handoff exempt: rc=$RC out=$OUT"; fi

# 5. Unknown zone (no snapshot) → fail-open, counter reset.
run "$H" "$D" nosuchsession '' blocking 2
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "unknown zone fails open"; else fail "unknown: rc=$RC out=$OUT"; fi

# 6. Leaving the dumb zone resets the counter.
write_snapshot "$H" s1 10
run "$H" "$D" s1 '' blocking 2
if [[ $RC -eq 0 && -z "$OUT" && ! -e "$D/state/s1.gate-count" ]]; then
  ok "smart zone allows and resets the grace counter"
else
  fail "smart reset: rc=$RC out=$OUT"
fi
write_snapshot "$H" s1 95
run "$H" "$D" s1 '' blocking 2
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "re-entering dumb starts a fresh grace budget"; else fail "fresh grace: rc=$RC out=$OUT"; fi

# 7. Kill switch wins over blocking mode.
OUT=$(printf '{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Write"}' |
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" CLAUDE_PLUGIN_OPTION_ZONE_HOOK_MODE=blocking \
    CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_HOOKS_ENABLED=false bash "$HOOK" 2>/dev/null)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch wins over blocking"; else fail "kill switch: rc=$RC out=$OUT"; fi

# 8. Hostile session id / empty stdin fail open.
run "$H" "$D" '../../etc' '' blocking 0
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "hostile session id fails open"; else fail "hostile sid: rc=$RC out=$OUT"; fi
OUT=$(printf '' | HOME="$H" CLAUDE_PLUGIN_DATA="$D" CLAUDE_PLUGIN_OPTION_ZONE_HOOK_MODE=blocking bash "$HOOK" 2>/dev/null)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "empty stdin fails open"; else fail "empty stdin: rc=$RC out=$OUT"; fi

# 9. Malformed grace value falls back to the in-script default (allows).
write_snapshot "$H" s9 95
run "$H" "$D" s9 '' blocking 'banana'
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "malformed grace falls back to default (call 1 allowed)"; else fail "malformed grace: rc=$RC out=$OUT"; fi

# 10. Large Write payload must still be denied (Win32-pipe single-read
# timeout made the gate fail open for exactly the biggest writes).
write_snapshot "$H" sbig 95
BIG=$(printf 'x%.0s' $(seq 1 130000))
OUT=$(printf '{"session_id":"sbig","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/w/big.txt","content":"%s"}}' "$BIG" |
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" HOOK_TELEMETRY_SINK=""     CLAUDE_PLUGIN_OPTION_ZONE_HOOK_MODE=blocking CLAUDE_PLUGIN_OPTION_ZONE_GATE_GRACE_CALLS=0 bash "$HOOK" 2>/dev/null)
RC=$?
if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$OUT" >/dev/null 2>&1; then
  ok "130KB Write payload still denied (chunked stdin read)"
else
  fail "large payload fail-open: rc=$RC out=${OUT:0:120}"
fi

# 11. Evidence-degraded marker: a green snapshot with the .compacted marker
# present is treated as dumb (reader contract: presence alone is the signal),
# so the gate stays armed after compaction resets the percentage.
write_snapshot "$H" smk 10
printf '{"compacted_at":"2026-07-26T00:00:00Z","trigger":"auto"}
' >"$H/$CTX_REL/smk.compacted"
run "$H" "$D" smk '' blocking 0
if jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$OUT" >/dev/null 2>&1; then
  ok "marker + smart snapshot still gates (evidence-degraded wins)"
else
  fail "marker ignored by gate: rc=$RC out=${OUT:0:120}"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
