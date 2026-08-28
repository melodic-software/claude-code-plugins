#!/usr/bin/env bash
# Black-box contract test for statusline-tee.sh (the rate-limit-guard
# statusline wrapper).
#
# Proves the two-sided contract: (a) TRANSPARENCY — the wrapped statusline
# command receives the stdin JSON and its stdout and exit code pass through
# unchanged, with NO tee failure ever propagating into the pipeline; and
# (b) the TEE — each run atomically writes the contract snapshot
# ($HOME/.claude/rate-limit-guard/rate-limits.json, so tests redirect via
# HOME) carrying captured_at + rate_limits + every session-distinguishing
# field, with the Windows locked-target rename failure handled as
# retry-then-skip. The rename-failure path is driven deterministically by a
# PATH `mv` shim (fail-N-times-then-delegate), which is the portable stand-in
# for the Windows EACCES rename-over-open-target case.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

# Hermeticity for the enablement-gate cases below: both of these are real inputs
# to _rlg_tee_enabled, so a developer's own exported value would otherwise decide
# what this suite proves. Every case supplies its settings through a scoped HOME.
unset CLAUDE_CONFIG_DIR CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED
unset RLG_TEE_ASYNC RLG_TEE_DISABLED_RECHECK

# The render path spools a per-session record with zero forks; ONE elected
# render per cadence drains the batch into the contract file (see THE SPOOL in
# statusline-tee.sh). Pinning the cadence to zero makes every refresh the
# elected one, which is exactly the synchronous visibility every case below
# already assumes — "the snapshot has been written" observable the moment the
# wrapper returns, so an assertion that a snapshot was NOT written cannot pass
# vacuously against a race. EXPORTED, not assigned: the suite runs the tee as a
# child process. Election itself is proven in dedicated cases at the end, which
# set their own cadence per invocation.
export RLG_TEE_DRAIN_INTERVAL=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEE="$SCRIPT_DIR/statusline-tee.sh"

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

TEE_REL=".claude/rate-limit-guard/rate-limits.json"

build_input() {
  # Optional extra top-level JSON fields as "$1" (an object body fragment).
  local extra="${1:-}"
  local base='{"session_id":"sess-42","model":{"id":"claude-opus-4-8","display_name":"Opus"},"context_window":{"used_percentage":8},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}'
  if [[ -n "$extra" ]]; then
    printf '%s,%s}' "$base" "$extra"
  else
    printf '%s}' "$base"
  fi
}

# Runner: HOME-scoped invocation. Remaining args are the wrapped command.
run() {
  local home="$1" input="$2"
  shift 2
  printf '%s' "$input" | HOME="$home" bash "$TEE" "$@"
}

# --- Case 1: passthrough — wrapped stdout and exit 0 --------------------------
HOME1="$WORK/home1"
mkdir -p "$HOME1"
OUT="$(run "$HOME1" "$(build_input)" jq -r '.model.display_name')"
RC=$?
if [[ $RC -eq 0 ]]; then ok "wrapped run exit 0"; else fail "wrapped run exit $RC"; fi
if [[ "$OUT" == "Opus" ]]; then ok "wrapped stdout passes through unchanged"; else fail "wrapped stdout: $OUT"; fi

# --- Case 2: tee snapshot written with the contract fields --------------------
TEEFILE="$HOME1/$TEE_REL"
if [[ -f "$TEEFILE" ]]; then ok "tee file created at contract path"; else fail "tee file missing: $TEEFILE"; fi
if jq -e '.rate_limits and .captured_at' <"$TEEFILE" >/dev/null 2>&1; then
  ok "tee has rate_limits and captured_at (live-probe contract)"
else
  fail "tee contract fields missing: $(cat "$TEEFILE" 2>/dev/null)"
fi
if [[ "$(jq -r '.rate_limits.five_hour.used_percentage' <"$TEEFILE")" == "23.5" ]]; then ok "five_hour.used_percentage teed"; else fail "five_hour = $(jq -c '.rate_limits.five_hour' <"$TEEFILE")"; fi
if [[ "$(jq -r '.rate_limits.seven_day.resets_at' <"$TEEFILE")" == "1738857600" ]]; then ok "seven_day.resets_at teed"; else fail "seven_day = $(jq -c '.rate_limits.seven_day' <"$TEEFILE")"; fi
if [[ "$(jq -r '.session_id' <"$TEEFILE")" == "sess-42" ]]; then ok "session_id teed (session-distinguishing field)"; else fail "session_id = $(jq -r '.session_id' <"$TEEFILE")"; fi
if jq -r '.captured_at' <"$TEEFILE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  ok "captured_at is ISO-8601 UTC"
else
  fail "captured_at = $(jq -r '.captured_at' <"$TEEFILE")"
fi
if jq -e 'has("model") or has("context_window") | not' <"$TEEFILE" >/dev/null 2>&1; then
  ok "unrelated fields not teed (bounded snapshot)"
else
  fail "unrelated fields leaked into tee: $(jq -c 'keys' <"$TEEFILE")"
fi

# --- Case 3: future account-distinguishing field adopted automatically -------
HOME3="$WORK/home3"
mkdir -p "$HOME3"
run "$HOME3" "$(build_input '"account_id":"acct-9","session_name":"lane-1"')" cat >/dev/null
TEEFILE3="$HOME3/$TEE_REL"
if [[ "$(jq -r '.account_id' <"$TEEFILE3")" == "acct-9" ]]; then ok "future account field adopted into tee"; else fail "account_id = $(jq -r '.account_id' <"$TEEFILE3")"; fi
if [[ "$(jq -r '.session_name' <"$TEEFILE3")" == "lane-1" ]]; then ok "session_name teed"; else fail "session_name = $(jq -r '.session_name' <"$TEEFILE3")"; fi

