#!/usr/bin/env bash
# Black-box contract test for lane-stop-gate.sh (autonomy Stop hook).
#
# Proves WIRING: default-OFF inertness, the completion-signal matrix (sentinel
# token / marker file), the standalone-token match guard, the one-nudge-then-
# allow+notify loop behavior via stop_hook_active, the Stop-only event guard,
# fail-open on empty stdin and missing jq, that a legitimate signaled stop is
# allowed silently — and, since #1784, that gate config is honored from TRUSTED
# sources only: the user settings.json derived from the hook's own install
# anchor, and the launcher-written arm record, never the bare
# CLAUDE_PLUGIN_OPTION_* environment.
#
# The whole suite therefore runs the hook from a STAGED synthetic install
# (<root>/plugins/cache/<marketplace>/<name>/<version>/hooks/), because an
# unanchored checkout invocation has no trusted user-settings location and can
# never enable the gate — which is itself the documented --plugin-dir behavior.
# The managed-settings layer reads fixed root-owned system paths and is
# deliberately not seam-injectable (an override would BE the tamper channel),
# so it is exercised only through the shared reader the user-settings cases
# cover, not end-to-end.
#
# Self-contained: installed plugins are cache-isolated with no shared test lib,
# so this defines its own assertions and builds throwaway inputs with jq. The OS
# toast is never exercised here (notification channels are disabled on the paths
# that would fire one) — lane-notify.test.sh covers the notifier.

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

