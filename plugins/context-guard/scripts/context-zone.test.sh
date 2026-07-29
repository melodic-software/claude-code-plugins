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
sed 's/"session_id":"simposter"/"session_id":"someone-else"/' "$H/$CTX_REL/simposter.json" \
  >"$H/$CTX_REL/simposter.json.tmp" &&
  mv "$H/$CTX_REL/simposter.json.tmp" "$H/$CTX_REL/simposter.json"
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

# --- Token shape: version gate, window-class bands, combination, plausibility -
# write_snapshot_tok <home> <sid> <used-json> <ti-json> <to-json> <cws-json> [<captured_at>] [<cli_version-json>]
# cli_version defaults to a version at or above the current-occupancy floor;
# pass the literal `omit` to write a snapshot with no cli_version at all.
write_snapshot_tok() {
  local home="$1" sid="$2" used="$3" ti="$4" to="$5" cws="$6" ts="${7:-}" ver="${8:-\"2.1.218\"}"
  [[ -n "$ts" ]] || ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local verfield=""
  [[ "$ver" == "omit" ]] || verfield=",\"cli_version\":$ver"
  mkdir -p "$home/$CTX_REL"
  printf '{"captured_at":"%s","session_id":"%s"%s,"context_window":{"total_input_tokens":%s,"total_output_tokens":%s,"context_window_size":%s,"used_percentage":%s,"remaining_percentage":50,"current_usage":{"input_tokens":100}}}\n' \
    "$ts" "$sid" "$verfield" "$ti" "$to" "$cws" "$used" >"$home/$CTX_REL/$sid.json"
}

HT="$WORK/h-token"
# Token shape stands alone when used_percentage is null but tokens are valid.
write_snapshot_tok "$HT" t1 null 150000 10000 1000000 && expect "tokens alone: occ=160k on 1M" smart "$HT" t1
write_snapshot_tok "$HT" t2 null 280000 20000 1000000 && expect "tokens alone: occ=300k on 1M" acceptable "$HT" t2
write_snapshot_tok "$HT" t3 null 390000 10001 1000000 && expect "tokens alone: occ=400001 on 1M" dumb "$HT" t3
# Shipped 200k-class edges, uppers inclusive.
write_snapshot_tok "$HT" t4 null 90000 10000 200000 && expect "200k class: occ=100000 (smart edge)" smart "$HT" t4
write_snapshot_tok "$HT" t5 null 150000 10000 200000 && expect "200k class: occ=160000 (acceptable edge)" acceptable "$HT" t5
write_snapshot_tok "$HT" t6 null 150001 10000 200000 && expect "200k class: occ=160001" dumb "$HT" t6
# Combination rule: the worse of the two computable shapes wins.
write_snapshot_tok "$HT" c1 40 150000 20000 200000 && expect "pct smart + tokens dumb → dumb" dumb "$HT" c1
write_snapshot_tok "$HT" c2 80 40000 10000 200000 && expect "pct dumb + tokens smart → dumb" dumb "$HT" c2
write_snapshot_tok "$HT" c3 40 40000 10000 200000 && expect "pct smart + tokens smart → smart" smart "$HT" c3
write_snapshot_tok "$HT" c4 60 40000 10000 200000 && expect "pct acceptable + tokens smart → acceptable" acceptable "$HT" c4
# Plausibility guard: occupancy above the window size is impossible as current
# occupancy (corrupt or forged data); the percentage shape stands alone.
write_snapshot_tok "$HT" p1 40 450000 50000 200000 && expect "implausible occ=500k>200k: pct stands alone" smart "$HT" p1
write_snapshot_tok "$HT" p2 null 450000 50000 200000 && expect "implausible occ + null pct → unknown" unknown "$HT" p2

# Version gate. Before 2.1.132 the token fields were CUMULATIVE session totals,
# and a cumulative total below the window size is indistinguishable from a real
# occupancy — the occupancy>window guard alone never catches it. The regression
# case is exactly that: 170k cumulative in a 200k window sits inside the window,
# passes the plausibility guard, and would resolve dumb while the live context
# is smart-zone.
write_snapshot_tok "$HT" g1 10 160000 10000 200000 '' '"2.1.131"' &&
  expect "pre-2.1.132 cumulative 170k in a 200k window: token shape dropped, pct stands alone" smart "$HT" g1