# --- Case 4: rate_limits absent → snapshot still written, key absent ---------
HOME4="$WORK/home4"
mkdir -p "$HOME4"
printf '{"session_id":"s-api-key","model":{"display_name":"Opus"}}' | HOME="$HOME4" bash "$TEE" cat >/dev/null
TEEFILE4="$HOME4/$TEE_REL"
if [[ -f "$TEEFILE4" ]] && jq -e '.captured_at' <"$TEEFILE4" >/dev/null 2>&1; then
  ok "no rate_limits → snapshot still written (staleness signal stays fresh)"
else
  fail "no rate_limits → snapshot missing/invalid: $(cat "$TEEFILE4" 2>/dev/null)"
fi
if jq -e 'has("rate_limits") | not' <"$TEEFILE4" >/dev/null 2>&1; then
  ok "no rate_limits → key honestly absent (unknown, not fabricated)"
else
  fail "rate_limits fabricated: $(jq -c '.rate_limits' <"$TEEFILE4")"
fi

# --- Case 5: wrapped exit code propagates ------------------------------------
run "$HOME1" "$(build_input)" sh -c 'cat >/dev/null; exit 3' >/dev/null
RC=$?
if [[ $RC -eq 3 ]]; then ok "wrapped exit code propagates (3)"; else fail "wrapped exit code: $RC, want 3"; fi

# --- mv shim machinery: fail N times, then delegate to the real mv -----------
REAL_MV="$(command -v mv)"
make_mv_shim() {
  # $1 = shim dir, $2 = failure count file, $3 = failures before delegating
  local dir="$1" counter="$2" fails="$3"
  mkdir -p "$dir"
  {
    printf '#!/usr/bin/env bash\n'
    # shellcheck disable=SC2016  # $n must appear LITERALLY in the emitted shim, not expand here
    printf 'n=$(cat "%s" 2>/dev/null || echo 0)\n' "$counter"
    # shellcheck disable=SC2016
    printf 'n=$((n + 1))\n'
    # shellcheck disable=SC2016
    printf 'printf %%s "$n" >"%s"\n' "$counter"
    # shellcheck disable=SC2016
    printf 'if [ "$n" -le %s ]; then exit 1; fi\n' "$fails"
    printf 'exec "%s" "$@"\n' "$REAL_MV"
  } >"$dir/mv"
  chmod +x "$dir/mv"
}

# --- Case 6: rename fails twice then succeeds → retry lands the snapshot -----
HOME6="$WORK/home6"
mkdir -p "$HOME6"
SHIM6="$WORK/shim6"
COUNT6="$WORK/count6"
make_mv_shim "$SHIM6" "$COUNT6" 2
OUT="$(printf '%s' "$(build_input)" | HOME="$HOME6" PATH="$SHIM6:$PATH" bash "$TEE" jq -r '.model.display_name')"
RC=$?
TEEFILE6="$HOME6/$TEE_REL"
if [[ $RC -eq 0 && "$OUT" == "Opus" ]]; then ok "retry path → passthrough intact"; else fail "retry path (rc=$RC out=$OUT)"; fi
if [[ -f "$TEEFILE6" ]] && jq -e '.rate_limits' <"$TEEFILE6" >/dev/null 2>&1; then
  ok "rename retried past 2 transient failures (locked-target case)"
else
  fail "retry did not land the snapshot"
fi
if [[ "$(cat "$COUNT6")" == "3" ]]; then ok "third rename attempt succeeded"; else fail "mv attempts = $(cat "$COUNT6"), want 3"; fi

# --- Case 7: rename always fails → skip, clean up, never propagate -----------
HOME7="$WORK/home7"
mkdir -p "$HOME7"
SHIM7="$WORK/shim7"
COUNT7="$WORK/count7"
make_mv_shim "$SHIM7" "$COUNT7" 999
OUT="$(printf '%s' "$(build_input)" | HOME="$HOME7" PATH="$SHIM7:$PATH" bash "$TEE" jq -r '.model.display_name' 2>&1)"
RC=$?
if [[ $RC -eq 0 && "$OUT" == "Opus" ]]; then
  ok "persistent rename failure → statusline pipeline unaffected"
else
  fail "persistent rename failure propagated (rc=$RC out=$OUT)"
fi
if [[ ! -e "$HOME7/$TEE_REL" ]]; then ok "persistent failure → snapshot honestly absent"; else fail "snapshot exists despite failing mv"; fi
LEFTOVER=$(find "$HOME7/.claude/rate-limit-guard" -name '*.tmp*' 2>/dev/null | wc -l | tr -d ' \r')
if [[ "$LEFTOVER" == "0" ]]; then ok "persistent failure → no temp-file residue"; else fail "$LEFTOVER temp files left behind"; fi

# --- jq-absent PATH: real tools minus jq -------------------------------------
FAKEBIN="$WORK/fakebin"
mkdir -p "$FAKEBIN"
for t in bash sh cat date dirname basename mktemp mkdir rm mv sleep tr grep sed find wc tail printf env; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done

# --- Case 8: jq absent → passthrough + visible notice, no tee -----------------
HOME8="$WORK/home8"
mkdir -p "$HOME8"
OUT="$(printf '%s' "$(build_input)" | HOME="$HOME8" PATH="$FAKEBIN" bash "$TEE" cat)"
RC=$?
if [[ $RC -eq 0 ]]; then ok "jq absent → exit 0"; else fail "jq absent → exit $RC"; fi
if printf '%s' "$OUT" | grep -q 'sess-42'; then ok "jq absent → wrapped output intact"; else fail "jq absent → wrapped output lost: $OUT"; fi
if printf '%s' "$OUT" | grep -qi 'jq'; then ok "jq absent → visible notice appended"; else fail "jq absent → silent skip: $OUT"; fi
if [[ ! -e "$HOME8/$TEE_REL" ]]; then ok "jq absent → no tee file"; else fail "jq absent → tee file written"; fi

