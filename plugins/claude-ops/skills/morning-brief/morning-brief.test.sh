#!/usr/bin/env bash
# Regression tests for the morning-brief script's pure rendering logic.
# Every data source is fed as a fixture (no network, no gh required); the clock
# is pinned with --now so staleness is deterministic. Self-contained and
# cwd-independent per the plugin-test runner contract.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIEF="$SCRIPT_DIR/scripts/morning-brief.sh"

have() { command -v "$1" >/dev/null 2>&1; }
if ! have jq; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi
# morning-brief.sh parses timestamps on either the GNU (`date -d`) or the
# BSD/macOS (`date -j -f`) dialect, so the staleness path runs on both. Run the
# suite whenever either dialect is present; skip only when the host has neither
# (the age fixtures genuinely cannot be evaluated then).
have_gnu_date() { date -u -d "2026-01-01T00:00Z" +%s >/dev/null 2>&1; }
have_bsd_date() { date -u -j -f "%Y-%m-%dT%H:%MZ" "2026-01-01T00:00Z" +%s >/dev/null 2>&1; }
if ! have_gnu_date && ! have_bsd_date; then
  echo "SKIP: no supported date dialect (need GNU 'date -d' or BSD 'date -j -f')" >&2
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
CASE_NUM=0
pass() { CASE_NUM=$((CASE_NUM + 1)); printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"; }
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s\n  expected: %q\n  got: %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }
assert_exit() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi; }

# --- Fixtures -----------------------------------------------------------------
NOW="2026-07-20T08:00Z"

cat >"$TMP/counts.json" <<'EOF'
{"priority: needs-triage": 28, "status: ready": 44, "status: needs-decision": 3, "needs-human": 7}
EOF

# One clean non-draft (#10, kept), one draft-but-clean (#11, excluded), one
# non-draft BLOCKED (#12, excluded), one clean non-draft with a review (#13).
cat >"$TMP/pr.json" <<'EOF'
[
  {"number": 12, "title": "blocked pr", "url": "http://x/12", "isDraft": false, "mergeStateStatus": "BLOCKED", "reviewDecision": ""},
  {"number": 11, "title": "draft pr", "url": "http://x/11", "isDraft": true, "mergeStateStatus": "CLEAN", "reviewDecision": ""},
  {"number": 13, "title": "approved clean pr", "url": "http://x/13", "isDraft": false, "mergeStateStatus": "CLEAN", "reviewDecision": "APPROVED"},
  {"number": 10, "title": "clean pr", "url": "http://x/10", "isDraft": false, "mergeStateStatus": "CLEAN", "reviewDecision": ""}
]
EOF

# #100 uppercase marker must beat an earlier "not recommended"; #101 lowercase
# fallback; #102 no marker at all; #103 marker only in a comment.
cat >"$TMP/decisions.json" <<'EOF'
[
  {"number": 100, "title": "storage decision", "url": "http://x/i/100",
   "body": "Bare-clone hub is not recommended for this profile.\n1. **RECOMMENDED — Store the root in a userConfig key.**\nOther text.",
   "comments": []},
  {"number": 101, "title": "lowercase decision", "url": "http://x/i/101",
   "body": "Options weighed.\nrecommended: keep the interim surface for now.",
   "comments": []},
  {"number": 102, "title": "undecided", "url": "http://x/i/102",
   "body": "Still weighing options, no lean yet.",
   "comments": []},
  {"number": 103, "title": "comment-only rec", "url": "http://x/i/103",
   "body": "Original ask.",
   "comments": [{"body": "After review, RECOMMENDED: adopt option B."}]},
  {"number": 104, "title": "long rec", "url": "http://x/i/104",
   "body": "RECOMMENDED: alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi.",
   "comments": []}
]
EOF

# babysit fresh (1h30m), triage stale (26h), work unparsable stamp, work-2 has
# flags, and a non-lane scope-note comment that must be skipped.
cat >"$TMP/telemetry.json" <<'EOF'
[
  {"body": "- lane: babysit\n- last-cycle: 2026-07-20T06:30Z\n- flags: none"},
  {"body": "- lane: triage\n- last-cycle: 2026-07-19T06:00Z\n- flags: queue-depth climbing"},
  {"body": "- lane: work\n- last-cycle: 2026-07-20T07:XX\n- flags: -"},
  {"body": "- lane: work-2\n- last-cycle: 2026-07-20T07:40Z\n- flags: gh-identity drift detected"},
  {"body": "Scope note: this issue is the interim telemetry surface."}
]
EOF

