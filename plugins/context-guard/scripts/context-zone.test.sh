#!/usr/bin/env bash
# Black-box contract test for context-zone.sh (the context-guard zone
# resolver).
#
# Contract: `context-zone.sh <session_id>` reads that session's snapshot
# ($HOME/.claude/context-guard/context/<session_id>.json — tests redirect via
# HOME) plus the optional $HOME/.claude/context-guard/zones.json override and
# prints EXACTLY ONE of: smart / acceptable / dumb / unknown. Fail-open:
# absent, stale (captured_at older than the 10-minute staleness window), or
# unparsable snapshot → unknown; used_percentage null / missing / non-numeric
# / outside 0–100 → unknown; current_usage null or missing (documented
# early-session and post-/compact states) → unknown. Shipped default bands:
# smart ≤ 50 < acceptable ≤ 75 < dumb. Malformed zones.json → shipped
# defaults + a visible stderr notice. Exit code is always 0 (fail-open
# resolver; the word IS the contract).
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZONE="$SCRIPT_DIR/context-zone.sh"

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

# write_snapshot <home> <sid> <used_percentage-json> [<captured_at>] [<current_usage-json>]
# used_percentage-json / current_usage-json are raw JSON fragments (numbers,
# null) so tests can express null and absurd values directly.
write_snapshot() {
  local home="$1" sid="$2" used="$3" ts="${4:-}" cu="${5:-{\"input_tokens\":100\}}"
  [[ -n "$ts" ]] || ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  mkdir -p "$home/$CTX_REL"
  printf '{"captured_at":"%s","session_id":"%s","context_window":{"used_percentage":%s,"remaining_percentage":50,"current_usage":%s}}\n' \
    "$ts" "$sid" "$used" "$cu" >"$home/$CTX_REL/$sid.json"
}

old_ts() { # ISO timestamp N minutes in the past
  # portability-ok: GNU-first, BSD fallback on the continuation line below (#1510)
  date -u -d "$1 minutes ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null ||
    date -u -v "-$1M" '+%Y-%m-%dT%H:%M:%SZ'
}

# resolve <home> <sid> → stdout word (stderr passed through to the test's own)
resolve() {
  local home="$1" sid="$2"
  HOME="$home" bash "$ZONE" "$sid"
}

# expect <label> <want-word> <home> <sid>
expect() {
  local label="$1" want="$2" home="$3" sid="$4"
  local got rc
  got="$(resolve "$home" "$sid" 2>>"$WORK/stderr.log")"
  rc=$?
  if [[ "$got" == "$want" && $rc -eq 0 ]]; then
    ok "$label → $want"
  else
    fail "$label: want '$want' rc 0, got '$got' rc $rc"
  fi
}

# --- Shipped default band edges ----------------------------------------------
H="$WORK/h-bands"
write_snapshot "$H" s0 0 && expect "used=0" smart "$H" s0
write_snapshot "$H" s50 50 && expect "used=50 (smart upper edge, inclusive)" smart "$H" s50
write_snapshot "$H" s50x 50.5 && expect "used=50.5" acceptable "$H" s50x
write_snapshot "$H" s75 75 && expect "used=75 (acceptable upper edge, inclusive)" acceptable "$H" s75
write_snapshot "$H" s75x 75.1 && expect "used=75.1" dumb "$H" s75x
write_snapshot "$H" s100 100 && expect "used=100" dumb "$H" s100

# --- Fail-open: absurd / null / missing used_percentage ----------------------
write_snapshot "$H" sneg -1 && expect "used=-1 (absurd)" unknown "$H" sneg
write_snapshot "$H" sbig 101 && expect "used=101 (absurd)" unknown "$H" sbig
write_snapshot "$H" snull null && expect "used=null (early-session)" unknown "$H" snull
write_snapshot "$H" sstr '"forty"' && expect "used=non-numeric" unknown "$H" sstr
mkdir -p "$H/$CTX_REL"
printf '{"captured_at":"%s","session_id":"snoused","context_window":{"remaining_percentage":50,"current_usage":{"input_tokens":1}}}\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >"$H/$CTX_REL/snoused.json"
expect "used_percentage missing" unknown "$H" snoused

# --- Fail-open: null / missing current_usage (post-/compact state) -----------
write_snapshot "$H" scu 40 "" null && expect "current_usage=null (post-compact)" unknown "$H" scu
printf '{"captured_at":"%s","session_id":"snocu","context_window":{"used_percentage":40}}\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >"$H/$CTX_REL/snocu.json"
expect "current_usage missing" unknown "$H" snocu

# --- Fail-open: absent / stale / unparsable snapshot -------------------------
expect "snapshot absent" unknown "$H" nosuchsession
write_snapshot "$H" sold 40 "$(old_ts 20)" && expect "snapshot stale (20 min > 10-min window)" unknown "$H" sold
write_snapshot "$H" sfresh 40 "$(old_ts 5)" && expect "snapshot 5 min old (inside window)" smart "$H" sfresh
mkdir -p "$H/$CTX_REL" && printf 'torn{not json' >"$H/$CTX_REL/storn.json"
expect "snapshot unparsable" unknown "$H" storn
printf '{"session_id":"snots","context_window":{"used_percentage":40,"current_usage":{"input_tokens":1}}}\n' >"$H/$CTX_REL/snots.json"
expect "captured_at missing (staleness unverifiable)" unknown "$H" snots