# --- Case 9: standalone mode (no statusline configured) ----------------------
HOME9="$WORK/home9"
mkdir -p "$HOME9"
OUT="$(run "$HOME9" "$(build_input)")"
RC=$?
if [[ $RC -eq 0 && -n "$OUT" ]]; then ok "standalone mode → prints a statusline"; else fail "standalone (rc=$RC out=$OUT)"; fi
if printf '%s' "$OUT" | grep -q 'Opus'; then ok "standalone line carries the model"; else fail "standalone line: $OUT"; fi
if printf '%s' "$OUT" | grep -q '23.5%'; then ok "standalone line carries 5h window usage"; else fail "standalone line lacks window usage: $OUT"; fi
if [[ -f "$HOME9/$TEE_REL" ]]; then ok "standalone mode still tees"; else fail "standalone mode did not tee"; fi

# --- Case 10: standalone + jq absent → visible degraded line -----------------
OUT="$(printf '%s' "$(build_input)" | HOME="$HOME9" PATH="$FAKEBIN" bash "$TEE")"
RC=$?
if [[ $RC -eq 0 && "$OUT" == *jq* ]]; then ok "standalone, jq absent → visible degraded line"; else fail "standalone jq absent (rc=$RC out=$OUT)"; fi

# --- Case 11: malformed stdin → passthrough intact, no snapshot update -------
HOME11="$WORK/home11"
mkdir -p "$HOME11"
OUT="$(printf 'not json at all' | HOME="$HOME11" bash "$TEE" cat)"
RC=$?
if [[ $RC -eq 0 && "$OUT" == "not json at all" ]]; then ok "malformed stdin → bytes pass through"; else fail "malformed stdin (rc=$RC out=$OUT)"; fi
if [[ ! -e "$HOME11/$TEE_REL" ]]; then ok "malformed stdin → no snapshot written"; else fail "malformed stdin wrote a snapshot"; fi

# --- Case 12: non-stdin-reading wrapped command + oversized payload ----------
# A wrapped command that never reads stdin closes the pipe while printf still
# has more than a pipe buffer to write; the wrapper must report the wrapped
# command's own exit code, not printf's SIGPIPE (141).
HOME12="$WORK/home12"
mkdir -p "$HOME12"
BIG_FILLER="$(head -c 200000 /dev/zero | tr '\0' 'x')"
BIG_INPUT="$(printf '{"session_id":"sess-big","filler":"%s","rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1738425600}}}' "$BIG_FILLER")"
printf '%s' "$BIG_INPUT" | HOME="$HOME12" bash "$TEE" sh -c 'exit 7' >/dev/null 2>&1
RC=$?
if [[ $RC -eq 7 ]]; then ok "oversized payload + stdin-ignoring command → wrapped exit code (7), not SIGPIPE"; else fail "oversized payload exit code: $RC, want 7"; fi
if [[ -f "$HOME12/$TEE_REL" ]] && [[ "$(jq -r '.session_id' <"$HOME12/$TEE_REL")" == "sess-big" ]]; then
  ok "oversized payload still teed"
else
  fail "oversized payload not teed"
fi

# --- Case 13: newest write wins (last-writer-wins contract) ------------------
run "$HOME1" "$(build_input)" cat >/dev/null
printf '{"session_id":"sess-later","rate_limits":{"five_hour":{"used_percentage":91,"resets_at":1738425600}}}' |
  HOME="$HOME1" bash "$TEE" cat >/dev/null
if [[ "$(jq -r '.session_id' <"$TEEFILE")" == "sess-later" ]]; then ok "snapshot is last-writer-wins"; else fail "stale snapshot retained: $(jq -c . <"$TEEFILE")"; fi

# --- Case 14: cancellation mid-window leaves no temp behind ------------------
# Claude Code "cancels the in-flight script" when a new update arrives while
# this one is still running, so a kill between the write and the rename is
# routine rather than exceptional. Driven by an `mv` shim that parks, so the
# signal lands inside the window deterministically.
HOME14="$WORK/home14"
mkdir -p "$HOME14"
SHIM14="$WORK/shim14"
mkdir -p "$SHIM14"
printf '#!/usr/bin/env bash\nsleep 10\n' >"$SHIM14/mv"
chmod +x "$SHIM14/mv"
printf '%s' "$(build_input)" | HOME="$HOME14" PATH="$SHIM14:$PATH" bash "$TEE" >/dev/null 2>&1 &
TEE_PID=$!
sleep 2
kill -TERM "$TEE_PID" 2>/dev/null
wait "$TEE_PID" 2>/dev/null
sleep 0.5
LEFT14=$(find "$HOME14/.claude/rate-limit-guard" -name '.rate-limits.json.tmp.*' 2>/dev/null | wc -l | tr -d ' \r')
if [[ "$LEFT14" == "0" ]]; then
  ok "cancelled mid-window → temp reclaimed by trap"
else
  fail "$LEFT14 temp file(s) leaked on cancellation"
fi

# --- Case 15: the sweep reclaims an aged orphan and spares a live sibling -----
# A trap cannot survive SIGKILL, a crash, or power loss, so the sweep is the
# mechanism that actually bounds the litter. The age floor is what keeps it
# from racing a concurrent session's in-flight temp.
HOME15="$WORK/home15"
DIR15="$HOME15/.claude/rate-limit-guard"
mkdir -p "$DIR15"
OLD15="$DIR15/.rate-limits.json.tmp.111.222"
FRESH15="$DIR15/.rate-limits.json.tmp.333.444"
printf 'orphan\n' >"$OLD15"
printf 'live\n' >"$FRESH15"
# POSIX `touch -t [[CC]YY]MMDDhhmm` — no GNU `-d 'N minutes ago'`.
touch -t 200001010000 "$OLD15"
run "$HOME15" "$(build_input)" cat >/dev/null
if [[ ! -e "$OLD15" ]]; then ok "sweep reclaims an aged temp orphan"; else fail "aged orphan survived the sweep"; fi
if [[ -e "$FRESH15" ]]; then ok "sweep spares a live sibling temp"; else fail "sweep deleted a live sibling temp"; fi
if [[ -e "$HOME15/$TEE_REL" ]]; then ok "sweep does not disturb the snapshot write"; else fail "snapshot missing after sweep"; fi

