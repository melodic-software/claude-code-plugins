#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/post-compact-mark.sh"

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
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# shellcheck source=hook-test-sink.sh
source "$SCRIPT_DIR/hook-test-sink.sh"

H="$WORK/home"
D="$WORK/data"
MARK="$H/.claude/context-usage/context"

run() {
  local payload="$1"
  shift
  printf '%s' "$payload" >"$WORK/stdin.json"
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" HOOK_TELEMETRY_SINK="" env "$@" bash "$HOOK" <"$WORK/stdin.json" 2>/dev/null
}

run '{"session_id":"s1","hook_event_name":"PostCompact","trigger":"auto"}'
RC=$?
if [[ $RC -eq 0 && -f "$MARK/s1.compacted" ]]; then ok "marker written (auto)"; else fail "marker missing: rc=$RC"; fi
if grep -q '"trigger":"auto"' "$MARK/s1.compacted" 2>/dev/null; then ok "trigger=auto recorded"; else fail "trigger not recorded"; fi
if grep -Eq '"compacted_at":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "$MARK/s1.compacted"; then
  ok "compacted_at is strict ISO-8601 UTC"
else
  fail "compacted_at malformed: $(cat "$MARK/s1.compacted" 2>/dev/null)"
fi
if command -v jq >/dev/null 2>&1; then
  if jq -e . "$MARK/s1.compacted" >/dev/null 2>&1; then ok "marker is valid JSON"; else fail "marker JSON invalid"; fi
fi

run '{"session_id":"s1","hook_event_name":"PostCompact","trigger":"manual"}'
if grep -q '"trigger":"manual"' "$MARK/s1.compacted" 2>/dev/null; then ok "manual overwrite (last-write-wins)"; else fail "manual overwrite failed"; fi

run '{"session_id":"s2","hook_event_name":"PostCompact","trigger":"weird"}'
if grep -q '"trigger":"unknown"' "$MARK/s2.compacted" 2>/dev/null; then ok "unrecognized trigger → unknown"; else fail "trigger sanitization failed"; fi

before=$(find "$MARK" -name '*.compacted' 2>/dev/null | wc -l)
run '{"hook_event_name":"PostCompact","trigger":"auto"}'
RC=$?
after=$(find "$MARK" -name '*.compacted' 2>/dev/null | wc -l)
if [[ $RC -eq 0 && "$before" == "$after" ]]; then ok "missing session id fails open"; else fail "missing sid: rc=$RC"; fi

run '{"session_id":"../../evil","hook_event_name":"PostCompact","trigger":"auto"}'
RC=$?
if [[ $RC -eq 0 && ! -e "$H/.claude/evil.compacted" && ! -e "$H/.claude/context-usage/evil.compacted" ]]; then
  ok "hostile session id fails open (no traversal)"
else
  fail "hostile sid: rc=$RC"
fi

run '{"session_id":"s4","hook_event_name":"PostCompact","trigger":"auto"}' CLAUDE_PLUGIN_OPTION_CONTEXT_USAGE_HOOKS_ENABLED=false
RC=$?
if [[ $RC -eq 0 && ! -e "$MARK/s4.compacted" ]]; then ok "kill switch suppresses the marker"; else fail "kill switch: rc=$RC"; fi

run ''
RC=$?
if [[ $RC -eq 0 ]]; then ok "empty stdin fails open"; else fail "empty stdin: rc=$RC"; fi

BIG=$(printf 'x%.0s' $(seq 1 150000))
run "{\"session_id\":\"sbig\",\"hook_event_name\":\"PostCompact\",\"trigger\":\"auto\",\"compact_summary\":\"$BIG\"}"
RC=$?
if [[ $RC -eq 0 && -f "$MARK/sbig.compacted" ]]; then ok "marker written for a 150KB payload"; else fail "large payload: rc=$RC marker=$([[ -f "$MARK/sbig.compacted" ]] && echo yes || echo no)"; fi

printf '{"compacted_at":"2020-01-01T00:00:00Z","trigger":"auto"}
' >"$MARK/sold.compacted"
if command -v touch >/dev/null 2>&1; then
  touch -d '30 days ago' "$MARK/sold.compacted" 2>/dev/null || touch -t 202001010000 "$MARK/sold.compacted" 2>/dev/null || true
