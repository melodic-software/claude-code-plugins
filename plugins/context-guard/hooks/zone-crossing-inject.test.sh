#!/usr/bin/env bash
# Contract test for zone-crossing-inject.sh (PostToolBatch/UserPromptSubmit).
#
# Contract: emit ONCE per transition into a WORSE zone, splitting the report
# across two channels — the counter-steer to the model, the continuation menu to
# the operator; silent while the zone is unchanged, improving, or unknown;
# unknown never updates state; kill switch honored; hostile ids fail open.
# Exit 0 always.
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

# 1b. Channel separation. The continuation menu is the OPERATOR's choice
# and must reach systemMessage only; the model's channel carries the
# determination plus the counter-steer and never an exit menu, because an
# injected menu manufactures the model's own initiative to stop (catalog I23).
CTX=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$OUT" 2>/dev/null)
SYS=$(jq -r '.systemMessage // ""' <<<"$OUT" 2>/dev/null)
menu_free=1
for token in "/compact" "/clear" "/session-flow:workflow" "/session-flow:handoff"; do
  [[ "$CTX" == *"$token"* ]] && menu_free=0
done
if ((menu_free)) && [[ "$CTX" == *"Do not volunteer"* ]]; then
  ok "model channel carries the counter-steer and no exit menu"
else
  fail "model channel leaked an exit menu or lost the counter-steer: $CTX"
fi
# The model channel may say the choice is the operator's; it may never say the
# operator has SEEN it. Nothing tells a hook whether an operator is present, so
# a delivery claim is unknowable in every mode. Asserted here so the sentence
# cannot creep back on a later rewording pass.
if [[ "$CTX" != *"has been shown"* && "$CTX" != *"shown to"* && "$CTX" == *"operator's call"* ]]; then
  ok "model channel claims ownership without claiming delivery"
else
  fail "model channel asserts operator receipt it cannot know: $CTX"
fi
if [[ "$SYS" == *"/compact"* && "$SYS" == *"/session-flow:handoff"* && "$SYS" == *"yours to choose"* ]]; then
  ok "operator channel carries the continuation menu"
else
  fail "operator channel missing the continuation menu: $SYS"
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

# 4. Relapse after a FULL recovery (dumb → smart → acceptable) injects again.
# smart is the bottom of the ladder, so the armed marker decayed and the ladder
# re-armed. This is the discriminating half of the hysteresis pair: a real
# recovery must not be silenced by the rule that silences a flap.
write_snapshot "$H" s1 60
run "$H" "$D" s1 UserPromptSubmit
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *acceptable* ]]; then
  ok "relapse after a two-rank recovery injects again (UserPromptSubmit)"
else
  fail "relapse: rc=$RC out=$OUT"
fi

# 4a. HYSTERESIS — the flap. A session hovering on the acceptable/dumb boundary
# re-crosses it repeatedly; before the armed rank existed, every re-crossing was
# a fresh "transition" and re-injected the ~1KB block. Only the FIRST dumb here
# may emit.
#
# NOT the recurring 10s-timeout defect fixed in context-guard 0.4.8
# (squash-merged 925c3259), which was about the hook dying before it ran. This
# is about how often it injects WHEN it runs.
write_snapshot "$H" sflap 90 # dumb — first observation, injects
run "$H" "$D" sflap
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *dumb* ]]; then
  ok "flap: the first dumb observation injects"
else
  fail "flap setup did not inject: rc=$RC out=$OUT"
fi
write_snapshot "$H" sflap 60 # acceptable — a ONE-rank dip, below the margin
run "$H" "$D" sflap
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "flap: the one-rank dip is silent"
else
  fail "flap dip emitted: rc=$RC out=$OUT"
fi
if [[ "$(cat "$D/state/sflap.armed" 2>/dev/null)" == "dumb" ]]; then
  ok "flap: a one-rank dip does NOT decay the armed rank"
else
  fail "armed rank decayed on a one-rank dip: $(cat "$D/state/sflap.armed" 2>/dev/null)"
