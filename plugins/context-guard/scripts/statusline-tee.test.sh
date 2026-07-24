#!/usr/bin/env bash
# Black-box contract test for statusline-tee.sh (the context-guard statusline
# wrapper).
#
# Proves the two-sided contract: (a) TRANSPARENCY — the wrapped statusline
# command receives the stdin JSON and its stdout and exit code pass through
# unchanged, with NO tee failure ever propagating into the pipeline; and
# (b) the TEE — each run atomically writes the PER-SESSION snapshot
# ($HOME/.claude/context-guard/context/<session_id>.json, so tests redirect
# via HOME) carrying captured_at + session_id + the stdin context_window
# object copied verbatim. session_id is sanitized to [A-Za-z0-9_-] before
# filename use (anything else skips the tee — path-containment guard).
# Stale sibling snapshots are pruned on write with a cutoff far larger than
# the reader contract's 10-minute staleness window (live-but-idle sessions
# survive; in-flight .tmp.* files are never pruned). The Windows
# locked-target rename failure is retry-then-skip, driven deterministically
# by a PATH `mv` shim.
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

CTX_REL=".claude/context-guard/context"

build_input() {
  # Optional session id as $1 (default sess-42), optional extra top-level
  # JSON fields as $2 (an object body fragment).
  local sid="${1:-sess-42}" extra="${2:-}"
  local base
  base=$(printf '{"session_id":"%s","model":{"id":"claude-opus-4-8","display_name":"Opus"},"context_window":{"total_input_tokens":15500,"total_output_tokens":1200,"context_window_size":200000,"used_percentage":8,"remaining_percentage":92,"current_usage":{"input_tokens":8500,"output_tokens":1200,"cache_creation_input_tokens":5000,"cache_read_input_tokens":2000}},"rate_limits":{"five_hour":{"used_percentage":23.5}}' "$sid")
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

# --- Case 2: per-session snapshot with contract fields ------------------------
SNAP1="$HOME1/$CTX_REL/sess-42.json"
if [[ -f "$SNAP1" ]]; then ok "snapshot created at per-session contract path"; else fail "snapshot missing: $SNAP1"; fi
if jq -e '.captured_at and .session_id and .context_window' <"$SNAP1" >/dev/null 2>&1; then
  ok "snapshot has captured_at + session_id + context_window"
else
  fail "snapshot contract fields missing: $(cat "$SNAP1" 2>/dev/null)"
fi
if jq -r '.captured_at' <"$SNAP1" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  ok "captured_at is ISO-8601 UTC"
else
  fail "captured_at = $(jq -r '.captured_at' <"$SNAP1")"
fi
WANT_CTX="$(printf '%s' "$(build_input)" | jq -cS '.context_window')"
GOT_CTX="$(jq -cS '.context_window' <"$SNAP1")"
if [[ "$GOT_CTX" == "$WANT_CTX" ]]; then
  ok "context_window copied verbatim (deep equality)"
else
  fail "context_window altered: want $WANT_CTX got $GOT_CTX"
fi
if [[ "$(jq -r '.session_id' <"$SNAP1")" == "sess-42" ]]; then ok "session_id recorded"; else fail "session_id = $(jq -r '.session_id' <"$SNAP1")"; fi

# --- Case 3: bounded snapshot — unrelated top-level fields not teed ----------
if jq -e 'has("model") or has("rate_limits") | not' <"$SNAP1" >/dev/null 2>&1; then
  ok "unrelated fields not teed (bounded snapshot)"
else
  fail "unrelated fields leaked into snapshot: $(jq -c 'keys' <"$SNAP1")"
fi

# --- Case 4: wrapped exit code propagates ------------------------------------
run "$HOME1" "$(build_input)" sh -c 'cat >/dev/null; exit 3' >/dev/null
RC=$?
if [[ $RC -eq 3 ]]; then ok "wrapped exit code propagates (3)"; else fail "wrapped exit code: $RC, want 3"; fi

# --- Case 5: missing context_window → snapshot still written, key absent ------
HOME5="$WORK/home5"
mkdir -p "$HOME5"
printf '{"session_id":"s-early","model":{"display_name":"Opus"}}' | HOME="$HOME5" bash "$TEE" cat >/dev/null
SNAP5="$HOME5/$CTX_REL/s-early.json"
if [[ -f "$SNAP5" ]] && jq -e '.captured_at' <"$SNAP5" >/dev/null 2>&1; then
  ok "no context_window → snapshot still written (staleness signal stays fresh)"
else
  fail "no context_window → snapshot missing/invalid: $(cat "$SNAP5" 2>/dev/null)"
fi
if jq -e 'has("context_window") | not' <"$SNAP5" >/dev/null 2>&1; then
  ok "no context_window → key honestly absent (unknown, not fabricated)"
else
  fail "context_window fabricated: $(jq -c '.context_window' <"$SNAP5")"
fi

# --- Case 6: missing session_id → no snapshot, passthrough intact -------------
HOME6="$WORK/home6"
mkdir -p "$HOME6"
OUT="$(printf '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":8}}' | HOME="$HOME6" bash "$TEE" cat)"
RC=$?
if [[ $RC -eq 0 && -n "$OUT" ]]; then ok "no session_id → passthrough intact"; else fail "no session_id (rc=$RC out=$OUT)"; fi
COUNT6=$(find "$HOME6/$CTX_REL" -type f 2>/dev/null | wc -l | tr -d ' \r')
if [[ "$COUNT6" == "0" ]]; then ok "no session_id → no snapshot written"; else fail "snapshot written without session_id"; fi