# --- Case 16: a windowless session never clobbers a snapshot with windows ----
# The reader contract routes a snapshot missing rate_limits to whole-guard
# reactive-only. Such a write carries a FRESH captured_at, so consumers never
# see "stale" — they see a current snapshot with no data, and lose up to the
# full staleness budget of usable proactive data on a mixed-auth machine.
HOME16="$WORK/home16"
mkdir -p "$HOME16"
run "$HOME16" "$(build_input)" cat >/dev/null
BEFORE16="$(jq -r '.captured_at' <"$HOME16/$TEE_REL")"
printf '{"session_id":"sess-no-windows","model":{"display_name":"Opus"}}' |
  HOME="$HOME16" bash "$TEE" cat >/dev/null
if jq -e '.rate_limits' <"$HOME16/$TEE_REL" >/dev/null 2>&1; then
  ok "windowless session does not clobber windows"
else
  fail "windowless write destroyed the window-bearing snapshot"
fi
if [[ "$(jq -r '.captured_at' <"$HOME16/$TEE_REL")" == "$BEFORE16" ]]; then
  ok "windowless session does not refresh captured_at over real data"
else
  fail "windowless write refreshed captured_at, hiding staleness"
fi

# A windowless session still writes when there is nothing to preserve, so a
# machine with no window-bearing session keeps its staleness signal honest.
HOME17="$WORK/home17"
mkdir -p "$HOME17"
printf '{"session_id":"sess-no-windows","model":{"display_name":"Opus"}}' |
  HOME="$HOME17" bash "$TEE" cat >/dev/null
if [[ -e "$HOME17/$TEE_REL" ]]; then
  ok "windowless session still writes when the target has no windows"
else
  fail "windowless session wrote nothing on a fresh machine"
fi

# --- Case 18: window-bearing is a structural property, not a substring --------
# A windowless payload whose forwarded value merely CONTAINS the string
# "rate_limits" (session_name here) must still be classified windowless, or it
# skips the preservation check and clobbers real windows.
HOME18="$WORK/home18"
mkdir -p "$HOME18"
run "$HOME18" "$(build_input)" cat >/dev/null
printf '{"session_id":"sess-imposter","session_name":"rate_limits"}' |
  HOME="$HOME18" bash "$TEE" cat >/dev/null
if jq -e '.rate_limits' <"$HOME18/$TEE_REL" >/dev/null 2>&1; then
  ok "substring imposter payload stays windowless — windows preserved"
else
  fail "payload containing the literal string rate_limits clobbered real windows"
fi

# --- Case 19: the sweep runs even on a refresh that skips its write -----------
# A machine where only windowless sessions remain active takes the preserve
# early-return on every refresh; the orphan a killed window-bearing session
# left must still be reclaimed there, or it survives indefinitely.
HOME19="$WORK/home19"
DIR19="$HOME19/.claude/rate-limit-guard"
mkdir -p "$DIR19"
run "$HOME19" "$(build_input)" cat >/dev/null
OLD19="$DIR19/.rate-limits.json.tmp.555.666"
printf 'orphan\n' >"$OLD19"
touch -t 200001010000 "$OLD19"
printf '{"session_id":"sess-no-windows"}' | HOME="$HOME19" bash "$TEE" cat >/dev/null
if [[ ! -e "$OLD19" ]]; then
  ok "sweep reclaims the orphan on a skipped windowless refresh"
else
  fail "orphan survived — sweep does not run before the windowless early return"
fi
if jq -e '.rate_limits' <"$HOME19/$TEE_REL" >/dev/null 2>&1; then
  ok "skipped windowless refresh still preserved the windows"
else
  fail "windowless refresh clobbered windows in the sweep-order case"
fi

# --- Case 20: the writer lock serializes the preservation decision ------------
# A fresh (unstealable) lock held by another writer: the windowless writer
# must skip its write, the window-bearing writer must still write (its
# payload carries data; last-writer-wins between window-bearing snapshots is
# the pre-existing contract). A stale lock left by a killed writer is stolen.
HOME20="$WORK/home20"
DIR20="$HOME20/.claude/rate-limit-guard"
LOCK20="$DIR20/.rate-limits.json.lock"
mkdir -p "$LOCK20"
printf '{"session_id":"sess-no-windows"}' | HOME="$HOME20" bash "$TEE" cat >/dev/null
if [[ ! -e "$HOME20/$TEE_REL" ]]; then
  ok "held lock → windowless writer skips its write"
else
  fail "windowless writer wrote through a held lock"
fi
run "$HOME20" "$(build_input)" cat >/dev/null
if jq -e '.rate_limits' <"$HOME20/$TEE_REL" >/dev/null 2>&1; then
  ok "held lock → window-bearing writer still writes"
else
  fail "window-bearing writer lost its snapshot to a held lock"
fi
rmdir "$LOCK20" 2>/dev/null || true
HOME21="$WORK/home21"
DIR21="$HOME21/.claude/rate-limit-guard"
LOCK21="$DIR21/.rate-limits.json.lock"
mkdir -p "$LOCK21"
touch -t 200001010000 "$LOCK21"
printf '{"session_id":"sess-no-windows"}' | HOME="$HOME21" bash "$TEE" cat >/dev/null
if [[ -e "$HOME21/$TEE_REL" ]]; then
  ok "stale lock is stolen — windowless writer proceeds on a fresh machine"
else
  fail "stale lock permanently blocked the writer"
fi
if [[ ! -e "$LOCK21" ]]; then
  ok "stolen stale lock directory removed"
else
  fail "stale lock directory survived"
fi