# --- Hostile session id → unknown, no path traversal -------------------------
expect "hostile session id (../zones)" unknown "$H" "../zones"
expect "empty session id" unknown "$H" ""

# --- Forged captured_at: GNU date natural-language values must not pass ------
for TS in now yesterday "1 second ago"; do
  write_snapshot "$H" sforged 40 "$TS"
  expect "captured_at '$TS' (non-ISO) rejected" unknown "$H" sforged
done

# --- Snapshot session_id must match the requested id -------------------------
write_snapshot "$H" simposter 40
# portability-ok: GNU sed -i (no suffix) fails on BSD; perl -pi -e below is the
# actual portable fallback (perl's -i needs no backup-suffix argument on
# either dialect) — not the auto-recognized -i ''/-i "" guard shape.
sed -i 's/"session_id":"simposter"/"session_id":"someone-else"/' "$H/$CTX_REL/simposter.json" 2>/dev/null ||
  perl -pi -e 's/"session_id":"simposter"/"session_id":"someone-else"/' "$H/$CTX_REL/simposter.json"
expect "snapshot session_id mismatch (copied/renamed file)" unknown "$H" simposter

# --- zones.json override -----------------------------------------------------
HO="$WORK/h-override"
mkdir -p "$HO/.claude/context-guard"
printf '{"smart_max_used_percentage":30,"acceptable_max_used_percentage":60}\n' >"$HO/.claude/context-guard/zones.json"
write_snapshot "$HO" o40 40 && expect "override 30/60: used=40" acceptable "$HO" o40
write_snapshot "$HO" o25 25 && expect "override 30/60: used=25" smart "$HO" o25
write_snapshot "$HO" o61 61 && expect "override 30/60: used=61" dumb "$HO" o61

# --- zones.json preserves unrecognized keys' file (read-only resolver) -------
if [[ "$(cat "$HO/.claude/context-guard/zones.json")" == '{"smart_max_used_percentage":30,"acceptable_max_used_percentage":60}' ]]; then
  ok "resolver never rewrites zones.json"
else
  fail "resolver mutated zones.json"
fi

# --- Malformed zones.json → shipped defaults + visible stderr notice ---------
HM="$WORK/h-malformed"
mkdir -p "$HM/.claude/context-guard"
printf 'not json' >"$HM/.claude/context-guard/zones.json"
write_snapshot "$HM" m40 40
GOT="$(HOME="$HM" bash "$ZONE" m40 2>"$WORK/m-stderr")"
if [[ "$GOT" == "smart" ]]; then ok "malformed zones.json → shipped defaults applied"; else fail "malformed zones.json: got '$GOT'"; fi
if grep -qi 'zones' "$WORK/m-stderr"; then ok "malformed zones.json → visible stderr notice"; else fail "malformed zones.json: silent fallback"; fi

# Ordering violation (smart_max >= acceptable_max) is malformed too
printf '{"smart_max_used_percentage":80,"acceptable_max_used_percentage":60}\n' >"$HM/.claude/context-guard/zones.json"
GOT="$(HOME="$HM" bash "$ZONE" m40 2>"$WORK/m2-stderr")"
if [[ "$GOT" == "smart" ]]; then ok "inverted bands → shipped defaults applied"; else fail "inverted bands: got '$GOT'"; fi
if grep -qi 'zones' "$WORK/m2-stderr"; then ok "inverted bands → visible stderr notice"; else fail "inverted bands: silent fallback"; fi

# Wrong types are malformed
printf '{"smart_max_used_percentage":"low","acceptable_max_used_percentage":60}\n' >"$HM/.claude/context-guard/zones.json"
GOT="$(HOME="$HM" bash "$ZONE" m40 2>/dev/null)"
if [[ "$GOT" == "smart" ]]; then ok "non-numeric band → shipped defaults applied"; else fail "non-numeric band: got '$GOT'"; fi

# --- Exactly one word on stdout, always --------------------------------------
for sid in s0 s75x snull nosuchsession storn; do
  OUT="$(resolve "$H" "$sid" 2>/dev/null)"
  WORDS=$(printf '%s' "$OUT" | wc -w | tr -d ' \r')
  LINES=$(printf '%s' "$OUT" | grep -c . || true)
  if [[ "$WORDS" == "1" && "$LINES" == "1" ]]; then
    ok "single-word stdout for '$sid' ($OUT)"
  else
    fail "stdout not exactly one word for '$sid': '$OUT'"
  fi
  case "$OUT" in
    smart | acceptable | dumb | unknown) ok "vocabulary word for '$sid'" ;;
    *) fail "out-of-vocabulary output for '$sid': '$OUT'" ;;
  esac
done

# --- jq absent → unknown (fail-open, no crash) -------------------------------
FAKEBIN="$WORK/fakebin"
mkdir -p "$FAKEBIN"
for t in bash sh cat date dirname basename mktemp mkdir rm mv sleep tr grep sed find wc tail printf env; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
GOT="$(HOME="$H" PATH="$FAKEBIN" bash "$ZONE" s0 2>/dev/null)"
RC=$?
if [[ "$GOT" == "unknown" && $RC -eq 0 ]]; then ok "jq absent → unknown (fail-open)"; else fail "jq absent: got '$GOT' rc $RC"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
