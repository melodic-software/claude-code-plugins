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
have_gnu_date() { date -u -d "2026-01-01T00:00Z" +%s >/dev/null 2>&1; } # portability-ok: dialect probe, BSD probe below (#1510)
have_bsd_date() { date -u -j -f "%Y-%m-%dT%H:%MZ" "2026-01-01T00:00Z" +%s >/dev/null 2>&1; }
if ! have_gnu_date && ! have_bsd_date; then
  # portability-ok: names both dialects inside a skip message; neither is invoked (#1510)
  echo "SKIP: no supported date dialect (need GNU 'date -d' or BSD 'date -j -f')" >&2
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
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
FIXTURE_REPO="example/test-repo"

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
   "comments": []},
  {"number": 105, "title": "lowercase after rejection", "url": "http://x/i/105",
   "body": "The bare-clone hub is not recommended here.\nrecommended: keep the sibling worktree layout.",
   "comments": []},
  {"number": 106, "title": "uppercase after rejection", "url": "http://x/i/106",
   "body": "Option A is NOT RECOMMENDED because of drift.\nRECOMMENDED: choose the managed sync path.",
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

# Merged-PR fixture for the stranded-findings section, shaped like the real case
# (#1720): a P1 review comment posted 46 SECONDS AFTER the merge landed. The
# fixture mirrors `gh api graphql --paginate` output — a list of page documents.
#   #1720 — P1 thread created after merge      -> stranded, must report
#   #1707 — thread created BEFORE the merge     -> gate saw it, must NOT report
#   #1712 — post-merge thread already resolved  -> handled, must NOT report
#   #1690 — merged outside the window           -> too old, must NOT report
cat >"$TMP/merged.json" <<'EOF'
[
  {"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
    {"number": 1720, "title": "feat(claude-ops): consume lane restart-requests",
     "url": "https://github.com/o/r/pull/1720", "mergedAt": "2026-07-19T19:23:17Z",
     "reviewThreads": {"nodes": [
       {"isResolved": false, "comments": {"nodes": [
         {"createdAt": "2026-07-19T19:24:03Z", "author": {"login": "chatgpt-codex-connector"},
          "body": "![P1 Badge](x) Distinguish lock-storage errors from held locks"}]}},
       {"isResolved": false, "comments": {"nodes": [
         {"createdAt": "2026-07-19T19:24:03Z", "author": {"login": "chatgpt-codex-connector"},
          "body": "![P2 Badge](x) Preserve scheduler options"}]}}]}},
    {"number": 1707, "title": "feat(planning): draft non-quantifiable goals",
     "url": "https://github.com/o/r/pull/1707", "mergedAt": "2026-07-19T16:23:23Z",
     "reviewThreads": {"nodes": [
       {"isResolved": false, "comments": {"nodes": [
         {"createdAt": "2026-07-19T15:00:00Z", "author": {"login": "a-human"},
          "body": "P1 this predates the merge"}]}}]}},
    {"number": 1712, "title": "docs(loop-lane): pin the prompt-fresh distinction",
     "url": "https://github.com/o/r/pull/1712", "mergedAt": "2026-07-19T16:24:00Z",
     "reviewThreads": {"nodes": [
       {"isResolved": true, "comments": {"nodes": [
         {"createdAt": "2026-07-19T16:30:00Z", "author": {"login": "chatgpt-codex-connector"},
          "body": "P1 already dealt with"}]}}]}},
    {"number": 1690, "title": "feat(loop-lane): out-of-band escalation",
     "url": "https://github.com/o/r/pull/1690", "mergedAt": "2026-07-01T10:00:00Z",
     "reviewThreads": {"nodes": [
       {"isResolved": false, "comments": {"nodes": [
         {"createdAt": "2026-07-01T10:05:00Z", "author": {"login": "chatgpt-codex-connector"},
          "body": "P1 but long outside the window"}]}}]}}
  ]}}}}
]
EOF