# --- Staged install (the trust anchor everything reads from) ------------------
CACHE_ROOT="$(mktemp -d "$WORK/install.XXXXXX")"
STAGED_DIR="$CACHE_ROOT/plugins/cache/melodic/autonomy/9.9.9/hooks"
mkdir -p "$STAGED_DIR"
cp "$HOOK_DIR"/*.sh "$STAGED_DIR/"
HOOK="$STAGED_DIR/lane-stop-gate.sh"
ARM="$STAGED_DIR/lane-stop-gate-arm.sh"
PLUGIN_ID="autonomy@melodic"
SETTINGS="$CACHE_ROOT/settings.json"
DATA_DIR="$CACHE_ROOT/plugins/data/autonomy-melodic"

# build_input — assemble a Stop payload. Positional: event, last message,
# stop_hook_active, cwd, session id (default test-sess).
build_input() {
  local event="${1:-Stop}" last="${2:-}" stop_active="${3:-false}" cwd="${4:-}" sess="${5:-test-sess}"
  MSYS_NO_PATHCONV=1 jq -n \
    --arg e "$event" --arg l "$last" --argjson s "$stop_active" --arg c "$cwd" --arg sid "$sess" \
    '{hook_event_name:$e, last_assistant_message:$l, stop_hook_active:$s, cwd:$c, session_id:$sid}'
}

# write_settings <enabled> [sentinel-set sentinel] [marker-set marker] — write
# the staged user settings.json carrying the gate's pluginConfigs entry.
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

# run <input> [KEY=VAL ...] — invoke the staged hook from an unrelated cwd with
# a hermetic env and notifications muted. The three gate option spellings
# (CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED/SENTINEL/MARKER) are intercepted
# and written into the staged user settings.json — the trusted channel — AND
# still exported to the environment, mirroring what the harness injects for a
# configured key; the gate must take its values from the settings, not the env.
# A RAWENV_-prefixed spelling is exported to the environment ONLY (no settings
# entry): that is the repo-env-block attack shape the #1784 cases pin.
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

# run_bare <input> [KEY=VAL ...] — invoke the staged hook with NO settings file
# at all: only what the caller exports exists. The shape of an interactive
# session, and of the repo-env attack.
run_bare() {
  local input="$1"
  shift
  rm -f "$SETTINGS"
  (cd "$UNRELATED" && printf '%s' "$input" |
    env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED \
      -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL \
      -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER \
      -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID \
      -u CLAUDE_PLUGIN_DATA \
      CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
      "$@" \
      bash "$HOOK" 2>/dev/null)
}

is_block() { printf '%s' "$1" | jq -e '.decision == "block"' >/dev/null 2>&1; }

# --- Case 1: gate unconfigured everywhere → silent exit 0 -------------------
OUT="$(run_bare "$(build_input Stop "" false)")"
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

# --- Case 5: marker file exists → allow, and the marker is CONSUMED ---------
# One marker, one authorized stop: a file left by a prior completed run must
# not authorize every stop of a later lane run in the same checkout.
MARK="$WORK/done.marker"
: >"$MARK"
OUT="$(run "$(build_input Stop "no token here" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$MARK")"
if is_block "$OUT"; then fail "marker present → still blocked: $OUT"; else ok "marker file present → stop allowed"; fi
if [[ -f "$MARK" ]]; then fail "marker not consumed after authorizing a stop"; else ok "marker consumed on use"; fi
OUT="$(run "$(build_input Stop "no token here" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$MARK")"
if is_block "$OUT"; then ok "consumed marker no longer authorizes the next stop"; else fail "stale marker path wrongly allowed after consumption: $OUT"; fi
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
write_settings true
OUT="$(cd "$UNRELATED" && env CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true bash "$HOOK" </dev/null 2>&1)"
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "empty stdin → silent exit 0 (fail-open)"; else fail "empty stdin (rc=$RC out=$OUT)"; fi

# --- Case 11: custom sentinel via trusted settings → allow ------------------
OUT="$(run "$(build_input Stop "queue empty
DONE-ROTATE" false)" CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="DONE-ROTATE")"
if is_block "$OUT"; then fail "custom sentinel → still blocked: $OUT"; else ok "custom sentinel honored → allowed"; fi

# --- Case 12: jq absent → visible systemMessage notice + exit 0 (fail-open) --
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash dirname cat env printf mktemp mkdir find tr grep sed uname sleep git awk date; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
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

# --- Case 19: a marker whose deletion FAILS is still consumed ---------------
# Regression (#1784): consumption was latched ONLY by deleting the marker, so
# an `rm` the OS refuses left a file that satisfied `[[ -f ]]` on a later,
# unrelated lane run — the cross-run bypass consuming the marker exists to
# close. Deletion is made to fail with a PATH-stub `rm`: a read-only parent
# directory does not reliably block deletion on every host this suite runs on,
# an `rm` that refuses does. The consumption ledger lands under the staged
# install's derived data directory (cases 22-23 pin that derivation).
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

# --- Case 20: the surviving marker does not authorize a later run -----------
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STICKY")"
if is_block "$OUT"; then ok "an undeletable consumed marker does not authorize a later run"; else fail "a surviving consumed marker wrongly authorized a later run: $OUT"; fi

# --- Case 21: recreating the marker authorizes again ------------------------
# The consumption record is keyed to the file that was consumed, not to the
# path forever — a fresh marker is a fresh signal.
printf 'done\n' >"$STICKY"
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STICKY")"
if is_block "$OUT"; then fail "a recreated marker was wrongly treated as consumed: $OUT"; else ok "a recreated marker authorizes a stop again"; fi
if [[ -f "$STICKY" ]]; then fail "recreated marker not consumed after authorizing a stop"; else ok "recreated marker consumed on use"; fi

# --- Case 21b: the same-second, same-size recreation boundary ---------------
# Pins the DOCUMENTED limit of the identity read rather than an aspiration: the
# portable `stat` mtime is whole-second, so an empty marker recreated at the
# same size within the same second is indistinguishable from the consumed one
# and stays latched. Case 21 above changes the size, which is why it recovers.
#
# The collision is FORCED with `touch -r` rather than raced for: recreating and
# hoping the wall clock has not ticked yields a case that passes on either
# outcome, which pins nothing. Copying the consumed file's own timestamp makes
# the boundary a decision this suite owns, so a future finer-grained identity
# has to move this case deliberately, and the gate's failure direction (a stop
# delayed, never a second unearned one) is what is actually held.
STICKY2="$WORK/sticky2.marker"
MTIME_REF="$WORK/sticky2.mtime-ref"
: >"$STICKY2"
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STICKY2" \
  PATH="$RMFAIL:$PATH")"
if is_block "$OUT"; then fail "same-second setup: marker did not authorize: $OUT"; else ok "same-second setup: marker authorizes once"; fi
if [[ -f "$STICKY2" ]]; then ok "same-second setup: the rm stub prevented the delete (case precondition)"; else fail "same-second setup: the rm stub did not take — the case would prove nothing"; fi
touch -r "$STICKY2" "$MTIME_REF" # the consumed file's own mtime, before it moves
: >"$STICKY2"                    # recreate: same size (0), new mtime
touch -r "$MTIME_REF" "$STICKY2" # force the same whole second the record holds
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STICKY2" \
  PATH="$RMFAIL:$PATH")"
if is_block "$OUT"; then ok "same-second same-size recreation stays latched (documented coarse-identity limit)"; else fail "same-second same-size recreation read as a fresh signal — the identity read got finer without this case moving: $OUT"; fi

# --- Case 22: the ledger is keyed to the hook's OWN install path ------------
# The tamper-resistant property the ledger rests on is the primary path: the
# data directory derived from the script's location under the documented
# plugins/cache anchor, which no repo file reaches. An unrelated
# CLAUDE_PLUGIN_DATA is present to show it does NOT win.
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

# --- Case 23: the install-derived record is honored on the next run ---------
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$STAGED_MARKER")"
if is_block "$OUT"; then ok "staged install: the derived record blocks a later run"; else fail "staged install: a consumed marker wrongly authorized a later run: $OUT"; fi

# ============================================================================
# #1784 P1 — the enable flag (and sentinel/marker) come from trusted channels
# only; the bare environment is never authority.
# ============================================================================

# --- Case 24: a repo env block cannot enable the gate (the pinned attack) ---
# Channel B's unset case: nothing trusted configures the gate, and the
# environment — which a watched repository's own .claude/settings.json `env`
# block populates freely for an unconfigured key — claims enabled=true. The
# gate must stay OFF, and must say so visibly (a silent disengage would hide
# both this attack and a stale launcher).
OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true)"
RC=$?
if is_block "$OUT"; then fail "env-only ENABLED=true wrongly engaged the gate (channel-B authority): $OUT"; else ok "env-only ENABLED=true does not engage the gate"; fi
if [[ $RC -eq 0 && "$OUT" == *'"systemMessage"'* && "$OUT" == *"environment channel"* ]]; then
  ok "env-only enable claim surfaces a visible notice instead of silence"
else
  fail "env-only enable claim not surfaced (rc=$RC out=$OUT)"
fi

# --- Case 25: a repo env block cannot weaken the sentinel -------------------
# On a trusted-enabled session, an env-only SENTINEL must be ignored: the
# easy token does not authorize, and the trusted default still does.
OUT="$(run "$(build_input Stop "some ordinary line
EASY" false)" RAWENV_CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="EASY")"
if is_block "$OUT"; then ok "env-only sentinel is not honored (weakened token does not authorize)"; else fail "env-only sentinel wrongly honored: $OUT"; fi
OUT="$(run "$(build_input Stop "LANE-STOP-OK" false)" RAWENV_CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="EASY")"
if is_block "$OUT"; then fail "trusted default sentinel stopped working under an env-only override: $OUT"; else ok "trusted default sentinel still authorizes under an env-only override"; fi

# --- Case 26: a repo env block cannot point the gate at its own marker ------
# On a trusted-enabled session with NO trusted marker configured, an env-only
# MARKER naming an existing file must not authorize the stop.
ATTACK_MARKER="$WORK/attack.marker"
: >"$ATTACK_MARKER"
OUT="$(run "$(build_input Stop "no token" false)" \
  RAWENV_CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER="$ATTACK_MARKER")"
if is_block "$OUT"; then ok "env-only marker path is not honored"; else fail "env-only marker path wrongly authorized a stop: $OUT"; fi
if [[ -f "$ATTACK_MARKER" ]]; then ok "env-only marker file left untouched"; else fail "env-only marker file was consumed despite not being trusted"; fi

# --- Case 27: a trusted explicit false wins silently ------------------------
# enabled=false configured in user settings + env claiming true → off, and NO
# notice: a configured verdict is not an unhonored claim.
OUT="$(run "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=false \
  RAWENV_CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true)"
if is_block "$OUT"; then fail "configured enabled=false wrongly engaged the gate: $OUT"; else ok "configured enabled=false keeps the gate off"; fi
if [[ "$OUT" == *systemMessage* ]]; then fail "configured false wrongly emitted the unhonored-claim notice: $OUT"; else ok "configured false stays silent (a verdict, not an unhonored claim)"; fi

# --- Case 28: an unreadable trusted source contributes no verdict (fail-open)
# Malformed user settings + env claiming true → off with the visible notice,
# never a wedged stop and never an env fallback.
printf '{ not json' >"$SETTINGS"
OUT="$(cd "$UNRELATED" && build_input Stop "no token" false |
  env -u CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID -u CLAUDE_PLUGIN_DATA \
    CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED=true \
    CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED=false \
    bash "$HOOK" 2>/dev/null)"
RC=$?
if [[ $RC -eq 0 ]] && ! is_block "$OUT"; then ok "malformed user settings → gate off, stop allowed (fail-open)"; else fail "malformed user settings (rc=$RC out=$OUT)"; fi
if [[ "$OUT" == *'"systemMessage"'* ]]; then ok "malformed settings + env claim → visible notice"; else fail "malformed settings + env claim stayed silent: $OUT"; fi

# ============================================================================
# #1784 P1 — the arm record: the launcher's per-session trusted channel.
# ============================================================================
ARM_ID_1="cafe1234deadbeef"

# --- Case 29: arming enables the gate with NO settings entry at all ---------
LANE_MARKER="$WORK/lane.marker"
bash "$ARM" --id "$ARM_ID_1" --cwd "$WORK" --marker "$LANE_MARKER" 2>/dev/null ||
  fail "arm helper refused a valid arming (precondition for cases 29-32)"
if [[ -f "$DATA_DIR/lane-arms/$ARM_ID_1" ]]; then ok "arm record lands under the install-derived data directory"; else fail "arm record missing from $DATA_DIR/lane-arms"; fi
OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_1")"
if is_block "$OUT"; then ok "an armed session is gated (no settings entry needed)"; else fail "an armed session was not gated: $OUT"; fi

# --- Case 30: the record's marker is honored; the record SURVIVES the stop ---
# A lane is one session across many /loop cycles: the record must not be
# consumed by a single completion-signaled stop, or every later cycle runs
# ungated (#1784, finding 2).
: >"$LANE_MARKER"
OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_1")"
if is_block "$OUT"; then fail "record-configured marker did not authorize: $OUT"; else ok "record-configured marker authorizes the stop"; fi
if [[ -f "$DATA_DIR/lane-arms/$ARM_ID_1" ]]; then ok "the arm record survives a completion-signaled stop (not consumed)"; else fail "arm record was consumed on a stop — a later /loop cycle would run ungated"; fi

# --- Case 30b: a LATER stop in the same armed session is still gated ---------
# The record persisted through case 30's signaled stop; a subsequent unsignaled
# stop of the same session must still be caught. This is the multi-cycle
# coverage the no-consume design protects.
rm -f "$LANE_MARKER"
OUT="$(run_bare "$(build_input Stop "no token this cycle" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_1")"
if is_block "$OUT"; then ok "a later cycle of the same armed session is still gated (record persisted)"; else fail "a later cycle ran ungated after an earlier signaled stop: $OUT"; fi

# --- Case 31: a DANGLING arm id does not engage the gate, with the RIGHT notice
# An id whose record never existed (or was cleaned up) is not the env attack —
# the notice must not blame a repo env block; it must point at re-arming.
OUT="$(run_bare "$(build_input Stop "no token" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="deadbeefdeadbeef")"
if is_block "$OUT"; then fail "a dangling arm id wrongly engaged the gate: $OUT"; else ok "a dangling arm id does not engage the gate"; fi
if [[ "$OUT" == *'"systemMessage"'* && "$OUT" == *"no matching arm record"* ]]; then
  ok "a dangling arm id surfaces the arm-specific notice (not the env-attack notice)"
else
  fail "a dangling arm id gave the wrong or no notice: $OUT"
fi
if [[ "$OUT" == *"environment channel"* ]]; then fail "a dangling arm id wrongly blamed the env channel"; else ok "a dangling arm id does not blame the env channel"; fi

# --- Case 32: a replayed arm id is refused for a different session ----------
# First presenter claims the record; a later session presenting the same id
# (the shape of a leaked id served back via a repo env block) gets nothing.
ARM_ID_2="feedface00112233"
bash "$ARM" --id "$ARM_ID_2" --cwd "$WORK" 2>/dev/null
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-A")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_2")"
if is_block "$OUT"; then ok "arm id claimed by its first session (gated)"; else fail "first session with a fresh arm id not gated: $OUT"; fi
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-B")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_2")"
if is_block "$OUT"; then fail "a replayed arm id engaged the gate for a different session: $OUT"; else ok "a replayed arm id is refused for a different session"; fi

# --- Case 33: the record's sentinel is honored ------------------------------
ARM_ID_3="0123456789abcdef"
bash "$ARM" --id "$ARM_ID_3" --cwd "$WORK" --sentinel "DONE-LANE-7" 2>/dev/null
OUT="$(run_bare "$(build_input Stop "wrapping up
DONE-LANE-7" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_3")"
if is_block "$OUT"; then fail "record-configured sentinel did not authorize: $OUT"; else ok "record-configured sentinel authorizes the stop"; fi

# --- Case 34: an expired record does not engage the gate --------------------
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

# --- Case 35: a post-nudge (down-lane) stop is allowed; record still survives
# The record is not consumed here either — the session may /loop onward.
ARM_ID_5="1234abcd5678efab"
bash "$ARM" --id "$ARM_ID_5" --cwd "$WORK" 2>/dev/null
OUT="$(run_bare "$(build_input Stop "still no token" true)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_5")"
if is_block "$OUT"; then fail "post-nudge armed stop wrongly blocked: $OUT"; else ok "post-nudge armed stop allowed"; fi
if [[ -f "$DATA_DIR/lane-arms/$ARM_ID_5" ]]; then ok "the arm record survives a post-nudge stop (not consumed)"; else fail "arm record was consumed on the post-nudge stop"; fi

# --- Case 36: a traversal-shaped arm id is rejected — at the GUARD, provably --
# The gate not blocking would pass whether or not the id-shape guard existed
# (a traversal path is not a readable JSON record either way), so this pins the
# guard directly: gate_arm_record_path must REFUSE a traversal id, so no path
# under lane-arms/ can ever be escaped. Sourced from the staged lib.
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

# --- Case 37: the arm helper refuses to arm without an install anchor -------
# A --plugin-dir checkout install has no trusted record store; arming must fail
# closed (the launcher then skips the lane) rather than write to a forgeable
# location.
UNANCHORED="$(mktemp -d "$WORK/unanchored.XXXXXX")"
cp "$HOOK_DIR"/*.sh "$UNANCHORED/"
if bash "$UNANCHORED/lane-stop-gate-arm.sh" --id "$ARM_ID_1" --cwd "$WORK" 2>/dev/null; then
  fail "the arm helper armed without a plugins/cache anchor"
else
  ok "the arm helper fails closed without a plugins/cache anchor"
fi

# --- Case 38: the managed-settings path is selected by uname, not $OSTYPE ----
# Regression guard for #1784 finding 1: $OSTYPE is a bash variable a repo `env`
# block can set, so branching the highest-precedence (managed) scope on it let a
# repo suppress or relocate it. Selection now reads `uname -s`, and the resolved
# primary is asserted absolute. Sourced from the staged lib; `uname` is stubbed
# so the platform is controlled independently of the host, and $OSTYPE is set
# hostile.
if (
  # shellcheck source=/dev/null
  source "$STAGED_DIR/lane-stop-gate-lib.sh"
  # shellcheck disable=SC2329 # invoked indirectly by gate_managed_settings_files
  uname() { printf '%s\n' "${STUB_UNAME:-Linux}"; }
  export OSTYPE=msys # would force the Windows relative-on-POSIX branch in old code
  # Every emitted managed path must be absolute, whatever uname reports.
  for plat in Linux Darwin MINGW64_NT CYGWIN_NT bogus-platform; do
    STUB_UNAME="$plat"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      case "$line" in
      /* | [A-Za-z]:[/\\]*) ;;
      *) exit 1 ;; # a relative (cwd-resolved, repo-plantable) managed path
      esac
    done < <(gate_managed_settings_files)
  done
  # An unrecognized platform yields NO managed file, regardless of $OSTYPE.
  STUB_UNAME="bogus-platform"
  [[ -z "$(gate_managed_settings_files)" ]] || exit 1
  exit 0
); then
  ok "managed-settings selection ignores hostile \$OSTYPE and never yields a relative path"
else
  fail "managed-settings path selection is influenced by \$OSTYPE or can be relative (#1784 finding 1)"
fi

# --- Case 39: an UNANCHORED install still reads managed settings ------------
# A --plugin-dir checkout has no plugins/cache anchor, so no marketplace
# qualifier to match — but managed settings are its ONLY enable path, and the
# arm helper refuses to arm there precisely on that premise (case 37). Keying
# the read on the anchor alone would make an org's managed mandate silently
# not apply to that whole install class. The reader falls back to the manifest
# name; anchored installs keep their exact-id match so another marketplace's
# entry cannot mask this install's.
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
  # A bare key and a marketplace-qualified key both reach an unanchored install.
  printf '{"pluginConfigs":{"autonomy":{"options":{"lane_stop_gate_enabled":true}}}}\n' >"$MANAGED_STUB"
  [[ "$(gate_settings_option "$MANAGED_STUB" lane_stop_gate_enabled)" == "true" ]] || exit 1
  printf '{"pluginConfigs":{"autonomy@melodic":{"options":{"lane_stop_gate_enabled":true}}}}\n' >"$MANAGED_STUB"
  [[ "$(gate_settings_option "$MANAGED_STUB" lane_stop_gate_enabled)" == "true" ]] || exit 1
  # A different plugin's entry must NOT be picked up.
  printf '{"pluginConfigs":{"other@melodic":{"options":{"lane_stop_gate_enabled":true}}}}\n' >"$MANAGED_STUB"
  gate_settings_option "$MANAGED_STUB" lane_stop_gate_enabled >/dev/null 2>&1 && exit 1
  exit 0
); then
  ok "an unanchored install resolves managed settings by manifest name"
else
  fail "an unanchored (--plugin-dir) install cannot read managed settings — its only enable path"
fi
# The anchored install must still match ONLY its exact marketplace-qualified id.
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

# --- Case 40: an empty configured sentinel falls back to the default --------
# Emptiness is not a documented way to disable the token channel, and honoring
# it would leave the block reason instructing the agent to emit an empty token.
OUT="$(run "$(build_input Stop "LANE-STOP-OK" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="")"
if is_block "$OUT"; then fail "an empty configured sentinel silenced the token channel: $OUT"; else ok "an empty configured sentinel falls back to the default token"; fi
OUT="$(run "$(build_input Stop "no token here" false)" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL="")"
if [[ "$OUT" == *'LANE-STOP-OK'* ]]; then ok "the nudge names the default token, never an empty one"; else fail "the nudge did not name a usable token: $OUT"; fi

# The claim-ownership cases below assert the exit code alongside the decision.
# A Stop hook that starts exiting non-zero — 127 for a helper that stopped
# resolving — is a regression a stdout-only assertion passes over in silence.
rc0() {
  [[ -n "${1:-}" ]] || fail "$2 had no exit code to check"
  [[ "$1" -eq 0 ]] || fail "$2 exited $1"
}

# --- Case 41: the PERSISTED owner decides, not the presenting session --------
# Case 32 proves a sequential replay is refused; that passes whether the claim
# is atomic or a read-then-write. This pins the verify-the-owner clause with a
# guaranteed signal: a claim sidecar already naming another session must refuse
# the presenter outright, and must still honor the session it names.
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

# --- Case 42: re-arming the same id clears the claim ------------------------
# The sidecar outlives the record it names, so an id re-armed for a new lane
# would otherwise stay bound to the dead session and the new lane run ungated.
bash "$ARM" --id "$ARM_ID_6" --cwd "$WORK" 2>/dev/null
if [[ -e "$DATA_DIR/lane-arms/$ARM_ID_6.claim" ]]; then fail "re-arming left the previous lane's claim in place"; else ok "re-arming clears the previous lane's claim"; fi
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-relaunched")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_6")"
rc0 $? "the relaunched lane's first claim"
if is_block "$OUT"; then ok "a re-armed id is claimable by the relaunched lane"; else fail "a re-armed id stayed bound to the previous lane: $OUT"; fi

# --- Case 43: a record claimed before the sidecar existed stays bound -------
# Compatibility: an in-record session_id is authoritative and has no sidecar, so
# an upgrade must not let a second session claim a record already bound.
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

# --- Case 44: concurrent presenters of one fresh id — exactly one wins ------
# The race the atomic claim exists to close: N sessions presenting the same
# fresh id at once. A read-then-write claim lets every one of them read the
# record unclaimed and honor the arm, and the last writer binds it — leaving
# the legitimate lane ungated on every later stop. Settings are removed once up
# front so the concurrent invocations share no file the harness rewrites.
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

# --- Case 45: a durably ownerless claim honors the arm ----------------------
# The fall-through direction of the re-read that closes case 44's window. A
# claim whose owner never lands (a winner that died mid-write) must NOT make the
# record permanently unclaimable — that is the original finding's harm in a new
# shape. Over-gate instead: honor every presenter for as long as it lasts.
ARM_ID_9="1234abcd5678ef90"
bash "$ARM" --id "$ARM_ID_9" --cwd "$WORK" 2>/dev/null
: >"$DATA_DIR/lane-arms/$ARM_ID_9.claim"
OUT="$(run_bare "$(build_input Stop "no token" false "" "sess-after-a-dead-writer")" \
  CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID="$ARM_ID_9")"
rc0 $? "the stop that met an ownerless claim"
if is_block "$OUT"; then ok "an ownerless claim still honors the arm (fail direction: gate ON)"; else fail "an ownerless claim left the lane ungated: $OUT"; fi

# --- Case 46: a non-regular file at the claim path decides nothing ----------
# The claim is a second predictable name in the store, and the record path has
# always been `[[ -f ]]`-guarded. Without the same guard a planted FIFO takes
# the write with no reader and the whole Stop event hangs until the harness
# gives up — a stop allowed on every attempt, i.e. an ungated lane. Watchdogged
# rather than run bare, so a regression fails this suite instead of stalling CI.
ARM_ID_10="fedcba9876543210"
bash "$ARM" --id "$ARM_ID_10" --cwd "$WORK" 2>/dev/null
rm -f "$SETTINGS"
if ! mkfifo "$DATA_DIR/lane-arms/$ARM_ID_10.claim" 2>/dev/null; then
  ok "mkfifo unavailable; skip non-regular claim path hang case"
else
FIFO_INPUT=$(build_input Stop "no token" false "" "sess-fifo")
FIFO_OUT="$WORK/fifo-out"
FIFO_RC=0
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

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