fi
write_snapshot "$H" sflap 90 # back to dumb — the re-crossing that re-injects without the armed gate
run "$H" "$D" sflap
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "flap: re-crossing into an already-reported zone does NOT re-inject"
else
  fail "flap re-crossing re-injected (the #2220 defect): rc=$RC out=$OUT"
fi
# ...and the same session still reports nothing on further oscillation.
write_snapshot "$H" sflap 60
run "$H" "$D" sflap
write_snapshot "$H" sflap 90
run "$H" "$D" sflap
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "flap: repeated oscillation stays silent (injections are bounded, not counted)"
else
  fail "second flap cycle emitted: rc=$RC out=$OUT"
fi

# 4b. HYSTERESIS — the discriminating opposite, on a session of its own so the
# two paths cannot share state: dumb → smart → dumb DOES inject twice, because
# a return to smart is a real state change rather than edge noise.
write_snapshot "$H" srec 90
run "$H" "$D" srec
if [[ "$OUT" == *additionalContext* ]]; then ok "recovery: first dumb injects"; else fail "recovery setup: $OUT"; fi
write_snapshot "$H" srec 10 # smart — the bottom of the ladder, re-arms
run "$H" "$D" srec
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "recovery: the improvement itself is silent"; else fail "improvement emitted: $OUT"; fi
if [[ "$(cat "$D/state/srec.armed" 2>/dev/null)" == "smart" ]]; then
  ok "recovery: a two-rank improvement decays the armed rank"
else
  fail "armed rank did not decay on a full recovery: $(cat "$D/state/srec.armed" 2>/dev/null)"
fi
write_snapshot "$H" srec 90
run "$H" "$D" srec
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *dumb* ]]; then
  ok "recovery: relapse after a genuine recovery injects again"
else
  fail "genuine relapse suppressed by hysteresis: rc=$RC out=$OUT"
fi

# 4d. HYSTERESIS — the same discriminating pair one band lower, on a session of
# its own. `acceptable` is the MIDDLE of the ladder, so the only improvement
# available to it is `smart`: exactly ONE rank. A re-arm rule expressed as a
# fixed rank DELTA cannot see that — under 0.7.0's `armed_rank - new_rank >= 2`
# the difference tops out at 1 here, so the marker could never decay and a
# session that armed at `acceptable` stayed silent through every later relapse
# for the rest of its life. Structurally this path is 4b's, one band down.
#
# It is also the path where a flap and a genuine recovery are the same
# observation: `smart` is both the bottom of the ladder and the far side of the
# `smart`/`acceptable` edge. The rule announces it — a re-arm here is deliberate
# and is the stated residual, not an oversight (see the hook header).
write_snapshot "$H" sacc 60 # acceptable — first observation, injects
run "$H" "$D" sacc
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *acceptable* ]]; then
  ok "middle band: the first acceptable observation injects"
else
  fail "middle band setup did not inject: rc=$RC out=$OUT"
fi
write_snapshot "$H" sacc 10 # smart — a full recovery, one rank from acceptable
run "$H" "$D" sacc
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "middle band: the recovery itself is silent"
else
  fail "middle band recovery emitted: rc=$RC out=$OUT"
fi
if [[ "$(cat "$D/state/sacc.armed" 2>/dev/null)" == "smart" ]]; then
  ok "middle band: a return to smart decays the armed rank"
else
  fail "armed rank did not decay on a full recovery from acceptable: $(cat "$D/state/sacc.armed" 2>/dev/null)"
fi
write_snapshot "$H" sacc 60 # relapse — structurally identical to 4b's relapse
run "$H" "$D" sacc
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *acceptable* ]]; then
  ok "middle band: relapse after a genuine recovery injects again"
else
  fail "genuine relapse from the middle band suppressed: rc=$RC out=$OUT"