# Severity classification and ranking edge cases, all three found by review on
# the PR that added this section:
#   #300 — a P2 whose PROSE says "P1" and "CRITICAL": body-substring matching
#          falsely promoted it. Only the structured marker counts.
#   #301 — an unclassified thread beside a P0: "--" sorts before "P0"
#          lexicographically, so the PR would render "[--]" and hide the P0.
#   #302 — the shields badge/P0 URL form, with no alt-text marker.
cat >"$TMP/merged-severity.json" <<'EOF'
[
  {"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
    {"number": 300, "title": "prose mentions a higher severity",
     "url": "https://github.com/o/r/pull/300", "mergedAt": "2026-07-19T16:00:00Z",
     "reviewThreads": {"nodes": [
       {"isResolved": false, "comments": {"nodes": [
         {"createdAt": "2026-07-19T17:00:00Z", "author": {"login": "bot"},
          "body": "![P2 Badge](x) Preserve P1 labels when CRITICAL SECURITY findings appear"}]}}]}},
    {"number": 301, "title": "unclassified thread beside a real P0",
     "url": "https://github.com/o/r/pull/301", "mergedAt": "2026-07-19T16:00:00Z",
     "reviewThreads": {"nodes": [
       {"isResolved": false, "comments": {"nodes": [
         {"createdAt": "2026-07-19T17:00:00Z", "author": {"login": "bot"},
          "body": "a plain comment carrying no severity marker at all"}]}},
       {"isResolved": false, "comments": {"nodes": [
         {"createdAt": "2026-07-19T17:01:00Z", "author": {"login": "bot"},
          "body": "![P0 Badge](x) the real problem"}]}}]}},
    {"number": 302, "title": "shields url badge form only",
     "url": "https://github.com/o/r/pull/302", "mergedAt": "2026-07-19T16:00:00Z",
     "reviewThreads": {"nodes": [
       {"isResolved": false, "comments": {"nodes": [
         {"createdAt": "2026-07-19T17:00:00Z", "author": {"login": "bot"},
          "body": "see https://img.shields.io/badge/P0-red?style=flat for the rating"}]}}]}}
  ]}}}}
]
EOF

# A PR whose thread connection was TRUNCATED: the read is partial, so neither
# the finding list nor an all-clear can be trusted to be complete.
cat >"$TMP/merged-truncated.json" <<'EOF'
[
  {"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
    {"number": 400, "title": "more than one page of review threads",
     "url": "https://github.com/o/r/pull/400", "mergedAt": "2026-07-19T16:00:00Z",
     "reviewThreads": {"pageInfo": {"hasNextPage": true}, "nodes": [
       {"isResolved": true, "comments": {"nodes": [
         {"createdAt": "2026-07-19T17:00:00Z", "author": {"login": "bot"},
          "body": "![P2 Badge](x) resolved, so nothing is reported for this PR"}]}}]}}
  ]}}}}
]
EOF

# A GraphQL error document: well-formed JSON with no `data`. Must never render
# as an all-clear — observed live, where a rate-limit error read as a clean
# window, which is the fail-open shape this whole section exists to catch.
cat >"$TMP/merged-apierror.json" <<'EOF'
[
  {"errors": [{"type": "RATE_LIMIT", "code": "graphql_rate_limit",
               "message": "API rate limit already exceeded for user ID 1."}]}
]
EOF

# No merged PR carries a post-merge thread — the clean-window branch.
cat >"$TMP/merged-clean.json" <<'EOF'
[
  {"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
    {"number": 1707, "title": "all clear", "url": "https://github.com/o/r/pull/1707",
     "mergedAt": "2026-07-19T16:23:23Z", "reviewThreads": {"nodes": []}}
  ]}}}}
]
EOF

# Non-empty telemetry array with zero lane-tagged comments (only scope notes) —
# the any=0 branch, distinct from the null/no-issue-found case above.
cat >"$TMP/telemetry-no-lanes.json" <<'EOF'
[
  {"body": "Scope note: this issue is the interim telemetry surface."},
  {"body": "Another housekeeping comment with no lane field."}
]
EOF

# A repo whose label taxonomy does not include the melodic-software defaults.
cat >"$TMP/repo-labels-alternate.json" <<'EOF'
["bug", "enhancement", "status: blocked"]
EOF

# A repo that carries only a subset of the defaults (ready + needs-human).
cat >"$TMP/repo-labels-partial.json" <<'EOF'
["status: ready", "needs-human", "documentation"]
EOF

# A repo with no labels at all (successful empty lookup, not a failed one).
printf '[]\n' >"$TMP/repo-labels-empty.json"