# --- Case 7: hostile session_id → tee skipped, no path escape -----------------
HOME7="$WORK/home7"
mkdir -p "$HOME7"
for SID in '../evil' 'a/b' 'a b' 'x;rm' '.hidden.'; do
  OUT="$(printf '{"session_id":"%s","context_window":{"used_percentage":8}}' "$SID" | HOME="$HOME7" bash "$TEE" cat)"
  RC=$?
  if [[ $RC -ne 0 ]]; then fail "hostile session_id '$SID' broke passthrough (rc=$RC)"; fi
done
FILECOUNT7=$(find "$HOME7/.claude" -type f 2>/dev/null | wc -l | tr -d ' \r')
EVIL=$(find "$HOME7" -name 'evil*' 2>/dev/null | wc -l | tr -d ' \r')
if [[ "$FILECOUNT7" == "0" && "$EVIL" == "0" ]]; then
  ok "hostile session_id → tee skipped, no file anywhere (path containment)"
else
  fail "hostile session_id wrote files: $(find "$HOME7" -type f 2>/dev/null)"
fi

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

# --- Case 8: rename fails twice then succeeds → retry lands the snapshot -----
HOME8="$WORK/home8"
mkdir -p "$HOME8"
SHIM8="$WORK/shim8"
COUNT8="$WORK/count8"
make_mv_shim "$SHIM8" "$COUNT8" 2
OUT="$(printf '%s' "$(build_input)" | HOME="$HOME8" PATH="$SHIM8:$PATH" bash "$TEE" jq -r '.model.display_name')"
RC=$?
SNAP8="$HOME8/$CTX_REL/sess-42.json"
if [[ $RC -eq 0 && "$OUT" == "Opus" ]]; then ok "retry path → passthrough intact"; else fail "retry path (rc=$RC out=$OUT)"; fi
if [[ -f "$SNAP8" ]] && jq -e '.context_window' <"$SNAP8" >/dev/null 2>&1; then
  ok "rename retried past 2 transient failures (locked-target case)"
else
  fail "retry did not land the snapshot"
fi

# --- Case 9: rename always fails → skip, clean up, never propagate -----------
HOME9="$WORK/home9"
mkdir -p "$HOME9"
SHIM9="$WORK/shim9"
COUNT9="$WORK/count9"
make_mv_shim "$SHIM9" "$COUNT9" 999
OUT="$(printf '%s' "$(build_input)" | HOME="$HOME9" PATH="$SHIM9:$PATH" bash "$TEE" jq -r '.model.display_name' 2>&1)"
RC=$?
if [[ $RC -eq 0 && "$OUT" == "Opus" ]]; then
  ok "persistent rename failure → statusline pipeline unaffected"
else
  fail "persistent rename failure propagated (rc=$RC out=$OUT)"
fi
if [[ ! -e "$HOME9/$CTX_REL/sess-42.json" ]]; then ok "persistent failure → snapshot honestly absent"; else fail "snapshot exists despite failing mv"; fi
LEFTOVER=$(find "$HOME9/.claude/context-guard" -name '*.tmp*' 2>/dev/null | wc -l | tr -d ' \r')
if [[ "$LEFTOVER" == "0" ]]; then ok "persistent failure → no temp-file residue"; else fail "$LEFTOVER temp files left behind"; fi

# --- jq-absent PATH: real tools minus jq -------------------------------------
FAKEBIN="$WORK/fakebin"
mkdir -p "$FAKEBIN"
for t in bash sh cat date dirname basename mktemp mkdir rm mv sleep tr grep sed find wc tail printf env touch; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done

