#!/usr/bin/env bash
# Black-box contract test for record-rate-limit-stop.sh (the rate-limit-guard
# StopFailure hook).
#
# Proves the side-effect contract: kill switch, one appended JSONL detection
# record per invocation at the fixed contract path (HOME-anchored, so tests
# redirect via HOME), jq-free operation, degraded-payload tolerance (empty
# stdin still records — the event firing IS the signal), size rotation, and
# silent exit 0 when the contract directory cannot be created. The harness
# ignores StopFailure output and exit codes, so the record file is the only
# observable surface.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/record-rate-limit-stop.sh"

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

EVENTS_REL=".claude/rate-limit-guard/stop-events.jsonl"

build_input() {
  local session="$1"
  printf '{"session_id":"%s","hook_event_name":"StopFailure","cwd":"/tmp/x"}' "$session"
}

# Runner: fresh-HOME-scoped hook invocation with the kill switch enabled unless
# the caller overrides it. Output and exit code are captured even though the
# harness ignores them — the hook must still be silent and exit 0.
run() {
  local home="$1" input="$2"
  shift 2
  printf '%s' "$input" |
    env -u CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED \
      HOME="$home" \
      "$@" \
      bash "$HOOK" 2>&1
}

# --- Case 1: kill switch false → silent exit 0, nothing written --------------
HOME1="$WORK/home1"
mkdir -p "$HOME1"
OUT="$(run "$HOME1" "$(build_input s-kill)" CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED=false)"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch false → silent exit 0"; else fail "kill switch (rc=$RC out=$OUT)"; fi
if [[ ! -e "$HOME1/$EVENTS_REL" ]]; then ok "kill switch false → no record written"; else fail "kill switch false → record written"; fi

# --- Case 2: payload → one valid JSONL record with contract fields -----------
HOME2="$WORK/home2"
mkdir -p "$HOME2"
OUT="$(run "$HOME2" "$(build_input s-abc-123)")"
RC=$?
EVENTS="$HOME2/$EVENTS_REL"
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "payload run → silent exit 0"; else fail "payload run (rc=$RC out=$OUT)"; fi
if [[ -f "$EVENTS" ]]; then ok "record file created at contract path"; else fail "record file missing: $EVENTS"; fi
LINES=$(wc -l <"$EVENTS" | tr -d ' \r')
if [[ "$LINES" == "1" ]]; then ok "exactly one record appended"; else fail "record count $LINES, want 1"; fi
if jq -e . <"$EVENTS" >/dev/null 2>&1; then ok "record is valid JSON"; else fail "record not valid JSON: $(cat "$EVENTS")"; fi
if [[ "$(jq -r '.session_id' <"$EVENTS")" == "s-abc-123" ]]; then ok "session_id recorded"; else fail "session_id = $(jq -r '.session_id' <"$EVENTS")"; fi
if [[ "$(jq -r '.matcher' <"$EVENTS")" == "rate_limit" ]]; then ok "matcher recorded"; else fail "matcher = $(jq -r '.matcher' <"$EVENTS")"; fi
if [[ "$(jq -r '.hook_event_name' <"$EVENTS")" == "StopFailure" ]]; then ok "hook_event_name recorded"; else fail "hook_event_name = $(jq -r '.hook_event_name' <"$EVENTS")"; fi
if jq -r '.detected_at' <"$EVENTS" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  ok "detected_at is ISO-8601 UTC"
else
  fail "detected_at = $(jq -r '.detected_at' <"$EVENTS")"
fi

# --- Case 3: second invocation appends ---------------------------------------
run "$HOME2" "$(build_input s-second)" >/dev/null
LINES=$(wc -l <"$EVENTS" | tr -d ' \r')
if [[ "$LINES" == "2" ]]; then ok "second invocation appends (2 records)"; else fail "record count $LINES, want 2"; fi
if [[ "$(tail -n 1 "$EVENTS" | jq -r '.session_id')" == "s-second" ]]; then ok "newest record last"; else fail "newest record wrong: $(tail -n 1 "$EVENTS")"; fi

# --- Case 4: empty stdin → still records (event firing is the signal) --------
HOME4="$WORK/home4"
mkdir -p "$HOME4"
OUT="$(env -u CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED HOME="$HOME4" bash "$HOOK" </dev/null 2>&1)"
RC=$?
EVENTS4="$HOME4/$EVENTS_REL"
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "empty stdin → silent exit 0"; else fail "empty stdin (rc=$RC out=$OUT)"; fi
if [[ -f "$EVENTS4" ]] && jq -e '.detected_at' <"$EVENTS4" >/dev/null 2>&1; then
  ok "empty stdin → record still written with detected_at"
else
  fail "empty stdin → no usable record: $(cat "$EVENTS4" 2>/dev/null)"
fi
if jq -e 'has("session_id") | not' <"$EVENTS4" >/dev/null 2>&1; then
  ok "empty stdin → session_id omitted, not fabricated"
else
  fail "empty stdin → session_id = $(jq -r '.session_id' <"$EVENTS4")"
fi

# --- Case 5: hostile session_id is JSON-escaped, record stays parseable ------
HOME5="$WORK/home5"
mkdir -p "$HOME5"
run "$HOME5" '{"session_id":"a\"b\\c","hook_event_name":"StopFailure"}' >/dev/null
EVENTS5="$HOME5/$EVENTS_REL"
if jq -e . <"$EVENTS5" >/dev/null 2>&1; then ok "escaped session_id → record valid JSON"; else fail "escaped session_id broke record: $(cat "$EVENTS5" 2>/dev/null)"; fi

# --- Case 6: rotation bounds the file ----------------------------------------
HOME6="$WORK/home6"
mkdir -p "$HOME6/.claude/rate-limit-guard"
EVENTS6="$HOME6/$EVENTS_REL"
for ((i = 0; i < 250; i++)); do printf '{"detected_at":"old-%s"}\n' "$i"; done >"$EVENTS6"
run "$HOME6" "$(build_input s-rotated)" >/dev/null
LINES=$(wc -l <"$EVENTS6" | tr -d ' \r')
if [[ "$LINES" =~ ^[0-9]+$ ]] && ((LINES <= 150)); then ok "rotation bounds the file ($LINES lines)"; else fail "rotation did not bound the file ($LINES lines)"; fi
if grep -q 's-rotated' "$EVENTS6"; then ok "rotation keeps the newest record"; else fail "rotation dropped the newest record"; fi

# --- Case 7: contract dir cannot be created → silent exit 0 ------------------
HOME7="$WORK/home7"
mkdir -p "$HOME7"
: >"$HOME7/.claude" # a FILE where the directory belongs → mkdir -p fails
OUT="$(run "$HOME7" "$(build_input s-blocked)")"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "uncreatable contract dir → silent exit 0"; else fail "uncreatable dir (rc=$RC out=$OUT)"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