printf '[]\n' >"$TMP/empty.json"

# --- Full render --------------------------------------------------------------
OUT="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" 2>&1)"
RC=$?

assert_exit "renders successfully" 0 "$RC"

# Queues
assert_contains "queue: needs-triage count" "$OUT" "priority: needs-triage"
assert_contains "queue: ready count 44" "$OUT" "44"

# Merge-ready — only clean non-drafts, sorted; excludes draft + blocked
assert_contains "merge-ready keeps clean #10" "$OUT" "#10 clean pr"
assert_contains "merge-ready keeps clean #13" "$OUT" "#13 approved clean pr"
assert_contains "merge-ready shows review verdict" "$OUT" "review=APPROVED"
assert_contains "merge-ready none-review shows 'none'" "$OUT" "review=none"
assert_not_contains "merge-ready drops draft #11" "$OUT" "#11 draft pr"
assert_not_contains "merge-ready drops blocked #12" "$OUT" "#12 blocked pr"
assert_contains "merge-ready points to authoritative gate" "$OUT" "/source-control:babysit-prs"

# Decisions — two-tier RECOMMENDED extraction
assert_contains "decision #100 uppercase marker wins" "$OUT" "Store the root in a userConfig key"
assert_not_contains "decision #100 ignores 'not recommended'" "$OUT" "not recommended for this profile"
assert_contains "decision #101 lowercase fallback" "$OUT" "keep the interim surface for now"
assert_contains "decision #102 no marker" "$OUT" "(no RECOMMENDED line found)"
assert_contains "decision #103 scans comments" "$OUT" "adopt option B"

# Telemetry — staleness + flags + skips
assert_contains "telemetry babysit fresh age" "$OUT" "babysit"
assert_contains "telemetry babysit not stale" "$OUT" "age=1h 30m"
assert_contains "telemetry triage stale flagged" "$OUT" "STALE (>6h)"
assert_contains "telemetry unparsable stamp handled" "$OUT" "unparsable timestamp"
assert_contains "telemetry surfaces flags" "$OUT" "gh-identity drift detected"
assert_not_contains "telemetry hides flags=none" "$OUT" "flags: none"

# --- RECOMMENDED preview truncation ------------------------------------------
OUT_TRUNC="$(bash "$BRIEF" --now "$NOW" --rec-maxlen 30 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/empty.json" 2>&1)"
assert_contains "long rec is truncated with ellipsis" "$OUT_TRUNC" "alpha beta gamma delta epsilon…"
assert_not_contains "long rec tail is dropped" "$OUT_TRUNC" "omicron pi"

# --- Graceful: no telemetry issue found --------------------------------------
printf 'null\n' >"$TMP/no-telemetry.json"
OUT2="$(bash "$BRIEF" --now "$NOW" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/no-telemetry.json" 2>&1)"
assert_contains "missing telemetry degrades gracefully" "$OUT2" "no telemetry issue found"

# --- Graceful: empty queues / no parked decisions ----------------------------
OUT3="$(bash "$BRIEF" --now "$NOW" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" 2>&1)"
assert_contains "no clean PRs message" "$OUT3" "(none clean right now)"
assert_contains "no parked decisions message" "$OUT3" "(none parked)"

# --- Argument handling --------------------------------------------------------
bash "$BRIEF" --help >/dev/null 2>&1
assert_exit "--help exits 0" 0 "$?"
bash "$BRIEF" --bogus >/dev/null 2>&1
assert_exit "unknown flag exits 3" 3 "$?"
bash "$BRIEF" --counts-json "$TMP/does-not-exist.json" >/dev/null 2>&1
assert_exit "missing fixture file exits 3" 3 "$?"

# Numeric-flag validation: a non-numeric value must fail with a clear message,
# not crash cryptically under `set -u` in the later arithmetic.
ERR_STALE="$(bash "$BRIEF" --stale-hours abc 2>&1)"
assert_exit "non-numeric --stale-hours exits 3" 3 "$?"
assert_contains "non-numeric --stale-hours clear message" "$ERR_STALE" "--stale-hours requires a non-negative integer"
ERR_MAXLEN="$(bash "$BRIEF" --rec-maxlen 12x 2>&1)"
assert_exit "non-numeric --rec-maxlen exits 3" 3 "$?"
assert_contains "non-numeric --rec-maxlen clear message" "$ERR_MAXLEN" "--rec-maxlen requires a non-negative integer"