# --- Case 10: jq absent → passthrough + visible notice, no tee ----------------
HOME10="$WORK/home10"
mkdir -p "$HOME10"
OUT="$(printf '%s' "$(build_input)" | HOME="$HOME10" PATH="$FAKEBIN" bash "$TEE" cat)"
RC=$?
if [[ $RC -eq 0 ]]; then ok "jq absent → exit 0"; else fail "jq absent → exit $RC"; fi
if printf '%s' "$OUT" | grep -q 'sess-42'; then ok "jq absent → wrapped output intact"; else fail "jq absent → wrapped output lost: $OUT"; fi
if printf '%s' "$OUT" | grep -qi 'jq'; then ok "jq absent → visible notice appended"; else fail "jq absent → silent skip: $OUT"; fi
COUNT10=$(find "$HOME10/$CTX_REL" -type f 2>/dev/null | wc -l | tr -d ' \r')
if [[ "$COUNT10" == "0" ]]; then ok "jq absent → no tee file"; else fail "jq absent → tee file written"; fi

# --- Case 11: standalone mode (no statusline configured) ---------------------
HOME11="$WORK/home11"
mkdir -p "$HOME11"
OUT="$(run "$HOME11" "$(build_input)")"
RC=$?
if [[ $RC -eq 0 && -n "$OUT" ]]; then ok "standalone mode → prints a statusline"; else fail "standalone (rc=$RC out=$OUT)"; fi
if printf '%s' "$OUT" | grep -q 'Opus'; then ok "standalone line carries the model"; else fail "standalone line: $OUT"; fi
if printf '%s' "$OUT" | grep -q '8%'; then ok "standalone line carries context usage"; else fail "standalone line lacks context usage: $OUT"; fi
if [[ -f "$HOME11/$CTX_REL/sess-42.json" ]]; then ok "standalone mode still tees"; else fail "standalone mode did not tee"; fi

# --- Case 12: standalone + jq absent → visible degraded line -----------------
OUT="$(printf '%s' "$(build_input)" | HOME="$HOME11" PATH="$FAKEBIN" bash "$TEE")"
RC=$?
if [[ $RC -eq 0 && "$OUT" == *jq* ]]; then ok "standalone, jq absent → visible degraded line"; else fail "standalone jq absent (rc=$RC out=$OUT)"; fi

# --- Case 13: malformed stdin → passthrough intact, no snapshot --------------
HOME13="$WORK/home13"
mkdir -p "$HOME13"
OUT="$(printf 'not json at all' | HOME="$HOME13" bash "$TEE" cat)"
RC=$?
if [[ $RC -eq 0 && "$OUT" == "not json at all" ]]; then ok "malformed stdin → bytes pass through"; else fail "malformed stdin (rc=$RC out=$OUT)"; fi
COUNT13=$(find "$HOME13/$CTX_REL" -type f 2>/dev/null | wc -l | tr -d ' \r')
if [[ "$COUNT13" == "0" ]]; then ok "malformed stdin → no snapshot written"; else fail "malformed stdin wrote a snapshot"; fi

# --- Case 14: unwritable target dir → silent skip, passthrough intact --------
HOME14="$WORK/home14"
mkdir -p "$HOME14/.claude/context-guard"
: >"$HOME14/.claude/context-guard/context" # occupy the dir path with a FILE
OUT="$(run "$HOME14" "$(build_input)" cat)"
RC=$?
if [[ $RC -eq 0 && -n "$OUT" ]]; then ok "unwritable context dir → passthrough intact"; else fail "unwritable dir (rc=$RC)"; fi
if [[ -f "$HOME14/.claude/context-guard/context" ]]; then ok "unwritable context dir → silent skip (no clobber)"; else fail "context path clobbered"; fi

# --- Case 15: non-stdin-reading wrapped command + oversized payload ----------
# A wrapped command that never reads stdin closes the pipe while printf still
# has more than a pipe buffer to write; the wrapper must report the wrapped
# command's own exit code, not printf's SIGPIPE (141).
HOME15="$WORK/home15"
mkdir -p "$HOME15"
BIG_FILLER="$(head -c 200000 /dev/zero | tr '\0' 'x')"
BIG_INPUT="$(printf '{"session_id":"sess-big","filler":"%s","context_window":{"used_percentage":42}}' "$BIG_FILLER")"
printf '%s' "$BIG_INPUT" | HOME="$HOME15" bash "$TEE" sh -c 'exit 7' >/dev/null 2>&1
RC=$?
if [[ $RC -eq 7 ]]; then ok "oversized payload + stdin-ignoring command → wrapped exit code (7), not SIGPIPE"; else fail "oversized payload exit code: $RC, want 7"; fi
if [[ -f "$HOME15/$CTX_REL/sess-big.json" ]] && [[ "$(jq -r '.context_window.used_percentage' <"$HOME15/$CTX_REL/sess-big.json")" == "42" ]]; then
  ok "oversized payload still teed"