# --- Full render --------------------------------------------------------------
OUT="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged.json" 2>&1)"
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
# #105: the lowercase fallback must anchor to marker position, not grab the
# incidental "recommended" inside an earlier "not recommended" rejection line.
assert_contains "decision #105 lowercase marker beats earlier 'not recommended'" "$OUT" "keep the sibling worktree layout"
assert_not_contains "decision #105 ignores 'not recommended' rejection" "$OUT" "bare-clone hub is not recommended"
# #106: tier 1 (uppercase) must anchor too — an unanchored uppercase scan grabs
# the "NOT RECOMMENDED" prose line before the real marker.
assert_contains "decision #106 uppercase marker beats earlier 'NOT RECOMMENDED'" "$OUT" "choose the managed sync path"
assert_not_contains "decision #106 ignores 'NOT RECOMMENDED' rejection" "$OUT" "because of drift"

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

# --- RECOMMENDED preview: 0 = full (no truncation) ---------------------------
OUT_FULL="$(bash "$BRIEF" --now "$NOW" --rec-maxlen 0 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/empty.json" 2>&1)"
assert_contains "rec-maxlen 0 keeps the full tail untruncated" "$OUT_FULL" "omicron pi"
assert_not_contains "rec-maxlen 0 never inserts an ellipsis" "$OUT_FULL" "…"

# --- Telemetry: non-empty array with no lane-tagged comments (any=0) ---------
OUT_NO_LANES="$(bash "$BRIEF" --now "$NOW" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/telemetry-no-lanes.json" 2>&1)"
assert_contains "telemetry with no lane-tagged comments reports none found" "$OUT_NO_LANES" "(no per-lane comments found on the telemetry issue)"

# --- Graceful: no telemetry issue found --------------------------------------
printf 'null\n' >"$TMP/no-telemetry.json"
OUT2="$(bash "$BRIEF" --now "$NOW" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/no-telemetry.json" 2>&1)"
assert_contains "missing telemetry degrades gracefully" "$OUT2" "no telemetry issue found"

# --- Graceful: queue labels absent in consuming repo -------------------------
OUT_NO_QL="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" \
  --repo-labels-json "$TMP/repo-labels-alternate.json" \
  --counts-json "$TMP/empty.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "no matching queue labels degrades gracefully" "$OUT_NO_QL" "no queue labels found in this repo"
assert_contains "degradation names the defaults" "$OUT_NO_QL" "pass --queue-labels to customize"
QUEUE_ONLY="$(printf '%s\n' "$OUT_NO_QL" | awk '/^== Queues/,/^== /{if (!/^== / || /^== Queues/) print}')"
assert_not_contains "absent defaults are not rendered as 0 count rows" "$QUEUE_ONLY" $'priority: needs-triage          0'
assert_not_contains "absent defaults are not rendered as ? count rows" "$QUEUE_ONLY" $'priority: needs-triage          ?'

OUT_PARTIAL_QL="$(bash "$BRIEF" --now "$NOW" \
  --repo-labels-json "$TMP/repo-labels-partial.json" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "partial taxonomy shows only labels that exist" "$OUT_PARTIAL_QL" "status: ready"
assert_contains "partial taxonomy keeps another existing label" "$OUT_PARTIAL_QL" "needs-human"
assert_not_contains "partial taxonomy drops absent default labels" "$OUT_PARTIAL_QL" "priority: needs-triage"

OUT_CUSTOM_QL="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" \
  --queue-labels "bug, enhancement" \
  --repo-labels-json "$TMP/repo-labels-alternate.json" \
  --counts-json "$TMP/empty.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "pinned queue labels are honored" "$OUT_CUSTOM_QL" "bug"
assert_contains "pinned queue labels include the second entry" "$OUT_CUSTOM_QL" "enhancement"

OUT_NO_DEC="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" \
  --repo-labels-json "$TMP/repo-labels-alternate.json" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "missing decision label degrades gracefully" "$OUT_NO_DEC" "decision label not found in this repo"

OUT_EMPTY_LABELS="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" \
  --repo-labels-json "$TMP/repo-labels-empty.json" \
  --counts-json "$TMP/empty.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "empty label inventory degrades queue section" "$OUT_EMPTY_LABELS" "no queue labels found in this repo"

OUT_EMPTY_LABELS_DEC="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" \
  --repo-labels-json "$TMP/repo-labels-empty.json" \
  --counts-json "$TMP/empty.json" \
  --pr-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "empty label inventory degrades decision section" "$OUT_EMPTY_LABELS_DEC" "decision label not found in this repo"

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
# unparsable decision on the `07:XX` fixture. It does not re-implement strptime,
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

