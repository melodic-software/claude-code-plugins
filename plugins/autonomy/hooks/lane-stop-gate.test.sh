#!/usr/bin/env bash
# test-scope: plugins/autonomy/hooks/*.sh
# test-scope: plugins/autonomy/hooks/hooks.json

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

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

CACHE_ROOT="$(mktemp -d "$WORK/install.XXXXXX")"
STAGED_DIR="$CACHE_ROOT/plugins/cache/melodic/autonomy/9.9.9/hooks"
mkdir -p "$STAGED_DIR"
cp "$HOOK_DIR"/*.sh "$STAGED_DIR/"
HOOK="$STAGED_DIR/lane-stop-gate.sh"
ARM="$STAGED_DIR/lane-stop-gate-arm.sh"
PLUGIN_ID="autonomy@melodic"
SETTINGS="$CACHE_ROOT/settings.json"
DATA_DIR="$CACHE_ROOT/plugins/data/autonomy-melodic"

build_input() {
  local event="${1:-Stop}" last="${2:-}" stop_active="${3:-false}" cwd="${4:-}" sess="${5:-test-sess}"
  MSYS_NO_PATHCONV=1 jq -n \
    --arg e "$event" --arg l "$last" --argjson s "$stop_active" --arg c "$cwd" --arg sid "$sess" \
    '{hook_event_name:$e, last_assistant_message:$l, stop_hook_active:$s, cwd:$c, session_id:$sid}'
}

write_settings() {
  local enabled="$1" ss="${2:-0}" sentinel="${3:-}" ms="${4:-0}" marker="${5:-}"
  jq -n --arg id "$PLUGIN_ID" --argjson e "$enabled" \
    --argjson ss "$ss" --arg s "$sentinel" --argjson ms "$ms" --arg m "$marker" \
    '{pluginConfigs: {($id): {options: (
        {lane_stop_gate_enabled: $e}
        + (if $ss == 1 then {lane_stop_gate_sentinel: $s} else {} end)
        + (if $ms == 1 then {lane_stop_gate_marker: $m} else {} end))}}}' \
    >"$SETTINGS"
}

run() {
  local input="$1"
  shift
  local enabled="true" sentinel="" marker="" ss=0 ms=0
  local -a extra=()
  local kv
  for kv in "$@"; do
    case "$kv" in
    CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=*) enabled="${kv#*=}" ;;
    CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL=*)
      sentinel="${kv#*=}"
      ss=1
      ;;
    CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER=*)
      marker="${kv#*=}"
      ms=1
      ;;
    RAWENV_*) extra+=("${kv#RAWENV_}") ;;
    *) extra+=("$kv") ;;
    esac
  done
  local ejson=false
  [[ "$enabled" == "true" ]] && ejson=true
  write_settings "$ejson" "$ss" "$sentinel" "$ms" "$marker"
  local -a mirror=(CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED="$enabled")
  ((ss)) && mirror+=(CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="$sentinel")
  ((ms)) && mirror+=(CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$marker")
  (cd "$UNRELATED" && printf '%s' "$input" |
    env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
      -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
      -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID \
      -u CLAUDE_PLUGIN_DATA \
      CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
      "${mirror[@]}" \
      ${extra[@]+"${extra[@]}"} \
      bash "$HOOK" 2>/dev/null)
}

run_bare() {
  local input="$1"
  shift
  rm -f "$SETTINGS"
  (cd "$UNRELATED" && env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
    -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
    -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
    -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID \
    -u CLAUDE_PLUGIN_DATA \
    CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
    "$@" \
    bash "$HOOK" < <(printf '%s' "$input") 2>/dev/null)
}

is_block() { printf '%s' "$1" | jq -e '.decision == "block"' >/dev/null 2>&1; }

OUT="$(run_bare "$(build_input Stop "" false)")"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "default OFF → silent exit 0 (interactive-safe)"; else fail "default OFF (rc=$RC out=$OUT)"; fi

OUT="$(run "$(build_input Stop "working on it" false)")"
RC=$?
if [[ $RC -eq 0 ]]; then ok "first stop no-signal: exit 0"; else fail "first stop no-signal exit $RC"; fi
if is_block "$OUT"; then ok "first stop no-signal → decision:block"; else fail "first stop no-signal → not blocked: $OUT"; fi
if grep -q 'LANE-STOP-OK' < <(jq -re '.reason' <<<"$OUT"); then ok "block reason names the sentinel"; else fail "block reason missing sentinel: $OUT"; fi

OUT="$(run "$(build_input Stop "All queue items cleared.
LANE-STOP-OK" false)")"
if is_block "$OUT"; then fail "sentinel on its own line → still blocked: $OUT"; else ok "sentinel on its own line → stop allowed (no block)"; fi

OUT="$(run "$(build_input Stop "status: LANE-STOP-OKAYISH maybe" false)")"
if is_block "$OUT"; then ok "sentinel-as-substring → not a signal, blocked"; else fail "sentinel-as-substring wrongly allowed: $OUT"; fi

MARK="$WORK/done.marker"
: >"$MARK"
OUT="$(run "$(build_input Stop "no token here" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$MARK")"
if is_block "$OUT"; then fail "marker present → still blocked: $OUT"; else ok "marker file present → stop allowed"; fi
if [[ -f "$MARK" ]]; then fail "marker not consumed after authorizing a stop"; else ok "marker consumed on use"; fi
OUT="$(run "$(build_input Stop "no token here" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$MARK")"
if is_block "$OUT"; then ok "consumed marker no longer authorizes the next stop"; else fail "stale marker path wrongly allowed after consumption: $OUT"; fi
rm -f "$MARK"

OUT="$(run "$(build_input Stop "no token here" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$WORK/never.marker")"
if is_block "$OUT"; then ok "marker absent → blocked"; else fail "marker absent wrongly allowed: $OUT"; fi

REPO="$WORK/lane"
mkdir -p "$REPO"
: >"$REPO/complete"
OUT="$(run "$(build_input Stop "" false "$REPO")" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="complete")"
if is_block "$OUT"; then fail "relative marker under cwd → still blocked: $OUT"; else ok "relative marker resolves against cwd → allowed"; fi
rm -rf "$REPO"

OUT="$(run "$(build_input Stop "still no token" true)")"
RC=$?
if [[ $RC -eq 0 ]]; then ok "post-nudge stop: exit 0"; else fail "post-nudge stop exit $RC"; fi
if is_block "$OUT"; then fail "post-nudge stop → blocked again (would risk runaway): $OUT"; else ok "post-nudge stop → allowed (no second block)"; fi

OUT="$(run "$(build_input SubagentStop "no token" false)")"
if is_block "$OUT"; then fail "SubagentStop → blocked (must not gate subagents): $OUT"; else ok "SubagentStop event → not gated"; fi

write_settings true
OUT="$(cd "$UNRELATED" && env CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true bash "$HOOK" </dev/null 2>&1)"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "empty stdin → silent exit 0 (fail-open)"; else fail "empty stdin (rc=$RC out=$OUT)"; fi

OUT="$(run "$(build_input Stop "queue empty
DONE-ROTATE" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="DONE-ROTATE")"
if is_block "$OUT"; then fail "custom sentinel → still blocked: $OUT"; else ok "custom sentinel honored → allowed"; fi

FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash dirname cat env printf mktemp mkdir find tr grep sed uname sleep git awk date; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
JQ_DATA="$(mktemp -d "$WORK/plugdata.XXXXXX")"
write_settings true
OUT_NOJQ="$(cd "$UNRELATED" && printf '{"session_id":"nojq-1","hook_event_name":"Stop","stop_hook_active":false}' |
  env -i PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA" \
    CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true bash "$HOOK" 2>/dev/null)"
RC=$?
if [[ $RC -eq 0 && "$OUT_NOJQ" == *'"systemMessage"'* && "$OUT_NOJQ" == *jq* ]]; then
  ok "jq-absent → exit 0 with visible systemMessage notice (fail-open)"
else
  fail "jq-absent (rc=$RC out=$OUT_NOJQ)"
fi
if [[ "$OUT_NOJQ" == *additionalContext* ]]; then fail "jq-absent notice reached the model on Stop: $OUT_NOJQ"; else ok "jq-absent notice is user-only on Stop"; fi

OUT="$(run "$(build_input Stop "I should not emit LANE-STOP-OK yet" false)")"
if is_block "$OUT"; then ok "inline mention/negation of sentinel → not a signal, blocked"; else fail "inline sentinel mention wrongly allowed: $OUT"; fi

OUT="$(run "$(build_input Stop "Goal verified, tests green.
  LANE-STOP-OK
(stopping now)" false)")"
if is_block "$OUT"; then fail "sentinel alone on its line (indented) → wrongly blocked: $OUT"; else ok "sentinel alone on its own line (whitespace ok) → stop allowed"; fi

build_big_input() {
  jq -Rs \
    '{hook_event_name:"Stop", last_assistant_message:., stop_hook_active:false, cwd:"", session_id:"test-sess"}' \
    <"$1"
}
BIGFILE="$WORK/bigmsg.txt"
{
  printf 'LANE-STOP-OK\n'
  head -c 120000 /dev/zero | tr '\0' 'x'
} >"$BIGFILE"
head -c 120000 /dev/zero | tr '\0' 'x' >"$BIGFILE.nosig"
OUT="$(run "$(build_big_input "$BIGFILE.nosig")" CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=30)"
if is_block "$OUT"; then ok "~120KB message without sentinel → blocked (long payload really evaluated)"; else fail "long-message control not blocked — long payload not reaching the gate: $OUT"; fi
OUT="$(run "$(build_big_input "$BIGFILE")" CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=30)"
if is_block "$OUT"; then fail "early sentinel in long message → wrongly blocked (pipefail/SIGPIPE): $OUT"; else ok "early sentinel in ~120KB message → stop allowed (no SIGPIPE loss)"; fi

# shellcheck source=hook-test-sink.sh
source "$HOOK_DIR/hook-test-sink.sh"

TEL="$WORK/tel-block.jsonl"
SINK="$(make_sink "cat >>\"$TEL\"")"
OUT="$(run "$(build_input Stop "no token" false)" HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$WORK")"
if is_block "$OUT"; then ok "telemetry block case still blocks"; else fail "telemetry block case not blocked: $OUT"; fi
if wait_for_sink "$TEL"; then
  if jq -e '.hook=="lane-stop-gate" and .status=="blocked" and .data.outcome=="nudged" and .data.signal=="none" and (.duration_ms|type)=="number"' "$TEL" >/dev/null 2>&1; then
    ok "telemetry on block: envelope hook/status/outcome/signal/duration correct"
  else
    fail "telemetry on block: bad envelope: $(cat "$TEL")"
  fi
  if grep -q "LANE-STOP-OK" "$TEL"; then fail "telemetry envelope leaks the sentinel token"; else ok "telemetry envelope carries no sentinel token"; fi
else
  fail "telemetry on block: no envelope written"
fi

TEL="$WORK/tel-ok.jsonl"
SINK="$(make_sink "cat >>\"$TEL\"")"
OUT="$(run "$(build_input Stop "LANE-STOP-OK" false)" HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$WORK")"
if is_block "$OUT"; then fail "telemetry signaled case wrongly blocked: $OUT"; fi
if wait_for_sink "$TEL" && jq -e '.status=="ok" and .data.outcome=="completion-signaled" and .data.signal=="sentinel"' "$TEL" >/dev/null 2>&1; then
  ok "telemetry on signaled allow: ok/completion-signaled/sentinel"
else
  fail "telemetry on signaled allow: bad or missing envelope: $(cat "$TEL" 2>/dev/null)"
fi

TEL="$WORK/tel-nudge.jsonl"
SINK="$(make_sink "cat >>\"$TEL\"")"
OUT="$(run "$(build_input Stop "still no token" true)" HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$WORK")"
if is_block "$OUT"; then fail "telemetry post-nudge case wrongly blocked: $OUT"; fi
if wait_for_sink "$TEL" && jq -e '.status=="ok" and .data.outcome=="stopped-after-nudge" and .data.signal=="none"' "$TEL" >/dev/null 2>&1; then
  ok "telemetry on post-nudge allow: ok/stopped-after-nudge/none"
else
  fail "telemetry on post-nudge allow: bad or missing envelope: $(cat "$TEL" 2>/dev/null)"
fi

RMFAIL="$(mktemp -d "$WORK/rmfail.XXXXXX")"
printf '#!/bin/sh\nexit 1\n' >"$RMFAIL/rm"
chmod +x "$RMFAIL/rm"
STICKY="$WORK/sticky.marker"
: >"$STICKY"
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STICKY" \
  PATH="$RMFAIL:$PATH")"
if is_block "$OUT"; then fail "marker present with a failing rm → still blocked: $OUT"; else ok "marker present with a failing rm → stop allowed"; fi
if [[ -f "$STICKY" ]]; then ok "the rm stub really prevented the delete (case precondition)"; else fail "the rm stub did not take — the next case would prove nothing"; fi

OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STICKY")"
if is_block "$OUT"; then ok "an undeletable consumed marker does not authorize a later run"; else fail "a surviving consumed marker wrongly authorized a later run: $OUT"; fi

printf 'done\n' >"$STICKY"
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STICKY")"
if is_block "$OUT"; then fail "a recreated marker was wrongly treated as consumed: $OUT"; else ok "a recreated marker authorizes a stop again"; fi
if [[ -f "$STICKY" ]]; then fail "recreated marker not consumed after authorizing a stop"; else ok "recreated marker consumed on use"; fi

STICKY2="$WORK/sticky2.marker"
MTIME_REF="$WORK/sticky2.mtime-ref"
: >"$STICKY2"
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STICKY2" \
  PATH="$RMFAIL:$PATH")"
if is_block "$OUT"; then fail "same-second setup: marker did not authorize: $OUT"; else ok "same-second setup: marker authorizes once"; fi
if [[ -f "$STICKY2" ]]; then ok "same-second setup: the rm stub prevented the delete (case precondition)"; else fail "same-second setup: the rm stub did not take — the case would prove nothing"; fi
touch -r "$STICKY2" "$MTIME_REF"
: >"$STICKY2"
touch -r "$MTIME_REF" "$STICKY2"
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STICKY2" \
  PATH="$RMFAIL:$PATH")"
if is_block "$OUT"; then ok "same-second same-size recreation stays latched (documented coarse-identity limit)"; else fail "same-second same-size recreation read as a fresh signal — the identity read got finer without this case moving: $OUT"; fi

DECOY_DATA="$(mktemp -d "$WORK/decoy.XXXXXX")"
STAGED_MARKER="$WORK/staged.marker"
: >"$STAGED_MARKER"
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STAGED_MARKER" \
  RAWENV_CLAUDE_PLUGIN_DATA="$DECOY_DATA" \
  PATH="$RMFAIL:$PATH")"
if is_block "$OUT"; then fail "staged install: marker present → wrongly blocked: $OUT"; else ok "staged install: marker authorizes a stop"; fi
DERIVED_LEDGER="$DATA_DIR/consumed-markers"
if [[ -d "$DERIVED_LEDGER" ]] && [[ -n "$(ls -A "$DERIVED_LEDGER" 2>/dev/null)" ]]; then
  ok "staged install: the record lands under the install-derived data directory"
else
  fail "staged install: no record under the install-derived data directory ($DERIVED_LEDGER)"
fi
if [[ -n "$(ls -A "$DECOY_DATA" 2>/dev/null)" ]]; then fail "CLAUDE_PLUGIN_DATA wrongly won over the install path"; else ok "CLAUDE_PLUGIN_DATA does not win over the install path"; fi

OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STAGED_MARKER")"
if is_block "$OUT"; then ok "staged install: the derived record blocks a later run"; else fail "staged install: a consumed marker wrongly authorized a later run: $OUT"; fi


OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true)"
RC=$?
if is_block "$OUT"; then fail "env-only ENABLED=true wrongly engaged the gate (channel-B authority): $OUT"; else ok "env-only ENABLED=true does not engage the gate"; fi
if [[ $RC -eq 0 && "$OUT" == *'"systemMessage"'* && "$OUT" == *"environment channel"* ]]; then
  ok "env-only enable claim surfaces a visible notice instead of silence"
else
  fail "env-only enable claim not surfaced (rc=$RC out=$OUT)"
fi
if [[ "$OUT" == *additionalContext* ]]; then fail "env-only enable notice reached the model on Stop: $OUT"; else ok "env-only enable notice is user-only"; fi

OUT="$(run "$(build_input Stop "some ordinary line
EASY" false)" RAWENV_CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="EASY")"
if is_block "$OUT"; then ok "env-only sentinel is not honored (weakened token does not authorize)"; else fail "env-only sentinel wrongly honored: $OUT"; fi
OUT="$(run "$(build_input Stop "LANE-STOP-OK" false)" RAWENV_CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="EASY")"
if is_block "$OUT"; then fail "trusted default sentinel stopped working under an env-only override: $OUT"; else ok "trusted default sentinel still authorizes under an env-only override"; fi

ATTACK_MARKER="$WORK/attack.marker"
: >"$ATTACK_MARKER"
OUT="$(run "$(build_input Stop "no token" false)" \
  RAWENV_CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$ATTACK_MARKER")"
if is_block "$OUT"; then ok "env-only marker path is not honored"; else fail "env-only marker path wrongly authorized a stop: $OUT"; fi
if [[ -f "$ATTACK_MARKER" ]]; then ok "env-only marker file left untouched"; else fail "env-only marker file was consumed despite not being trusted"; fi

OUT="$(run "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=false \
  RAWENV_CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true)"
if is_block "$OUT"; then fail "configured enabled=false wrongly engaged the gate: $OUT"; else ok "configured enabled=false keeps the gate off"; fi
if [[ "$OUT" == *systemMessage* ]]; then fail "configured false wrongly emitted the unhonored-claim notice: $OUT"; else ok "configured false stays silent (a verdict, not an unhonored claim)"; fi

printf '{ not json' >"$SETTINGS"
OUT="$(cd "$UNRELATED" && build_input Stop "no token" false |
  env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID -u CLAUDE_PLUGIN_DATA \
    CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true \
    CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
    bash "$HOOK" 2>/dev/null)"
RC=$?
if [[ $RC -eq 0 ]] && ! is_block "$OUT"; then ok "malformed user settings → gate off, stop allowed (fail-open)"; else fail "malformed user settings (rc=$RC out=$OUT)"; fi
if [[ "$OUT" == *'"systemMessage"'* ]]; then ok "malformed settings + env claim → visible notice"; else fail "malformed settings + env claim stayed silent: $OUT"; fi

ARM_ID_1="cafe1234deadbeef"

LANE_MARKER="$WORK/lane.marker"
bash "$ARM" --id "$ARM_ID_1" --cwd "$WORK" --marker "$LANE_MARKER" 2>/dev/null ||
  fail "arm helper refused a valid arming (precondition for cases 29-32)"
if [[ -f "$DATA_DIR/lane-arms/$ARM_ID_1" ]]; then ok "arm record lands under the install-derived data directory"; else fail "arm record missing from $DATA_DIR/lane-arms"; fi
OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_1")"
if is_block "$OUT"; then ok "an armed session is gated (no settings entry needed)"; else fail "an armed session was not gated: $OUT"; fi

: >"$LANE_MARKER"
OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_1")"
if is_block "$OUT"; then fail "record-configured marker did not authorize: $OUT"; else ok "record-configured marker authorizes the stop"; fi
if [[ -f "$DATA_DIR/lane-arms/$ARM_ID_1" ]]; then ok "the arm record survives a completion-signaled stop (not consumed)"; else fail "arm record was consumed on a stop — a later /loop cycle would run ungated"; fi

rm -f "$LANE_MARKER"
OUT="$(run_bare "$(build_input Stop "no token this cycle" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_1")"
if is_block "$OUT"; then ok "a later cycle of the same armed session is still gated (record persisted)"; else fail "a later cycle ran ungated after an earlier signaled stop: $OUT"; fi

OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="deadbeefdeadbeef")"
if is_block "$OUT"; then fail "a dangling arm id wrongly engaged the gate: $OUT"; else ok "a dangling arm id does not engage the gate"; fi
if [[ "$OUT" == *'"systemMessage"'* && "$OUT" == *"no matching arm record"* ]]; then
  ok "a dangling arm id surfaces the arm-specific notice (not the env-attack notice)"
else
  fail "a dangling arm id gave the wrong or no notice: $OUT"
fi
if [[ "$OUT" == *additionalContext* ]]; then fail "the stale-arm notice reached the model on Stop: $OUT"; else ok "the stale-arm notice is user-only"; fi
if [[ "$OUT" == *"environment channel"* ]]; then fail "a dangling arm id wrongly blamed the env channel"; else ok "a dangling arm id does not blame the env channel"; fi

ARM_ID_2="feedface00112233"
bash "$ARM" --id "$ARM_ID_2" --cwd "$WORK" 2>/dev/null
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-A")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_2")"
if is_block "$OUT"; then ok "arm id claimed by its first session (gated)"; else fail "first session with a fresh arm id not gated: $OUT"; fi
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-B")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_2")"
if is_block "$OUT"; then fail "a replayed arm id engaged the gate for a different session: $OUT"; else ok "a replayed arm id is refused for a different session"; fi

ARM_ID_3="0123456789abcdef"
bash "$ARM" --id "$ARM_ID_3" --cwd "$WORK" --sentinel "DONE-LANE-7" 2>/dev/null
OUT="$(run_bare "$(build_input Stop "wrapping up
DONE-LANE-7" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_3")"
if is_block "$OUT"; then fail "record-configured sentinel did not authorize: $OUT"; else ok "record-configured sentinel authorizes the stop"; fi

ARM_ID_4="aaaabbbbccccdddd"
bash "$ARM" --id "$ARM_ID_4" --cwd "$WORK" 2>/dev/null
REC_4="$DATA_DIR/lane-arms/$ARM_ID_4"
jq -c '.armed_at = 1000' <"$REC_4" >"$REC_4.new" && mv -f "$REC_4.new" "$REC_4"
printf 'sess-expired\n' >"$REC_4.claim"
OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_4")"
if is_block "$OUT"; then fail "an expired arm record wrongly engaged the gate: $OUT"; else ok "an expired arm record does not engage the gate (TTL)"; fi
if [[ -f "$REC_4" ]]; then fail "an expired arm record was not dropped"; else ok "an expired arm record is dropped on sight"; fi
if [[ -e "$REC_4.claim" ]]; then fail "an expired record's claim sidecar outlived it"; else ok "an expired record's claim sidecar is dropped with it"; fi

NOW_EPOCH="$(date +%s)"
ARM_ID_4B="aaaabbbbcccc0008"
bash "$ARM" --id "$ARM_ID_4B" --cwd "$WORK" 2>/dev/null
REC_4B="$DATA_DIR/lane-arms/$ARM_ID_4B"
jq -c --argjson t "$((NOW_EPOCH - 8 * 86400))" '.armed_at = $t' <"$REC_4B" >"$REC_4B.new" && mv -f "$REC_4B.new" "$REC_4B"
OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_4B")"
if is_block "$OUT"; then ok "an arm record aged 8 days still engages the gate (31-day TTL)"; else fail "an arm record aged 8 days wrongly expired: $OUT"; fi
if [[ -f "$REC_4B" ]]; then ok "an arm record aged 8 days is kept"; else fail "an arm record aged 8 days was dropped"; fi

ARM_ID_4C="aaaabbbbcccc0032"
bash "$ARM" --id "$ARM_ID_4C" --cwd "$WORK" 2>/dev/null
REC_4C="$DATA_DIR/lane-arms/$ARM_ID_4C"
jq -c --argjson t "$((NOW_EPOCH - 32 * 86400))" '.armed_at = $t' <"$REC_4C" >"$REC_4C.new" && mv -f "$REC_4C.new" "$REC_4C"
OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_4C")"
if is_block "$OUT"; then fail "an arm record aged 32 days wrongly engaged the gate: $OUT"; else ok "an arm record aged 32 days does not engage the gate (31-day TTL)"; fi
if [[ -f "$REC_4C" ]]; then fail "an arm record aged 32 days was not dropped"; else ok "an arm record aged 32 days is dropped on sight"; fi

age_file_days() {
  local t=$((NOW_EPOCH - $2 * 86400)) stamp
  stamp="$(TZ=UTC printf '%(%Y%m%d%H%M)T' "$t")"
  : >"$1"
  TZ=UTC touch -t "$stamp" "$1"
}
SWEEP_KEEP="$DATA_DIR/lane-arms/sweepkeep0008aaaa"
SWEEP_GONE="$DATA_DIR/lane-arms/sweepgone0032aaaa"
age_file_days "$SWEEP_KEEP" 8
age_file_days "$SWEEP_GONE" 32
bash "$ARM" --id "sweepfresh00aaaa" --cwd "$WORK" 2>/dev/null
if [[ -f "$SWEEP_KEEP" ]]; then ok "the arm helper's sweep keeps a file aged 8 days (31-day TTL)"; else fail "the arm helper's sweep dropped a file aged 8 days"; fi
if [[ -e "$SWEEP_GONE" ]]; then fail "the arm helper's sweep kept a file aged 32 days"; else ok "the arm helper's sweep drops a file aged 32 days (31-day TTL)"; fi

ARM_ID_5="1234abcd5678efab"
bash "$ARM" --id "$ARM_ID_5" --cwd "$WORK" 2>/dev/null
OUT="$(run_bare "$(build_input Stop "still no token" true)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_5")"
if is_block "$OUT"; then fail "post-nudge armed stop wrongly blocked: $OUT"; else ok "post-nudge armed stop allowed"; fi
if [[ -f "$DATA_DIR/lane-arms/$ARM_ID_5" ]]; then ok "the arm record survives a post-nudge stop (not consumed)"; else fail "arm record was consumed on the post-nudge stop"; fi

if (
  # shellcheck source=/dev/null
  source "$STAGED_DIR/lane-stop-gate-lib.sh"
  gate_resolve_anchor "$STAGED_DIR/.." >/dev/null 2>&1 || true
  if gate_arm_record_path "../../../etc/passwd" >/dev/null 2>&1; then exit 1; fi
  if gate_arm_record_path "a/b" >/dev/null 2>&1; then exit 1; fi
  gate_arm_record_path "cafe1234deadbeef" >/dev/null 2>&1 || exit 1
  exit 0
); then
  ok "gate_arm_record_path refuses a traversal/slash id but accepts a valid one"
else
  fail "gate_arm_record_path did not enforce the id shape at the path boundary"
fi
OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="../../../etc/passwd")"
if is_block "$OUT"; then fail "a traversal-shaped arm id engaged the gate: $OUT"; else ok "a traversal-shaped arm id does not engage the gate (end to end)"; fi
if bash "$ARM" --id "bad/../id" --cwd "$WORK" 2>/dev/null; then
  fail "the arm helper accepted a malformed id"
else
  ok "the arm helper rejects a malformed id"
fi

UNANCHORED="$(mktemp -d "$WORK/unanchored.XXXXXX")"
cp "$HOOK_DIR"/*.sh "$UNANCHORED/"
if bash "$UNANCHORED/lane-stop-gate-arm.sh" --id "$ARM_ID_1" --cwd "$WORK" 2>/dev/null; then
  fail "the arm helper armed without a plugins/cache anchor"
else
  ok "the arm helper fails closed without a plugins/cache anchor"
fi

if (
  # shellcheck source=/dev/null
  source "$STAGED_DIR/lane-stop-gate-lib.sh"
  # shellcheck disable=SC2329 # invoked indirectly by gate_managed_settings_files
  uname() { printf '%s\n' "${STUB_UNAME:-Linux}"; }
  export OSTYPE=msys
  for plat in Linux Darwin MINGW64_NT CYGWIN_NT bogus-platform; do
    STUB_UNAME="$plat"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      case "$line" in
      /* | [A-Za-z]:[/\\]*) ;;
      *) exit 1 ;;
      esac
    done < <(gate_managed_settings_files)
  done
  STUB_UNAME="bogus-platform"
  [[ -z "$(gate_managed_settings_files)" ]] || exit 1
  exit 0
); then
  ok "managed-settings selection ignores hostile \$OSTYPE and never yields a relative path"
else
  fail "managed-settings path selection is influenced by \$OSTYPE or can be relative (#1784 finding 1)"
fi

UNANCHORED_ROOT="$(mktemp -d "$WORK/plugindir.XXXXXX")"
mkdir -p "$UNANCHORED_ROOT/hooks" "$UNANCHORED_ROOT/.claude-plugin"
cp "$HOOK_DIR"/*.sh "$UNANCHORED_ROOT/hooks/"
printf '{"name":"autonomy"}\n' >"$UNANCHORED_ROOT/.claude-plugin/plugin.json"
MANAGED_STUB="$WORK/managed-stub.json"
if (
  # shellcheck source=lane-stop-gate-lib.sh
  source "$UNANCHORED_ROOT/hooks/lane-stop-gate-lib.sh"
  gate_resolve_install "$UNANCHORED_ROOT" || exit 1
  [[ -z "$GATE_PLUGIN_ID" && "$GATE_PLUGIN_NAME" == "autonomy" ]] || exit 1
  printf '{"pluginConfigs":{"autonomy":{"options":{"lane_stop_gate_enabled":true}}}}\n' >"$MANAGED_STUB"
  [[ "$(gate_settings_option "$MANAGED_STUB" lane_stop_gate_enabled)" == "true" ]] || exit 1
  printf '{"pluginConfigs":{"autonomy@melodic":{"options":{"lane_stop_gate_enabled":true}}}}\n' >"$MANAGED_STUB"
  [[ "$(gate_settings_option "$MANAGED_STUB" lane_stop_gate_enabled)" == "true" ]] || exit 1
  printf '{"pluginConfigs":{"other@melodic":{"options":{"lane_stop_gate_enabled":true}}}}\n' >"$MANAGED_STUB"
  gate_settings_option "$MANAGED_STUB" lane_stop_gate_enabled >/dev/null 2>&1 && exit 1
  exit 0
); then
  ok "an unanchored install resolves managed settings by manifest name"
else
  fail "an unanchored (--plugin-dir) install cannot read managed settings — its only enable path"
fi
if (
  # shellcheck source=lane-stop-gate-lib.sh
  source "$STAGED_DIR/lane-stop-gate-lib.sh"
  gate_resolve_install "$STAGED_DIR/.." || exit 1
  [[ "$GATE_PLUGIN_ID" == "autonomy@melodic" ]] || exit 1
  printf '{"pluginConfigs":{"autonomy@other":{"options":{"lane_stop_gate_enabled":true}}}}\n' >"$MANAGED_STUB"
  gate_settings_option "$MANAGED_STUB" lane_stop_gate_enabled >/dev/null 2>&1 && exit 1
  exit 0
); then
  ok "an anchored install still matches only its exact marketplace-qualified id"
else
  fail "an anchored install accepted another marketplace's entry"
fi

OUT="$(run "$(build_input Stop "LANE-STOP-OK" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="")"
if is_block "$OUT"; then fail "an empty configured sentinel silenced the token channel: $OUT"; else ok "an empty configured sentinel falls back to the default token"; fi
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="")"
if [[ "$OUT" == *'LANE-STOP-OK'* ]]; then ok "the nudge names the default token, never an empty one"; else fail "the nudge did not name a usable token: $OUT"; fi

rc0() {
  [[ -n "${1:-}" ]] || fail "$2 had no exit code to check"
  [[ "$1" -eq 0 ]] || fail "$2 exited $1"
}

ARM_ID_6="beefbeef11223344"
bash "$ARM" --id "$ARM_ID_6" --cwd "$WORK" 2>/dev/null
printf 'sess-owner\n' >"$DATA_DIR/lane-arms/$ARM_ID_6.claim"
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-intruder")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_6")"
rc0 $? "the non-owner refusal on a pre-claimed record"
if is_block "$OUT"; then fail "a pre-claimed record was honored for a non-owner: $OUT"; else ok "a pre-claimed record is refused for a non-owner"; fi
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-owner")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_6")"
rc0 $? "the persisted owner's honored stop"
if is_block "$OUT"; then ok "a pre-claimed record is honored for its persisted owner"; else fail "the persisted owner was not honored: $OUT"; fi

bash "$ARM" --id "$ARM_ID_6" --cwd "$WORK" 2>/dev/null
if [[ -e "$DATA_DIR/lane-arms/$ARM_ID_6.claim" ]]; then fail "re-arming left the previous lane's claim in place"; else ok "re-arming clears the previous lane's claim"; fi
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-relaunched")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_6")"
rc0 $? "the relaunched lane's first claim"
if is_block "$OUT"; then ok "a re-armed id is claimable by the relaunched lane"; else fail "a re-armed id stayed bound to the previous lane: $OUT"; fi

ARM_ID_7="c0ffee1122334455"
bash "$ARM" --id "$ARM_ID_7" --cwd "$WORK" 2>/dev/null
REC_7="$DATA_DIR/lane-arms/$ARM_ID_7"
jq -c '.session_id = "legacy-owner"' <"$REC_7" >"$REC_7.new" && mv -f "$REC_7.new" "$REC_7"
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-intruder")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_7")"
rc0 $? "the non-owner refusal on a legacy-claimed record"
if is_block "$OUT"; then fail "a legacy-claimed record was honored for a non-owner: $OUT"; else ok "a legacy-claimed record is refused for a non-owner"; fi
OUT="$(run_bare "$(build_input Stop "no token" false "" "legacy-owner")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_7")"
rc0 $? "the legacy owner's honored stop"
if is_block "$OUT"; then ok "a legacy-claimed record is still honored for its owner"; else fail "a legacy-claimed record stopped gating its own session: $OUT"; fi

ARM_ID_8="99887766aabbccdd"
bash "$ARM" --id "$ARM_ID_8" --cwd "$WORK" 2>/dev/null
rm -f "$SETTINGS"
RACE_DIR="$WORK/race"
mkdir -p "$RACE_DIR"
for i in 1 2 3 4 5 6; do
  (
    cd "$UNRELATED" && printf '%s' "$(build_input Stop "no token" false "" "race-$i")" |
      env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
        -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
        -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
        -u CLAUDE_PLUGIN_DATA \
        CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
        CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_8" \
        bash "$HOOK" 2>/dev/null >"$RACE_DIR/$i"
    printf '%s\n' "$?" >"$RACE_DIR/$i.rc"
  ) &
done
wait
RACE_WINNERS=0
RACE_WINNER=""
for i in 1 2 3 4 5 6; do
  if is_block "$(cat "$RACE_DIR/$i" 2>/dev/null)"; then
    RACE_WINNERS=$((RACE_WINNERS + 1))
    RACE_WINNER="race-$i"
  fi
done
if [[ $RACE_WINNERS -eq 1 ]]; then ok "exactly one concurrent presenter claims a fresh arm id"; else fail "$RACE_WINNERS of 6 concurrent presenters were honored for one fresh arm id"; fi
RACE_CLAIMED="$(head -n 1 "$DATA_DIR/lane-arms/$ARM_ID_8.claim" 2>/dev/null)"
for i in 1 2 3 4 5 6; do rc0 "$(cat "$RACE_DIR/$i.rc" 2>/dev/null || echo 1)" "concurrent presenter race-$i"; done
if [[ -n "$RACE_WINNER" && "$RACE_CLAIMED" == "$RACE_WINNER" ]]; then ok "the persisted claim names the session that was honored"; else fail "persisted claim '$RACE_CLAIMED' does not name the honored session '$RACE_WINNER'"; fi

ARM_ID_9="1234abcd5678ef90"
bash "$ARM" --id "$ARM_ID_9" --cwd "$WORK" 2>/dev/null
: >"$DATA_DIR/lane-arms/$ARM_ID_9.claim"
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-after-a-dead-writer")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_9")"
rc0 $? "the stop that met an ownerless claim"
if is_block "$OUT"; then ok "an ownerless claim still honors the arm (fail direction: gate ON)"; else fail "an ownerless claim left the lane ungated: $OUT"; fi

ARM_ID_10="fedcba9876543210"
bash "$ARM" --id "$ARM_ID_10" --cwd "$WORK" 2>/dev/null
rm -f "$SETTINGS"
if ! mkfifo "$DATA_DIR/lane-arms/$ARM_ID_10.claim" 2>/dev/null; then
  ok "mkfifo unavailable; skip non-regular claim path hang case"
elif ! command -v timeout >/dev/null 2>&1 ||
  ! grep -Fq -- '--kill-after' < <(timeout --help 2>&1); then
  ok "GNU timeout unavailable; skip non-regular claim path hang case"
else
  FIFO_INPUT=$(build_input Stop "no token" false "" "sess-fifo")
  FIFO_OUT="$WORK/fifo-out"
  FIFO_RC=0
  # shellcheck disable=SC2016 # bash -c program is single-quoted; \$1..\$4 expand in the child
  if timeout 5 bash -c '
  cd "$1" && printf "%s" "$2" |
    env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
      -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
      -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
      -u CLAUDE_PLUGIN_DATA \
      CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
      CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$3" \
      bash "$4" 2>/dev/null
' _ "$UNRELATED" "$FIFO_INPUT" "$ARM_ID_10" "$HOOK" >"$FIFO_OUT" 2>/dev/null; then
    FIFO_RC=0
  else
    FIFO_RC=$?
  fi
  if [[ "$FIFO_RC" -eq 124 ]]; then
    fail "a planted FIFO at the claim path hung the Stop hook"
  elif is_block "$(cat "$FIFO_OUT" 2>/dev/null)"; then
    ok "a non-regular file at the claim path neither hangs the hook nor loses the gate"
  else
    fail "a planted FIFO at the claim path left the lane ungated"
  fi
fi

PROBE_OUT=""
PROBE_RC=0
PROBE_LEFT=""
probe_run() {
  local payload="$1"
  PROBE_OUT=""
  PROBE_RC=0
  PROBE_LEFT=""
  {
    PROBE_OUT=$(cd "$UNRELATED" &&
      env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
        -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
        -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
        -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID \
        -u CLAUDE_PLUGIN_DATA \
        CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
        bash "$HOOK" 0<&3 2>/dev/null)
    PROBE_RC=$?
    PROBE_LEFT=$(cat <&3)
  } 3<"$payload"
}

PROBE_PAYLOAD="$WORK/stdin-probe.json"
build_input Stop "no token" false >"$PROBE_PAYLOAD"
PROBE_EXPECT="$(<"$PROBE_PAYLOAD")"
if [[ -n "$PROBE_EXPECT" ]]; then ok "stdin probe payload built (case precondition)"; else fail "stdin probe payload is empty — the leftover check would prove nothing"; fi
rm -f "$SETTINGS"
probe_run "$PROBE_PAYLOAD"
if [[ $PROBE_RC -eq 0 && -z "$PROBE_OUT" ]]; then ok "unarmed session → silent exit 0 (fd-bound stdin)"; else fail "unarmed fd-bound session (rc=$PROBE_RC out=$PROBE_OUT)"; fi
if [[ "$PROBE_LEFT" == "$PROBE_EXPECT" ]]; then
  ok "unarmed session leaves the whole payload unread (arm pre-filter runs before the stdin buffer)"
else
  fail "unarmed session consumed stdin — the pre-filter is running after the buffered read (leftover=${#PROBE_LEFT} of ${#PROBE_EXPECT} bytes)"
fi

write_settings true
probe_run "$PROBE_PAYLOAD"
if [[ $PROBE_RC -eq 0 ]]; then ok "armed fd-bound session: exit 0"; else fail "armed fd-bound session exited $PROBE_RC"; fi
if [[ -z "$PROBE_LEFT" ]]; then ok "armed session drains stdin (the buffered read still runs when the gate is armed)"; else fail "armed session left ${#PROBE_LEFT} bytes unread — the payload never reached the gate"; fi
if is_block "$PROBE_OUT"; then ok "armed session still blocks an unsignaled stop (payload reads intact below the buffer)"; else fail "armed session did not block — the reorder changed armed-lane behavior: $PROBE_OUT"; fi


OPTS_STUB="$WORK/opts-stub.json"
if (
  # shellcheck source=lane-stop-gate-lib.sh
  source "$STAGED_DIR/lane-stop-gate-lib.sh"
  gate_resolve_install "$STAGED_DIR/.." || exit 1
  printf '{"pluginConfigs":{"autonomy@melodic":{"options":{"lane_stop_gate_enabled":true,"lane_stop_gate_sentinel":"X\\n\\n"}}}}\n' >"$OPTS_STUB"
  gate_settings_options_to "$OPTS_STUB" lane_stop_gate_enabled lane_stop_gate_sentinel lane_stop_gate_marker || exit 1
  [[ "${GATE_FILE_OPT_HAVE[*]}" == "1 1 0" ]] || exit 1
  [[ "${GATE_FILE_OPT_VALUE[0]}" == "true" && "${GATE_FILE_OPT_VALUE[1]}" == "X" && -z "${GATE_FILE_OPT_VALUE[2]}" ]] || exit 1
  [[ "$(gate_settings_option "$OPTS_STUB" lane_stop_gate_sentinel)" == "X" ]] || exit 1
  gate_settings_option "$OPTS_STUB" lane_stop_gate_marker >/dev/null 2>&1 && exit 1
  printf '{"pluginConfigs":{"autonomy@melodic":{"options":"lane_stop_gate_enabled"}}}\n' >"$OPTS_STUB"
  gate_settings_options_to "$OPTS_STUB" lane_stop_gate_enabled lane_stop_gate_sentinel && exit 1
  [[ "${GATE_FILE_OPT_HAVE[*]}" == "0 0" ]] || exit 1
  exit 0
); then
  ok "one settings pass answers every key with the single-key verdicts"
else
  fail "gate_settings_options_to disagrees with the per-key reader (#3515)"
fi

if (
  # shellcheck source=lane-stop-gate-lib.sh
  source "$STAGED_DIR/lane-stop-gate-lib.sh"
  gate_resolve_install "$STAGED_DIR/.." || exit 1
  printf '{"pluginConfigs":{"autonomy@melodic":{"options":{"lane_stop_gate_sentinel":"Y\\r\\n"}}}}\n' >"$OPTS_STUB"
  gate_settings_options_to "$OPTS_STUB" lane_stop_gate_sentinel || exit 1
  [[ "${GATE_FILE_OPT_VALUE[0]}" == "Y" ]] || exit 1
  exit 0
); then
  ok "a CRLF-terminated option value chomps to the bare string"
else
  fail "gate_settings_options_to left a trailing CR on a CRLF-terminated value"
fi

OUT="$(run "$(build_input Stop "A" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL=$'A\nB')"
if is_block "$OUT"; then ok "newline-bearing sentinel: half the token does not authorize"; else fail "newline-bearing sentinel: half the token authorized a stop: $OUT"; fi
OUT="$(run "$(build_input Stop $'done\nA\nB' false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL=$'A\nB')"
if is_block "$OUT"; then fail "newline-bearing sentinel: the whole token on its own lines was not honored: $OUT"; else ok "newline-bearing sentinel: the whole token on its own lines authorizes"; fi

UNREADABLE_ERR="$WORK/unreadable.err"
write_settings true
chmod 000 "$SETTINGS" 2>/dev/null || true
if [[ -r "$SETTINGS" ]]; then
  ok "SKIP: chmod 000 does not deny for this user — unreadable-source stderr not asserted here"
else
  OUT="$(cd "$UNRELATED" && env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
    -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
    -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
    -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID \
    -u CLAUDE_PLUGIN_DATA \
    CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
    bash "$HOOK" <"$PROBE_PAYLOAD" 2>"$UNREADABLE_ERR")"
  RC=$?
  UNREADABLE_STDERR="$(<"$UNREADABLE_ERR")"
  if [[ -z "$UNREADABLE_STDERR" ]]; then
    ok "an unreadable settings file produces no stderr (redirection order holds)"
  else
    fail "an unreadable settings file leaked to stderr — silence stderr BEFORE the input redirection: $UNREADABLE_STDERR"
  fi
  if [[ $RC -eq 0 ]] && ! is_block "$OUT"; then ok "an unreadable settings file contributes no verdict (stop allowed)"; else fail "unreadable settings file changed the verdict (rc=$RC out=$OUT)"; fi
fi
chmod 600 "$SETTINGS" 2>/dev/null || true
rm -f "$SETTINGS"

OUT="$(run "$(build_input Stop $'LANE-STOP\r-OK' false)")"
if is_block "$OUT"; then ok "embedded CR in the completion token does not authorize"; else fail "LANE-STOP\\r-OK authorized — LAST must preserve CR: $OUT"; fi
OUT="$(run "$(build_input Stop $'LANE-STOP-OK\r' false)")"
if is_block "$OUT"; then fail "CRLF-terminated sentinel was not honored: $OUT"; else ok "CRLF-terminated sentinel still authorizes (CR as line-ending whitespace)"; fi

if (
  # shellcheck source=lane-stop-gate-lib.sh
  source "$STAGED_DIR/lane-stop-gate-lib.sh"
  gate_epochseconds_is_clock() { return 1; }
  # The spoof is confined to this subshell; the Bash 5+ case below runs in another.
  # shellcheck disable=SC2030
  EPOCHSECONDS=1
  export EPOCHSECONDS
  got=""
  gate_epoch_seconds_to got
  [[ "$got" =~ ^[0-9]+$ ]] || exit 1
  [[ "$got" != "1" ]] || exit 1
  ((got > 1)) || exit 1
  exit 0
); then
  ok "pre-5.0 path ignores inherited EPOCHSECONDS (date fallback)"
else
  fail "pre-5.0 path trusted inherited EPOCHSECONDS=1"
fi
if ((BASH_VERSINFO[0] >= 5)); then
  if (
    # shellcheck source=lane-stop-gate-lib.sh
    source "$STAGED_DIR/lane-stop-gate-lib.sh"
    got=""
    gate_epoch_seconds_to got
    [[ "$got" =~ ^[0-9]+$ ]] || exit 1
    # shellcheck disable=SC2031  # independent subshell; parent clock is the contract
    [[ "$got" == "$EPOCHSECONDS" ]] || exit 1
    exit 0
  ); then
    ok "Bash 5+ path uses EPOCHSECONDS as the clock"
  else
    fail "Bash 5+ path did not use EPOCHSECONDS"
  fi
fi

UNREAD_PLUGIN="$WORK/unreadable-plugin"
mkdir -p "$UNREAD_PLUGIN/.claude-plugin"
printf '{"name":"autonomy"}\n' >"$UNREAD_PLUGIN/.claude-plugin/plugin.json"
UNREAD_OPTS="$WORK/unreadable-opts.json"
printf '{"pluginConfigs":{"autonomy@melodic":{"options":{"lane_stop_gate_enabled":true}}}}\n' >"$UNREAD_OPTS"
chmod 000 "$UNREAD_PLUGIN/.claude-plugin/plugin.json" "$UNREAD_OPTS" 2>/dev/null || true
if [[ -r "$UNREAD_PLUGIN/.claude-plugin/plugin.json" || -r "$UNREAD_OPTS" ]]; then
  ok "SKIP: chmod 000 does not deny for this user — remaining unreadable-source stderr not asserted here"
else
  UNREAD_LIB_ERR="$WORK/unreadable-lib.err"
  if (
    # shellcheck source=lane-stop-gate-lib.sh
    source "$STAGED_DIR/lane-stop-gate-lib.sh"
    gate_resolve_install "$STAGED_DIR/.." || exit 1
    gate_resolve_plugin_name "$UNREAD_PLUGIN"
    gate_settings_options_to "$UNREAD_OPTS" lane_stop_gate_enabled lane_stop_gate_sentinel lane_stop_gate_marker || true
    exit 0
  ) 2>"$UNREAD_LIB_ERR"; then
    UNREAD_LIB_STDERR="$(<"$UNREAD_LIB_ERR")"
    if [[ -z "$UNREAD_LIB_STDERR" ]]; then
      ok "unreadable manifest and settings file produce no stderr (lib redirection order holds)"
    else
      fail "unreadable lib file leaked to stderr — silence stderr BEFORE the input redirection: $UNREAD_LIB_STDERR"
    fi
  else
    fail "unreadable lib file reads aborted the sourced helpers"
  fi
  ARM_ID_UNREAD="unreadarm0123456"
  bash "$ARM" --id "$ARM_ID_UNREAD" --cwd "$WORK" 2>/dev/null
  REC_UNREAD="$DATA_DIR/lane-arms/$ARM_ID_UNREAD"
  chmod 000 "$REC_UNREAD" 2>/dev/null || true
  if [[ -r "$REC_UNREAD" ]]; then
    ok "SKIP: chmod 000 does not deny the arm record for this user"
  else
    UNREAD_ARM_ERR="$WORK/unreadable-arm.err"
    rm -f "$SETTINGS"
    OUT="$(cd "$UNRELATED" && build_input Stop "no token" false |
      env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
        -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
        -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
        -u CLAUDE_PLUGIN_DATA \
        CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
        CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_UNREAD" \
        bash "$HOOK" 2>"$UNREAD_ARM_ERR")"
    RC=$?
    UNREAD_ARM_STDERR="$(<"$UNREAD_ARM_ERR")"
    if [[ -z "$UNREAD_ARM_STDERR" ]]; then
      ok "unreadable arm record produces no stderr (redirection order holds)"
    else
      fail "unreadable arm record leaked to stderr — silence stderr BEFORE the input redirection: $UNREAD_ARM_STDERR"
    fi
    if [[ $RC -eq 0 ]] && ! is_block "$OUT"; then
      ok "unreadable arm record contributes no verdict (stop allowed)"
    else
      fail "unreadable arm record changed the verdict (rc=$RC out=$OUT)"
    fi
  fi
  chmod 600 "$REC_UNREAD" 2>/dev/null || true
  rm -f "$REC_UNREAD" "$REC_UNREAD.claim"
fi
chmod 600 "$UNREAD_PLUGIN/.claude-plugin/plugin.json" "$UNREAD_OPTS" 2>/dev/null || true
rm -rf "$UNREAD_PLUGIN" "$UNREAD_OPTS"

HOOK_TEXT="$(<"$HOOK")"
if (
  # shellcheck source=lane-stop-gate-lib.sh
  source "$STAGED_DIR/lane-stop-gate-lib.sh"
  for p in "$GATE_MANAGED_PRIMARY_DARWIN" "$GATE_MANAGED_PRIMARY_WINDOWS" "$GATE_MANAGED_PRIMARY_LINUX"; do
    [[ "$HOOK_TEXT" == *"\"$p\""* ]] || exit 1
  done
); then
  ok "the pre-filter's managed-settings primaries match the lib's literals"
else
  fail "the pre-filter's managed-settings primaries drifted from GATE_MANAGED_PRIMARY_* in the lib"
fi

SRC_ROOT="$(mktemp -d "$WORK/srcprobe.XXXXXX")"
SRC_DIR="$SRC_ROOT/plugins/cache/melodic/autonomy/9.9.9/hooks"
SRC_MARK="$WORK/sourced.txt"
mkdir -p "$SRC_DIR"
cp "$HOOK" "$SRC_DIR/"
for lib in hook-utils.sh lane-notify.sh lane-stop-gate-lib.sh; do
  printf 'printf "%%s\\n" %s >>"%s"\nexit 0\n' "$lib" "$SRC_MARK" >"$SRC_DIR/$lib"
done
src_probe() {
  rm -f "$SRC_MARK"
  SRC_OUT="$(cd "${SRC_CWD:-$UNRELATED}" && env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
    -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID \
    "$@" bash "$SRC_DIR/lane-stop-gate.sh" <"$PROBE_PAYLOAD" 2>&1)"
  SRC_RC=$?
}
rm -f "$SRC_ROOT/settings.json"
src_probe
if [[ $SRC_RC -eq 0 && -z "$SRC_OUT" && ! -e "$SRC_MARK" ]]; then
  ok "unconfigured: silent exit 0 without sourcing any library"
else
  fail "unconfigured session sourced a library or spoke (rc=$SRC_RC out=$SRC_OUT sourced=$(cat "$SRC_MARK" 2>/dev/null))"
fi
src_probe CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID=probe-arm-id
if [[ -e "$SRC_MARK" ]]; then ok "arm id env presence reaches the full path"; else fail "arm id env presence exited at the pre-filter"; fi
src_probe CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true
if [[ -e "$SRC_MARK" ]]; then ok "enabled env presence reaches the full path"; else fail "enabled env presence exited at the pre-filter"; fi
printf '{"pluginConfigs":{"autonomy@melodic":{"options":{"lane_stop_gate_enabled":false}}}}\n' >"$SRC_ROOT/settings.json"
src_probe
if [[ -e "$SRC_MARK" ]]; then ok "anchored user settings mentioning the gate reach the full path"; else fail "anchored user settings were missed by the pre-filter"; fi
printf '{"pluginConfigs":{}}\n' >"$SRC_ROOT/settings.json"
src_probe
if [[ ! -e "$SRC_MARK" ]]; then ok "user settings without the gate key stay on the early exit"; else fail "user settings without the gate key reached the libraries"; fi

MANAGED_CWD="$(mktemp -d "$WORK/managedcwd.XXXXXX")"
mkdir -p "$MANAGED_CWD/C:/lane-stop-gate-probe" 2>/dev/null || true
if (cd "$MANAGED_CWD" && [[ -d "C:/lane-stop-gate-probe" ]]); then
  mkdir -p "$MANAGED_CWD/C:/Program Files/ClaudeCode/managed-settings.d"
  printf '{"pluginConfigs":{"autonomy@melodic":{"options":{"lane_stop_gate_enabled":false}}}}\n' \
    >"$MANAGED_CWD/C:/Program Files/ClaudeCode/managed-settings.d/50-lane.json"
  SRC_CWD="$MANAGED_CWD" src_probe
  if [[ -e "$SRC_MARK" ]]; then ok "a managed-settings drop-in mentioning the gate reaches the full path"; else fail "the pre-filter missed a managed-settings drop-in"; fi
else
  ok "SKIP: the Windows managed path is a real drive here — drop-in route not exercised"
fi

write_settings true
OUT="$(cd "$STAGED_DIR/.." && build_input Stop "no token" false |
  env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
    -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID \
    -u CLAUDE_PLUGIN_DATA \
    CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
    bash hooks/lane-stop-gate.sh 2>/dev/null)"
if is_block "$OUT"; then ok "relative invocation: the pre-filter resolves the anchor and the lane blocks"; else fail "relative invocation lost the enabled lane's block: $OUT"; fi

write_settings true
if command -v cygpath >/dev/null 2>&1; then
  BS_CWD="$UNRELATED"
  BS_ROOT="$(cygpath -m "$CACHE_ROOT")"
  BS_ROOT="${BS_ROOT//\//\\}"
else
  BS_CWD="$(mktemp -d "$WORK/bscwd.XXXXXX")"
  BS_ROOT='C:'
  ln -s "$CACHE_ROOT" "$BS_CWD/C:"
  ln -s "C:/plugins/cache/melodic/autonomy/9.9.9" "$BS_CWD/C:\\plugins\\cache\\melodic\\autonomy\\9.9.9"
fi
OUT="$(cd "$BS_CWD" && build_input Stop "no token" false |
  env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
    -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID \
    -u CLAUDE_PLUGIN_DATA \
    CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
    bash "$BS_ROOT\\plugins\\cache\\melodic\\autonomy\\9.9.9/hooks/lane-stop-gate.sh" 2>/dev/null)"
if is_block "$OUT"; then ok "backslashed drive root: the anchor resolves and the lane blocks"; else fail "backslashed drive root lost the enabled lane's block: $OUT"; fi
if (cd "$BS_CWD" && bash "$BS_ROOT\\plugins\\cache\\melodic\\autonomy\\9.9.9/hooks/lane-stop-gate-arm.sh" \
  --id "bs-arm-id-4420" --cwd "$WORK" 2>/dev/null); then
  ok "backslashed drive root: the arm helper resolves the anchor"
else
  fail "backslashed drive root: the arm helper found no anchor"
fi

NOSPAWN="$(mktemp -d "$WORK/nospawn.XXXXXX")"
NOSPAWN_MARK="$WORK/nospawn-launched.txt"
for t in uname realpath readlink cygpath dirname basename jq grep sed tr cat awk date cksum find wc; do # portability-ok: a list of stub NAMES, not a date -d invocation
  # shellcheck disable=SC2016 # $0 is the STUB's own argument, expanded when it runs
  printf '#!/bin/sh\nprintf "%%s\\n" "$0" >>"%s"\nexit 99\n' "$NOSPAWN_MARK" >"$NOSPAWN/$t"
  chmod +x "$NOSPAWN/$t"
done
rm -f "$SETTINGS" "$NOSPAWN_MARK"
NOSPAWN_OUT="$(cd "$UNRELATED" && env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
  -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
  -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
  -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID \
  -u CLAUDE_PLUGIN_DATA \
  CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false HOOK_TELEMETRY_SINK="" \
  PATH="$NOSPAWN" "$BASH" "$HOOK" <"$PROBE_PAYLOAD" 2>&1)"
NOSPAWN_RC=$?
if [[ $NOSPAWN_RC -eq 0 && -z "$NOSPAWN_OUT" ]]; then
  ok "PATH-shim: the interactive default path still exits 0 silently"
else
  fail "PATH-shim: default path (rc=$NOSPAWN_RC out=$NOSPAWN_OUT)"
fi
if [[ -s "$NOSPAWN_MARK" ]]; then
  fail "PATH-shim: the default path launched $(tr '\n' ' ' <"$NOSPAWN_MARK") — it must launch nothing"
else
  ok "PATH-shim: the default path launches no external command at all"
fi

write_settings true
OUT="$(run "$(build_input Stop "no token" false)")"
if is_block "$OUT"; then ok "an enabled lane still blocks after the pre-filter lost uname"; else fail "the pre-filter change lost the enabled lane's block: $OUT"; fi

if command -v strace >/dev/null 2>&1 && strace -qq -o /dev/null -e trace=execve true 2>/dev/null; then
  trace_hook() {
    local input="$1" log="$WORK/gate-strace.log"
    TRACE_OUT=$(cd "$UNRELATED" && printf '%s' "$input" |
      env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
        -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
        -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
        -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID \
        -u CLAUDE_PLUGIN_DATA \
        CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false HOOK_TELEMETRY_SINK="" \
        strace -f -qq -e trace=clone,clone3,fork,vfork,execve -o "$log" bash "$HOOK" 2>/dev/null)
    TRACE_CREATIONS=$(grep -cE '^[0-9]+ +(clone|clone3|fork|vfork)\(' "$log" 2>/dev/null | tr -cd '0-9')
    TRACE_PROGS=$(grep -E '^[0-9]+ +execve\(' "$log" 2>/dev/null | grep -v 'ENOENT' |
      sed -E 's/^[0-9]+ +execve\("([^"]*)".*/\1/; s|.*/||' | tail -n +2 | tr '\n' ' ')
    TRACE_LAUNCHES=$(printf '%s' "$TRACE_PROGS" | wc -w | tr -cd '0-9')
    [[ -s "$log" ]]
  }
  replaced_helper_back() {
    case " $1" in
    *' dirname '* | *' tr '* | *' sed '* | *' grep '* | *' cksum '* | *' date '*) return 0 ;;
    *) return 1 ;;
    esac
  }

  rm -f "$SETTINGS"
  if trace_hook "$(build_input Stop "no token" false)"; then
    ok "strace: the interactive default path was traced"
    if [[ -z "$TRACE_OUT" ]]; then ok "strace: the traced default path stayed silent (it is the real default path)"; else fail "strace: the traced default path emitted output: $TRACE_OUT"; fi
    if [[ "$TRACE_CREATIONS" == "0" ]]; then
      ok "strace: the default path creates no process at all"
    else
      fail "strace: default path creates $TRACE_CREATIONS processes, budget is 0 (launches: $TRACE_PROGS)"
    fi
    if [[ -z "$TRACE_PROGS" ]]; then
      ok "strace: the default path launches nothing"
    else
      fail "strace: default path launched '$TRACE_PROGS', expected nothing"
    fi
  else
    fail "strace: no usable trace captured for the default path"
  fi

  write_settings true
  if trace_hook "$(build_input Stop "no token" false)"; then
    ok "strace: the enabled block path was traced"
    if is_block "$TRACE_OUT"; then ok "strace: the traced enabled path is the real block path"; else fail "strace: the traced enabled path did not block: $TRACE_OUT"; fi
    if [[ -n "$TRACE_CREATIONS" && "$TRACE_CREATIONS" -le 10 ]]; then
      ok "strace: the enabled block path creates $TRACE_CREATIONS processes (ceiling 10)"
    else
      fail "strace: enabled block path creates $TRACE_CREATIONS processes, ceiling is 10 (launches: $TRACE_PROGS)"
    fi
    if [[ -n "$TRACE_LAUNCHES" && "$TRACE_LAUNCHES" -le 5 ]]; then
      ok "strace: the enabled block path launches $TRACE_LAUNCHES programs (ceiling 5)"
    else
      fail "strace: enabled block path launches $TRACE_LAUNCHES programs, ceiling is 5: $TRACE_PROGS"
    fi
    if replaced_helper_back "$TRACE_PROGS"; then
      fail "strace: a helper process this change replaced is back on the enabled path: $TRACE_PROGS"
    else
      ok "strace: no dirname, tr, sed, grep, cksum or date on the enabled path"
    fi
  else
    fail "strace: no usable trace captured for the enabled path"
  fi
else
  ok "SKIP: strace unavailable — process-creation budget not asserted here"
fi

if jq -e '[.hooks.Stop[].hooks[].args] == [[
    "${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs",
    "--run-if-any-set", "LANE_STOP_GATE_ARM_ID,LANE_STOP_GATE_ENABLED",
    "--run-if-settings-mention", "lane_stop_gate",
    "${CLAUDE_PLUGIN_ROOT}/hooks/lane-stop-gate.sh"]]' "$HOOK_DIR/hooks.json" >/dev/null; then
  ok "the Stop row gates the launcher on ARM_ID, ENABLED, or a settings mention"
else
  fail "the Stop row's launcher gate no longer matches gate_maybe_configured"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