else
  fail "oversized payload not teed"
fi

# --- Case 15b: payload beyond one read chunk still passes through whole ------
HOME15B="$WORK/home15b"
mkdir -p "$HOME15B"
HUGE_FILLER="$(head -c 1500000 /dev/zero | tr '\0' 'y')"
HUGE_INPUT="$(printf '{"session_id":"sess-huge","filler":"%s","context_window":{"used_percentage":9}}' "$HUGE_FILLER")"
WANT_BYTES=${#HUGE_INPUT}
GOT_BYTES=$(printf '%s' "$HUGE_INPUT" | HOME="$HOME15B" bash "$TEE" wc -c | tr -d ' \r\n')
if [[ "$GOT_BYTES" == "$WANT_BYTES" ]]; then
  ok ">1MiB payload → wrapped command receives every byte ($GOT_BYTES)"
else
  fail ">1MiB payload truncated: wrapped command saw $GOT_BYTES of $WANT_BYTES bytes"
fi
if [[ -f "$HOME15B/$CTX_REL/sess-huge.json" ]] && [[ "$(jq -r '.context_window.used_percentage' <"$HOME15B/$CTX_REL/sess-huge.json")" == "9" ]]; then
  ok ">1MiB payload still teed"
else
  fail ">1MiB payload not teed"
fi

# --- Case 16: same-session re-write → newest wins ----------------------------
printf '{"session_id":"sess-42","context_window":{"used_percentage":77}}' | HOME="$HOME1" bash "$TEE" cat >/dev/null
if [[ "$(jq -r '.context_window.used_percentage' <"$SNAP1")" == "77" ]]; then
  ok "same-session re-write → newest snapshot wins"
else
  fail "stale per-session snapshot retained: $(jq -c . <"$SNAP1")"
fi

# --- Case 16b: never regress a newer same-session snapshot -------------------
# An overlapping older refresh must not overwrite a target that already
# carries a NEWER captured_at (the delayed-writer race, observable form).
HOME16B="$WORK/home16b"
CTXDIR16B="$HOME16B/$CTX_REL"
mkdir -p "$CTXDIR16B"
FUTURE_TS=$(date -u -d '2 minutes' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v '+2M' '+%Y-%m-%dT%H:%M:%SZ')
printf '{"captured_at":"%s","session_id":"sess-42","context_window":{"used_percentage":66}}\n' "$FUTURE_TS" >"$CTXDIR16B/sess-42.json"
run "$HOME16B" "$(build_input)" cat >/dev/null
if [[ "$(jq -r '.context_window.used_percentage' <"$CTXDIR16B/sess-42.json")" == "66" ]]; then
  ok "newer target preserved against an older overlapping write"
else
  fail "older write regressed a newer snapshot: $(jq -c . <"$CTXDIR16B/sess-42.json")"
fi

# --- Case 17: pruning — old siblings die, idle + recent + tmp survive --------
HOME17="$WORK/home17"
CTXDIR17="$HOME17/$CTX_REL"
mkdir -p "$CTXDIR17"
printf '{"session_id":"ancient"}\n' >"$CTXDIR17/ancient.json"
touch -d '15 days ago' "$CTXDIR17/ancient.json"
printf '{"session_id":"idle"}\n' >"$CTXDIR17/idle.json"
touch -d '2 hours ago' "$CTXDIR17/idle.json" # beyond 10-min staleness, below prune cutoff
printf '{"session_id":"recent"}\n' >"$CTXDIR17/recent.json"
touch -d '5 minutes ago' "$CTXDIR17/recent.json"
printf 'torn' >"$CTXDIR17/.ctx.json.tmp.99.123"
touch -d '15 days ago' "$CTXDIR17/.ctx.json.tmp.99.123"
run "$HOME17" "$(build_input)" cat >/dev/null
if [[ ! -e "$CTXDIR17/ancient.json" ]]; then ok "prune: 15-day-old sibling removed"; else fail "prune: ancient sibling survived"; fi
if [[ -f "$CTXDIR17/idle.json" ]]; then ok "prune: live-but-idle sibling (2h) survives"; else fail "prune: idle sibling deleted (cutoff too tight)"; fi
if [[ -f "$CTXDIR17/recent.json" ]]; then ok "prune: recent sibling survives"; else fail "prune: recent sibling deleted"; fi
if [[ -f "$CTXDIR17/.ctx.json.tmp.99.123" ]]; then ok "prune: in-flight .tmp.* never pruned"; else fail "prune: tmp file deleted"; fi
if [[ -f "$CTXDIR17/sess-42.json" ]]; then ok "prune pass still wrote the live snapshot"; else fail "live snapshot missing after prune"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