# --- Stranded findings on merged PRs (#1777) ----------------------------------
# The discriminator is the comment's timestamp vs the merge's: a thread the merge
# gate could never have seen, because it did not exist yet.
assert_contains "stranded: reports the post-merge P1" "$OUT" "#1720"
assert_contains "stranded: severity survives to the operator" "$OUT" "[P1]"
# One line per PR, not per thread: #1720 carries a P1 and a P2, and must render
# once at its WORST severity with the count — repeating a title per thread buries
# every other PR in the section.
assert_contains "stranded: several findings on one PR collapse to one line" "$OUT" "(2 findings)"
assert_not_contains "stranded: a collapsed PR is not softened to its lesser severity" "$OUT" "[P2] #1720"
assert_contains "stranded: names the reviewer" "$OUT" "by chatgpt-codex-connector"
assert_contains "stranded: says why it was missed" "$OUT" "merge gate could not see it"
# The three negative cases matter more than the positive: a check that reports
# every unresolved thread on every merged PR is noise, not a signal.
assert_not_contains "stranded: a thread PREDATING the merge is not stranded" "$OUT" "#1707"
assert_not_contains "stranded: an already-RESOLVED post-merge thread is excluded" "$OUT" "#1712"
assert_not_contains "stranded: a merge outside the window is excluded" "$OUT" "#1690"

# Severity ordering: a P0/P1 must not sort below advisory findings.
STRANDED_BLOCK="$(printf '%s\n' "$OUT" | sed -n '/stranded on merged/,$p')"
FIRST_SEV="$(printf '%s\n' "$STRANDED_BLOCK" | grep -oE '^[[:space:]]+\[P[0-9]\]' | head -1 | tr -d ' ')"
assert_contains "stranded: highest severity is listed first" "$FIRST_SEV" "[P1]"

# Clean window renders the reassuring branch rather than an empty section.
OUT_CLEAN="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "stranded: a clean window says so explicitly" "$OUT_CLEAN" "every merged PR in the window is clear"

# An API error must NOT read as an all-clear. This is the section's own fail-open
# failure mode, and it was observed live before being fixed.
OUT_ERR="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged-apierror.json" 2>&1)"
assert_not_contains "stranded: an API error is NEVER reported as clear" "$OUT_ERR" "every merged PR in the window is clear"
assert_contains "stranded: an API error renders the section UNREADABLE" "$OUT_ERR" "UNREADABLE: API rate limit"
assert_contains "stranded: the API error message is surfaced" "$OUT_ERR" "rate limit already exceeded"
assert_contains "stranded: the header counts the unreadable section" "$OUT_ERR" "1 of 5 sections unreadable: stranded"

# --- Severity classification and ranking -------------------------------------
OUT_SEV="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged-severity.json" 2>&1)"
# Prose is not a severity marker: only the structured badge counts.
assert_contains "severity: a P2 whose prose says P1/CRITICAL stays P2" "$OUT_SEV" "[P2] #300"
assert_not_contains "severity: prose never promotes a finding" "$OUT_SEV" "[P1] #300"
assert_not_contains "severity: the word CRITICAL in prose never promotes to P0" "$OUT_SEV" "[P0] #300"
# Ranking is numeric, so an unclassified thread cannot mask a real P0.
assert_contains "severity: an unclassified thread never hides a P0" "$OUT_SEV" "[P0] #301"
assert_not_contains "severity: the unclassified marker never wins the collapse" "$OUT_SEV" "[--] #301"
# Both structured marker forms the bots emit are recognized.
assert_contains "severity: the shields badge/P0 URL form is recognized" "$OUT_SEV" "[P0] #302"

# --- Truncated thread page is a PARTIAL read, never an all-clear -------------
OUT_TRUNC="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged-truncated.json" 2>&1)"
assert_contains "truncation: a partial thread read is reported" "$OUT_TRUNC" "this read is PARTIAL"
assert_contains "truncation: the affected PR is named" "$OUT_TRUNC" "#400"

# The window is operator-tunable, and widening it must pull in the older merge.
OUT_WIDE="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 --stranded-days 60 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged.json" 2>&1)"
assert_contains "stranded: --stranded-days widens the window" "$OUT_WIDE" "#1690"
assert_contains "stranded: the window is reported in the header" "$OUT_WIDE" "last 60d"