write_snapshot_tok "$HT" g2 null 160000 10000 200000 '' '"2.1.131"' &&
  expect "pre-2.1.132 + null pct → unknown, never a token-band zone" unknown "$HT" g2
write_snapshot_tok "$HT" g3 null 160000 10000 200000 '' '"2.1.132"' &&
  expect "2.1.132 exactly (floor, inclusive): token shape computable" dumb "$HT" g3
write_snapshot_tok "$HT" g4 null 160000 10000 200000 '' '"2.2"' &&
  expect "2.2 (short form, > floor): token shape computable" dumb "$HT" g4
write_snapshot_tok "$HT" g5 null 160000 10000 200000 '' '"3.0.0"' &&
  expect "3.0.0 (major bump): token shape computable" dumb "$HT" g5
write_snapshot_tok "$HT" g6 null 160000 10000 200000 '' '"2.1.99"' &&
  expect "2.1.99 (numeric, not lexical, comparison): token shape dropped" unknown "$HT" g6
write_snapshot_tok "$HT" g7 null 160000 10000 200000 '' omit &&
  expect "cli_version absent (older tee, or no version on stdin): token shape dropped" unknown "$HT" g7
write_snapshot_tok "$HT" g8 null 160000 10000 200000 '' '"2.1.132-beta"' &&
  expect "non-numeric version string: token shape dropped" unknown "$HT" g8
write_snapshot_tok "$HT" g9 null 160000 10000 200000 '' 2 &&
  expect "cli_version not a string: token shape dropped" unknown "$HT" g9
# Window smaller than every configured class: token shape not computable.
write_snapshot_tok "$HT" w1 null 40000 10000 100000 && expect "window below all classes + null pct → unknown" unknown "$HT" w1
write_snapshot_tok "$HT" w2 40 40000 10000 100000 && expect "window below all classes: pct stands alone" smart "$HT" w2

# token_bands override honored.
HTB="$WORK/h-tokenbands"
mkdir -p "$HTB/.claude/context-guard"
printf '{"smart_max_used_percentage":50,"acceptable_max_used_percentage":75,"token_bands":{"200000":{"smart_max_tokens":50000,"acceptable_max_tokens":80000}}}\n' \
  >"$HTB/.claude/context-guard/zones.json"
write_snapshot_tok "$HTB" b1 null 60000 10000 200000 && expect "override token bands 50k/80k: occ=70k" acceptable "$HTB" b1
write_snapshot_tok "$HTB" b2 null 40000 5000 200000 && expect "override token bands 50k/80k: occ=45k" smart "$HTB" b2

# Malformed token_bands → shipped token defaults + visible stderr notice;
# valid percentage keys in the same file still apply.
HTM="$WORK/h-tokenmal"
mkdir -p "$HTM/.claude/context-guard"
printf '{"smart_max_used_percentage":50,"acceptable_max_used_percentage":75,"token_bands":{"200000":{"smart_max_tokens":300000,"acceptable_max_tokens":400000}}}\n' \
  >"$HTM/.claude/context-guard/zones.json"
write_snapshot_tok "$HTM" tm1 null 150000 20000 200000
GOT="$(HOME="$HTM" bash "$ZONE" tm1 2>"$WORK/tb-stderr")"
if [[ "$GOT" == "dumb" ]]; then ok "malformed token_bands (acceptable>class) → shipped token defaults"; else fail "malformed token_bands: got '$GOT'"; fi
if grep -qi 'token_bands' "$WORK/tb-stderr"; then ok "malformed token_bands → visible stderr notice"; else fail "malformed token_bands: silent fallback"; fi

# v1 percentage-only zones.json: token_bands absent is zero-config (shipped
# token defaults apply, silently).
HTV="$WORK/h-tokenv1"
mkdir -p "$HTV/.claude/context-guard"
printf '{"smart_max_used_percentage":30,"acceptable_max_used_percentage":60}\n' >"$HTV/.claude/context-guard/zones.json"
write_snapshot_tok "$HTV" v1 null 150000 20000 200000
GOT="$(HOME="$HTV" bash "$ZONE" v1 2>"$WORK/v1-stderr")"
if [[ "$GOT" == "dumb" ]]; then ok "v1 zones.json: shipped token defaults still apply"; else fail "v1 zones.json token defaults: got '$GOT'"; fi
if [[ -s "$WORK/v1-stderr" ]]; then fail "v1 zones.json: unexpected stderr notice for absent token_bands"; else ok "v1 zones.json: absent token_bands is silent zero-config"; fi

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