# --- The enablement gate (_rlg_tee_enabled) ----------------------------------
# Third limb of the contract: the tee's WRITE is gated by
# `rate_limit_guard_enabled`, resolved from the settings scopes Claude Code
# actually reads pluginConfigs back from (docs/conventions/hook-config-delivery,
# fact 5) rather than from an environment variable this non-hook process never
# receives. Two properties are inseparable and every case asserts BOTH: the gate
# decides whether tee_snapshot runs, and it NEVER touches the wrapped
# statusline's stdout — a gate that blanked the status line would be worse than
# the bug it closes.
#
# Managed settings live at fixed, root-owned system paths, unwritable from a test
# by design, so those cases source the wrapper (its `main` sourcing guard keeps
# that inert) to stub the path list and then drive the real end-to-end path
# through `main`. The user-scope cases are also proven black-box, unstubbed, by
# the plain `run()` case at the end.

write_settings() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" >"$1"
}

# Sourced-with-stub runner: $1 HOME, $2 managed settings file (may not exist),
# $3 stdin payload, rest = the wrapped statusline command.
gate_run() {
  local home="$1" managed="$2" input="$3"
  shift 3
  printf '%s' "$input" | HOME="$home" RLG_TEST_MANAGED="$managed" bash -c '
    source "$1" </dev/null
    _rlg_managed_settings_files() {
      [[ -f "$RLG_TEST_MANAGED" ]] && printf "%s\n" "$RLG_TEST_MANAGED"
      return 0
    }
    shift
    main "$@"
  ' _ "$TEE" "$@"
}

GATE_INPUT="$(build_input)"
# Deliberately never created: the default "managed configures nothing" stub, so a
# real managed-settings file on the machine running this suite can never make the
# user-scope cases non-deterministic.
NO_MANAGED="$WORK/managed-absent.json"
GATE_N=0

# $1 label, $2 expected tee|no-tee, $3 user settings JSON ("" = no file at all),
# $4 managed settings JSON ("" = managed configures nothing).
gate_case() {
  local label="$1" expect="$2" user="$3" managed="$4"
  local home="$WORK/gate$GATE_N" managed_file="$NO_MANAGED" out rc
  GATE_N=$((GATE_N + 1))
  mkdir -p "$home"
  [[ -n "$user" ]] && write_settings "$home/.claude/settings.json" "$user"
  if [[ -n "$managed" ]]; then
    managed_file="$home/managed-settings.json"
    write_settings "$managed_file" "$managed"
  fi
  out="$(gate_run "$home" "$managed_file" "$GATE_INPUT" jq -r '.model.display_name')"
  rc=$?
  if [[ $rc -eq 0 && "$out" == "Opus" ]]; then
    ok "gate/$label: statusline passthrough unchanged"
  else
    fail "gate/$label: passthrough broken (rc=$rc out=$out)"
  fi
  if [[ "$expect" == tee ]]; then
    if [[ -f "$home/$TEE_REL" ]]; then ok "gate/$label: tee runs"; else fail "gate/$label: tee suppressed, want it to run"; fi
  else
    if [[ ! -e "$home/$TEE_REL" ]]; then ok "gate/$label: tee_snapshot suppressed"; else fail "gate/$label: tee ran, want it suppressed"; fi
  fi
}

USER_FALSE='{"pluginConfigs":{"rate-limit-guard@melodic-software":{"options":{"rate_limit_guard_enabled":false}}}}'
USER_TRUE='{"pluginConfigs":{"rate-limit-guard@melodic-software":{"options":{"rate_limit_guard_enabled":true}}}}'
MANAGED_FALSE='{"pluginConfigs":{"rate-limit-guard@melodic-software":{"options":{"rate_limit_guard_enabled":false}}}}'
MANAGED_TRUE='{"pluginConfigs":{"rate-limit-guard@melodic-software":{"options":{"rate_limit_guard_enabled":true}}}}'

# Unconfigured → the plugin default, enabled. Both the no-file and the
# no-pluginConfigs shapes, since they take different branches in the reader.
gate_case "no settings file" tee "" ""
gate_case "settings without pluginConfigs" tee '{"statusLine":{"type":"command","command":"x"}}' ""

# The configured user-scope verdicts.
gate_case "user settings false" no-tee "$USER_FALSE" ""
gate_case "user settings true" tee "$USER_TRUE" ""

# Marketplace handling: matched by PREFIX so a fork or private catalog install is
# still gated, but never so loosely that another plugin's identically-named
# option or a longer plugin name whose prefix collides can decide it.
gate_case "false under a different marketplace suffix" no-tee \
  '{"pluginConfigs":{"rate-limit-guard@a-fork":{"options":{"rate_limit_guard_enabled":false}}}}' ""
gate_case "another plugin's identically-named option" tee \
  '{"pluginConfigs":{"disk-hygiene@melodic-software":{"options":{"rate_limit_guard_enabled":false}},"rate-limit-guardian@melodic-software":{"options":{"rate_limit_guard_enabled":false}}}}' ""

# Fail OPEN: an unreadable verdict is never a disable.
gate_case "malformed settings JSON" tee 'not json at all' ""

# Managed precedence, both directions. The false-over-true case is the policy
# bypass this gate exists to close; the true-over-false MIRROR is what proves it
# is real precedence rather than an or-of-falses that suppresses on any `false`.
gate_case "managed false overrides user true" no-tee "$USER_TRUE" "$MANAGED_FALSE"
gate_case "managed true overrides user false" tee "$USER_FALSE" "$MANAGED_TRUE"

# --- Gate, unstubbed: the real script, invoked exactly as settings.json does --
HOME_GATE="$WORK/home-gate-e2e"
mkdir -p "$HOME_GATE"
write_settings "$HOME_GATE/.claude/settings.json" "$USER_FALSE"
OUT="$(run "$HOME_GATE" "$GATE_INPUT" jq -r '.model.display_name')"
RC=$?
if [[ $RC -eq 0 && "$OUT" == "Opus" ]]; then ok "gate end-to-end: passthrough unchanged"; else fail "gate end-to-end passthrough (rc=$RC out=$OUT)"; fi
if [[ ! -e "$HOME_GATE/$TEE_REL" ]]; then ok "gate end-to-end: user settings false suppresses the tee"; else fail "gate end-to-end: tee ran despite a configured false"; fi