# Leading-zero values are normalized to base-10, not misread as octal. A raw
# `08` errors in the `(( ))` staleness arithmetic and silently suppresses the
# STALE verdict; a raw `010` truncates to 8 chars instead of 10. Both must
# behave as the decimal the user wrote (normal-value paths above use 6 / 30).
OUT_LZ_STALE="$(bash "$BRIEF" --now "$NOW" --stale-hours 08 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/telemetry.json" 2>&1)"
assert_contains "--stale-hours 08 normalizes to 8 (stale still flagged)" "$OUT_LZ_STALE" "STALE (>8h)"
assert_not_contains "--stale-hours 08 no octal arithmetic error" "$OUT_LZ_STALE" "value too great for base"

OUT_LZ_MAXLEN="$(bash "$BRIEF" --now "$NOW" --rec-maxlen 010 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/empty.json" 2>&1)"
assert_contains "--rec-maxlen 010 normalizes to 10 (truncates at 10 chars)" "$OUT_LZ_MAXLEN" "alpha beta…"

# --- BSD/macOS date fallback --------------------------------------------------
# On macOS the relaxed guard above already drives the real BSD `date -j -f`
# branch (GNU `-d` fails, so to_epoch/from_epoch fall through to it). On a GNU
# host that branch is otherwise never taken, so a regression in it would ship
# undetected. Force it here with a `date` test double that rejects GNU `-d`
# (as real BSD date does) and services `-j -f` / `-r` by delegating the epoch
# math to the host's real date. This proves the BSD branch is reached and wired
# — return handling, TZ, from_epoch's `-r` render, and the parseable-vs-
# unparseable decision on the `07:XX` fixture. It does not re-implement strptime,
# so it does not assert format-string matching (only a real BSD date or a Python
# strptime could, and neither is in the bash+jq runner contract). The double
# relies on the host's `date -d`, so run it only when GNU date is present.
if have_gnu_date; then
  REAL_DATE="$(command -v date)"
  STUB_DIR="$TMP/bsd-date-stub"
  mkdir -p "$STUB_DIR"
  cat >"$STUB_DIR/date" <<'STUB'
#!/usr/bin/env bash
# BSD/macOS `date` test double. See morning-brief.test.sh for scope.
real="${MB_REAL_DATE:?MB_REAL_DATE not set}"
# Real BSD date has no `-d`; reject it so callers fall through to `-j -f` / `-r`.
for a in "$@"; do
  [[ "$a" == "-d" ]] && { echo "date: illegal option -- d" >&2; exit 1; }
done
uflag=() outfmt="" mode="" input="" epoch=""
while (($#)); do
  case "$1" in
    -u) uflag=(-u) ;;
    -j) mode="parse" ;;
    -f) shift ;;
    -r) mode="render"; epoch="$2"; shift ;;
    +*) outfmt="$1" ;;
    *)  input="$1" ;;
  esac
  shift
done
case "$mode" in
  parse)  exec "$real" "${uflag[@]}" -d "$input" "$outfmt" ;;
  render) exec "$real" "${uflag[@]}" -d "@$epoch" "$outfmt" ;;
  *)      exec "$real" "${uflag[@]}" "$outfmt" ;;
esac
STUB
  chmod +x "$STUB_DIR/date" 2>/dev/null || true

  OUT_BSD="$(PATH="$STUB_DIR:$PATH" MB_REAL_DATE="$REAL_DATE" \
    bash "$BRIEF" --now "$NOW" --stale-hours 6 \
    --counts-json "$TMP/counts.json" \
    --pr-json "$TMP/pr.json" \
    --decisions-json "$TMP/decisions.json" \
    --telemetry-json "$TMP/telemetry.json" 2>&1)"
  RC_BSD=$?
  assert_exit "BSD fallback: renders successfully" 0 "$RC_BSD"
  assert_contains "BSD fallback: fresh age computed via date -j -f" "$OUT_BSD" "age=1h 30m"
  assert_contains "BSD fallback: stale verdict via date -j -f" "$OUT_BSD" "STALE (>6h)"
  assert_contains "BSD fallback: unparsable stamp still unparsable" "$OUT_BSD" "unparsable timestamp"
fi

# --- Summary ------------------------------------------------------------------
echo
if ((FAILED > 0)); then
  printf 'morning-brief.test.sh: %d case(s) FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'morning-brief.test.sh: all %d cases passed\n' "$CASE_NUM"