fi
# ...and the re-armed ladder latches again exactly as a fresh one does, so the
# recovery bought exactly ONE re-announcement.
run "$H" "$D" sacc
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "middle band: the re-armed ladder latches again (exactly one re-injection)"
else
  fail "middle band re-injected twice for one recovery: rc=$RC out=$OUT"
fi
# A second down-up cycle buys a second announcement and no more. This is the
# stated residual at the `smart`/`acceptable` edge — where a flap and a full
# recovery are the same observation — pinned as an assertion rather than left as
# prose: the cadence is ONE announcement per down-up cycle, bounded rather than
# runaway. 0.7.2's entry additionally called that "the pre-0.7.0 cadence, and no
# worse"; that comparative was never executed against 0.6.6 and is withdrawn in
# 0.7.3. What is asserted here is only what this suite runs.
write_snapshot "$H" sacc 10 # smart — a second full recovery
run "$H" "$D" sacc
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "middle band: the second recovery is silent too"
else
  fail "middle band second recovery emitted: rc=$RC out=$OUT"
fi
write_snapshot "$H" sacc 60
run "$H" "$D" sacc
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *acceptable* ]]; then
  ok "middle band: the second down-up cycle announces exactly once more"
else
  fail "second cycle suppressed: rc=$RC out=$OUT"
fi
run "$H" "$D" sacc
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "middle band: one announcement per down-up cycle, bounded not runaway"
else
  fail "middle band announced twice in one cycle: rc=$RC out=$OUT"
fi

# 4c. LEGACY STATE: a session already running when this version lands has a
# `.zone` file and no `.armed` file. The armed rank seeds from the last-seen
# zone, so the first call after the upgrade decides exactly as the previous
# version would have, and latches from there.
mkdir -p "$D/state"
printf 'acceptable\n' >"$D/state/slegacy.zone"
rm -f "$D/state/slegacy.armed"
write_snapshot "$H" slegacy 90 # acceptable → dumb: a worsening under either rule
run "$H" "$D" slegacy
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *dumb* ]]; then
  ok "legacy state without an .armed marker still injects on a real worsening"
else
  fail "legacy state broke the first post-upgrade decision: rc=$RC out=$OUT"
fi
if [[ "$(cat "$D/state/slegacy.armed" 2>/dev/null)" == "dumb" ]]; then
  ok "legacy state gains an .armed marker on first write (no migration step)"
else
  fail "armed marker not seeded: $(cat "$D/state/slegacy.armed" 2>/dev/null)"
fi

# 4e. CROSS-VERSION STATE: 0.7.1 shipped a dwell whose `.armed` marker carried
# TWO fields — "<zone> <streak>", e.g. "dumb 0" — for one version before 0.7.2
# replaced the rule with a return-to-`smart` target and went back to one word. A
# session that started under 0.7.1 and continued under 0.7.2 still has the
# two-field marker on disk, and the reader must resolve it to the zone rather
# than to a fresh baseline: `tr -cd '[:lower:]'` strips the digit and the
# separator, so the armed rank survives and an already-reported zone stays
# suppressed instead of being announced twice. Held by construction; pinned here
# so the next edit to the reader cannot quietly break it.
mkdir -p "$D/state"
printf 'dumb 0\n' >"$D/state/sdwell.armed"
printf 'dumb\n' >"$D/state/sdwell.zone"
write_snapshot "$H" sdwell 90 # dumb again — already reported under 0.7.1
run "$H" "$D" sdwell
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "a 0.7.1 two-field .armed marker still suppresses an already-reported zone"
else
  fail "0.7.1-format marker misread as a fresh baseline: rc=$RC out=${OUT:0:120}"
fi
if [[ "$(cat "$D/state/sdwell.armed" 2>/dev/null)" == "dumb" ]]; then
  ok "a 0.7.1 two-field .armed marker is rewritten in the one-word format"
else
  fail "0.7.1-format marker not normalized: $(cat "$D/state/sdwell.armed" 2>/dev/null)"
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