# --- Gate: jq absent fails OPEN ----------------------------------------------
# The reader cannot parse anything without jq, and a gate that read that as
# "disabled" would silently drop the tee on every machine without it.
VERDICT="$(HOME="$HOME_GATE" PATH="$FAKEBIN" bash -c '
  source "$1" </dev/null
  if _rlg_tee_enabled; then printf enabled; else printf disabled; fi
' _ "$TEE")"
if [[ "$VERDICT" == "enabled" ]]; then ok "gate: jq absent fails open despite a configured false"; else fail "gate: jq absent → $VERDICT"; fi

# --- Gate: the managed path table is fixed and absolute ----------------------
# The managed scope is only tamper-resistant while its paths are the documented
# root-owned absolutes; a relative one would resolve against this process's cwd.
UNAME_SHIM="$WORK/uname-shim"
mkdir -p "$UNAME_SHIM"
printf '#!/bin/sh\necho Plan9\n' >"$UNAME_SHIM/uname"
chmod +x "$UNAME_SHIM/uname"
if [[ -z "$(PATH="$UNAME_SHIM:$PATH" bash -c 'source "$1" </dev/null; _rlg_managed_settings_files' _ "$TEE")" ]]; then
  ok "gate: unrecognized platform contributes no managed path"
else
  fail "gate: unrecognized platform produced a managed path"
