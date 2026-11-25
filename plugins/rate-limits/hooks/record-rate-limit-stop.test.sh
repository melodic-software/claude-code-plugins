#!/usr/bin/env bash
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

EVENTS_REL=".claude/rate-limits/stop-events.jsonl"

build_input() {
  local session="$1"
  printf '{"session_id":"%s","hook_event_name":"StopFailure","cwd":"/tmp/x"}' "$session"
}

count_records() {
  wc -l <"$1" | tr -d ' \r'
}

run() {
  local home="$1" input="$2"
  shift 2
  printf '%s' "$input" >"$WORK/stdin.json"
  env -u CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED \
    HOME="$home" \
    "$@" \
    bash "$HOOK" <"$WORK/stdin.json" 2>&1
}

HOME1="$WORK/home1"
mkdir -p "$HOME1"
OUT="$(run "$HOME1" "$(build_input s-kill)" CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED=false)"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch false → silent exit 0"; else fail "kill switch (rc=$RC out=$OUT)"; fi
if [[ ! -e "$HOME1/$EVENTS_REL" ]]; then ok "kill switch false → no record written"; else fail "kill switch false → record written"; fi

HOME2="$WORK/home2"
mkdir -p "$HOME2"
OUT="$(run "$HOME2" "$(build_input s-abc-123)")"
RC=$?
EVENTS="$HOME2/$EVENTS_REL"
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "payload run → silent exit 0"; else fail "payload run (rc=$RC out=$OUT)"; fi
if [[ -f "$EVENTS" ]]; then ok "record file created at contract path"; else fail "record file missing: $EVENTS"; fi
LINES=$(count_records "$EVENTS")
if [[ "$LINES" == "1" ]]; then ok "exactly one record appended"; else fail "record count $LINES, want 1"; fi
if jq -e . <"$EVENTS" >/dev/null 2>&1; then ok "record is valid JSON"; else fail "record not valid JSON: $(cat "$EVENTS")"; fi
if [[ "$(jq -r '.session_id' <"$EVENTS")" == "s-abc-123" ]]; then ok "session_id recorded"; else fail "session_id = $(jq -r '.session_id' <"$EVENTS")"; fi
if [[ "$(jq -r '.matcher' <"$EVENTS")" == "rate_limit" ]]; then ok "matcher recorded"; else fail "matcher = $(jq -r '.matcher' <"$EVENTS")"; fi
if [[ "$(jq -r '.hook_event_name' <"$EVENTS")" == "StopFailure" ]]; then ok "hook_event_name recorded"; else fail "hook_event_name = $(jq -r '.hook_event_name' <"$EVENTS")"; fi
if grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' < <(jq -r '.detected_at' <"$EVENTS"); then
  ok "detected_at is ISO-8601 UTC"
else
  fail "detected_at = $(jq -r '.detected_at' <"$EVENTS")"
fi

run "$HOME2" "$(build_input s-second)" >/dev/null
LINES=$(count_records "$EVENTS")
if [[ "$LINES" == "2" ]]; then ok "second invocation appends (2 records)"; else fail "record count $LINES, want 2"; fi
if [[ "$(tail -n 1 "$EVENTS" | jq -r '.session_id')" == "s-second" ]]; then ok "newest record last"; else fail "newest record wrong: $(tail -n 1 "$EVENTS")"; fi

HOME4="$WORK/home4"
mkdir -p "$HOME4"
OUT="$(env -u CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED HOME="$HOME4" bash "$HOOK" </dev/null 2>&1)"
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

HOME5="$WORK/home5"
mkdir -p "$HOME5"
run "$HOME5" '{"session_id":"a\"b\\c","hook_event_name":"StopFailure"}' >/dev/null
EVENTS5="$HOME5/$EVENTS_REL"
if jq -e . <"$EVENTS5" >/dev/null 2>&1; then ok "escaped session_id → record valid JSON"; else fail "escaped session_id broke record: $(cat "$EVENTS5" 2>/dev/null)"; fi

HOME6="$WORK/home6"
mkdir -p "$HOME6/.claude/rate-limits"
EVENTS6="$HOME6/$EVENTS_REL"
for ((i = 0; i < 250; i++)); do printf '{"detected_at":"old-%s"}\n' "$i"; done >"$EVENTS6"
run "$HOME6" "$(build_input s-rotated)" >/dev/null
LINES=$(count_records "$EVENTS6")
if [[ "$LINES" =~ ^[0-9]+$ ]] && ((LINES <= 150)); then ok "rotation bounds the file ($LINES lines)"; else fail "rotation did not bound the file ($LINES lines)"; fi
if grep -q 's-rotated' "$EVENTS6"; then ok "rotation keeps the newest record"; else fail "rotation dropped the newest record"; fi

HOME7="$WORK/home7"
mkdir -p "$HOME7"
: >"$HOME7/.claude"
OUT="$(run "$HOME7" "$(build_input s-blocked)")"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "uncreatable contract dir → silent exit 0"; else fail "uncreatable dir (rc=$RC out=$OUT)"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
