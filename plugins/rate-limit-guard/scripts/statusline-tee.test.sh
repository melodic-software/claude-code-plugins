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

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