fi
MANAGED_ABS=ok
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  case "$p" in
  /* | [A-Za-z]:[/\\]*) ;;
  *) MANAGED_ABS="relative path: $p" ;;
  esac
done < <(bash -c 'source "$1" </dev/null; _rlg_managed_settings_files' _ "$TEE")
if [[ "$MANAGED_ABS" == ok ]]; then ok "gate: every managed path is absolute"; else fail "gate: $MANAGED_ABS"; fi

# --- Opt-in asynchrony: the snapshot still lands, and stdout stays clean ------
# Everything above exercised the default synchronous path. RLG_TEE_ASYNC=1
# detaches the snapshot; these cases prove the detachment is real (stdout is not
# held open) without giving up the guarantee that the snapshot is still written.
HOME_ASYNC="$WORK/home-async"
mkdir -p "$HOME_ASYNC"
ASYNC_OUT="$(printf '%s' "$GATE_INPUT" | HOME="$HOME_ASYNC" RLG_TEE_ASYNC=1 \
  bash "$TEE" jq -r '.model.display_name')"
ASYNC_RC=$?
if [[ $ASYNC_RC -eq 0 && "$ASYNC_OUT" == "Opus" ]]; then
  ok "async: wrapped stdout is exactly the wrapped command's, nothing leaks from the child"
else
  fail "async: stdout polluted or rc bad (rc=$ASYNC_RC out=$ASYNC_OUT)"
fi

# Bounded wait, not a fixed sleep: fails honestly if the write never happens.
ASYNC_DEADLINE=$((SECONDS + 10))
while [[ ! -f "$HOME_ASYNC/$TEE_REL" && $SECONDS -lt $ASYNC_DEADLINE ]]; do
  sleep 0.05
done
if [[ -f "$HOME_ASYNC/$TEE_REL" ]]; then
  ok "async: the detached snapshot is still written"
else
  fail "async: no snapshot appeared within 10s"
fi
if jq -e '.rate_limits' <"$HOME_ASYNC/$TEE_REL" >/dev/null 2>&1; then
  ok "async: the detached snapshot carries the session's windows"
else
  fail "async: snapshot body wrong: $(cat "$HOME_ASYNC/$TEE_REL" 2>/dev/null)"
fi

# The detached child must not hold the statusline pipe open: if it did, a reader
# consuming to EOF would block until the snapshot finished, which is the whole
# cost the asynchrony exists to remove. Reading to EOF must therefore complete
# well inside the time the snapshot itself takes.
HOME_EOF="$WORK/home-async-eof"
mkdir -p "$HOME_EOF"
EOF_START=$SECONDS
printf '%s' "$GATE_INPUT" | HOME="$HOME_EOF" RLG_TEE_ASYNC=1 bash "$TEE" \
  jq -r '.model.display_name' >/dev/null
EOF_ELAPSED=$((SECONDS - EOF_START))
if [[ $EOF_ELAPSED -le 5 ]]; then
  ok "async: stdout reaches EOF without waiting on the detached snapshot"
else
  fail "async: reader blocked ${EOF_ELAPSED}s — the child is holding the pipe"
fi

# Let the last detached child finish before the suite's cleanup trap removes the
# work directory out from under it. Without this the run ends on a spurious
# "Directory not empty" from rm — harmless, but it reads like a failure.
EOF_DEADLINE=$((SECONDS + 10))
while [[ ! -f "$HOME_EOF/$TEE_REL" && $SECONDS -lt $EOF_DEADLINE ]]; do
  sleep 0.05
done

# --- THE SPOOL: election, drain selection, sharding, and the zero-fork claim --
# Everything above pins RLG_TEE_DRAIN_INTERVAL=0 so each refresh drains
# synchronously. These cases set the cadence per invocation instead, because
# what they prove IS the cadence: a render that loses the election must spool
# and stop, and the render that wins must apply the whole batch.

SPOOL_REL=".claude/rate-limit-guard/spool"

# --- Case 22: a fresh stamp → the second render spools but does NOT drain ----
HOME_EL="$WORK/home-elect"
mkdir -p "$HOME_EL"
# Bootstrap: no stamp yet, so this render is elected and snapshots immediately.
printf '%s' "$(build_input)" | HOME="$HOME_EL" RLG_TEE_DRAIN_INTERVAL=30 bash "$TEE" cat >/dev/null
EL_FILE="$HOME_EL/$TEE_REL"
if [[ -f "$EL_FILE" ]] && [[ "$(jq -r '.session_id' <"$EL_FILE")" == "sess-42" ]]; then
  ok "election: the first-ever render drains immediately (bootstrap)"
else
  fail "election: bootstrap render did not snapshot: $(cat "$EL_FILE" 2>/dev/null)"
fi
printf '{"session_id":"sess-fresh","rate_limits":{"five_hour":{"used_percentage":99,"resets_at":1738425600}}}' |
  HOME="$HOME_EL" RLG_TEE_DRAIN_INTERVAL=30 bash "$TEE" cat >/dev/null
if [[ -f "$HOME_EL/$SPOOL_REL/sess-fresh.json" ]]; then
  ok "election: the non-elected render still spools its record"
else
  fail "election: non-elected render wrote no spool record"
fi
if [[ "$(jq -r '.session_id' <"$EL_FILE")" == "sess-42" ]]; then
  ok "election: a fresh stamp suppresses the drain (snapshot untouched)"
else
  fail "election: fresh stamp did not suppress the drain: $(jq -r '.session_id' <"$EL_FILE")"
fi

# --- Case 23: a stale stamp → drain applies the newest window-bearing record --
# Two sessions have spooled; the draining render is a THIRD, windowless one, so
# what lands can only have come from the batch and not from this render.
write_settings "$HOME_EL/$SPOOL_REL/.last-drain" "0"
printf '{"session_id":"sess-drainer"}' |
  HOME="$HOME_EL" RLG_TEE_DRAIN_INTERVAL=30 bash "$TEE" cat >/dev/null
if [[ "$(jq -r '.session_id' <"$EL_FILE")" == "sess-fresh" ]]; then
  ok "election: a stale stamp drains, and the newest window-bearing record wins"
else
  fail "election: stale-stamp drain chose $(jq -r '.session_id' <"$EL_FILE"), want sess-fresh"
fi
if [[ "$(jq -r '.rate_limits.five_hour.used_percentage' <"$EL_FILE")" == "99" ]]; then
  ok "election: the drained snapshot carries the chosen record's windows"
else
  fail "election: drained windows wrong: $(jq -c '.rate_limits' <"$EL_FILE")"
fi
# captured_at is the OBSERVATION time of the chosen record, not the drain time.
WANT_CAP="$(jq -r '.e | todate' <"$HOME_EL/$SPOOL_REL/sess-fresh.json")"
if [[ "$(jq -r '.captured_at' <"$EL_FILE")" == "$WANT_CAP" ]]; then
  ok "election: captured_at is the chosen record's observation time"
else
  fail "election: captured_at = $(jq -r '.captured_at' <"$EL_FILE"), want $WANT_CAP"
fi
if [[ "$(cat "$HOME_EL/$SPOOL_REL/.last-drain")" != "0" ]]; then
  ok "election: the drain refreshes the stamp"
else
  fail "election: stamp not refreshed — every later render would re-drain"
fi

# --- Case 24: a torn spool line is dropped, a valid sibling still drains ------
# Atomicity here comes from file disjointness, not from a write-size argument,
# so a record torn by a kill mid-write is a case the drain must survive rather
# than one it can rule out. The torn record carries a far-future epoch: if it
# parsed at all it would win, so this cannot pass by accident.
HOME_TORN="$WORK/home-torn"
mkdir -p "$HOME_TORN/$SPOOL_REL"
write_settings "$HOME_TORN/$SPOOL_REL/sess-torn.json" \
  '{"e":9999999999,"p":{"session_id":"sess-torn","rate_limits":{"five_hour":{"used_perc'
run "$HOME_TORN" "$(build_input)" cat >/dev/null
if [[ "$(jq -r '.session_id' <"$HOME_TORN/$TEE_REL")" == "sess-42" ]]; then
  ok "drain: a torn spool line is dropped and the valid sibling still lands"
else
  fail "drain: torn line polluted the snapshot: $(cat "$HOME_TORN/$TEE_REL" 2>/dev/null)"
fi
if jq -e '.rate_limits.five_hour.used_percentage == 23.5' <"$HOME_TORN/$TEE_REL" >/dev/null 2>&1; then
  ok "drain: the surviving record's windows are intact"
else
  fail "drain: surviving windows wrong: $(jq -c '.rate_limits' <"$HOME_TORN/$TEE_REL")"
fi

# --- Case 25: a hostile session_id shards to `misc` and never escapes spool/ --
# The spool filename is a SHARD KEY, never trusted data: session_id reaches the
# writer from the harness payload, and a name that escaped the directory would
# turn a statusline refresh into an arbitrary-path write.
HOME_HOSTILE="$WORK/home-hostile"
mkdir -p "$HOME_HOSTILE"
printf -v LONG_ID '%0200d' 0
HOSTILE_N=0
for bad in '../../pwned' 'a\"b' "$LONG_ID" '.hidden' 'has space'; do
  printf '{"session_id":"%s","rate_limits":{"five_hour":{"used_percentage":7,"resets_at":1738425600}}}' "$bad" |
    HOME="$HOME_HOSTILE" bash "$TEE" cat >/dev/null
  HOSTILE_N=$((HOSTILE_N + 1))
done
HOSTILE_JSON="$(find "$HOME_HOSTILE/$SPOOL_REL" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' \r')"
if [[ "$HOSTILE_JSON" == "1" && -f "$HOME_HOSTILE/$SPOOL_REL/misc.json" ]]; then
  ok "shard: $HOSTILE_N hostile session_ids all collapse to the single misc shard"
else
  fail "shard: $HOSTILE_JSON spool files: $(find "$HOME_HOSTILE/$SPOOL_REL" -maxdepth 1 -type f | tr '\n' ' ')"
fi
ESCAPED="$(find "$HOME_HOSTILE" -mindepth 1 -maxdepth 4 \
  -not -path "$HOME_HOSTILE/.claude*" 2>/dev/null | wc -l | tr -d ' \r')"
if [[ "$ESCAPED" == "0" ]]; then
  ok "shard: nothing was written outside the contract directory"
else
  fail "shard: $ESCAPED path(s) escaped: $(find "$HOME_HOSTILE" -mindepth 1 -maxdepth 4 -not -path "$HOME_HOSTILE/.claude*" | tr '\n' ' ')"
fi
if [[ ! -e "$HOME_HOSTILE/.claude/rate-limit-guard/pwned" && ! -e "$HOME_HOSTILE/pwned.json" ]]; then
  ok "shard: the traversal attempt created no file above spool/"
else
  fail "shard: a traversal attempt escaped spool/"
fi

# --- Case 26: a disabled verdict marks, stops spooling, and rechecks back -----
# The render path cannot evaluate the gate — that costs a jq, which is the whole
# expense being removed — so the drain stamps a marker the render can read with
# one builtin test, and the marker expires so a re-enabled plugin recovers on
# its own rather than needing a restart.
HOME_DIS="$WORK/home-disabled"
mkdir -p "$HOME_DIS"
DIS_MARKER="$HOME_DIS/.claude/rate-limit-guard/.tee-disabled"
write_settings "$HOME_DIS/.claude/settings.json" "$USER_FALSE"
DIS_OUT="$(run "$HOME_DIS" "$GATE_INPUT" jq -r '.model.display_name')"
if [[ "$DIS_OUT" == "Opus" ]]; then ok "disabled: statusline passthrough unchanged"; else fail "disabled: passthrough broken ($DIS_OUT)"; fi
if [[ -f "$DIS_MARKER" && ! -e "$HOME_DIS/$TEE_REL" ]]; then
  ok "disabled: the drain writes the marker and no snapshot"
else
  fail "disabled: marker=$([[ -f $DIS_MARKER ]] && echo yes || echo no) snapshot=$([[ -e $HOME_DIS/$TEE_REL ]] && echo yes || echo no)"
fi
DIS_SPOOLED="$(find "$HOME_DIS/$SPOOL_REL" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' \r')"
if [[ "$DIS_SPOOLED" == "0" ]]; then
  ok "disabled: the drain drops what was already spooled"
else
  fail "disabled: $DIS_SPOOLED spool record(s) retained while disabled"
fi
printf '%s' "$GATE_INPUT" | HOME="$HOME_DIS" bash "$TEE" cat >/dev/null
DIS_SPOOLED2="$(find "$HOME_DIS/$SPOOL_REL" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' \r')"
if [[ "$DIS_SPOOLED2" == "0" ]]; then
  ok "disabled: a fresh marker stops the render spooling at all"
else
  fail "disabled: render spooled through a fresh marker"
fi
write_settings "$HOME_DIS/.claude/settings.json" "$USER_TRUE"
printf '%s' "$GATE_INPUT" | HOME="$HOME_DIS" RLG_TEE_DISABLED_RECHECK=0 bash "$TEE" cat >/dev/null
if [[ ! -e "$DIS_MARKER" && -f "$HOME_DIS/$TEE_REL" ]]; then
  ok "disabled: the recheck clears the marker and the tee resumes"
else
  fail "disabled: recheck did not restore (marker=$([[ -e $DIS_MARKER ]] && echo present || echo gone))"
fi

# --- Case 27: the zero-fork render path, proven by trace ----------------------
# Reading the code cannot prove this: a command substitution anywhere on the
# render path forks a subshell, and the subshell fork is precisely the MSYS cost
# the spool exists to remove. So the claim is asserted against an xtrace of a
# NON-ELECTED render — stamp and spool primed so even the cold-start mkdir is
# out of the picture — up to the passthrough, which is the one fork the wrapper
# has always paid.
TRACE_HOME="$WORK/home-trace"
TRACE_SPOOL="$TRACE_HOME/$SPOOL_REL"
mkdir -p "$TRACE_SPOOL"
TRACE_NOW="$(date +%s)"
TRACE_INPUT='{"session_id":"sess-trace","rate_limits":{"five_hour":{"used_percentage":5,"resets_at":1738425600}}}'
write_settings "$TRACE_SPOOL/.last-drain" "$TRACE_NOW"
write_settings "$TRACE_SPOOL/sess-trace.json" "{\"e\":$TRACE_NOW,\"p\":$TRACE_INPUT}"
TRACE_LOG="$WORK/xtrace.log"
printf '%s' "$TRACE_INPUT" | HOME="$TRACE_HOME" RLG_TEE_DRAIN_INTERVAL=30 \
  BASH_XTRACEFD=9 bash -x "$TEE" cat >/dev/null 9>"$TRACE_LOG"
# Up to `set +o pipefail`, which main executes immediately before the
# passthrough pipeline. (The script's own `set -uo pipefail` does not match.)
TRACE_PRE="$(sed -n '1,/set +o pipefail/p' "$TRACE_LOG")"
if [[ -n "$TRACE_PRE" ]] && printf '%s\n' "$TRACE_PRE" | grep -q '_rlg_spool_dispatch'; then
  ok "trace: the render path was traced (spool dispatch present)"
else
  fail "trace: no usable xtrace captured: $(head -c 200 "$TRACE_LOG" 2>/dev/null)"
fi
FORKED="$(printf '%s\n' "$TRACE_PRE" |
  grep -nE '(^|[^[:alnum:]_])(jq|mkdir|mv|rmdir|find|date|uname|sleep|chmod|rm)([^[:alnum:]_]|$)' || true)"
if [[ -z "$FORKED" ]]; then
  ok "trace: no external command runs before the passthrough (zero forks)"
else
  fail "trace: external command(s) on the render path: $FORKED"
fi
SUBSHELLS="$(printf '%s\n' "$TRACE_PRE" | grep -c '^++' | tr -d ' \r')"
if [[ "$SUBSHELLS" == "0" ]]; then
  ok "trace: no command-substitution subshell frames on the non-elected path"
else
  fail "trace: $SUBSHELLS subshell frame(s) before the passthrough"
fi
if [[ ! -e "$TRACE_HOME/$TEE_REL" ]]; then
  ok "trace: the non-elected render wrote no snapshot, as elected"
else
  fail "trace: the non-elected render drained anyway"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