# --- Degraded-mode contract: an unreadable source is never an all-clear -------
# A `gh` test double on PATH stands in for the network. MB_GH_MODE selects the
# host's behavior:
#   blocked  every call is refused with the pinned-GraphQL 403 shape (body on
#            stdout, message on stderr, exit 1) — the cloud-session shape
#   fail     every call fails with an unrelated error
#   rest     GraphQL-backed subcommands are refused as in `blocked`; `gh api
#            repos/...` is served from MB_GH_FIXTURES/<sanitized path>.json,
#            a missing fixture answering 404
GH_STUB_DIR="$TMP/gh-stub"
mkdir -p "$GH_STUB_DIR"
cat >"$GH_STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
mode="${MB_GH_MODE:?MB_GH_MODE not set}"
blocked() {
  printf '{"message":"This GraphQL query is not enabled for this session — only the pinned set of PR-review operations is served. Use REST via `gh api repos/{owner}/{repo}/...` instead.","documentation_url":"https://example.invalid/docs"}\n'
  printf 'gh: This GraphQL query is not enabled for this session — only the pinned set of PR-review operations is served. (HTTP 403)\n' >&2
  exit 1
}
case "$mode" in
  blocked) blocked ;;
  fail)
    printf 'gh: boom, the upstream fell over (HTTP 500)\n' >&2
    exit 1
    ;;
  rest)
    [[ "${1:-}" == "api" ]] || blocked
    shift
    path=""
    for a in "$@"; do
      [[ "$a" == repos/* ]] && path="$a"
    done
    [[ -n "$path" ]] || blocked
    key="$(printf '%s' "$path" | sed -E 's/[^A-Za-z0-9._-]/_/g')"
    f="${MB_GH_FIXTURES:?MB_GH_FIXTURES not set}/$key.json"
    if [[ -f "$f" ]]; then
      cat "$f"
      exit 0
    fi
    printf '{"message":"Not Found","documentation_url":"https://example.invalid/docs"}\n'
    printf 'gh: Not Found (HTTP 404) — no fixture %s\n' "$key" >&2
    exit 1
    ;;
  *)
    printf 'gh stub: unknown MB_GH_MODE %s\n' "$mode" >&2
    exit 2
    ;;
esac
STUB
chmod +x "$GH_STUB_DIR/gh"

run_stub() {
  # run_stub MODE args... — runs the brief with the gh double on PATH.
  local mode="$1"
  shift
  PATH="$GH_STUB_DIR:$PATH" MB_GH_MODE="$mode" MB_GH_FIXTURES="${MB_GH_FIXTURES:-$TMP/rest}" \
    bash "$BRIEF" --now "$NOW" --stale-hours 6 --repo "$FIXTURE_REPO" "$@" 2>&1
}

section() {
  # section OUTPUT "== heading prefix" — the lines of one section, heading included.
  printf '%s\n' "$1" | awk -v h="$2" 'index($0, h) == 1 {p = 1; print; next} /^== / {p = 0} p'
}

# Every section live, every call refused: nothing may read as clear or absent.
OUT_BLOCKED="$(run_stub blocked)"
RC_BLOCKED=$?
assert_exit "blocked: every live section unreadable exits 5" 5 "$RC_BLOCKED"
assert_contains "blocked: header counts every section" "$OUT_BLOCKED" "5 of 5 sections unreadable"
assert_contains "blocked: queues are UNREADABLE" "$(section "$OUT_BLOCKED" "== Queues")" "UNREADABLE:"
assert_contains "blocked: merge-ready is UNREADABLE" "$(section "$OUT_BLOCKED" "== Merge-ready")" "UNREADABLE:"
assert_contains "blocked: decisions are UNREADABLE" "$(section "$OUT_BLOCKED" "== Parked")" "UNREADABLE:"
assert_contains "blocked: telemetry is UNREADABLE" "$(section "$OUT_BLOCKED" "== Lane telemetry")" "UNREADABLE:"
assert_contains "blocked: stranded is UNREADABLE" "$(section "$OUT_BLOCKED" "== Findings stranded")" "UNREADABLE:"
assert_not_contains "blocked: stranded never renders an all-clear" "$OUT_BLOCKED" "every merged PR in the window is clear"
assert_not_contains "blocked: telemetry never renders as absent" "$OUT_BLOCKED" "no telemetry issue found"
assert_not_contains "blocked: merge-ready never renders as none clean" "$OUT_BLOCKED" "(none clean right now)"
assert_not_contains "blocked: decisions never render as none parked" "$OUT_BLOCKED" "(none parked)"
assert_not_contains "blocked: queues never render a ? count" "$(section "$OUT_BLOCKED" "== Queues")" " ?"
assert_contains "blocked: the refusal is surfaced verbatim" "$OUT_BLOCKED" "not enabled for this session"

# An unrelated failure degrades the same way; the shape of the error does not
# decide whether a section is readable.
OUT_FAIL="$(run_stub fail)"
RC_FAIL=$?
assert_exit "fail: every live section unreadable exits 5" 5 "$RC_FAIL"
assert_contains "fail: the error is surfaced" "$OUT_FAIL" "UNREADABLE: boom, the upstream fell over"
assert_not_contains "fail: no REST transport claimed for an unrelated error" "$OUT_FAIL" "transport: REST"

# One live section among fixtures: a partial brief is still a brief (exit 0),
# and the header says which section was lost.
OUT_ONE="$(run_stub blocked \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json")"
RC_ONE=$?
assert_exit "partial: one unreadable section among fixtures exits 0" 0 "$RC_ONE"
assert_contains "partial: header names the lost section" "$OUT_ONE" "1 of 5 sections unreadable: stranded"
assert_contains "partial: the fixture sections still render" "$OUT_ONE" "#10 clean pr"

# A `message`-shaped error body (the REST/403 shape, no `errors` key) fed as a
# fixture is an unreadable source, exactly like the GraphQL `errors` shape.
cat >"$TMP/merged-message-error.json" <<'EOF'
{"message":"This GraphQL query is not enabled for this session — only the pinned set of PR-review operations is served.","documentation_url":"https://example.invalid/docs"}
EOF
OUT_MSG="$(bash "$BRIEF" --now "$NOW" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged-message-error.json" 2>&1)"
assert_not_contains "message-shaped error: never an all-clear" "$OUT_MSG" "every merged PR in the window is clear"
assert_contains "message-shaped error: renders UNREADABLE" "$OUT_MSG" "UNREADABLE: This GraphQL query is not enabled"

# --- Repo resolution falls back to the git origin remote ---------------------
if have git; then
  CHECKOUT="$TMP/checkout"
  mkdir -p "$CHECKOUT"
  git -C "$CHECKOUT" init -q 2>/dev/null
  git -C "$CHECKOUT" remote add origin "https://github.com/$FIXTURE_REPO.git"
  OUT_REMOTE="$(cd "$CHECKOUT" && PATH="$GH_STUB_DIR:$PATH" MB_GH_MODE=blocked \
    bash "$BRIEF" --now "$NOW" \
    --counts-json "$TMP/counts.json" \
    --pr-json "$TMP/pr.json" \
    --decisions-json "$TMP/decisions.json" 2>&1)"
  RC_REMOTE=$?
  assert_exit "git remote fallback: renders (exit 0, two of five unreadable)" 0 "$RC_REMOTE"
  assert_contains "git remote fallback: owner/repo taken from origin" "$OUT_REMOTE" "Morning brief — $FIXTURE_REPO —"
  assert_contains "git remote fallback: the header names the source" "$OUT_REMOTE" "repo resolved from the git origin remote"
  assert_contains "git remote fallback: live sections still degrade honestly" "$OUT_REMOTE" "2 of 5 sections unreadable: telemetry stranded"
fi

# --- REST fallback: sections 1-4 from repository-scoped endpoints -------------
# The REST fixtures and the gh-shaped fixtures below describe the SAME data, so
# the two paths must render sections 1-3 byte-identically (and telemetry
# identically once the REST path's source line is set aside).
REST="$TMP/rest"
mkdir -p "$REST"
rest_key() { printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]/_/g'; }
R="repos/$FIXTURE_REPO"
cat >"$REST/$(rest_key "$R/labels?per_page=100").json" <<'EOF'
[{"name": "status: ready"}, {"name": "needs-human"}, {"name": "status: needs-decision"}]
EOF
# Two issues and one pull request carry the label: the count excludes the PR.
cat >"$REST/$(rest_key "$R/issues?state=open&per_page=100&labels=status%3A%20ready").json" <<'EOF'
[{"number": 1, "title": "a"}, {"number": 2, "title": "b"}, {"number": 3, "title": "pr", "pull_request": {"url": "x"}}]
EOF
cat >"$REST/$(rest_key "$R/issues?state=open&per_page=100&labels=needs-human").json" <<'EOF'
[{"number": 4, "title": "c"}]
EOF
cat >"$REST/$(rest_key "$R/issues?state=open&per_page=100&labels=status%3A%20needs-decision").json" <<'EOF'
[{"number": 42, "title": "pick a store", "html_url": "http://x/i/42", "body": "Options weighed.\nRECOMMENDED: option B."}]
EOF
cat >"$REST/$(rest_key "$R/issues/42/comments?per_page=100").json" <<'EOF'
[{"body": "no change of lean"}]
EOF
cat >"$REST/$(rest_key "$R/pulls?state=open&per_page=100").json" <<'EOF'
[{"number": 9, "title": "blocked one"}, {"number": 8, "title": "draft one"}, {"number": 7, "title": "clean one"}]
EOF
cat >"$REST/$(rest_key "$R/pulls/7").json" <<'EOF'
{"number": 7, "title": "clean one", "html_url": "http://x/7", "draft": false, "mergeable": true, "mergeable_state": "clean"}
EOF
cat >"$REST/$(rest_key "$R/pulls/8").json" <<'EOF'
{"number": 8, "title": "draft one", "html_url": "http://x/8", "draft": true, "mergeable": true, "mergeable_state": "clean"}
EOF
cat >"$REST/$(rest_key "$R/pulls/9").json" <<'EOF'
{"number": 9, "title": "blocked one", "html_url": "http://x/9", "draft": false, "mergeable": true, "mergeable_state": "blocked"}
EOF
cat >"$REST/$(rest_key "$R/issues?state=open&per_page=100").json" <<'EOF'
[{"number": 51, "title": "unrelated"},
 {"number": 50, "title": "Loop-lane telemetry: running per-lane status"},
 {"number": 52, "title": "loop-lane telemetry running per-lane status (older duplicate)", "pull_request": {"url": "x"}}]
EOF
cat >"$REST/$(rest_key "$R/issues/50/comments?per_page=100").json" <<'EOF'
[{"body": "- lane: babysit\n- last-cycle: 2026-07-20T06:30Z\n- flags: none"}]
EOF

OUT_REST="$(run_stub rest)"
RC_REST=$?
assert_exit "rest: renders with the stranded section unreadable (exit 0)" 0 "$RC_REST"
assert_contains "rest: the header names the transport" "$OUT_REST" "transport: REST"
assert_contains "rest: queue count excludes pull requests" "$(section "$OUT_REST" "== Queues")" "status: ready            2"
assert_contains "rest: queue count for the second label" "$(section "$OUT_REST" "== Queues")" "needs-human              1"
assert_not_contains "rest: absent default labels are not rendered" "$(section "$OUT_REST" "== Queues")" "priority: needs-triage"
assert_contains "rest: merge-ready keeps the clean non-draft" "$OUT_REST" "#7 clean one"
assert_not_contains "rest: merge-ready drops the draft" "$OUT_REST" "#8 draft one"
assert_not_contains "rest: merge-ready drops the blocked" "$OUT_REST" "#9 blocked one"
assert_contains "rest: review decision is reported as n/a" "$OUT_REST" "review=n/a"
assert_contains "rest: decision RECOMMENDED line is extracted" "$OUT_REST" "RECOMMENDED: option B."
assert_contains "rest: telemetry issue found by title" "$OUT_REST" "source: issue #50"
assert_contains "rest: telemetry lane age computed" "$OUT_REST" "babysit    last-cycle=2026-07-20T06:30Z  age=1h 30m"
assert_contains "rest: stranded is UNREADABLE, never clear" "$(section "$OUT_REST" "== Findings stranded")" "UNREADABLE: review threads need GraphQL"
assert_contains "rest: header counts the one lost section" "$OUT_REST" "1 of 5 sections unreadable: stranded"

# The same data through the gh-shaped fixtures.
cat >"$TMP/same-counts.json" <<'EOF'
{"status: ready": 2, "needs-human": 1, "status: needs-decision": 1}
EOF
cat >"$TMP/same-labels.json" <<'EOF'
["status: ready", "needs-human", "status: needs-decision"]
EOF
cat >"$TMP/same-pr.json" <<'EOF'
[
  {"number": 9, "title": "blocked one", "url": "http://x/9", "isDraft": false, "mergeStateStatus": "BLOCKED", "reviewDecision": "n/a"},
  {"number": 8, "title": "draft one", "url": "http://x/8", "isDraft": true, "mergeStateStatus": "CLEAN", "reviewDecision": "n/a"},
  {"number": 7, "title": "clean one", "url": "http://x/7", "isDraft": false, "mergeStateStatus": "CLEAN", "reviewDecision": "n/a"}
]
EOF
cat >"$TMP/same-decisions.json" <<'EOF'
[{"number": 42, "title": "pick a store", "url": "http://x/i/42", "body": "Options weighed.\nRECOMMENDED: option B.", "comments": [{"body": "no change of lean"}]}]
EOF
cat >"$TMP/same-telemetry.json" <<'EOF'
[{"body": "- lane: babysit\n- last-cycle: 2026-07-20T06:30Z\n- flags: none"}]
EOF
OUT_SAME="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 --repo "$FIXTURE_REPO" \
  --repo-labels-json "$TMP/same-labels.json" \
  --counts-json "$TMP/same-counts.json" \
  --pr-json "$TMP/same-pr.json" \
  --decisions-json "$TMP/same-decisions.json" \
  --telemetry-json "$TMP/same-telemetry.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
for heading in "== Queues" "== Merge-ready" "== Parked"; do
  if [[ "$(section "$OUT_REST" "$heading")" == "$(section "$OUT_SAME" "$heading")" ]]; then
    pass "rest and gh paths render '$heading' byte-identically"
  else
    fail "rest and gh paths render '$heading' byte-identically" "$(section "$OUT_SAME" "$heading")" "$(section "$OUT_REST" "$heading")"
  fi
done
TEL_REST="$(section "$OUT_REST" "== Lane telemetry" | grep -v '^  source: issue')"
TEL_SAME="$(section "$OUT_SAME" "== Lane telemetry")"
if [[ "$TEL_REST" == "$TEL_SAME" ]]; then
  pass "rest and gh paths render telemetry identically past the source line"
else
  fail "rest and gh paths render telemetry identically past the source line" "$TEL_SAME" "$TEL_REST"
fi

# A pull whose mergeability GitHub has not finished computing (`mergeable: null`,
# `mergeable_state: "unknown"`) is retried once, then reported as inconclusive,
# never rendered as "not clean".
UNCOMPUTED="$TMP/rest-uncomputed"
mkdir -p "$UNCOMPUTED"
cp "$REST/"*.json "$UNCOMPUTED/"
cat >"$UNCOMPUTED/$(rest_key "$R/pulls?state=open&per_page=100").json" <<'EOF'
[{"number": 7, "title": "clean one"}, {"number": 10, "title": "still computing"}]
EOF
cat >"$UNCOMPUTED/$(rest_key "$R/pulls/10").json" <<'EOF'
{"number": 10, "title": "still computing", "html_url": "http://x/10", "draft": false, "mergeable": null, "mergeable_state": "unknown"}
EOF
OUT_UNCOMPUTED="$(MB_GH_FIXTURES="$UNCOMPUTED" MORNING_BRIEF_MERGE_STATE_RETRY_SECS=0 run_stub rest)"
assert_contains "rest: an uncomputed merge state is reported as inconclusive" "$OUT_UNCOMPUTED" "PARTIAL: merge state not yet computed by GitHub for #10"
assert_contains "rest: the computed PR beside it still renders" "$OUT_UNCOMPUTED" "#7 clean one"
assert_not_contains "rest: the uncomputed PR is never listed as merge-ready" "$OUT_UNCOMPUTED" "#10 still computing"

# The per-PR merge-state read is capped, and a capped read says so.
OUT_CAP="$(run_stub rest --pr-limit 1)"
assert_contains "rest: a capped merge-state read is reported as PARTIAL" "$OUT_CAP" "PARTIAL: 3 open PRs; merge state read for the first 1 only"
bash "$BRIEF" --pr-limit x --repo "$FIXTURE_REPO" >/dev/null 2>&1
assert_exit "non-numeric --pr-limit exits 3" 3 "$?"

# --- Summary ------------------------------------------------------------------
echo
if ((FAILED > 0)); then
  printf 'morning-brief.test.sh: %d case(s) FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'morning-brief.test.sh: all %d cases passed\n' "$CASE_NUM"