fi
run '{"session_id":"sprune","hook_event_name":"PostCompact","trigger":"auto"}'
if [[ ! -e "$MARK/sold.compacted" && -f "$MARK/sprune.compacted" ]]; then
  ok "stale markers pruned on write (14-day cutoff)"
else
  fail "stale marker not pruned"
fi

BLOCKED="$MARK/sfail.compacted"
mkdir -p "$BLOCKED"
TEL="$WORK/tel-fail.json"
SINK="$(make_sink "cat >\"$TEL\"")"
printf '{"session_id":"sfail","hook_event_name":"PostCompact","trigger":"auto"}' |
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" HOOK_TELEMETRY_SINK="$SINK" bash "$HOOK" >/dev/null 2>&1
RC=$?
if [[ $RC -eq 0 ]]; then ok "marker persist failure still exits 0"; else fail "marker persist failure: rc=$RC"; fi
if wait_for_sink "$TEL" && [[ "$(jq -r '.status' "$TEL" 2>/dev/null)" == "error" ]]; then
  ok "marker persist failure reports telemetry status=error"
else
  fail "telemetry status not error: $(cat "$TEL" 2>/dev/null)"
fi
if [[ -z "$(ls -A "$BLOCKED" 2>/dev/null)" ]]; then
  ok "no temp file stranded at the blocked contract path"
else
  fail "temp file stranded at blocked path: $(ls -A "$BLOCKED")"
fi

FB_LOG="$WORK/compact-xtrace-fallback.log"
(
  # shellcheck disable=SC2329,SC2059 # imported by the child bash, not called here; forwards the caller's format verbatim
  printf() {
    if [[ "${1:-}" == "-v" && "${3:-}" == *'%('*')T'* ]]; then return 1; fi
    builtin printf "$@"
  }
  export -f printf
  builtin printf '%s' '{"session_id":"sfb","hook_event_name":"PostCompact","trigger":"auto"}' |
    HOME="$H" CLAUDE_PLUGIN_DATA="$D" HOOK_TELEMETRY_SINK="" \
      BASH_XTRACEFD=9 bash -x "$HOOK" >/dev/null 2>/dev/null 9>"$FB_LOG"
)
if grep -Eq '"compacted_at":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "$MARK/sfb.compacted" 2>/dev/null; then
  ok "fallback: compacted_at is still strict ISO-8601 UTC when printf has no %()T"
else
  fail "fallback: compacted_at without %()T: $(cat "$MARK/sfb.compacted" 2>/dev/null)"
fi
FB_DATE=$(grep -cE '^\++ date ' "$FB_LOG" 2>/dev/null | tr -cd '0-9') # portability-ok: the word date is a grep pattern over an xtrace log, not a date call; -cd is tr's flag
if [[ "$FB_DATE" == "1" ]]; then
  ok "fallback: the timestamp comes from exactly one date process there"
else
  fail "fallback: $FB_DATE date process(es) without %()T, want exactly 1 (shim not imported?)"
fi

run '{"session_id":"ssub","hook_event_name":"PostCompact","trigger":"auto","agent_id":"agent-abc123","agent_type":"Explore"}'
RC=$?
if [[ $RC -eq 0 && ! -e "$MARK/ssub.compacted" ]]; then
  ok "subagent compaction (agent_id set) writes no main-session marker"
else
  fail "subagent compaction: rc=$RC marker=$([[ -e "$MARK/ssub.compacted" ]] && echo yes || echo no)"
fi
run '{"session_id":"smain","hook_event_name":"PostCompact","trigger":"auto","agent_type":"reviewer"}'
RC=$?
if [[ $RC -eq 0 && -f "$MARK/smain.compacted" ]]; then
  ok "main-session compaction under --agent (agent_type, no agent_id) still writes the marker"
else
  fail "main-session compaction under --agent: rc=$RC"
fi
run '{"session_id":"ssum","hook_event_name":"PostCompact","trigger":"auto","compact_summary":"quoted \"agent_id\":\"agent-x\" text"}'
if [[ -f "$MARK/ssum.compacted" ]]; then
  ok "an escaped agent_id inside compact_summary does not suppress the marker"
else
  fail "escaped agent_id in compact_summary suppressed the marker"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
