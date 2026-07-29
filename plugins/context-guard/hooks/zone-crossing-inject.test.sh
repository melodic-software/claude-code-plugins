#!/usr/bin/env bash
# Contract test for zone-crossing-inject.sh (PostToolBatch/UserPromptSubmit).
#
# Contract: inject additionalContext ONCE per transition into a WORSE zone;
# silent while the zone is unchanged, improving, or unknown; unknown never
# updates state; kill switch honored; hostile ids fail open. Exit 0 always.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/zone-crossing-inject.sh"

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

# write_snapshot <home> <sid> <used_percentage>
write_snapshot() {
  local home="$1" sid="$2" used="$3"
  mkdir -p "$home/$CTX_REL"
  printf '{"captured_at":"%s","session_id":"%s","context_window":{"used_percentage":%s,"remaining_percentage":50,"current_usage":{"input_tokens":100}}}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$sid" "$used" >"$home/$CTX_REL/$sid.json"
}

# run <home> <data-dir> <sid> [<event>] → stdout captured to $OUT, rc to $RC
OUT=""
RC=0
run() {
  local home="$1" data="$2" sid="$3" event="${4:-PostToolBatch}"
  OUT=$(printf '{"session_id":"%s","hook_event_name":"%s","cwd":"/tmp"}' "$sid" "$event" |
    HOME="$home" CLAUDE_PLUGIN_DATA="$data" HOOK_TELEMETRY_SINK="" bash "$HOOK" 2>/dev/null)
  RC=$?
}

H="$WORK/home"
D="$WORK/data"

# 1. First observation in the dumb zone (no prior state) injects.
write_snapshot "$H" s1 90
run "$H" "$D" s1
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *dumb* ]]; then
  ok "first-seen dumb injects additionalContext"
else
  fail "first-seen dumb: rc=$RC out=$OUT"
fi
if jq -e '.hookSpecificOutput.hookEventName == "PostToolBatch"' <<<"$OUT" >/dev/null 2>&1; then
  ok "injection is valid JSON carrying the firing event name"
else
  fail "injection JSON invalid: $OUT"
fi

# 2. Same zone again → silent (once per transition).
run "$H" "$D" s1
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "unchanged zone is silent"; else fail "unchanged zone: rc=$RC out=$OUT"; fi

# 3. Improvement (dumb → smart) → silent, state updated.
write_snapshot "$H" s1 10
run "$H" "$D" s1
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "improvement is silent"; else fail "improvement: rc=$RC out=$OUT"; fi
if [[ "$(cat "$D/state/s1.zone" 2>/dev/null)" == "smart" ]]; then
  ok "improvement still updates state"
else
  fail "state not updated on improvement"
fi

# 4. Relapse after improvement (smart → acceptable) injects again.
write_snapshot "$H" s1 60
run "$H" "$D" s1 UserPromptSubmit
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *acceptable* ]]; then
  ok "relapse injects again (UserPromptSubmit)"
else
  fail "relapse: rc=$RC out=$OUT"
fi

# 5. Unknown zone (no snapshot) → silent, state untouched.
run "$H" "$D" nosuchsession
if [[ $RC -eq 0 && -z "$OUT" && ! -e "$D/state/nosuchsession.zone" ]]; then
  ok "unknown zone is silent and stateless"
else
  fail "unknown zone: rc=$RC out=$OUT"
fi

# 6. Kill switch honored.
write_snapshot "$H" s2 90
OUT=$(printf '{"session_id":"s2","hook_event_name":"PostToolBatch"}' |
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_HOOKS_ENABLED=false bash "$HOOK" 2>/dev/null)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch silences the hook"; else fail "kill switch: rc=$RC out=$OUT"; fi