# 12a. PARTIAL WRITE, THEN RECOVERY — the half 12 never checked. Failing open
# silently is only correct if the notice SURVIVES the failure. If a marker
# advances while the write that should have accompanied it failed, the hook
# exits without emitting and the next identical observation is then suppressed
# by the emit gate — the first warning is lost though it was never reported.
# So: obstruct, observe the silent failure, confirm NEITHER marker moved, clear
# the obstruction, and demand the injection the session is still owed.
write_snapshot "$H" sretryz 90
mkdir -p "$D/state"
mkdir -p "$D/state/sretryz.zone" # same portable obstruction as 12
TELZ="$WORK/tel-retry-zone.json"
SINKZ="$(make_sink "$TELZ")"
OUT=$(printf '{"session_id":"sretryz","hook_event_name":"PostToolBatch"}' |
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" HOOK_TELEMETRY_SINK="$SINKZ" bash "$HOOK" 2>/dev/null)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "partial write: the blocked observation is silent"
else
  fail "partial write not silent: rc=$RC out=${OUT:0:120}"
fi
if [[ ! -e "$D/state/sretryz.armed" ]]; then
  ok "partial write: the emit gate does NOT advance when its companion write fails"
else
  fail "armed gate advanced on a failed write: $(cat "$D/state/sretryz.armed" 2>/dev/null)"
fi
rm -rf "$D/state/sretryz.zone" # the filesystem recovers
run "$H" "$D" sretryz
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *dumb* ]]; then
  ok "partial write: the unreported warning survives and injects after recovery"
else
  fail "warning lost to a partial write: rc=$RC out=${OUT:0:120}"
fi

# 12b. The mirror image: the OTHER marker blocked. This one already held under
# 0.7.0's ordering (the armed write came first and short-circuited before the
# zone write, so nothing moved) — it is asserted here as a guard on the new
# ordering, which writes the label first and must roll it back rather than
# leave the message reporting a previous zone the session never left.
write_snapshot "$H" sretrya 60 # acceptable — a real first observation
run "$H" "$D" sretrya
if [[ "$OUT" == *additionalContext* ]]; then
  ok "partial write (armed): setup observation injects"
else
  fail "partial write (armed) setup: rc=$RC out=${OUT:0:120}"
fi
rm -f "$D/state/sretrya.armed"
mkdir -p "$D/state/sretrya.armed" # now the GATE file is the blocked one
write_snapshot "$H" sretrya 90    # dumb — a real worsening, owed an injection
TELA="$WORK/tel-retry-armed.json"
SINKA="$(make_sink "$TELA")"
OUT=$(printf '{"session_id":"sretrya","hook_event_name":"PostToolBatch"}' |
  HOME="$H" CLAUDE_PLUGIN_DATA="$D" HOOK_TELEMETRY_SINK="$SINKA" bash "$HOOK" 2>/dev/null)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then
  ok "partial write (armed): the blocked observation is silent"
else
  fail "partial write (armed) not silent: rc=$RC out=${OUT:0:120}"
fi
if wait_for_sink "$TELA" && [[ "$(jq -r '.status' "$TELA" 2>/dev/null)" == "error" ]]; then
  ok "partial write (armed): telemetry status=error"
else
  fail "partial write (armed) telemetry not error: $(cat "$TELA" 2>/dev/null)"
fi
if [[ "$(cat "$D/state/sretrya.zone" 2>/dev/null)" == "acceptable" ]]; then
  ok "partial write (armed): the label marker still reports the zone the session was really in"
else
  fail "label marker moved without its gate: $(cat "$D/state/sretrya.zone" 2>/dev/null)"
fi
rm -rf "$D/state/sretrya.armed"
run "$H" "$D" sretrya
if [[ $RC -eq 0 && "$OUT" == *additionalContext* && "$OUT" == *"from the acceptable"* ]]; then
  ok "partial write (armed): the warning survives and names the true previous zone"
else
  fail "warning lost or mislabelled after an armed-write failure: rc=$RC out=${OUT:0:200}"
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