# 7. Hostile session id → silent exit 0, no state write.
OUT=$(printf '{"session_id":"../../etc","hook_event_name":"PostToolBatch"}' |
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" bash "$HOOK" 2>/dev/null)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "hostile session id fails open"; else fail "hostile sid: rc=$RC out=$OUT"; fi

# 8. Empty stdin → silent exit 0.
OUT=$(printf '' | HOME="$H" CLAUDE_PLUGIN_DATA="$D" bash "$HOOK" 2>/dev/null)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "empty stdin fails open"; else fail "empty stdin: rc=$RC out=$OUT"; fi

# 9. Injection body stays under the documented 10k output cap.
write_snapshot "$H" s3 90
run "$H" "$D" s3
LEN=${#OUT}
if ((LEN > 0 && LEN < 10000)); then ok "injection length $LEN under 10k cap"; else fail "injection length $LEN"; fi

# 10. Large PostToolBatch payload (serialized tool_calls) must not suppress
# a due injection (Win32-pipe single-read timeout regression guard).
write_snapshot "$H" sbig 90
BIG=$(printf 'x%.0s' $(seq 1 150000))
OUT=$(printf '{"session_id":"sbig","hook_event_name":"PostToolBatch","tool_calls":[{"tool_name":"Read","tool_response":"%s"}]}' "$BIG" |
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" HOOK_TELEMETRY_SINK="" bash "$HOOK" 2>/dev/null)
RC=$?
if [[ $RC -eq 0 && "$OUT" == *additionalContext* ]]; then
  ok "150KB batch payload still injects (chunked stdin read)"
else
  fail "large payload suppressed injection: rc=$RC out=${OUT:0:120}"
fi

# 11. Evidence-degraded marker: green snapshot + .compacted marker is treated
# as dumb — one injection fires (and mentions the degradation), then silence.
write_snapshot "$H" smk 10
printf '{"compacted_at":"2026-07-26T00:00:00Z","trigger":"auto"}
' >"$H/$CTX_REL/smk.compacted"
run "$H" "$D" smk
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *degraded* ]]; then
  ok "marker + smart snapshot injects the evidence-degraded notice once"
else
  fail "marker ignored by inject: rc=$RC out=${OUT:0:120}"
fi
run "$H" "$D" smk
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "marker-driven dumb state stays silent on repeat"
else
  fail "marker repeat not silent: rc=$RC out=${OUT:0:120}"
fi

# 12. State-persist failure (e.g. full/read-only filesystem) fails open
# SILENTLY — no additionalContext, exit 0 — rather than falling through and
# comparing against the same stale `last` again on every subsequent call.
# The failure itself is still surfaced as telemetry status=error, never
# swallowed twice. Simulated portably (no chmod/permission dependence): a
# directory sitting at the exact state-file path makes the write fail on
# every platform, including Git Bash on Windows.
make_sink() {
  local s
  s="$(mktemp "$WORK/sink.XXXXXX")"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'cat >%q\n' "$1"
  } >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}
wait_for_sink() {
  local f="$1" tries=150
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

write_snapshot "$H" spersist 90
mkdir -p "$D/state"
mkdir -p "$D/state/spersist.zone" # a directory blocks the write, not a permission bit
TEL="$WORK/tel-persist.json"
SINK="$(make_sink "$TEL")"
OUT=$(printf '{"session_id":"spersist","hook_event_name":"PostToolBatch"}' |
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" HOOK_TELEMETRY_SINK="$SINK" bash "$HOOK" 2>/dev/null)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "state-persist failure fails open silently (no additionalContext)"
else
  fail "state-persist failure: rc=$RC out=${OUT:0:120}"
fi
if wait_for_sink "$TEL" && [[ "$(jq -r '.status' "$TEL" 2>/dev/null)" == "error" ]]; then
  ok "state-persist failure reports telemetry status=error"
else
  fail "telemetry status not error: $(cat "$TEL" 2>/dev/null)"
fi

# No resolvable state root → stay silent rather than key the last-seen zone to
# the working directory, which would re-inject on every cd.
write_snapshot "$WORK/nohome" snr 90
NR_OUT=$(printf '{"session_id":"snr","hook_event_name":"PostToolBatch"}' |
  env -u HOME -u CLAUDE_PLUGIN_DATA HOOK_TELEMETRY_SINK="" bash "$HOOK" 2>/dev/null)
NR_RC=$?
if [[ $NR_RC -eq 0 && -z "$NR_OUT" ]]; then
  ok "no HOME and no CLAUDE_PLUGIN_DATA stays silent"
else
  fail "no state root: rc=$NR_RC out=${NR_OUT:0:120}"
fi
if [[ ! -e "./.claude/context-guard/state" ]]; then
  ok "no zone state written relative to the working directory"
else
  fail "zone state leaked into the working directory"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
