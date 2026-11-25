#!/usr/bin/env bash

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIEF="$SCRIPT_DIR/scripts/morning-brief.sh"

have() { command -v "$1" >/dev/null 2>&1; }
if ! have jq; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi
have_gnu_date() { date -u -d "2026-01-01T00:00Z" +%s >/dev/null 2>&1; } # portability-ok: dialect probe, BSD probe below (#1510)
have_bsd_date() { date -u -j -f "%Y-%m-%dT%H:%MZ" "2026-01-01T00:00Z" +%s >/dev/null 2>&1; }
if ! have_gnu_date && ! have_bsd_date; then
  # portability-ok: names both dialects inside a skip message; neither is invoked (#1510)
  echo "SKIP: no supported date dialect (need GNU 'date -d' or BSD 'date -j -f')" >&2
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1

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
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
section() {
  printf '%s\n' "$1" | awk -v h="$2" 'index($0, h) == 1 {p = 1; print; next} /^== / {p = 0} p'
}

NOW="2026-07-20T08:00Z"
FIXTURE_REPO="example/test-repo"

printf '{}\n' >"$TMP/lanes-empty.json"

cat >"$TMP/counts.json" <<'EOF'
{"needs-triage": 28, "status: ready": 44, "needs-owner-decision": 3, "needs-human": 7}
EOF

cat >"$TMP/pr.json" <<'EOF'
[
  {"number": 12, "title": "blocked pr", "url": "http://x/12", "isDraft": false, "mergeStateStatus": "BLOCKED", "reviewDecision": ""},
  {"number": 11, "title": "draft pr", "url": "http://x/11", "isDraft": true, "mergeStateStatus": "CLEAN", "reviewDecision": ""},
  {"number": 13, "title": "approved clean pr", "url": "http://x/13", "isDraft": false, "mergeStateStatus": "CLEAN", "reviewDecision": "APPROVED",
   "baseRefName": "main", "headRefOid": "1313131313131313131313131313131313131313"},
  {"number": 10, "title": "clean pr", "url": "http://x/10", "isDraft": false, "mergeStateStatus": "CLEAN", "reviewDecision": "",
   "baseRefName": "main", "headRefOid": "1010101010101010101010101010101010101010"}
]
EOF

cat >"$TMP/behind.json" <<'EOF'
{"10": 0, "13": 4}
EOF

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

cat >"$TMP/telemetry.json" <<'EOF'
[
  {"body": "<!-- harness-ops:lane-telemetry marker=lane:babysit -->\n- lane: babysit\n- last-cycle: 2026-07-20T06:30Z\n- flags: none"},
  {"body": "<!-- harness-ops:lane-telemetry marker=lane:triage -->\n- lane: triage\n- last-cycle: 2026-07-19T06:00Z\n- flags: queue-depth climbing"},
  {"body": "<!-- harness-ops:lane-telemetry marker=lane:work -->\n- lane: work\n- last-cycle: 2026-07-20T07:XX\n- flags: -"},
  {"body": "<!-- harness-ops:lane-telemetry marker=lane:work-2 -->\n- lane: work-2\n- last-cycle: 2026-07-20T07:40Z\n- flags: gh-identity drift detected"},
  {"body": "- lane: unmarked\n- last-cycle: 2026-07-18T06:00Z\n- flags: none"},
  {"body": "Scope note: this issue is the interim telemetry surface."}
]
EOF

printf '[]\n' >"$TMP/empty.json"

printf '{}\n' >"$TMP/stuck-empty.json"
printf '{"owner": "op-user", "pages": []}\n' >"$TMP/touch-empty.json"

cat >"$TMP/stuck.json" <<'EOF'
{
  "status: ready": [{"data": {"search": {"issueCount": 3, "pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
    {"__typename": "Issue", "number": 201, "title": "old ready item", "timelineItems": {"nodes": [
      {"createdAt": "2026-06-01T08:00:00Z", "label": {"name": "status: ready"}},
      {"createdAt": "2026-07-01T08:00:00Z", "label": {"name": "status: ready"}},
      {"createdAt": "2026-07-18T08:00:00Z", "label": {"name": "needs-human"}}]}},
    {"__typename": "PullRequest", "number": 202, "title": "fresh ready pr", "timelineItems": {"nodes": [
      {"createdAt": "2026-07-18T08:00:00Z", "label": {"name": "status: ready"}}]}},
    {"__typename": "Issue", "number": 203, "title": "unknown age", "timelineItems": {"nodes": []}}
  ]}}}],
  "needs-human": [{"data": {"search": {"issueCount": 2, "pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
    {"__typename": "PullRequest", "number": 204, "title": "boundary item", "timelineItems": {"nodes": [
      {"createdAt": "2026-07-12T08:00:00Z", "label": {"name": "needs-human"}}]}},
    {"__typename": "PullRequest", "number": 205, "title": "relabeled item", "timelineItems": {"nodes": [
      {"createdAt": "2026-06-01T08:00:00Z", "label": {"name": "needs-human"}},
      {"createdAt": "2026-07-19T08:00:00Z", "label": {"name": "needs-human"}}]}}
  ]}}}],
  "needs-triage": [{"data": {"search": {"issueCount": 1, "pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
    {"__typename": "Issue", "number": 206, "title": "triage stuck", "timelineItems": {"nodes": [
      {"createdAt": "2026-07-10T08:00:00Z", "label": {"name": "needs-triage"}}]}}
  ]}}}]
}
EOF

cat >"$TMP/merged.json" <<'EOF'
[
  {"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
    {"number": 1720, "title": "feat(harness-ops): consume lane restart-requests",
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

cat >"$TMP/merged-apierror.json" <<'EOF'
[
  {"errors": [{"type": "RATE_LIMIT", "code": "graphql_rate_limit",
               "message": "API rate limit already exceeded for user ID 1."}]}
]
EOF

cat >"$TMP/merged-clean.json" <<'EOF'
[
  {"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
    {"number": 1707, "title": "all clear", "url": "https://github.com/o/r/pull/1707",
     "mergedAt": "2026-07-19T16:23:23Z", "reviewThreads": {"nodes": []}}
  ]}}}}
]
EOF

cat >"$TMP/telemetry-no-lanes.json" <<'EOF'
[
  {"body": "Scope note: this issue is the interim telemetry surface."},
  {"body": "Another housekeeping comment with no lane field."}
]
EOF

cat >"$TMP/repo-labels-alternate.json" <<'EOF'
["bug", "enhancement", "status: blocked"]
EOF

cat >"$TMP/repo-labels-partial.json" <<'EOF'
["status: ready", "needs-human", "documentation"]
EOF

printf '[]\n' >"$TMP/repo-labels-empty.json"

cat >"$TMP/billing-usage-clear.json" <<'EOF'
{"usageItems": [
  {"date": "2026-06-01T00:00:00Z", "product": "actions", "sku": "Actions Linux", "unitType": "Minutes", "quantity": 2000, "repositoryName": "app-private", "grossAmount": 15, "discountAmount": 2.66, "netAmount": 12.34},
  {"date": "2026-07-01T00:00:00Z", "product": "actions", "sku": "Actions Linux", "unitType": "Minutes", "quantity": 300, "repositoryName": "app-private", "grossAmount": 3.5, "discountAmount": 3.5, "netAmount": 0},
  {"date": "2026-07-01T00:00:00Z", "product": "actions", "sku": "Actions Windows", "unitType": "Minutes", "quantity": 100, "repositoryName": "app-private", "grossAmount": 1.2, "discountAmount": 1.2, "netAmount": 0},
  {"date": "2026-07-01T00:00:00Z", "product": "actions", "sku": "Actions Linux", "unitType": "Minutes", "quantity": 9000, "repositoryName": "lib-public", "grossAmount": 54, "discountAmount": 54, "netAmount": 0},
  {"date": "2026-07-01T00:00:00Z", "product": "actions", "sku": "Actions storage", "unitType": "GigabyteHours", "quantity": 100, "repositoryName": "app-private", "grossAmount": 0.5, "discountAmount": 0.5, "netAmount": 0},
  {"date": "2026-07-01T00:00:00Z", "product": "git_lfs", "sku": "Git LFS Storage", "unitType": "GigabyteHours", "quantity": 4, "repositoryName": "app-private", "grossAmount": 0.2, "discountAmount": 0.2, "netAmount": 0}
]}
EOF
cat >"$TMP/org-scan-clear.json" <<'EOF'
{"admins": ["owner-example"], "partial": 0, "repos": [
  {"name": "app-private", "visibility": "private", "archived": false, "collaborators": ["owner-example"],
   "workflows": [{"path": ".github/workflows/ci.yml", "text": "on:\n  pull_request:\njobs:\n  t:\n    steps:\n      - env:\n          K: ${{ secrets.EXAMPLE_CLAUDE_KEY }}\n"},
                 {"path": ".github/workflows/after.yml", "text": "on:\n  workflow_run:\n    workflows: [ci]\njobs:\n  t:\n    steps:\n      - run: echo ${{ secrets.OTHER_TOKEN }}\n"}]},
  {"name": "lib-public", "visibility": "public", "archived": false, "collaborators": [], "workflows": []},
  {"name": "old-archived", "visibility": "private", "archived": true, "collaborators": ["someone-else"],
   "workflows": [{"path": ".github/workflows/x.yml", "text": "on: pull_request_target\njobs: {t: {steps: [{run: \"${{ secrets.OLD_CLAUDE_KEY }}\"}]}}\n"}]}
]}
EOF
cat >"$TMP/billing-budgets-clear.json" <<'EOF'
{"budgets": [
  {"id": "b1", "budget_type": "ProductPricing", "budget_product_sku": "actions", "budget_amount": 0, "prevent_further_usage": true},
  {"id": "b2", "budget_type": "BundlePricing", "budget_product_sku": "ai_credits", "budget_amount": 0, "prevent_further_usage": true}
], "has_next_page": false, "total_count": 2}
EOF
cat >"$TMP/azure-clear.json" <<'EOF'
{
  "account": {"id": "00000000-0000-0000-0000-000000000001", "name": "sub-example", "state": "Enabled"},
  "budgets": {"value": [
    {"name": "budget-example", "properties": {"amount": 100.0, "category": "Cost", "timeGrain": "Monthly",
     "currentSpend": {"amount": 1.5, "unit": "USD"}, "forecastSpend": {"amount": 3.25, "unit": "USD"},
     "timePeriod": {"startDate": "2026-07-01T00:00:00Z", "endDate": "2030-01-01T00:00:00Z"}}}]},
  "scheduledActions": {"value": [{"name": "anomaly-example", "kind": "InsightAlert",
    "properties": {"status": "Enabled", "schedule": {"frequency": "Daily", "endDate": "2030-01-01T00:00:00Z"}}}]},
  "workspaces": [{"name": "log-example", "customerId": "11111111-1111-1111-1111-111111111111", "workspaceCapping": {"dailyQuotaGb": 1.0}}],
  "laUsage": {"11111111-1111-1111-1111-111111111111": [{"Day": "2026-07-10T00:00:00Z", "GB": "0.2", "TableName": "PrimaryResult"}]},
  "pricings": {"value": [{"name": "VirtualMachines", "pricingTier": "Free"}, {"name": "StorageAccounts", "pricingTier": "Free"}, {"name": "Arm", "pricingTier": "Free"}]},
  "defenderCost": {"properties": {"nextLink": null,
    "columns": [{"name": "Cost", "type": "Number"}, {"name": "ServiceName", "type": "String"}, {"name": "MeterCategory", "type": "String"}, {"name": "Currency", "type": "String"}, {"name": "UsageDate", "type": "Number"}],
    "rows": [[2.5, "Storage", "Storage", "USD", 20260719], [0, "Microsoft Defender for Cloud", "Microsoft Defender for Cloud", "USD", 20260718]]}},
  "activity": [{"operationName": {"value": "Microsoft.Storage/storageAccounts/write"}, "status": {"value": "Succeeded"}, "caller": "someone@example.invalid", "eventTimestamp": "2000-01-01T00:00:00Z"}],
  "secureScores": [{"name": "ascScore", "displayName": "ASC score", "current": 30.0, "max": 60, "percentage": 0.5}],
  "advisorSecurity": [],
  "advisorCost": []
}
EOF
CLEAR_COST_ARGS=(--billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json"
  --org-scan-json "$TMP/org-scan-clear.json" --azure-json "$TMP/azure-clear.json"
  --actions-included-minutes 3000 --actions-included-storage-gb 2 --required-budgets budget-example --anomaly-alert anomaly-example)

OUT="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --behind-json "$TMP/behind.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged.json" "${CLEAR_COST_ARGS[@]}" 2>&1)"
RC=$?

assert_exit "renders successfully" 0 "$RC"

assert_contains "queue: needs-triage count" "$OUT" "needs-triage"
assert_contains "queue: ready count 44" "$OUT" "44"

assert_contains "merge-ready keeps clean #10" "$OUT" "#10 clean pr"
assert_contains "merge-ready keeps clean #13" "$OUT" "#13 approved clean pr"
assert_contains "merge-ready shows review verdict" "$OUT" "review=APPROVED"
assert_contains "merge-ready none-review shows 'none'" "$OUT" "review=none"
assert_not_contains "merge-ready drops draft #11" "$OUT" "#11 draft pr"
assert_not_contains "merge-ready drops blocked #12" "$OUT" "#12 blocked pr"
assert_contains "merge-ready points to authoritative gate" "$OUT" "/source-control:babysit-prs"
MERGE_READY="$(section "$OUT" "== Merge-ready")"
assert_contains "merge-ready flags a clean PR behind its base as unverified" "$MERGE_READY" \
  "    http://x/13  review=APPROVED
    UNVERIFIED: head is 4 commit(s) behind main; checks may predate the current base"
assert_contains "merge-ready leaves a clean PR containing the base tip unflagged" "$MERGE_READY" \
  "    http://x/10  review=none
  #13 approved clean pr"
assert_not_contains "merge-ready reports no unread freshness when every count is known" "$MERGE_READY" "base freshness unread"

OUT_NO_BEHIND="$(bash "$BRIEF" --now "$NOW" --pr-json "$TMP/pr.json" \
  --counts-json "$TMP/counts.json" --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged.json" 2>&1)"
assert_contains "merge-ready without a behind fixture says freshness is unread" "$(section "$OUT_NO_BEHIND" "== Merge-ready")" \
  "    http://x/10  review=none
    UNVERIFIED: base freshness unread: --pr-json given without --behind-json"
printf '{"10": 0}\n' >"$TMP/behind-partial.json"
OUT_PARTIAL_BEHIND="$(bash "$BRIEF" --now "$NOW" --pr-json "$TMP/pr.json" --behind-json "$TMP/behind-partial.json" \
  --counts-json "$TMP/counts.json" --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged.json" 2>&1)"
assert_contains "merge-ready with no count for a PR says freshness is unread" "$(section "$OUT_PARTIAL_BEHIND" "== Merge-ready")" \
  "    UNVERIFIED: base freshness unread: no behind count for #13"

OUT_FRESH_CAP="$(bash "$BRIEF" --now "$NOW" --pr-json "$TMP/pr.json" --behind-json "$TMP/behind.json" --pr-limit 1 \
  --counts-json "$TMP/counts.json" --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged.json" 2>&1)"
FRESH_CAP="$(section "$OUT_FRESH_CAP" "== Merge-ready")"
assert_contains "merge-ready reads freshness for clean PRs inside the cap" "$FRESH_CAP" \
  "    http://x/10  review=none
  #13 approved clean pr"
assert_contains "merge-ready marks a clean PR past the compare cap unverified" "$FRESH_CAP" \
  "    http://x/13  review=APPROVED
    UNVERIFIED: base freshness unread: compare reads capped at 1 (raise --pr-limit)"
assert_contains "merge-ready reports a capped compare read as PARTIAL" "$FRESH_CAP" \
  "PARTIAL: 2 clean PRs; base freshness read for the first 1 only (raise --pr-limit)"

assert_contains "decision #100 uppercase marker wins" "$OUT" "Store the root in a userConfig key"
assert_not_contains "decision #100 ignores 'not recommended'" "$OUT" "not recommended for this profile"
assert_contains "decision #101 lowercase fallback" "$OUT" "keep the interim surface for now"
assert_contains "decision #102 no marker" "$OUT" "(no RECOMMENDED line found)"
assert_contains "decision #103 scans comments" "$OUT" "adopt option B"
assert_contains "decision #105 lowercase marker beats earlier 'not recommended'" "$OUT" "keep the sibling worktree layout"
assert_not_contains "decision #105 ignores 'not recommended' rejection" "$OUT" "bare-clone hub is not recommended"
assert_contains "decision #106 uppercase marker beats earlier 'NOT RECOMMENDED'" "$OUT" "choose the managed sync path"
assert_not_contains "decision #106 ignores 'NOT RECOMMENDED' rejection" "$OUT" "because of drift"

assert_contains "telemetry babysit fresh age" "$OUT" "babysit"
assert_contains "telemetry babysit not stale" "$OUT" "age=1h 30m"
assert_contains "telemetry triage stale flagged" "$OUT" "STALE (>6h)"
assert_contains "telemetry unparsable stamp handled" "$OUT" "unparsable timestamp"
assert_contains "telemetry surfaces flags" "$OUT" "gh-identity drift detected"
assert_not_contains "telemetry hides flags=none" "$OUT" "flags: none"
assert_not_contains "telemetry skips a lane comment without the sentinel" "$OUT" "unmarked"

OUT_TRUNC="$(bash "$BRIEF" --now "$NOW" --rec-maxlen 30 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/empty.json" 2>&1)"
assert_contains "long rec is truncated with ellipsis" "$OUT_TRUNC" "alpha beta gamma delta epsilon…"
assert_not_contains "long rec tail is dropped" "$OUT_TRUNC" "omicron pi"

OUT_FULL="$(bash "$BRIEF" --now "$NOW" --rec-maxlen 0 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/empty.json" 2>&1)"
assert_contains "rec-maxlen 0 keeps the full tail untruncated" "$OUT_FULL" "omicron pi"
assert_not_contains "rec-maxlen 0 never inserts an ellipsis" "$OUT_FULL" "…"

OUT_NO_LANES="$(bash "$BRIEF" --now "$NOW" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/telemetry-no-lanes.json" 2>&1)"
assert_contains "telemetry with no lane-tagged comments reports none found" "$OUT_NO_LANES" "(no per-lane comments found on the telemetry issue)"

printf 'null\n' >"$TMP/no-telemetry.json"
OUT2="$(bash "$BRIEF" --now "$NOW" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/no-telemetry.json" 2>&1)"
assert_contains "missing telemetry degrades gracefully" "$OUT2" "no telemetry issue found"

OUT_NO_QL="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" --stuck-json "$TMP/stuck-empty.json" --touch-json "$TMP/touch-empty.json" \
  --repo-labels-json "$TMP/repo-labels-alternate.json" \
  --counts-json "$TMP/empty.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json" 2>&1)"
assert_contains "no matching queue labels degrades gracefully" "$OUT_NO_QL" "no queue labels found in this repo"
assert_contains "degradation names the defaults" "$OUT_NO_QL" "pass --queue-labels to customize"
QUEUE_ONLY="$(printf '%s\n' "$OUT_NO_QL" | awk '/^== Queues/,/^== /{if (!/^== / || /^== Queues/) print}')"
assert_not_contains "absent defaults are not rendered as 0 count rows" "$QUEUE_ONLY" $'needs-triage          0'
assert_not_contains "absent defaults are not rendered as ? count rows" "$QUEUE_ONLY" $'needs-triage          ?'

OUT_PARTIAL_QL="$(bash "$BRIEF" --now "$NOW" \
  --repo-labels-json "$TMP/repo-labels-partial.json" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "partial taxonomy shows only labels that exist" "$OUT_PARTIAL_QL" "status: ready"
assert_contains "partial taxonomy keeps another existing label" "$OUT_PARTIAL_QL" "needs-human"
assert_not_contains "partial taxonomy drops absent default labels" "$OUT_PARTIAL_QL" "needs-triage"

OUT_CUSTOM_QL="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" --stuck-json "$TMP/stuck-empty.json" --touch-json "$TMP/touch-empty.json" \
  --queue-labels "bug, enhancement" \
  --repo-labels-json "$TMP/repo-labels-alternate.json" \
  --counts-json "$TMP/empty.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json" 2>&1)"
assert_contains "pinned queue labels are honored" "$OUT_CUSTOM_QL" "bug"
assert_contains "pinned queue labels include the second entry" "$OUT_CUSTOM_QL" "enhancement"

OUT_NO_DEC="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" --stuck-json "$TMP/stuck-empty.json" --touch-json "$TMP/touch-empty.json" \
  --repo-labels-json "$TMP/repo-labels-alternate.json" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json" 2>&1)"
assert_contains "missing decision label degrades gracefully" "$OUT_NO_DEC" "decision label not found in this repo"

OUT_EMPTY_LABELS="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" --stuck-json "$TMP/stuck-empty.json" --touch-json "$TMP/touch-empty.json" \
  --repo-labels-json "$TMP/repo-labels-empty.json" \
  --counts-json "$TMP/empty.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json" 2>&1)"
assert_contains "empty label inventory degrades queue section" "$OUT_EMPTY_LABELS" "no queue labels found in this repo"

OUT_EMPTY_LABELS_DEC="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" --stuck-json "$TMP/stuck-empty.json" --touch-json "$TMP/touch-empty.json" \
  --repo-labels-json "$TMP/repo-labels-empty.json" \
  --counts-json "$TMP/empty.json" \
  --pr-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json" 2>&1)"
assert_contains "empty label inventory degrades decision section" "$OUT_EMPTY_LABELS_DEC" "decision label not found in this repo"

OUT3="$(bash "$BRIEF" --now "$NOW" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" 2>&1)"
assert_contains "no clean PRs message" "$OUT3" "(none clean right now)"
assert_contains "no parked decisions message" "$OUT3" "(none parked)"

bash "$BRIEF" --help >/dev/null 2>&1
assert_exit "--help exits 0" 0 "$?"
bash "$BRIEF" --bogus >/dev/null 2>&1
assert_exit "unknown flag exits 3" 3 "$?"
bash "$BRIEF" --counts-json "$TMP/does-not-exist.json" >/dev/null 2>&1
assert_exit "missing fixture file exits 3" 3 "$?"

ERR_STALE="$(bash "$BRIEF" --stale-hours abc 2>&1)"
assert_exit "non-numeric --stale-hours exits 3" 3 "$?"
assert_contains "non-numeric --stale-hours clear message" "$ERR_STALE" "--stale-hours requires a non-negative integer"
ERR_MAXLEN="$(bash "$BRIEF" --rec-maxlen 12x 2>&1)"
assert_exit "non-numeric --rec-maxlen exits 3" 3 "$?"
assert_contains "non-numeric --rec-maxlen clear message" "$ERR_MAXLEN" "--rec-maxlen requires a non-negative integer"

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
    --telemetry-json "$TMP/telemetry.json" "${CLEAR_COST_ARGS[@]}" 2>&1)"
  RC_BSD=$?
  assert_exit "BSD fallback: renders successfully" 0 "$RC_BSD"
  assert_contains "BSD fallback: fresh age computed via date -j -f" "$OUT_BSD" "age=1h 30m"
  assert_contains "BSD fallback: stale verdict via date -j -f" "$OUT_BSD" "STALE (>6h)"
  assert_contains "BSD fallback: unparsable stamp still unparsable" "$OUT_BSD" "unparsable timestamp"
fi

assert_contains "stranded: reports the post-merge P1" "$OUT" "#1720"
assert_contains "stranded: severity survives to the operator" "$OUT" "[P1]"
assert_contains "stranded: several findings on one PR collapse to one line" "$OUT" "(2 findings)"
assert_not_contains "stranded: a collapsed PR is not softened to its lesser severity" "$OUT" "[P2] #1720"
assert_contains "stranded: names the reviewer" "$OUT" "by chatgpt-codex-connector"
assert_contains "stranded: says why it was missed" "$OUT" "merge gate could not see it"
STRANDED_ONLY="$(printf '%s\n' "$OUT" | sed -n '/stranded on merged/,/^== Landed/p')"
assert_not_contains "stranded: a thread PREDATING the merge is not stranded" "$STRANDED_ONLY" "#1707"
assert_not_contains "stranded: an already-RESOLVED post-merge thread is excluded" "$STRANDED_ONLY" "#1712"
assert_not_contains "stranded: a merge outside the window is excluded" "$OUT" "#1690"

LANDED_BLOCK="$(printf '%s\n' "$OUT" | sed -n '/^== Landed/,/^$/p')"
assert_contains "landed: the first read on a machine covers the last day" "$LANDED_BLOCK" "first read on this machine: last 1d"
assert_contains "landed: counts the PRs merged in the window" "$LANDED_BLOCK" "3 PRs merged"
assert_contains "landed: lists every PR when there are no more than the sample" "$LANDED_BLOCK" "Read these (3 of 3"
assert_contains "landed: a listed PR carries its link" "$LANDED_BLOCK" "https://github.com/o/r/pull/1707"
assert_not_contains "landed: a merge outside the window is not listed" "$LANDED_BLOCK" "#1690"
OUT_LANDED_TWO="$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --behind-json "$TMP/behind.json" --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged.json" --landed-sample 2 "${CLEAR_COST_ARGS[@]}" 2>&1)"
LANDED_TWO="$(printf '%s\n' "$OUT_LANDED_TWO" | sed -n '/^== Landed/,/^$/p')"
assert_contains "landed: the sample size is a setting" "$LANDED_TWO" "Read these (2 of 3"
assert_contains "landed: the sample takes the oldest merge" "$LANDED_TWO" "#1707"
assert_contains "landed: the sample takes the newest merge" "$LANDED_TWO" "#1720"
assert_not_contains "landed: the sample skips the one between" "$LANDED_TWO" "#1712"
assert_contains "landed: a flag setting names its layer" "$LANDED_TWO" "setting: landed_sample=2 (flag)"

STRANDED_BLOCK="$(printf '%s\n' "$OUT" | sed -n '/stranded on merged/,$p')"
FIRST_SEV="$(printf '%s\n' "$STRANDED_BLOCK" | grep -oE '^[[:space:]]+\[P[0-9]\]' | head -1 | tr -d ' ')"
assert_contains "stranded: highest severity is listed first" "$FIRST_SEV" "[P1]"

OUT_CLEAN="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "stranded: a clean window says so explicitly" "$OUT_CLEAN" "every merged PR in the window is clear"

OUT_ERR="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged-apierror.json" "${CLEAR_COST_ARGS[@]}" 2>&1)"
assert_not_contains "stranded: an API error is NEVER reported as clear" "$OUT_ERR" "every merged PR in the window is clear"
assert_contains "stranded: an API error renders the section UNREADABLE" "$OUT_ERR" "UNREADABLE: API rate limit"
assert_contains "stranded: the API error message is surfaced" "$OUT_ERR" "rate limit already exceeded"
assert_contains "stranded: the header counts the unreadable section" "$OUT_ERR" "2 of 10 sections unreadable: stranded landed"

OUT_SEV="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged-severity.json" 2>&1)"
assert_contains "severity: a P2 whose prose says P1/CRITICAL stays P2" "$OUT_SEV" "[P2] #300"
assert_not_contains "severity: prose never promotes a finding" "$OUT_SEV" "[P1] #300"
assert_not_contains "severity: the word CRITICAL in prose never promotes to P0" "$OUT_SEV" "[P0] #300"
assert_contains "severity: an unclassified thread never hides a P0" "$OUT_SEV" "[P0] #301"
assert_not_contains "severity: the unclassified marker never wins the collapse" "$OUT_SEV" "[--] #301"
assert_contains "severity: the shields badge/P0 URL form is recognized" "$OUT_SEV" "[P0] #302"

OUT_TRUNC="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged-truncated.json" 2>&1)"
assert_contains "truncation: a partial thread read is reported" "$OUT_TRUNC" "this read is PARTIAL"
assert_contains "truncation: the affected PR is named" "$OUT_TRUNC" "#400"

OUT_WIDE="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 --stranded-days 60 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged.json" 2>&1)"
assert_contains "stranded: --stranded-days widens the window" "$OUT_WIDE" "#1690"
assert_contains "stranded: the window is reported in the header" "$OUT_WIDE" "last 60d"

run_stuck() {
  bash "$BRIEF" --now "$NOW" --stale-hours 6 \
    --counts-json "$TMP/counts.json" \
    --pr-json "$TMP/pr.json" \
    --behind-json "$TMP/behind.json" \
    --decisions-json "$TMP/decisions.json" \
    --telemetry-json "$TMP/telemetry.json" \
    --merged-json "$TMP/merged-clean.json" \
    --lane-runs-json "$TMP/lanes-empty.json" "${CLEAR_COST_ARGS[@]}" \
    --stuck-json "$TMP/stuck.json" "$@" 2>&1
}
stuck_order() { printf '%s\n' "$1" | grep -oE '^  #[0-9]+' | tr -d ' \n'; }

OUT_STUCK="$(run_stuck)"
RC_STUCK=$?
STUCK_SEC="$(section "$OUT_STUCK" "== Stuck")"
assert_exit "stuck: a fully fixtured brief exits 0" 0 "$RC_STUCK"
assert_contains "stuck: the heading names the threshold" "$STUCK_SEC" "== Stuck (open items in a queue label for more than 7d) =="
assert_contains "stuck: an issue past the threshold is listed with its days in stage" "$STUCK_SEC" \
  "  #201 issue  old ready item  (status: ready, 19d in stage)"
assert_contains "stuck: a PR is listed and labeled PR" "$STUCK_SEC" "  #204 PR  boundary item  (needs-human, 8d in stage)"
assert_contains "stuck: another label's item is listed under its own label" "$STUCK_SEC" \
  "  #206 issue  triage stuck  (needs-triage, 10d in stage)"
assert_not_contains "stuck: an item under the threshold is not listed" "$STUCK_SEC" "#202"
assert_not_contains "stuck: the newest labeled event decides, not the first" "$STUCK_SEC" "#205"
assert_contains "stuck: an item with no labeled event is listed as days unknown" "$STUCK_SEC" \
  "  #203 issue  unknown age  (status: ready, days unknown)"
assert_eq "stuck: oldest first, days unknown last" "#201#206#204#203" "$(stuck_order "$STUCK_SEC")"
assert_not_contains "stuck: under the cap there is no PARTIAL" "$STUCK_SEC" "PARTIAL"

STUCK_DAYS_SEC="$(section "$(run_stuck --stuck-days 9)" "== Stuck")"
assert_contains "stuck: --stuck-days is in the heading" "$STUCK_DAYS_SEC" "for more than 9d"
assert_eq "stuck: --stuck-days raises the threshold" "#201#206#203" "$(stuck_order "$STUCK_DAYS_SEC")"

STUCK_CAP_SEC="$(section "$(run_stuck --stuck-limit 2)" "== Stuck")"
assert_eq "stuck: --stuck-limit keeps the oldest items" "#201#206" "$(stuck_order "$STUCK_CAP_SEC")"
assert_contains "stuck: past the cap the section says PARTIAL" "$STUCK_CAP_SEC" \
  "PARTIAL: 4 stuck items; showing the oldest 2 (raise --stuck-limit)"

STUCK_LABEL_SEC="$(section "$(run_stuck --queue-labels needs-human)" "== Stuck")"
assert_eq "stuck: only the shown queue labels are read" "#204" "$(stuck_order "$STUCK_LABEL_SEC")"

STUCK_NONE_SEC="$(section "$(run_stuck --stuck-json "$TMP/stuck-empty.json")" "== Stuck")"
assert_contains "stuck: no stuck item says so" "$STUCK_NONE_SEC" "(none — no open item has held a queue label for more than 7d)"

jq '.["status: ready"][0].data.search.issueCount = 1500' "$TMP/stuck.json" >"$TMP/stuck-ceiling.json"
assert_contains "stuck: a search at its ceiling is PARTIAL" "$(section "$(run_stuck --stuck-json "$TMP/stuck-ceiling.json")" "== Stuck")" \
  "PARTIAL: status: ready: the search reached its 1,000-result ceiling"

printf '{"errors": [{"message": "boom stuck"}]}\n' >"$TMP/stuck-error.json"
OUT_STUCK_ERR="$(run_stuck --stuck-json "$TMP/stuck-error.json")"
RC_STUCK_ERR=$?
assert_exit "stuck: an error document exits 6" 6 "$RC_STUCK_ERR"
assert_contains "stuck: an error document is UNREADABLE" "$(section "$OUT_STUCK_ERR" "== Stuck")" "UNREADABLE: boom stuck"
assert_contains "stuck: the header counts the unreadable section" "$OUT_STUCK_ERR" "1 of 10 sections unreadable: stuck"
printf '[]\n' >"$TMP/stuck-array.json"
assert_contains "stuck: a fixture that is not a label map is UNREADABLE" "$(section "$(run_stuck --stuck-json "$TMP/stuck-array.json")" "== Stuck")" \
  "UNREADABLE: --stuck-json is not an object"
printf '{"needs-human": [{"nodes": 1}]}\n' >"$TMP/stuck-nopage.json"
assert_contains "stuck: a response with no page document is UNREADABLE" "$(section "$(run_stuck --stuck-json "$TMP/stuck-nopage.json")" "== Stuck")" \
  "UNREADABLE: needs-human: could not parse the search pages"

assert_contains "stuck: no repo and no fixture is an empty state, not UNREADABLE" "$(section "$OUT3" "== Stuck")" "(no repo resolved — pass --repo or --stuck-json)"
bash "$BRIEF" --stuck-days x >/dev/null 2>&1
assert_exit "non-numeric --stuck-days exits 3" 3 "$?"
bash "$BRIEF" --stuck-limit x >/dev/null 2>&1
assert_exit "non-numeric --stuck-limit exits 3" 3 "$?"

cat >"$TMP/touch.json" <<'EOF'
{"owner": "Op-User", "laneIdentity": "lanes-app[bot]", "pages": [{"data": {"search": {"issueCount": 3, "pageInfo": {"hasNextPage": false}, "nodes": [
  {"__typename": "PullRequest", "number": 301,
   "acts": {"pageInfo": {"hasNextPage": false}, "nodes": [
     {"__typename": "PullRequestReview", "createdAt": "2026-07-19T10:00:00Z", "author": {"login": "op-user"}, "state": "APPROVED"},
     {"__typename": "PullRequestReview", "createdAt": "2026-07-19T10:05:00Z", "author": {"login": "someone"}, "state": "APPROVED"},
     {"__typename": "PullRequestReview", "createdAt": "2026-07-19T10:06:00Z", "author": {"login": "op-user"}, "state": "COMMENTED"},
     {"__typename": "MergedEvent", "createdAt": "2026-07-20T07:00:00Z", "actor": {"login": "op-user"}},
     {"__typename": "IssueComment", "createdAt": "2026-07-19T09:00:00Z", "author": {"login": "lanes-app"},
      "body": "<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=abc -->\n<!-- stop-reason lane=pr-unblock reason=design -->\n### pr-unblock / report-escalation\nHeld for a person: why.\nReason: `design`\n\n- Lane code: `ci-fix-round-cap`"}]},
   "labels": {"nodes": [
     {"__typename": "LabeledEvent", "createdAt": "2026-07-19T09:00:00Z", "actor": {"login": "lanes-app"}, "label": {"name": "needs-human"}},
     {"__typename": "UnlabeledEvent", "createdAt": "2026-07-19T12:30:00Z", "actor": {"login": "op-user"}, "label": {"name": "needs-human"}},
     {"__typename": "UnlabeledEvent", "createdAt": "2026-07-20T06:00:00Z", "actor": {"login": "op-user"}, "label": {"name": "do-not-merge"}}]}},
  {"__typename": "PullRequest", "number": 302,
   "acts": {"pageInfo": {"hasNextPage": false}, "nodes": [
     {"__typename": "IssueComment", "createdAt": "2026-07-19T11:00:00Z", "author": {"login": "mallory"},
      "body": "<!-- work-items:escalation lane=pr-merge kind=escalated -->\nspoof"},
     {"__typename": "IssueComment", "createdAt": "2026-07-18T23:00:00Z", "author": {"login": "lanes-app"},
      "body": "<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-risk -->\nold"},
     {"__typename": "IssueComment", "createdAt": "2026-07-20T01:00:00Z", "author": {"login": "lanes-app"},
      "body": "<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-risk -->\nUnattended merge risk."}]},
   "labels": {"nodes": [
     {"__typename": "LabeledEvent", "createdAt": "2026-07-17T08:00:00Z", "actor": {"login": "lanes-app"}, "label": {"name": "needs-human"}},
     {"__typename": "UnlabeledEvent", "createdAt": "2026-07-20T02:00:00Z", "actor": {"login": "other-person"}, "label": {"name": "needs-human"}},
     {"__typename": "UnlabeledEvent", "createdAt": "2026-07-20T03:00:00Z", "actor": {"login": "other-person"}, "label": {"name": "do-not-merge"}}]}},
  {"__typename": "Issue", "number": 303,
   "acts": {"pageInfo": {"hasNextPage": true}, "nodes": [
     {"__typename": "IssueComment", "createdAt": "2026-07-20T03:00:00Z", "author": {"login": "lanes-app"},
      "body": "<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\n<!-- work-resolve-issue outcome=pushback run=5 -->\nPushed back."},
     {"__typename": "IssueComment", "createdAt": "2026-07-19T05:00:00Z", "author": {"login": "lanes-app"},
      "body": "<!-- work-items:escalation lane=work-loop kind=ratify-c3 -->\nRatify?"}]},
   "labels": {"nodes": [
     {"__typename": "UnlabeledEvent", "createdAt": "2026-07-19T20:00:00Z", "actor": {"login": "op-user"}, "label": {"name": "needs-human"}}]}}
]}}}]}
EOF

run_touch() {
  bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/empty.json" \
    --decisions-json "$TMP/empty.json" --telemetry-json "$TMP/empty.json" "${CLEAR_COST_ARGS[@]}" \
    --touch-json "$TMP/touch.json" "$@" 2>&1
}
OUT_TOUCH="$(run_touch)"
TOUCH_SEC="$(section "$OUT_TOUCH" "== Owner touches")"
assert_contains "touches: the heading names the window" "$TOUCH_SEC" "== Owner touches (last 2 UTC days) =="
assert_contains "touches: the operator and the trusted escalation authors are named" "$TOUCH_SEC" \
  "  operator: op-user; escalations trusted from: lanes-app, op-user"
assert_contains "touches: the first day's row" "$TOUCH_SEC" \
  "  2026-07-19          1        0        0        1        2        2                     2"
assert_contains "touches: the second day's row" "$TOUCH_SEC" \
  "  2026-07-20          0        1        1        0        1        2                     0"
assert_contains "touches: hold waits pair each lift with its apply event" "$TOUCH_SEC" \
  "  hold waits (needs-human applied to lifted): n=2, median 3h 30m, max 2d 18h, 1 with no apply event read"
assert_contains "touches: an escalation reason from the Lane code line" "$TOUCH_SEC" "       1  pr-unblock escalated ci-fix-round-cap"
assert_contains "touches: an escalation reason from the pr-merge marker" "$TOUCH_SEC" "       1  pr-merge escalated risk"
assert_contains "touches: an escalation reason from the outcome marker" "$TOUCH_SEC" "       1  work-resolve-issue escalated pushback"
assert_contains "touches: a marker with no reason" "$TOUCH_SEC" "       1  work-loop ratify-c3 unspecified"
assert_not_contains "touches: an untrusted author's marker does not count" "$TOUCH_SEC" "pr-merge escalated unspecified"
assert_contains "touches: items ranked by operator actions and escalations" "$TOUCH_SEC" \
  $'    #301 PR  approve 1, dnm-lift 1, escalate 1, hold-off 1, merge 1\n    #303 issue  escalate 2, hold-off 1\n    #302 PR  escalate 1'
assert_contains "touches: an item past the event cap is PARTIAL" "$TOUCH_SEC" "  PARTIAL: more than 100 events in the window on #303"
assert_contains "touches: the login caveat is printed" "$TOUCH_SEC" "including any agent session that holds it"

TOUCH_ONE_SEC="$(section "$(run_touch --touch-days 1)" "== Owner touches")"
assert_contains "touches: --touch-days sets the window" "$TOUCH_ONE_SEC" "(last 1 UTC days)"
assert_not_contains "touches: a day before the window has no row" "$TOUCH_ONE_SEC" "2026-07-19"
assert_contains "touches: an event before the window is not counted" "$TOUCH_ONE_SEC" \
  "  2026-07-20          0        1        1        0        1        2                     0"
assert_contains "touches: a hold lifted in the window counts its wait from before it" "$TOUCH_ONE_SEC" "n=1, median 2d 18h, max 2d 18h"

assert_contains "touches: --owner-login beats the fixture's owner" \
  "$(section "$(run_touch --owner-login other-person)" "== Owner touches")" \
  "  2026-07-20          0        0        1        0        1        2                     1"
assert_contains "touches: --hold-label picks the hold label" \
  "$(section "$(run_touch --hold-label do-not-merge)" "== Owner touches")" "n=0, 2 with no apply event read"
assert_contains "touches: a quiet window says so" \
  "$(section "$(run_touch --touch-json "$TMP/touch-empty.json")" "== Owner touches")" "  escalations: none in the window"

cat >"$TMP/touch-labelcap.json" <<'EOF'
{"owner": "op-user", "pages": [{"data": {"search": {"issueCount": 3, "pageInfo": {"hasNextPage": false}, "nodes": [
  {"__typename": "Issue", "number": 304, "acts": {"pageInfo": {"hasNextPage": false}, "nodes": []},
   "labels": {"pageInfo": {"hasPreviousPage": true}, "nodes": [
     {"__typename": "LabeledEvent", "createdAt": "2026-07-19T01:00:00Z", "actor": {"login": "x"}, "label": {"name": "triage"}}]}},
  {"__typename": "Issue", "number": 305, "acts": {"pageInfo": {"hasNextPage": false}, "nodes": []},
   "labels": {"pageInfo": {"hasPreviousPage": true}, "nodes": [
     {"__typename": "LabeledEvent", "createdAt": "2026-07-18T23:00:00Z", "actor": {"login": "x"}, "label": {"name": "triage"}},
     {"__typename": "LabeledEvent", "createdAt": "2026-07-19T01:00:00Z", "actor": {"login": "x"}, "label": {"name": "triage"}}]}},
  {"__typename": "Issue", "number": 306, "acts": {"pageInfo": {"hasNextPage": false}, "nodes": []},
   "labels": {"pageInfo": {"hasPreviousPage": false}, "nodes": [
     {"__typename": "LabeledEvent", "createdAt": "2026-07-19T01:00:00Z", "actor": {"login": "x"}, "label": {"name": "triage"}}]}}
]}}}]}
EOF
TOUCH_LABELCAP_SEC="$(section "$(run_touch --touch-json "$TMP/touch-labelcap.json")" "== Owner touches")"
assert_contains "touches: a label history cut off inside the window is PARTIAL" "$TOUCH_LABELCAP_SEC" \
  "  PARTIAL: more than 100 events in the window on #304"
assert_not_contains "touches: a label history cut off before the window is complete" "$TOUCH_LABELCAP_SEC" "#305"
assert_not_contains "touches: a label history with nothing before it is complete" "$TOUCH_LABELCAP_SEC" "#306"

printf '{"pages": []}\n' >"$TMP/touch-noowner.json"
assert_contains "touches: no operator login is UNREADABLE" \
  "$(section "$(run_touch --touch-json "$TMP/touch-noowner.json")" "== Owner touches")" "UNREADABLE: no operator login (pass --owner-login)"
printf '{"errors": [{"message": "boom touches"}]}\n' >"$TMP/touch-error.json"
OUT_TOUCH_ERR="$(run_touch --touch-json "$TMP/touch-error.json")"
assert_exit "touches: an error document exits 6" 6 "$?"
assert_contains "touches: the header counts the unreadable section" "$OUT_TOUCH_ERR" "1 of 10 sections unreadable: touches"
assert_contains "touches: no repo and no fixture is an empty state" "$(section "$OUT3" "== Owner touches")" \
  "(no repo resolved — pass --repo or --touch-json)"
bash "$BRIEF" --touch-days 0 >/dev/null 2>&1
assert_exit "touches: --touch-days 0 exits 3" 3 "$?"

cat >"$TMP/touch-merged.json" <<'EOF'
{"owner": "op-user", "laneIdentity": "lanes-app[bot]", "pages": [{"data": {"search": {"issueCount": 7, "pageInfo": {"hasNextPage": false}, "nodes": [
  {"__typename": "PullRequest", "number": 311, "createdAt": "2026-07-19T01:00:00Z", "mergedAt": "2026-07-20T05:00:00Z",
   "touch": {"pageInfo": {"hasNextPage": false}, "nodes": [
     {"__typename": "PullRequestCommit", "commit": {"author": {"email": "1+lanes-app[bot]@users.noreply.github.com", "user": null}}},
     {"__typename": "IssueComment", "createdAt": "2026-07-19T02:00:00Z", "author": {"__typename": "Bot", "login": "review-app"}},
     {"__typename": "PullRequestReview", "createdAt": "2026-07-19T03:00:00Z", "author": {"__typename": "User", "login": "lanes-app"}},
     {"__typename": "IssueComment", "createdAt": "2026-07-20T06:00:00Z", "author": {"__typename": "User", "login": "someone"}}]}},
  {"__typename": "PullRequest", "number": 312, "createdAt": "2026-07-19T01:00:00Z", "mergedAt": "2026-07-19T05:00:00Z",
   "touch": {"pageInfo": {"hasNextPage": false}, "nodes": [
     {"__typename": "PullRequestCommit", "commit": {"author": {"email": "dev@example.com", "user": {"login": "dev-person"}}}}]}},
  {"__typename": "PullRequest", "number": 313, "createdAt": "2026-07-19T01:00:00Z", "mergedAt": "2026-07-19T06:00:00Z",
   "touch": {"pageInfo": {"hasNextPage": false}, "nodes": [
     {"__typename": "PullRequestReview", "createdAt": "2026-07-19T02:00:00Z", "author": {"__typename": "User", "login": "op-user"}}]}},
  {"__typename": "PullRequest", "number": 314, "createdAt": "2026-07-19T01:00:00Z", "mergedAt": "2026-07-19T07:00:00Z",
   "touch": {"pageInfo": {"hasNextPage": false}, "nodes": [
     {"__typename": "IssueComment", "createdAt": "2026-07-19T02:00:00Z", "author": {"__typename": "User", "login": "someone"}}]}},
  {"__typename": "PullRequest", "number": 315, "createdAt": "2026-07-17T01:00:00Z", "mergedAt": "2026-07-18T05:00:00Z",
   "touch": {"pageInfo": {"hasNextPage": false}, "nodes": []}},
  {"__typename": "PullRequest", "number": 316, "createdAt": "2026-07-19T01:00:00Z", "mergedAt": null,
   "touch": {"pageInfo": {"hasNextPage": false}, "nodes": []}},
  {"__typename": "PullRequest", "number": 317, "createdAt": "2026-07-19T01:00:00Z", "mergedAt": "2026-07-19T08:00:00Z",
   "touch": {"pageInfo": {"hasNextPage": true}, "nodes": []}}
]}}}]}
EOF
TOUCH_MERGED_SEC="$(section "$(run_touch --touch-json "$TMP/touch-merged.json")" "== Owner touches")"
assert_contains "touches: merges no person touched, of those merged in the window" "$TOUCH_MERGED_SEC" \
  "  merged with no human touch: 2 of 5 pull requests merged in the window (40%)"
assert_contains "touches: an untouched merge past the timeline cap is PARTIAL" "$TOUCH_MERGED_SEC" \
  "  PARTIAL: more than 100 commits, reviews and comments on #317"
assert_contains "touches: how a touch is counted is printed" "$TOUCH_MERGED_SEC" \
  "  note: a touch is a commit on the pull request, or a review or comment from its open to its merge, by a person"
for touch_case in "312 commit" "313 review" "314 comment"; do
  jq --argjson n "${touch_case%% *}" '.pages[0].data.search.nodes |= map(select(.number == 311 or .number == $n))' \
    "$TMP/touch-merged.json" >"$TMP/touch-merged-one.json"
  assert_contains "touches: a person's ${touch_case#* } is a touch" \
    "$(section "$(run_touch --touch-json "$TMP/touch-merged-one.json")" "== Owner touches")" \
    "  merged with no human touch: 1 of 2 pull requests merged in the window (50%)"
done
assert_contains "touches: --touch-days narrows the merges counted" \
  "$(section "$(run_touch --touch-json "$TMP/touch-merged.json" --touch-days 1)" "== Owner touches")" \
  "  merged with no human touch: 1 of 1 pull requests merged in the window (100%)"
assert_contains "touches: no merge in the window says so" "$TOUCH_SEC" \
  "  merged with no human touch: no pull request merged in the window"

GH_STUB_DIR="$TMP/gh-stub"
mkdir -p "$GH_STUB_DIR"
cat >"$GH_STUB_DIR/gh" <<'STUB'
#!/usr/bin/env bash
mode="${MB_GH_MODE:?MB_GH_MODE not set}"
blocked() {
  printf '{"message":"GitHub GraphQL is not available from Claude Code sessions. Use REST via `gh api repos/{owner}/{repo}/...` instead.","documentation_url":"https://example.invalid/docs"}\n'
  printf 'gh: GitHub GraphQL is not available from Claude Code sessions. (HTTP 403)\n' >&2
  exit 1
}
case "$mode" in
  blocked) blocked ;;
  fail)
    printf 'gh: boom, the upstream fell over (HTTP 500)\n' >&2
    exit 1
    ;;
  forbidden)
    printf '{"message":"Must have admin rights to the organization.","documentation_url":"https://example.invalid/docs","status":"403"}\n'
    printf 'gh: Must have admin rights to the organization. (HTTP 403)\n' >&2
    exit 1
    ;;
  rest)
    [[ "${1:-}" == "api" ]] || blocked
    shift
    path=""
    for a in "$@"; do
      [[ "$a" == repos/* || "$a" == orgs/* ]] && path="$a"
    done
    [[ -n "$path" ]] || blocked
    key="$(printf '%s' "$path" | sed -E 's/[^A-Za-z0-9._-]/_/g')"
    f="${MB_GH_FIXTURES:?MB_GH_FIXTURES not set}/$key.json"
    if [[ -f "$f" ]]; then
      cat "$f"
      exit 0
    fi
    if [[ -f "${f%.json}.err" ]]; then
      cat "${f%.json}.err" >&2
      exit 1
    fi
    printf '{"message":"Not Found","documentation_url":"https://example.invalid/docs"}\n'
    printf 'gh: Not Found (HTTP 404) — no fixture %s\n' "$key" >&2
    exit 1
    ;;
  gql)
    san() { printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]/_/g'; }
    serve() {
      local f="${MB_GH_FIXTURES:?MB_GH_FIXTURES not set}/$1.json"
      [[ -n "${MB_GH_LOG:-}" ]] && printf '%s\n' "$1" >>"$MB_GH_LOG"
      [[ -f "$f" ]] || {
        printf 'gh: no fixture %s (HTTP 404)\n' "$1" >&2
        exit 1
      }
      cat "$f"
    }
    if [[ "$1" == api && "$2" != graphql ]]; then
      for a in "$@"; do
        [[ "$a" == repos/* ]] && { serve "$(san "$a")"; exit 0; }
      done
    fi
    cmd="$1 $2"
    shift 2
    limit="" q="" label="" search=0 cursor="first" num="" paginate=0 squery=""
    while (($#)); do
      case "$1" in
        --limit) limit="$2"; shift ;;
        -q) q="$2"; shift ;;
        --label) label="$2"; shift ;;
        --search) search=1; shift ;;
        -f | -F)
          [[ "$2" == endCursor=* ]] && cursor="${2#endCursor=}"
          [[ "$2" == search=* ]] && squery="${2#search=}"
          shift
          ;;
        --json | --repo | --state) shift ;;
        --paginate) paginate=1 ;;
        *) num="$1" ;;
      esac
      shift
    done
    case "$cmd" in
      "api graphql")
        if [[ "$squery" == *" updated:"* ]]; then
          # The owner-touch section's per-day search: one page per call, keyed
          # by the day the updated: range starts on and the cursor.
          day="${squery#* updated:}"
          page="$(serve "api-graphql-touch-${day:0:10}-$(san "$cursor")")" || exit 1
          printf '%s\n' "$page"
          exit 0
        fi
        if [[ -n "$squery" ]]; then
          # The stuck section's label search: one page per call, keyed by the
          # label inside `label:"..."` and the cursor.
          lbl="${squery#*label:\"}"
          lbl="${lbl%\"}"
          page="$(serve "api-graphql-stuck-$(san "$lbl")-$(san "$cursor")")" || exit 1
          printf '%s\n' "$page"
          exit 0
        fi
        while :; do
          page="$(serve "api-graphql-$(san "$cursor")")" || exit 1
          printf '%s\n' "$page"
          ((paginate)) || exit 0
          cursor="$(jq -r 'if .data.repository.pullRequests.pageInfo.hasNextPage then .data.repository.pullRequests.pageInfo.endCursor else "" end' <<<"$page")"
          [[ -n "$cursor" ]] || exit 0
        done
        ;;
      "label list") key="label-list" ;;
      "pr list") key="pr-list" ;;
      "issue list")
        key="issue-list"
        [[ -n "$label" ]] && key="$key-label-$(san "$label")"
        ((search)) && key="$key-search"
        ;;
      "issue view") key="issue-view-$num" ;;
      *) key="$(san "$cmd")" ;;
    esac
    [[ "$cmd" == *" list" ]] && limit="${limit:-30}"
    body="$(serve "$key")" || exit 1
    [[ -n "$limit" ]] && body="$(jq --argjson n "$limit" 'if type == "array" then .[:$n] else . end' <<<"$body")"
    if [[ -n "$q" ]]; then jq -r "$q" <<<"$body"; else printf '%s\n' "$body"; fi
    ;;
  *)
    printf 'gh stub: unknown MB_GH_MODE %s\n' "$mode" >&2
    exit 2
    ;;
esac
STUB
chmod +x "$GH_STUB_DIR/gh"

cat >"$GH_STUB_DIR/az" <<'STUB'
#!/usr/bin/env bash
# The real az reads whatever its stdin holds; drain what is waiting, as it does.
while IFS= read -r -t 0.05 _; do :; done
[[ -n "${MB_AZ_LOG:-}" ]] && printf '%s\n' "$*" >>"$MB_AZ_LOG"
if [[ "${MB_AZ_MODE:-logged-out}" != serve ]]; then
  printf "ERROR: Please run 'az login' to setup account.\n" >&2
  exit 1
fi
case "$1 $2 $3" in
  "account show"*) key=account ;;
  "rest --method get")
    key=""
    [[ "$*" == *"/Microsoft.Consumption/budgets?"* ]] && key=budgets
    [[ "$*" == *"/Microsoft.CostManagement/scheduledActions?"* ]] && key=scheduledActions
    ;;
  "security pricing list") key=pricings ;;
  "rest --method post")
    # A next page of the cost query names its page in $skiptoken: key defenderCost_<n>.
    key=defenderCost
    if [[ "$*" == *'$skiptoken='* ]]; then
      token="$*"
      token="${token##*\$skiptoken=}"
      key="defenderCost_${token%% *}"
    fi
    ;;
  "monitor log-analytics workspace") key=workspaces ;;
  "monitor log-analytics query") key="laUsage/$5" ;;
  "monitor activity-log list") key=activity ;;
  "security secure-scores list") key=secureScores ;;
  "advisor recommendation list")
    key=""
    [[ " $* " == *" --category Security "* ]] && key=advisorSecurity
    [[ " $* " == *" --category Cost "* ]] && key=advisorCost
    ;;
  *) key="" ;;
esac
if [[ -z "$key" ]] || ! jq -e --arg k "$key" 'getpath($k | split("/")) != null' "${MB_AZ_FIXTURE:?MB_AZ_FIXTURE not set}" >/dev/null; then
  printf 'ERROR: (NotFound) az stub has no answer for: %s\n' "$*" >&2
  exit 1
fi
if jq -e --arg k "$key" 'getpath($k | split("/")) | objects | has("__error")' "$MB_AZ_FIXTURE" >/dev/null; then
  printf 'ERROR: %s\n' "$(jq -r --arg k "$key" 'getpath($k | split("/")).__error' "$MB_AZ_FIXTURE")" >&2
  exit 1
fi
jq --arg k "$key" 'getpath($k | split("/"))' "$MB_AZ_FIXTURE"
STUB
chmod +x "$GH_STUB_DIR/az"

COST_ARGS=("${CLEAR_COST_ARGS[@]}")

run_stub() {
  local mode="$1" stuck=() data=(--data-dir "${MB_DATA_DIR:-$TMP/data}")
  shift
  [[ -n "${MB_NO_DATA_DIR:-}" ]] && data=()
  [[ "$mode" == gql && -z "${MB_STUCK_LIVE:-}" ]] && stuck=(--stuck-json "$TMP/stuck-empty.json")
  [[ "$mode" == gql && -z "${MB_TOUCH_LIVE:-}" ]] && stuck+=(--touch-json "$TMP/touch-empty.json")
  PATH="$GH_STUB_DIR:$PATH" MB_GH_MODE="$mode" MB_GH_FIXTURES="${MB_GH_FIXTURES:-$TMP/rest}" \
    bash "$BRIEF" --now "$NOW" --stale-hours 6 --repo "$FIXTURE_REPO" ${data[@]+"${data[@]}"} \
    "${COST_ARGS[@]}" ${stuck[@]+"${stuck[@]}"} "$@" 2>&1
}

COST_ARGS=()
OUT_BLOCKED="$(run_stub blocked)"
RC_BLOCKED=$?
OUT_FAIL="$(run_stub fail)"
RC_FAIL=$?
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_exit "blocked: every live section unreadable exits 5" 5 "$RC_BLOCKED"
assert_contains "blocked: header counts every section" "$OUT_BLOCKED" "10 of 10 sections unreadable"
assert_contains "blocked: stuck is UNREADABLE" "$(section "$OUT_BLOCKED" "== Stuck")" "UNREADABLE:"
assert_not_contains "blocked: stuck never renders an all-clear" "$OUT_BLOCKED" "no open item has held a queue label"
COST_BLOCKED="$(section "$OUT_BLOCKED" "== Cost")"
assert_contains "blocked: the billing usage read is UNREADABLE" "$COST_BLOCKED" "UNREADABLE GitHub usage 2026-07: GitHub GraphQL is not available"
assert_contains "blocked: the billing budgets read is UNREADABLE" "$COST_BLOCKED" "UNREADABLE GitHub budgets: GitHub GraphQL is not available"
assert_not_contains "blocked: the proxy's 403 is never read as a missing org admin" "$COST_BLOCKED" "org admin needed"
assert_contains "blocked: a logged-out az makes the Azure lines UNREADABLE, naming az login" "$COST_BLOCKED" \
  "UNREADABLE Azure budgets: Please run 'az login' to setup account."
assert_contains "blocked: lanes are UNREADABLE" "$(section "$OUT_BLOCKED" "== Lanes")" "UNREADABLE:"
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
assert_contains "blocked: the refusal is surfaced verbatim" "$OUT_BLOCKED" "GraphQL is not available from Claude Code sessions"

assert_exit "fail: every live section unreadable exits 5" 5 "$RC_FAIL"
assert_contains "fail: the error is surfaced" "$OUT_FAIL" "UNREADABLE: boom, the upstream fell over"
assert_not_contains "fail: no REST transport claimed for an unrelated error" "$OUT_FAIL" "transport: REST"

OUT_ONE="$(run_stub blocked \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --stuck-json "$TMP/stuck-empty.json" --touch-json "$TMP/touch-empty.json" \
  --lane-runs-json "$TMP/lanes-empty.json")"
RC_ONE=$?
assert_exit "partial: one unreadable section among fixtures exits 6" 6 "$RC_ONE"
assert_contains "partial: header names the lost section" "$OUT_ONE" "2 of 10 sections unreadable: stranded landed"
assert_contains "partial: the fixture sections still render" "$OUT_ONE" "#10 clean pr"

cat >"$TMP/merged-message-error.json" <<'EOF'
{"message":"GitHub GraphQL is not available from Claude Code sessions.","documentation_url":"https://example.invalid/docs"}
EOF
OUT_MSG="$(bash "$BRIEF" --now "$NOW" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged-message-error.json" 2>&1)"
assert_not_contains "message-shaped error: never an all-clear" "$OUT_MSG" "every merged PR in the window is clear"
assert_contains "message-shaped error: renders UNREADABLE" "$OUT_MSG" "UNREADABLE: GitHub GraphQL is not available"

if have git; then
  CHECKOUT="$TMP/checkout"
  mkdir -p "$CHECKOUT"
  git -C "$CHECKOUT" init -q 2>/dev/null
  git -C "$CHECKOUT" remote add origin "https://github.com/$FIXTURE_REPO.git"
  OUT_REMOTE="$(cd "$CHECKOUT" && PATH="$GH_STUB_DIR:$PATH" MB_GH_MODE=blocked \
    bash "$BRIEF" --now "$NOW" \
    --counts-json "$TMP/counts.json" \
    --pr-json "$TMP/pr.json" \
    --decisions-json "$TMP/decisions.json" \
    --stuck-json "$TMP/stuck-empty.json" 2>&1)"
  RC_REMOTE=$?
  assert_exit "git remote fallback: renders (exit 6, five of nine unreadable)" 6 "$RC_REMOTE"
  assert_contains "git remote fallback: owner/repo taken from origin" "$OUT_REMOTE" "Morning brief — $FIXTURE_REPO —"
  assert_contains "git remote fallback: the header names the source" "$OUT_REMOTE" "repo resolved from the git origin remote"
  assert_contains "git remote fallback: live sections still degrade honestly" "$OUT_REMOTE" "6 of 10 sections unreadable: telemetry stranded landed lanes touches cost"
fi

REST="$TMP/rest"
mkdir -p "$REST"
rest_key() { printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]/_/g'; }
R="repos/$FIXTURE_REPO"
cat >"$REST/$(rest_key "$R/labels?per_page=100").json" <<'EOF'
[{"name": "status: ready"}, {"name": "needs-human"}, {"name": "needs-owner-decision"}]
EOF
cat >"$REST/$(rest_key "$R/issues?state=open&per_page=100&labels=status%3A%20ready").json" <<'EOF'
[{"number": 1, "title": "a"}, {"number": 2, "title": "b"}, {"number": 3, "title": "pr", "pull_request": {"url": "x"}}]
EOF
cat >"$REST/$(rest_key "$R/issues?state=open&per_page=100&labels=needs-human").json" <<'EOF'
[{"number": 4, "title": "c"}]
EOF
cat >"$REST/$(rest_key "$R/issues?state=open&per_page=100&labels=needs-owner-decision").json" <<'EOF'
[{"number": 42, "title": "pick a store", "html_url": "http://x/i/42", "body": "Options weighed.\nRECOMMENDED: option B."}]
EOF
cat >"$REST/$(rest_key "$R/issues/42/comments?per_page=100").json" <<'EOF'
[{"body": "no change of lean"}]
EOF
cat >"$REST/$(rest_key "$R/pulls?state=open&per_page=100").json" <<'EOF'
[{"number": 9, "title": "blocked one"}, {"number": 8, "title": "draft one"}, {"number": 7, "title": "clean one"}]
EOF
cat >"$REST/$(rest_key "$R/pulls/7").json" <<'EOF'
{"number": 7, "title": "clean one", "html_url": "http://x/7", "draft": false, "mergeable": true, "mergeable_state": "clean",
 "base": {"ref": "release/1.x"}, "head": {"sha": "7777777777777777777777777777777777777777"}}
EOF
cat >"$REST/$(rest_key "$R/compare/release%2F1.x...7777777777777777777777777777777777777777?per_page=1").json" <<'EOF'
{"status": "diverged", "ahead_by": 1, "behind_by": 2}
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
[{"body": "<!-- harness-ops:lane-telemetry marker=lane:babysit -->\n- lane: babysit\n- last-cycle: 2026-07-20T06:30Z\n- flags: none"}]
EOF
cat >"$REST/$(rest_key "$R/actions/workflows?per_page=100").json" <<'EOF'
{"total_count": 4, "workflows": [{"path": ".github/workflows/intake-triage.yml"}, {"path": ".github/workflows/ci.yml"}, {"path": ".github/workflows/pr-unblock.yml"}, {"path": ".github/workflows/pr-review-main.yml"}]}
EOF
cat >"$REST/$(rest_key "$R/actions/workflows/pr-review-main.yml/runs?created=>=2026-07-13&per_page=100").json" <<'EOF'
{"total_count": 2, "workflow_runs": [{"id": 99, "html_url": "http://x/runs/99", "event": "push", "display_title": "main", "head_sha": "p1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T00:00:00Z"}]}
EOF
printf '%s\n' '{"total_count": 1, "workflow_runs": []}' \
  >"$REST/$(rest_key "$R/actions/workflows/pr-review-main.yml/runs?created=2026-07-18&per_page=100").json"
for d in 13 14 15 16 17 20; do
  printf '%s\n' '{"total_count": 0, "workflow_runs": []}' \
    >"$REST/$(rest_key "$R/actions/workflows/pr-review-main.yml/runs?created=2026-07-$d&per_page=100").json"
done
cat >"$REST/$(rest_key "$R/actions/workflows/pr-review-main.yml/runs?created=2026-07-19&per_page=100").json" <<'EOF'
{"total_count": 2, "workflow_runs": [{"id": 99, "html_url": "http://x/runs/99", "event": "push", "display_title": "main", "head_sha": "p1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T00:00:00Z"}, {"id": 98, "html_url": "http://x/runs/98", "event": "push", "display_title": "main", "head_sha": "p0", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T00:00:00Z"}]}
EOF
cat >"$REST/$(rest_key "$R/actions/runs/98/jobs?per_page=100").json" <<'EOF'
{"total_count": 0, "jobs": []}
EOF
cat >"$REST/$(rest_key "$R/actions/runs/99/jobs?per_page=100").json" <<'EOF'
{"total_count": 1, "jobs": [{"id": 990, "name": "Review Handoffs"}]}
EOF
cat >"$REST/$(rest_key "$R/check-runs/990/annotations?per_page=100").json" <<'EOF'
[]
EOF
cat >"$REST/$(rest_key "$R/actions/workflows/pr-unblock.yml/runs?created=>=2026-07-13&per_page=100").json" <<'EOF'
{"total_count": 1, "workflow_runs": [{"id": 88, "html_url": "http://x/runs/88", "event": "pull_request", "display_title": "PR R", "head_sha": "r1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T00:00:00Z"}]}
EOF
cat >"$REST/$(rest_key "$R/actions/runs/88/jobs?per_page=100").json" <<'EOF'
{"total_count": 2, "jobs": [{"id": 881, "name": "Publish Feedback / Run"}, {"id": 880, "name": "Resolve Conflicts / Run"}]}
EOF
cat >"$REST/$(rest_key "$R/check-runs/881/annotations?per_page=100").json" <<'EOF'
[]
EOF
cat >"$REST/$(rest_key "$R/check-runs/880/annotations?per_page=100").json" <<'EOF'
[{"message": "pr-unblock completed. lane-outcome {\"v\":1,\"lane\":\"resolve-conflicts\",\"outcome\":\"success\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"turns\":7,\"maxTurns\":40,\"models\":[\"claude-sonnet-5\"]} Findings (if any) are in the PR comments."}]
EOF
cat >"$REST/$(rest_key "$R/actions/workflows/intake-triage.yml/runs?created=>=2026-07-13&per_page=100").json" <<'EOF'
{"total_count": 1, "workflow_runs": [{"id": 77, "html_url": "http://x/runs/77", "event": "issues", "display_title": "Issue R", "head_sha": "m1", "status": "completed", "conclusion": "failure", "created_at": "2026-07-19T00:00:00Z"}]}
EOF
cat >"$REST/$(rest_key "$R/actions/runs/77/jobs?per_page=100").json" <<'EOF'
{"total_count": 1, "jobs": [{"id": 770}]}
EOF
cat >"$REST/$(rest_key "$R/check-runs/770/annotations?per_page=100").json" <<'EOF'
[{"message": "Process completed with exit code 1."}, {"message": "intake-triage exited with: failure. lane-outcome {\"v\":1,\"lane\":\"intake-triage\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"rate-limit\"}"}]
EOF
printf 'jobs:\n  t:\n    steps:\n      - uses: anthropics/claude-code-action@v1\n' \
  >"$REST/$(rest_key "$R/contents/.github/workflows/intake-triage.yml").json"
printf 'jobs:\n  t:\n    steps:\n      - uses: "anthropics/claude-code-action@v1"\n' \
  >"$REST/$(rest_key "$R/contents/.github/workflows/pr-review-main.yml").json"
printf 'jobs:\n  t:\n    steps:\n      - uses: anthropics/claude-code-base-action@0123abc\n' \
  >"$REST/$(rest_key "$R/contents/.github/workflows/pr-unblock.yml").json"
printf 'jobs:\n  t:\n    steps:\n      - run: make test\n' >"$REST/$(rest_key "$R/contents/.github/workflows/ci.yml").json"

OUT_REST="$(run_stub rest)"
RC_REST=$?
assert_contains "rest: lanes read live, keeping only lane workflows that exist" "$(section "$OUT_REST" "== Lanes")" \
  "intake-triage.yml  runs=1  failed=1 [rate-limit 1, max-turns 0, auth 0, other 0]  limit-stops=1  restarts=0"
assert_contains "rest: a day its own search still cut short marks the Lanes section PARTIAL" "$(section "$OUT_REST" "== Lanes")" \
  "PARTIAL: 1 runs not listed: a lane passed the runs search's result cap in one day"
assert_contains "rest: pr-review-main.yml is a default lane workflow, its capped week re-read by day" "$(section "$OUT_REST" "== Lanes")" \
  "pr-review-main.yml  runs=2  failed=0 [rate-limit 0, max-turns 0, auth 0, other 0]  limit-stops=0  restarts=0"
assert_contains "rest: the activity comes from the caller job of the job that carries the record" "$(section "$OUT_REST" "== Lanes")" \
  "    pr-unblock / resolve-conflicts  profile=unknown  runs=1  pass=1/1  median-turns=7  max-turns-hits=0  models=claude-sonnet-5"
assert_exit "rest: renders with the stranded section unreadable (exit 6)" 6 "$RC_REST"
assert_contains "rest: the header names the transport" "$OUT_REST" "transport: REST"
assert_contains "rest: queue count excludes pull requests" "$(section "$OUT_REST" "== Queues")" "status: ready            2"
assert_contains "rest: queue count for the second label" "$(section "$OUT_REST" "== Queues")" "needs-human              1"
assert_not_contains "rest: absent default labels are not rendered" "$(section "$OUT_REST" "== Queues")" "needs-triage"
assert_contains "rest: merge-ready keeps the clean non-draft" "$OUT_REST" "#7 clean one"
assert_not_contains "rest: merge-ready drops the draft" "$OUT_REST" "#8 draft one"
assert_not_contains "rest: merge-ready drops the blocked" "$OUT_REST" "#9 blocked one"
assert_contains "rest: review decision is reported as n/a" "$OUT_REST" "review=n/a"
assert_contains "rest: the compare read flags the clean PR behind its base" "$OUT_REST" \
  "UNVERIFIED: head is 2 commit(s) behind release/1.x; checks may predate the current base"
assert_contains "rest: decision RECOMMENDED line is extracted" "$OUT_REST" "RECOMMENDED: option B."
assert_contains "rest: telemetry issue found by title" "$OUT_REST" "source: issue #50"
assert_contains "rest: telemetry lane age computed" "$OUT_REST" "babysit    last-cycle=2026-07-20T06:30Z UTC  age=1h 30m"
assert_contains "rest: stranded is UNREADABLE, never clear" "$(section "$OUT_REST" "== Findings stranded")" "UNREADABLE: review threads need GraphQL"
assert_contains "rest: stuck is UNREADABLE, never empty" "$(section "$OUT_REST" "== Stuck")" "UNREADABLE: label events need GraphQL"
assert_contains "rest: header counts the four lost sections" "$OUT_REST" "4 of 10 sections unreadable: stuck stranded landed touches"

mkdir -p "$TMP/cfg-lanes" "$TMP/cfg-no-lanes"
cat >"$TMP/cfg-lanes/work-items.yaml" <<'EOF'
morning_brief:
  lane_workflows:
    - intake-triage.yml
    - absent-lane.yml
  lane_outcome_contract_ref:
    - "https://example.invalid/lane-outcome.md#fields"
    - docs/lane-record.md
EOF
LANES_CFG="$(section "$(run_stub rest --config-home "$TMP/cfg-lanes")" "== Lanes")"
assert_contains "lane_workflows: a configured file the repo has is read" "$LANES_CFG" "intake-triage.yml  runs=1"
assert_not_contains "lane_workflows: a file the list leaves out is not read" "$LANES_CFG" "pr-review-main.yml  runs="
assert_not_contains "lane_workflows: a configured file the repo lacks is dropped" "$LANES_CFG" "absent-lane.yml"
assert_contains "lane_outcome_contract_ref: each pointer prints under the heading, the anchor kept" "$LANES_CFG" \
  "lane-outcome record contract: https://example.invalid/lane-outcome.md#fields docs/lane-record.md"
LANES_DEFAULT="$(section "$(run_stub rest --config-home "$TMP/cfg-no-lanes")" "== Lanes")"
assert_contains "lane_workflows unset: a workflow using claude-code-action is a lane" "$LANES_DEFAULT" "intake-triage.yml  runs=1"
assert_contains "lane_workflows unset: a workflow using claude-code-base-action is a lane" "$LANES_DEFAULT" "pr-unblock.yml  runs=1"
assert_not_contains "lane_workflows unset: a workflow with no Claude action is not a lane" "$LANES_DEFAULT" "ci.yml"
assert_not_contains "lane_outcome_contract_ref unset: no contract line" "$LANES_DEFAULT" "lane-outcome record contract:"
cp -R "$REST" "$TMP/rest-err-wf"
rm -f "$TMP/rest-err-wf/$(rest_key "$R/contents/.github/workflows/ci.yml").json"
printf 'gh: boom, the upstream fell over (HTTP 500)\n' >"$TMP/rest-err-wf/$(rest_key "$R/contents/.github/workflows/ci.yml").err"
LANES_ERR_WF="$(section "$(MB_GH_FIXTURES="$TMP/rest-err-wf" run_stub rest --config-home "$TMP/cfg-no-lanes")" "== Lanes")"
assert_contains "lane_workflows unset: a workflow file read that fails is UNREADABLE" "$LANES_ERR_WF" "UNREADABLE: workflow .github/workflows/ci.yml"
assert_not_contains "lane_workflows unset: a failed workflow file read is never 'none found'" "$LANES_ERR_WF" "no lane workflows found"
cp -R "$REST" "$TMP/rest-gone-wf"
rm -f "$TMP/rest-gone-wf/$(rest_key "$R/contents/.github/workflows/ci.yml").json"
cat >"$TMP/rest-gone-wf/$(rest_key "$R/actions/workflows?per_page=100").json" <<'EOF'
{"total_count": 5, "workflows": [{"path": ".github/workflows/intake-triage.yml", "state": "active"}, {"path": ".github/workflows/old.yml", "state": "deleted"}, {"path": ".github/workflows/ci.yml", "state": "active"}, {"path": ".github/workflows/pr-unblock.yml", "state": "active"}, {"path": ".github/workflows/pr-review-main.yml", "state": "active"}]}
EOF
LANES_GONE_WF="$(section "$(MB_GH_FIXTURES="$TMP/rest-gone-wf" run_stub rest --config-home "$TMP/cfg-no-lanes")" "== Lanes")"
assert_not_contains "lane_workflows unset: a workflow file that answers 404 is not UNREADABLE" "$LANES_GONE_WF" "UNREADABLE"
assert_contains "lane_workflows unset: lanes are still read past a 404 and a deleted workflow" "$LANES_GONE_WF" "intake-triage.yml  runs=1"
assert_contains "lane_workflows unset: a lane listed after the 404 is read" "$LANES_GONE_WF" "pr-unblock.yml  runs=1"
assert_not_contains "lane_workflows unset: a deleted workflow is not a lane" "$LANES_GONE_WF" "old.yml"

cat >"$TMP/same-counts.json" <<'EOF'
{"status: ready": 2, "needs-human": 1, "needs-owner-decision": 1}
EOF
cat >"$TMP/same-labels.json" <<'EOF'
["status: ready", "needs-human", "needs-owner-decision"]
EOF
cat >"$TMP/same-pr.json" <<'EOF'
[
  {"number": 9, "title": "blocked one", "url": "http://x/9", "isDraft": false, "mergeStateStatus": "BLOCKED", "reviewDecision": "n/a"},
  {"number": 8, "title": "draft one", "url": "http://x/8", "isDraft": true, "mergeStateStatus": "CLEAN", "reviewDecision": "n/a"},
  {"number": 7, "title": "clean one", "url": "http://x/7", "isDraft": false, "mergeStateStatus": "CLEAN", "reviewDecision": "n/a",
   "baseRefName": "release/1.x", "headRefOid": "7777777777777777777777777777777777777777"}
]
EOF
printf '{"7": 2}\n' >"$TMP/same-behind.json"
cat >"$TMP/same-decisions.json" <<'EOF'
[{"number": 42, "title": "pick a store", "url": "http://x/i/42", "body": "Options weighed.\nRECOMMENDED: option B.", "comments": [{"body": "no change of lean"}]}]
EOF
cat >"$TMP/same-telemetry.json" <<'EOF'
[{"body": "<!-- harness-ops:lane-telemetry marker=lane:babysit -->\n- lane: babysit\n- last-cycle: 2026-07-20T06:30Z\n- flags: none"}]
EOF
OUT_SAME="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 --repo "$FIXTURE_REPO" \
  --stuck-json "$TMP/stuck-empty.json" --touch-json "$TMP/touch-empty.json" \
  --repo-labels-json "$TMP/same-labels.json" \
  --counts-json "$TMP/same-counts.json" \
  --pr-json "$TMP/same-pr.json" \
  --behind-json "$TMP/same-behind.json" \
  --decisions-json "$TMP/same-decisions.json" \
  --telemetry-json "$TMP/same-telemetry.json" \
  --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json" 2>&1)"
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

NO_COMPARE="$TMP/rest-no-compare"
mkdir -p "$NO_COMPARE"
cp "$REST/"*.json "$NO_COMPARE/"
rm "$NO_COMPARE/$(rest_key "$R/compare/release%2F1.x...7777777777777777777777777777777777777777?per_page=1").json"
OUT_NO_COMPARE="$(MB_GH_FIXTURES="$NO_COMPARE" run_stub rest)"
assert_contains "rest: a failed compare read flags the clean PR unverified" "$(section "$OUT_NO_COMPARE" "== Merge-ready")" \
  "    http://x/7  review=n/a
    UNVERIFIED: base freshness unread: Not Found"

OUT_CAP="$(run_stub rest --pr-limit 1)"
assert_contains "rest: a capped merge-state read is reported as PARTIAL" "$OUT_CAP" "PARTIAL: 3 open PRs; merge state read for the first 1 only"
bash "$BRIEF" --pr-limit x --repo "$FIXTURE_REPO" >/dev/null 2>&1
assert_exit "non-numeric --pr-limit exits 3" 3 "$?"

printf 'not json\n' >"$TMP/garbage.json"
OUT_BAD="$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/garbage.json" --decisions-json "$TMP/garbage.json" \
  --telemetry-json "$TMP/garbage.json" --merged-json "$TMP/garbage.json" "${CLEAR_COST_ARGS[@]}" 2>&1)"
RC_BAD=$?
assert_exit "unparsable: a brief with unreadable sections exits 6" 6 "$RC_BAD"
assert_contains "unparsable: the header counts the five lost sections" "$OUT_BAD" "5 of 10 sections unreadable: merge-ready decisions telemetry stranded landed"
assert_contains "unparsable: merge-ready is UNREADABLE" "$(section "$OUT_BAD" "== Merge-ready")" "UNREADABLE: could not parse the PR list"
assert_not_contains "unparsable: merge-ready never renders as none clean" "$OUT_BAD" "(none clean right now)"
assert_contains "unparsable: decisions are UNREADABLE" "$(section "$OUT_BAD" "== Parked")" "UNREADABLE: could not parse the decision issues"
assert_not_contains "unparsable: decisions never render as none parked" "$OUT_BAD" "(none parked)"
assert_contains "unparsable: telemetry is UNREADABLE" "$(section "$OUT_BAD" "== Lane telemetry")" "UNREADABLE: could not parse the telemetry comments"
assert_not_contains "unparsable: telemetry never renders as no lanes" "$OUT_BAD" "(no per-lane comments found"
assert_contains "unparsable: stranded is UNREADABLE" "$(section "$OUT_BAD" "== Findings stranded")" "UNREADABLE: could not parse the merged-PR pages"
assert_not_contains "unparsable: stranded never renders an all-clear" "$OUT_BAD" "every merged PR in the window is clear"

OUT_NO_PAGE="$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --behind-json "$TMP/behind.json" --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/empty.json" 2>&1)"
assert_contains "no page: stranded is UNREADABLE" "$(section "$OUT_NO_PAGE" "== Findings stranded")" "UNREADABLE: could not parse the merged-PR pages"
assert_not_contains "no page: stranded never renders an all-clear" "$OUT_NO_PAGE" "every merged PR in the window is clear"

CAPS="$TMP/gql-caps"
mkdir -p "$CAPS"
jq -n '[range(501) | {name: "label-\(.)"}]' >"$CAPS/label-list.json"
printf '[{"number": 1}]\n' >"$CAPS/issue-list-label-needs-triage.json"
jq -n '[range(1001) | {number: .}]' >"$CAPS/issue-list-label-status__ready.json"
printf '[]\n' >"$CAPS/issue-list-label-needs-human.json"
printf '[]\n' >"$CAPS/$(rest_key "$R/issues?state=open&per_page=100&labels=needs-human").json"
jq -n '[range(201) | {number: (. + 1), title: "decision \(.)", url: "http://x/d", body: "RECOMMENDED: go", comments: []}]' \
  >"$CAPS/issue-list-label-needs-owner-decision.json"
jq -n '[range(201) | {number: (. + 1), title: "pr \(.)", url: "http://x/p", isDraft: true, mergeStateStatus: "BLOCKED", reviewDecision: ""}]' \
  >"$CAPS/pr-list.json"
jq -n '[range(150) | {number: (. + 1000)}]' >"$CAPS/issue-list-search.json"
cat >"$CAPS/issue-view-1000.json" <<'EOF'
{"comments": [{"body": "<!-- harness-ops:lane-telemetry marker=lane:babysit -->\n- lane: babysit\n- last-cycle: 2026-07-20T06:30Z\n- flags: none"}]}
EOF
OUT_CAPS="$(MB_GH_FIXTURES="$CAPS" run_stub gql --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json")"
RC_CAPS=$?
assert_exit "caps: a capped but readable brief exits 0" 0 "$RC_CAPS"
QUEUES_CAPS="$(section "$OUT_CAPS" "== Queues")"
assert_contains "caps: a label inventory at its cap is PARTIAL" "$QUEUES_CAPS" "PARTIAL: the label inventory reached its 500-label cap"
assert_contains "caps: a capped inventory does not drop a configured label" "$QUEUES_CAPS" "needs-human              0"
assert_contains "caps: a count at its cap is shown as a floor" "$QUEUES_CAPS" "status: ready            1000+"
assert_contains "caps: a count at its cap is PARTIAL" "$QUEUES_CAPS" "PARTIAL: status: ready: count reached the 1000-issue read cap"
assert_not_contains "caps: a count under its cap is not flagged" "$QUEUES_CAPS" "needs-triage: count reached"
assert_contains "caps: an open-PR list at its cap is PARTIAL" "$(section "$OUT_CAPS" "== Merge-ready")" "PARTIAL: the open-PR list reached its 200-PR read cap"
assert_contains "caps: a decision list at its cap is PARTIAL" "$(section "$OUT_CAPS" "== Parked")" "PARTIAL: the decision list reached its 200-issue read cap"
TEL_CAPS="$(section "$OUT_CAPS" "== Lane telemetry")"
assert_contains "caps: a telemetry search at its cap is PARTIAL" "$TEL_CAPS" "PARTIAL: the telemetry issue search reached its 100-issue cap"
assert_contains "caps: the telemetry search still picks the oldest match it read" "$TEL_CAPS" "source: issue #1000"
assert_not_contains "caps: a search 0 the REST listing confirms is not flagged" "$QUEUES_CAPS" "count unavailable"

FALSE0="$TMP/gql-false-zero"
cp -r "$CAPS" "$FALSE0"
printf '[{"number": 9}]\n' >"$FALSE0/$(rest_key "$R/issues?state=open&per_page=100&labels=needs-human").json"
QUEUES_FALSE0="$(section "$(MB_GH_FIXTURES="$FALSE0" run_stub gql --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json")" "== Queues")"
assert_contains "false zero: a search 0 against a REST count above 0 is count unavailable" "$QUEUES_FALSE0" \
  "needs-human              count unavailable"
assert_contains "false zero: the section says why" "$QUEUES_FALSE0" \
  "PARTIAL: needs-human: count unavailable: the search read 0 and the REST issue listing did not confirm it"
rm "$FALSE0/$(rest_key "$R/issues?state=open&per_page=100&labels=needs-human").json"
assert_contains "false zero: a REST check that fails is count unavailable too" \
  "$(section "$(MB_GH_FIXTURES="$FALSE0" run_stub gql --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json")" "== Queues")" \
  "needs-human              count unavailable"

# --- A split parent with open sub-issues is not counted beside its children ---
# https://github.com/melodic-software/claude-code-plugins/issues/17859
PARENTS="$TMP/gql-parents"
cp -r "$CAPS" "$PARENTS"
cat >"$PARENTS/issue-list-label-needs-triage.json" <<'EOF'
[{"number": 10, "subIssuesSummary": {"total": 2, "completed": 0, "percentCompleted": 0}},
 {"number": 11, "subIssuesSummary": {"total": 0, "completed": 0, "percentCompleted": 0}},
 {"number": 12, "subIssuesSummary": {"total": 0, "completed": 0, "percentCompleted": 0}}]
EOF
QUEUES_PARENTS="$(section "$(MB_GH_FIXTURES="$PARENTS" run_stub gql --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json")" "== Queues")"
assert_contains "parents: one parent and two open children count 2, the parent listed beside them" "$QUEUES_PARENTS" \
  "$(printf '  %-24s %s' needs-triage '2 (+1 with open sub-issues)')"
assert_not_contains "parents: the parent is not in the count" "$QUEUES_PARENTS" "$(printf '  %-24s %s' needs-triage 3)"
jq '.[1:] + [{"number": 13, "subIssuesSummary": {"total": 1, "completed": 1, "percentCompleted": 100}}]' \
  "$PARENTS/issue-list-label-needs-triage.json" >"$PARENTS/finished.json"
mv "$PARENTS/finished.json" "$PARENTS/issue-list-label-needs-triage.json"
assert_contains "parents: a parent whose sub-issues are all completed counts as an open item" \
  "$(section "$(MB_GH_FIXTURES="$PARENTS" run_stub gql --merged-json "$TMP/merged-clean.json" --lane-runs-json "$TMP/lanes-empty.json")" "== Queues")" \
  "$(printf '  %-24s %s' needs-triage 3)"
# Over REST the summary is the snake_case sub_issues_summary field.
# https://docs.github.com/en/rest/issues/issues#list-repository-issues
REST_PARENTS="$TMP/rest-parents"
cp -R "$REST" "$REST_PARENTS"
cat >"$REST_PARENTS/$(rest_key "$R/issues?state=open&per_page=100&labels=needs-human").json" <<'EOF'
[{"number": 20, "title": "parent", "sub_issues_summary": {"total": 2, "completed": 0, "percent_completed": 0}},
 {"number": 21, "title": "child a", "sub_issues_summary": {"total": 0, "completed": 0, "percent_completed": 0}},
 {"number": 22, "title": "child b"}]
EOF
QUEUES_REST_PARENTS="$(section "$(MB_GH_FIXTURES="$REST_PARENTS" run_stub rest)" "== Queues")"
assert_contains "parents rest: one parent and two open children count 2, the parent listed beside them" "$QUEUES_REST_PARENTS" \
  "$(printf '  %-24s %s' needs-human '2 (+1 with open sub-issues)')"
assert_not_contains "parents rest: the parent is not in the count" "$QUEUES_REST_PARENTS" "$(printf '  %-24s %s' needs-human 3)"

STR="$TMP/gql-stranded"
mkdir -p "$STR"
cat >"$STR/api-graphql-first.json" <<'EOF'
{"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": true, "endCursor": "c1"}, "nodes": [
  {"number": 500, "title": "recent merge", "url": "https://github.com/o/r/pull/500",
   "mergedAt": "2026-07-19T10:00:00Z", "updatedAt": "2026-07-19T11:00:00Z",
   "reviewThreads": {"pageInfo": {"hasNextPage": false}, "nodes": [
     {"isResolved": false, "comments": {"nodes": [{"createdAt": "2026-07-19T10:30:00Z", "author": {"login": "bot"}, "body": "![P1 Badge](x) late finding"}]}}]}}
]}}}}
EOF
cat >"$STR/api-graphql-c1.json" <<'EOF'
{"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": true, "endCursor": "c2"}, "nodes": [
  {"number": 501, "title": "merge inside the bookmark", "url": "https://github.com/o/r/pull/501",
   "mergedAt": "2026-07-14T10:00:00Z", "updatedAt": "2026-07-14T12:00:00Z",
   "reviewThreads": {"pageInfo": {"hasNextPage": false}, "nodes": [
     {"isResolved": false, "comments": {"nodes": [{"createdAt": "2026-07-14T11:00:00Z", "author": {"login": "bot"}, "body": "![P2 Badge](x) older finding"}]}}]}},
  {"number": 502, "title": "merge before the bookmark", "url": "https://github.com/o/r/pull/502",
   "mergedAt": "2026-07-08T10:00:00Z", "updatedAt": "2026-07-08T10:00:00Z",
   "reviewThreads": {"pageInfo": {"hasNextPage": false}, "nodes": [
     {"isResolved": false, "comments": {"nodes": [{"createdAt": "2026-07-08T10:00:01Z", "author": {"login": "bot"}, "body": "![P1 Badge](x) too old"}]}}]}}
]}}}}
EOF
cat >"$STR/api-graphql-c2.json" <<'EOF'
{"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
  {"number": 503, "title": "never read", "url": "https://github.com/o/r/pull/503",
   "mergedAt": "2026-07-01T10:00:00Z", "updatedAt": "2026-07-01T10:00:00Z", "reviewThreads": {"nodes": []}}
]}}}}
EOF
FIX_ARGS=(--counts-json "$TMP/counts.json" --pr-json "$TMP/empty.json" --decisions-json "$TMP/empty.json" --telemetry-json "$TMP/empty.json" --lane-runs-json "$TMP/lanes-empty.json")
bookmark_of() { cat "$1/morning-brief/$FIXTURE_REPO/stranded-cutoff" 2>/dev/null; }

OUT_PAGE="$(MB_GH_FIXTURES="$STR" MB_GH_LOG="$TMP/log-page" MB_DATA_DIR="$TMP/data-page" run_stub gql "${FIX_ARGS[@]}")"
RC_PAGE=$?
STR_PAGE="$(section "$OUT_PAGE" "== Findings stranded")"
assert_exit "paging: a full read exits 0" 0 "$RC_PAGE"
assert_contains "paging: the page past the first is read" "$(cat "$TMP/log-page")" "api-graphql-c1"
assert_not_contains "paging: no page past the cutoff is requested" "$(cat "$TMP/log-page")" "api-graphql-c2"
assert_contains "paging: the header prints the window bounds" "$STR_PAGE" "merged since 2026-07-17T08:00Z UTC: last 3d"
assert_contains "paging: a merge inside the floor is reported" "$STR_PAGE" "[P1] #500"
assert_not_contains "paging: a merge before the floor is not reported" "$STR_PAGE" "#501"
assert_eq "bookmark: a full read saves this run's floor" "2026-07-17T08:00Z" "$(bookmark_of "$TMP/data-page")"

REALHOME_BIN="$TMP/realhome-bin"
mkdir -p "$REALHOME_BIN"
for tool in jq python3; do
  tool_path="$(command -v "$tool")" || continue
  printf '#!/usr/bin/env bash\nHOME=%q exec %q "$@"\n' "$HOME" "$tool_path" >"$REALHOME_BIN/$tool"
  chmod +x "$REALHOME_BIN/$tool"
done
MB_NO_DATA_DIR=1 CLAUDE_PLUGIN_DATA="$TMP/plugdata/work-items-mkt" HOME="$TMP/home-seg" PATH="$REALHOME_BIN:$PATH" \
  MB_GH_FIXTURES="$STR" run_stub gql "${FIX_ARGS[@]}" >/dev/null
assert_eq "data-dir fallback: a work-items CLAUDE_PLUGIN_DATA holds the bookmark" "2026-07-17T08:00Z" \
  "$(bookmark_of "$TMP/plugdata/work-items-mkt")"
MB_NO_DATA_DIR=1 CLAUDE_PLUGIN_DATA="$TMP/plugdata/harness-ops" HOME="$TMP/home-fb" PATH="$REALHOME_BIN:$PATH" \
  MB_GH_FIXTURES="$STR" run_stub gql "${FIX_ARGS[@]}" >/dev/null
assert_eq "data-dir fallback: a harness-ops CLAUDE_PLUGIN_DATA falls back to the home work-items dir" "2026-07-17T08:00Z" \
  "$(bookmark_of "$TMP/home-fb/.claude/plugins/data/work-items")"
assert_eq "data-dir fallback: no harness-ops data dir is written" "absent" \
  "$([[ -e "$TMP/plugdata/harness-ops" || -e "$TMP/home-fb/.claude/plugins/data/harness-ops" ]] && echo present || echo absent)"

mkdir -p "$TMP/data-mark/morning-brief/$FIXTURE_REPO"
printf '2026-07-10T08:00Z\n' >"$TMP/data-mark/morning-brief/$FIXTURE_REPO/stranded-cutoff"
OUT_MARK="$(MB_GH_FIXTURES="$STR" MB_GH_LOG="$TMP/log-mark" MB_DATA_DIR="$TMP/data-mark" run_stub gql "${FIX_ARGS[@]}")"
STR_MARK="$(section "$OUT_MARK" "== Findings stranded")"
assert_contains "bookmark: an older bookmark widens the window" "$STR_MARK" "merged since 2026-07-10T08:00Z UTC"
assert_contains "bookmark: a merge after the bookmark is reported" "$STR_MARK" "[P2] #501"
assert_not_contains "bookmark: a merge before the bookmark is not reported" "$STR_MARK" "#502"
assert_not_contains "bookmark: paging still stops at the cutoff" "$(cat "$TMP/log-mark")" "api-graphql-c2"
assert_eq "bookmark: a full read advances it to this run's floor" "2026-07-17T08:00Z" "$(bookmark_of "$TMP/data-mark")"

landed_of() { cat "$1/morning-brief/$FIXTURE_REPO/landed-at" 2>/dev/null; }
LANDED_PAGE="$(section "$OUT_PAGE" "== Landed")"
assert_contains "landed live: a first read covers the last day" "$LANDED_PAGE" "#500"
assert_not_contains "landed live: a merge before the last day is not listed" "$LANDED_PAGE" "#501"
assert_eq "landed live: the stranded pages are reused when they reach back far enough" "1" \
  "$(grep -c 'api-graphql-first' "$TMP/log-page")"
assert_eq "landed live: a full read saves landed_at as this run's clock" "2026-07-20T08:00Z" "$(landed_of "$TMP/data-page")"
mkdir -p "$TMP/data-landed/morning-brief/$FIXTURE_REPO"
printf '2026-07-10T08:00Z\n' >"$TMP/data-landed/morning-brief/$FIXTURE_REPO/landed-at"
OUT_LANDED="$(MB_GH_FIXTURES="$STR" MB_GH_LOG="$TMP/log-landed" MB_DATA_DIR="$TMP/data-landed" run_stub gql "${FIX_ARGS[@]}")"
LANDED_MARK="$(section "$OUT_LANDED" "== Landed")"
assert_contains "landed live: the window starts at landed_at" "$LANDED_MARK" "merged since 2026-07-10T08:00Z UTC: since landed_at"
assert_contains "landed live: a merge after landed_at is listed" "$LANDED_MARK" "#501"
assert_not_contains "landed live: a merge before landed_at is not listed" "$LANDED_MARK" "#502"
assert_eq "landed live: an older landed_at reads the pages again" "2" "$(grep -c 'api-graphql-first' "$TMP/log-landed")"
assert_eq "landed live: a full read advances landed_at" "2026-07-20T08:00Z" "$(landed_of "$TMP/data-landed")"

mkdir -p "$TMP/gql-none" "$TMP/data-fail/morning-brief/$FIXTURE_REPO"
printf '2026-07-10T08:00Z\n' >"$TMP/data-fail/morning-brief/$FIXTURE_REPO/stranded-cutoff"
OUT_MARK_FAIL="$(MB_GH_FIXTURES="$TMP/gql-none" MB_DATA_DIR="$TMP/data-fail" run_stub gql "${FIX_ARGS[@]}")"
assert_contains "bookmark: a failed read renders UNREADABLE" "$(section "$OUT_MARK_FAIL" "== Findings stranded")" "UNREADABLE:"
assert_eq "bookmark: a failed read leaves it where it was" "2026-07-10T08:00Z" "$(bookmark_of "$TMP/data-fail")"
printf '2026-07-10T08:00Z\n' >"$TMP/data-fail/morning-brief/$FIXTURE_REPO/landed-at"
OUT_LANDED_FAIL="$(MB_GH_FIXTURES="$TMP/gql-none" MB_DATA_DIR="$TMP/data-fail" run_stub gql "${FIX_ARGS[@]}")"
assert_contains "landed live: a failed read renders UNREADABLE" "$(section "$OUT_LANDED_FAIL" "== Landed")" "UNREADABLE:"
assert_eq "landed live: a failed read leaves landed_at where it was" "2026-07-10T08:00Z" "$(landed_of "$TMP/data-fail")"

mkdir -p "$TMP/gql-trunc" "$TMP/data-trunc/morning-brief/$FIXTURE_REPO"
jq '.[0] | .data.repository.pullRequests.nodes[0].updatedAt = "2026-07-19T17:00:00Z"' "$TMP/merged-truncated.json" >"$TMP/gql-trunc/api-graphql-first.json"
printf '2026-07-10T08:00Z\n' >"$TMP/data-trunc/morning-brief/$FIXTURE_REPO/stranded-cutoff"
OUT_MARK_TRUNC="$(MB_GH_FIXTURES="$TMP/gql-trunc" MB_DATA_DIR="$TMP/data-trunc" run_stub gql "${FIX_ARGS[@]}")"
assert_contains "bookmark: a partial thread read says it was not advanced" "$OUT_MARK_TRUNC" "bookmark not advanced: this read is PARTIAL"
assert_eq "bookmark: a partial thread read leaves it where it was" "2026-07-10T08:00Z" "$(bookmark_of "$TMP/data-trunc")"

mkdir -p "$TMP/data-garbage/morning-brief/$FIXTURE_REPO"
printf 'not a date\n' >"$TMP/data-garbage/morning-brief/$FIXTURE_REPO/stranded-cutoff"
OUT_GARBAGE="$(MB_GH_FIXTURES="$STR" MB_DATA_DIR="$TMP/data-garbage" run_stub gql "${FIX_ARGS[@]}")"
assert_contains "bookmark: an unparsable bookmark is named and ignored" "$(section "$OUT_GARBAGE" "== Findings stranded")" "bookmark unparsable, ignored"
assert_eq "bookmark: a full read replaces an unparsable bookmark" "2026-07-17T08:00Z" "$(bookmark_of "$TMP/data-garbage")"

printf 'a file, not a dir\n' >"$TMP/data-is-file"
OUT_NOSAVE="$(MB_GH_FIXTURES="$STR" MB_DATA_DIR="$TMP/data-is-file" run_stub gql "${FIX_ARGS[@]}")"
assert_contains "bookmark: a data dir it cannot write says so" "$(section "$OUT_NOSAVE" "== Findings stranded")" "bookmark not saved under the data dir"

mkdir -p "$TMP/rel-cwd"
OUT_REL="$(cd "$TMP/rel-cwd" && MB_GH_FIXTURES="$STR" MB_DATA_DIR="rel-data" run_stub gql "${FIX_ARGS[@]}")"
RC_REL=$?
assert_exit "data-dir: a relative path is refused with exit 3" 3 "$RC_REL"
assert_contains "data-dir: a relative path names the rule" "$OUT_REL" "--data-dir must be an absolute path"
assert_eq "data-dir: a relative path writes nothing" "" "$(ls -A "$TMP/rel-cwd")"
OUT_DOTDOT="$(MB_GH_FIXTURES="$STR" MB_DATA_DIR="$TMP/dd/../escaped" run_stub gql "${FIX_ARGS[@]}")"
RC_DOTDOT=$?
assert_exit "data-dir: a .. segment is refused with exit 3" 3 "$RC_DOTDOT"
assert_contains "data-dir: a .. segment names the rule" "$OUT_DOTDOT" "no .. segment"
assert_eq "data-dir: a .. segment writes nothing" "no" "$([[ -e "$TMP/escaped" || -e "$TMP/dd" ]] && echo yes || echo no)"
MB_GH_FIXTURES="$STR" MB_DATA_DIR="$TMP/abs/data..dir" run_stub gql "${FIX_ARGS[@]}" >/dev/null
RC_ABS=$?
assert_exit "data-dir: an absolute path (.. inside a name) is accepted" 0 "$RC_ABS"
assert_eq "data-dir: an absolute path still saves the bookmark" "2026-07-17T08:00Z" "$(bookmark_of "$TMP/abs/data..dir")"
mkdir -p "$TMP/data-link/morning-brief/$FIXTURE_REPO"
printf 'untouched\n' >"$TMP/link-target"
ln -s "$TMP/link-target" "$TMP/data-link/morning-brief/$FIXTURE_REPO/stranded-cutoff"
OUT_LINK="$(MB_GH_FIXTURES="$STR" MB_DATA_DIR="$TMP/data-link" run_stub gql "${FIX_ARGS[@]}")"
assert_contains "bookmark: a symlinked bookmark is not saved" "$(section "$OUT_LINK" "== Findings stranded")" "bookmark not saved under the data dir"
assert_eq "bookmark: a symlinked bookmark's target is untouched" "untouched" "$(cat "$TMP/link-target")"

mkdir -p "$TMP/gql-nocursor" "$TMP/data-nocursor/morning-brief/$FIXTURE_REPO"
jq '.data.repository.pullRequests.pageInfo.endCursor = null' "$STR/api-graphql-first.json" >"$TMP/gql-nocursor/api-graphql-first.json"
printf '2026-07-10T08:00Z\n' >"$TMP/data-nocursor/morning-brief/$FIXTURE_REPO/stranded-cutoff"
OUT_NOCURSOR="$(MB_GH_FIXTURES="$TMP/gql-nocursor" MB_DATA_DIR="$TMP/data-nocursor" run_stub gql "${FIX_ARGS[@]}")"
STR_NOCURSOR="$(section "$OUT_NOCURSOR" "== Findings stranded")"
assert_contains "paging: a next page without a cursor is UNREADABLE" "$STR_NOCURSOR" "UNREADABLE: a merged-PR page reported more results but no cursor to them"
assert_not_contains "paging: a next page without a cursor never reads as clear" "$STR_NOCURSOR" "every merged PR in the window is clear"
assert_eq "paging: a next page without a cursor leaves the bookmark" "2026-07-10T08:00Z" "$(bookmark_of "$TMP/data-nocursor")"

STK="$TMP/gql-stuck"
mkdir -p "$STK"
cat >"$STK/api-graphql-stuck-status__ready-first.json" <<'EOF'
{"data": {"search": {"issueCount": 2, "pageInfo": {"hasNextPage": true, "endCursor": "p2"}, "nodes": [
  {"__typename": "Issue", "number": 301, "title": "live ready item", "timelineItems": {"nodes": [
    {"createdAt": "2026-07-05T08:00:00Z", "label": {"name": "status: ready"}}]}}
]}}}
EOF
cat >"$STK/api-graphql-stuck-status__ready-p2.json" <<'EOF'
{"data": {"search": {"issueCount": 2, "pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
  {"__typename": "PullRequest", "number": 302, "title": "second page pr", "timelineItems": {"nodes": [
    {"createdAt": "2026-07-10T08:00:00Z", "label": {"name": "status: ready"}}]}}
]}}}
EOF
for stk_label in needs-triage needs-owner-decision needs-human; do
  cat >"$STK/api-graphql-stuck-$stk_label-first.json" <<'EOF'
{"data": {"search": {"issueCount": 0, "pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": []}}}
EOF
done
for stk_label in needs-triage needs-owner-decision needs-human; do
  printf '[]\n' >"$STK/$(rest_key "$R/issues?state=open&per_page=100&labels=$stk_label").json"
done
OUT_STUCK_LIVE="$(MB_STUCK_LIVE=1 MB_GH_FIXTURES="$STK" MB_GH_LOG="$TMP/log-stuck" run_stub gql "${FIX_ARGS[@]}" --merged-json "$TMP/merged-clean.json")"
RC_STUCK_LIVE=$?
STUCK_LIVE_SEC="$(section "$OUT_STUCK_LIVE" "== Stuck")"
assert_exit "stuck live: a full read exits 0" 0 "$RC_STUCK_LIVE"
assert_contains "stuck live: an item on the first page is listed" "$STUCK_LIVE_SEC" "  #301 issue  live ready item  (status: ready, 15d in stage)"
assert_contains "stuck live: an item on the second page is listed" "$STUCK_LIVE_SEC" "  #302 PR  second page pr  (status: ready, 10d in stage)"
assert_eq "stuck live: oldest first across pages" "#301#302" "$(stuck_order "$STUCK_LIVE_SEC")"
assert_contains "stuck live: the page past the first is read" "$(cat "$TMP/log-stuck")" "api-graphql-stuck-status__ready-p2"
assert_contains "stuck live: every queue label is searched" "$(cat "$TMP/log-stuck")" "api-graphql-stuck-needs-human-first"
assert_not_contains "stuck live: an empty search the REST listing confirms is not flagged" "$STUCK_LIVE_SEC" "count unavailable"

STK0="$TMP/gql-stuck-false-zero"
cp -r "$STK" "$STK0"
cp "$STK0/api-graphql-stuck-needs-human-first.json" "$STK0/api-graphql-stuck-status__ready-first.json"
printf '[]\n' >"$STK0/$(rest_key "$R/issues?state=open&per_page=100&labels=status%3A%20ready").json"
printf '[{"number": 9, "pull_request": {"url": "x"}}]\n' >"$STK0/$(rest_key "$R/issues?state=open&per_page=100&labels=needs-human").json"
STUCK_FALSE0="$(section "$(MB_STUCK_LIVE=1 MB_GH_FIXTURES="$STK0" run_stub gql "${FIX_ARGS[@]}" --merged-json "$TMP/merged-clean.json")" "== Stuck")"
assert_contains "stuck live: a search 0 against an open PR in the REST listing is count unavailable" "$STUCK_FALSE0" \
  "PARTIAL: needs-human: count unavailable: the search read 0 and the REST issue listing did not confirm it"
assert_not_contains "stuck live: a contradicted empty search never renders an all-clear" "$STUCK_FALSE0" "(none"

mkdir -p "$TMP/gql-stuck-none"
OUT_STUCK_FAIL="$(MB_STUCK_LIVE=1 MB_GH_FIXTURES="$TMP/gql-stuck-none" run_stub gql "${FIX_ARGS[@]}" --merged-json "$TMP/merged-clean.json")"
assert_contains "stuck live: a failed search renders UNREADABLE, never empty" "$(section "$OUT_STUCK_FAIL" "== Stuck")" "UNREADABLE: needs-triage: no fixture"

TCH="$TMP/gql-touch"
mkdir -p "$TCH"
printf '{"login": "Op-User"}\n' >"$TCH/api_user.json"
printf 'merge:\n  rung: C2\n  agent-identity: lanes-app[bot] # the lanes App\nother:\n  agent-identity: not-this\n' \
  >"$TCH/$(rest_key "$R/contents/docs/conventions/pr-pipeline.yaml").json"
touch_page() {
  jq --argjson i "$1" --argjson next "$2" --arg c "$3" \
    '{data: {search: {issueCount: 1, pageInfo: {hasNextPage: $next, endCursor: (if $c == "" then null else $c end)}, nodes: [.pages[0].data.search.nodes[$i]]}}}' \
    "$TMP/touch.json"
}
touch_page 0 true t2 >"$TCH/api-graphql-touch-2026-07-19-first.json"
touch_page 1 false "" >"$TCH/api-graphql-touch-2026-07-19-t2.json"
touch_page 2 false "" >"$TCH/api-graphql-touch-2026-07-20-first.json"
OUT_TOUCH_LIVE="$(MB_TOUCH_LIVE=1 MB_GH_FIXTURES="$TCH" MB_GH_LOG="$TMP/log-touch" run_stub gql "${FIX_ARGS[@]}" --merged-json "$TMP/merged-clean.json")"
TOUCH_LIVE_SEC="$(section "$OUT_TOUCH_LIVE" "== Owner touches")"
assert_contains "touches live: the operator and lane identity are read" "$TOUCH_LIVE_SEC" \
  "  operator: op-user; escalations trusted from: lanes-app, op-user"
assert_contains "touches live: the first day reads both its pages" "$TOUCH_LIVE_SEC" \
  "  2026-07-19          1        0        0        1        2        2                     2"
assert_contains "touches live: the second day is its own search" "$TOUCH_LIVE_SEC" \
  "  2026-07-20          0        1        1        0        1        2                     0"
assert_contains "touches live: the page past the first is read" "$(cat "$TMP/log-touch")" "api-graphql-touch-2026-07-19-t2"
OUT_TOUCH_PINNED="$(MB_TOUCH_LIVE=1 MB_GH_FIXTURES="$TCH" MB_GH_LOG="$TMP/log-touch-pinned" run_stub gql "${FIX_ARGS[@]}" \
  --merged-json "$TMP/merged-clean.json" --owner-login other-person --lane-identity nobody)"
assert_contains "touches live: --owner-login and --lane-identity pin both logins" "$(section "$OUT_TOUCH_PINNED" "== Owner touches")" \
  "  operator: other-person; escalations trusted from: nobody, other-person"
assert_not_contains "touches live: pinned logins skip both reads" "$(cat "$TMP/log-touch-pinned")" "api_user"
mkdir -p "$TMP/gql-touch-none"
printf '{"login": "op-user"}\n' >"$TMP/gql-touch-none/api_user.json"
assert_contains "touches live: a failed search renders UNREADABLE, never empty" \
  "$(section "$(MB_TOUCH_LIVE=1 MB_GH_FIXTURES="$TMP/gql-touch-none" run_stub gql "${FIX_ARGS[@]}" --merged-json "$TMP/merged-clean.json")" "== Owner touches")" \
  "UNREADABLE: no fixture api-graphql-touch-2026-07-19-first"

cat >"$TMP/lane-runs.json" <<'EOF'
{
  "intake-triage.yml": [
    {"id": 1, "html_url": "http://x/runs/1", "event": "issues", "display_title": "Issue A", "head_sha": "m1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"},
    {"id": 2, "html_url": "http://x/runs/2", "event": "issues", "display_title": "Issue B", "head_sha": "m1", "status": "completed", "conclusion": "failure", "created_at": "2026-07-19T11:00:00Z"},
    {"id": 3, "html_url": "http://x/runs/3", "event": "issues", "display_title": "Issue C", "head_sha": "m1", "status": "completed", "conclusion": "success", "created_at": "2026-07-18T00:00:00Z"},
    {"id": 4, "html_url": "http://x/runs/4", "event": "issues", "display_title": "Issue D", "head_sha": "m1", "status": "completed", "conclusion": "failure", "created_at": "2026-07-01T00:00:00Z"},
    {"id": 5, "html_url": "http://x/runs/5", "event": "issues", "display_title": "Issue E", "head_sha": "m1", "status": "completed", "conclusion": "skipped", "created_at": "2026-07-19T12:00:00Z"}
  ],
  "work-resolve-issue.yml": [
    {"id": 10, "html_url": "http://x/runs/10", "event": "issues", "display_title": "Issue X #7", "head_sha": "m1", "status": "completed", "conclusion": "failure", "created_at": "2026-07-15T00:00:00Z"},
    {"id": 11, "html_url": "http://x/runs/11", "event": "issues", "display_title": "Issue X #7", "head_sha": "m2", "status": "completed", "conclusion": "failure", "created_at": "2026-07-15T06:00:00Z"},
    {"id": 12, "html_url": "http://x/runs/12", "event": "issues", "display_title": "Issue X, renamed #7", "head_sha": "m3", "status": "completed", "conclusion": "failure", "created_at": "2026-07-16T00:00:00Z"},
    {"id": 13, "html_url": "http://x/runs/13", "event": "issues", "display_title": "Issue X, renamed #7", "head_sha": "m3", "status": "completed", "conclusion": "success", "created_at": "2026-07-16T06:00:00Z"},
    {"id": 14, "html_url": "http://x/runs/14", "event": "issues", "display_title": "Issue X #8", "head_sha": "m3", "status": "completed", "conclusion": "failure", "created_at": "2026-07-17T00:00:00Z"},
    {"id": 15, "html_url": "http://x/runs/15", "event": "issues", "display_title": "Issue X #8", "head_sha": "m3", "status": "completed", "conclusion": "failure", "created_at": "2026-07-17T01:00:00Z"}
  ],
  "pr-verify.yml": [
    {"id": 20, "html_url": "http://x/runs/20", "event": "workflow_run", "display_title": "PR Z", "head_sha": "abcdef1234", "status": "completed", "conclusion": "failure", "created_at": "2026-07-15T00:00:00Z"},
    {"id": 21, "html_url": "http://x/runs/21", "event": "workflow_run", "display_title": "PR Z", "head_sha": "abcdef1234", "status": "completed", "conclusion": "failure", "created_at": "2026-07-15T06:00:00Z"},
    {"id": 22, "html_url": "http://x/runs/22", "event": "workflow_run", "display_title": "PR Z", "head_sha": "abcdef1234", "status": "completed", "conclusion": "failure", "created_at": "2026-07-16T00:00:00Z"}
  ]
}
EOF
cat >"$TMP/lane-annotations.json" <<'EOF'
{
  "1": "intake-triage completed. lane-outcome {\"v\":1,\"lane\":\"intake-triage\",\"outcome\":\"success\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"turns\":10,\"maxTurns\":15}",
  "2": "failure-class=other job=success; read the job log.\nClaude intake triage exited with: failure class=other (infrastructure error, not a code-quality signal — e.g. usage limit, OIDC failure, SDK crash, is_error result, or max-turns exhaustion). Last SDK result: {\"subtype\":\"success\",\"is_error\":false,\"num_turns\":16,\"class\":\"other\"}\nClaude reported a successful result after 16 turns, exceeding the configured maximum of 15",
  "3": "intake-triage completed. lane-outcome {\"v\":1,\"lane\":\"intake-triage\",\"outcome\":\"success\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"turns\":12,\"maxTurns\":15}",
  "4": "intake-triage exited with: failure. lane-outcome {\"v\":1,\"lane\":\"intake-triage\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"rate-limit\"}",
  "10": "work-resolve-issue exited with: failure. lane-outcome {\"v\":1,\"lane\":\"work-resolve-issue\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"rate-limit\",\"resets\":{\"at\":\"2026-07-15T05:00:00Z\",\"window\":\"five_hour\"}}",
  "11": "work-resolve-issue exited with: failure. lane-outcome {\"v\":1,\"lane\":\"work-resolve-issue\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"rate-limit\"}",
  "12": "work-resolve-issue exited with: failure. lane-outcome {\"v\":1,\"lane\":\"work-resolve-issue\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"rate-limit\"}",
  "13": "work-resolve-issue completed. lane-outcome {\"v\":1,\"lane\":\"work-resolve-issue\",\"outcome\":\"success\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"turns\":4,\"maxTurns\":50}",
  "14": "work-resolve-issue exited with: failure. lane-outcome {\"v\":1,\"lane\":\"work-resolve-issue\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"auth\"}",
  "20": "pr-verify exited with: failure. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"rate-limit\",\"models\":[\"claude-opus-5-5\"]}",
  "21": "pr-verify exited with: failure. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"rate-limit\",\"models\":[\"claude-opus-5-5\"]}",
  "22": "pr-verify exited with: failure. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"rate-limit\",\"models\":[\"claude-opus-5-5\"]}"
}
EOF
OUT_LANES="$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
  --lane-runs-json "$TMP/lane-runs.json" --lane-annotations-json "$TMP/lane-annotations.json" "${CLEAR_COST_ARGS[@]}" 2>&1)"
LANES="$(section "$OUT_LANES" "== Lanes")"
assert_contains "lanes: a turn-cap stop that classify called other counts as max-turns" "$LANES" \
  "intake-triage.yml  runs=3  failed=1 [rate-limit 0, max-turns 1, auth 0, other 0]  limit-stops=0  restarts=0"
assert_contains "lanes: turn headroom flags a max-turns failure and a p90 at 80% of the cap" "$LANES" \
  "turns: max=16 p90=16 cap=15 (3 runs)  CHECK: 1 max-turns failure(s); p90 at or above 80% of the cap"
assert_contains "lanes: the max-turns run is linked" "$LANES" "      http://x/runs/2"
assert_contains "lanes: a run at 80% of the cap is linked" "$LANES" "      http://x/runs/3"
assert_not_contains "lanes: a run under 80% of the cap is not linked" "$LANES" "http://x/runs/1"
assert_not_contains "lanes: a run before the window is not counted" "$LANES" "http://x/runs/4"
assert_contains "lanes: limit stops, restarts, auth and an unread failure" "$LANES" \
  "work-resolve-issue.yml  runs=6  failed=5 [rate-limit 3, max-turns 0, auth 1, other 0, unread 1]  limit-stops=3  restarts=3"
assert_contains "lanes: headroom under 80% raises no CHECK" "$LANES" "    turns: max=4 p90=4 cap=50 (1 runs)"$'\n'
assert_contains "lanes: three limit stops on one issue are named, keyed by its number" "$LANES" "3 limit stops on one item: Issue X #7"
assert_contains "lanes: three limit stops on one head are named with the head" "$LANES" "3 limit stops on one head: PR Z @ abcdef1"
assert_contains "lanes: restarts on a pull request head" "$LANES" "pr-verify.yml  runs=3  failed=3 [rate-limit 3, max-turns 0, auth 0, other 0]  limit-stops=3  restarts=2"

cat >"$TMP/lane-runs-handoff.json" <<'EOF'
{
  "pr-review-main.yml": [
    {"id": 90, "html_url": "http://x/runs/90", "event": "workflow_run", "display_title": "PR H", "head_sha": "feed1234", "status": "completed", "conclusion": "failure", "created_at": "2026-07-18T00:00:00Z"}
  ]
}
EOF
cat >"$TMP/lane-annotations-handoff.json" <<'EOF'
{
  "90": "pr-review-main concluded: failure class=rate-limit turns=3 credential=REVIEWS_CLAUDE_CODE_OAUTH_TOKEN. lane-outcome {\"v\":1,\"lane\":\"pr-review-main-claude-review\",\"outcome\":\"failure\",\"class\":\"rate-limit\",\"credential\":{\"secret\":\"REVIEWS_CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\",\"role\":\"REVIEWS\"},\"handoff\":true,\"turns\":3}\npr-review-main concluded: failure class=other turns=5 credential=FALLBACK_CLAUDE_CODE_OAUTH_TOKEN. lane-outcome {\"v\":1,\"lane\":\"pr-review-main-claude-review\",\"outcome\":\"failure\",\"class\":\"other\",\"credential\":{\"secret\":\"FALLBACK_CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\",\"role\":\"FALLBACK\"},\"fallback\":{\"reason\":\"limit-stop\"},\"turns\":5}\npr-review-main concluded: failure class=credit-stop turns=1 credential=REVIEWS_CLAUDE_API_KEY. lane-outcome {\"v\":1,\"lane\":\"pr-review-main-claude-review\",\"outcome\":\"failure\",\"class\":\"credit-stop\",\"credential\":{\"secret\":\"REVIEWS_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"REVIEWS\"},\"handoff\":true,\"turns\":1}"
}
EOF
LANES_HANDOFF="$(section "$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
  --lane-runs-json "$TMP/lane-runs-handoff.json" --lane-annotations-json "$TMP/lane-annotations-handoff.json" "${CLEAR_COST_ARGS[@]}" 2>&1)" "== Lanes")"
assert_contains "lanes: a handoff record neither classes the run nor counts a limit stop" "$LANES_HANDOFF" \
  "pr-review-main.yml  runs=1  failed=1 [rate-limit 0, max-turns 0, auth 0, other 1]  limit-stops=0  restarts=0"
assert_contains "lanes: turns come from the leg that ended the run" "$LANES_HANDOFF" "turns: max=5"
assert_contains "lanes: a handed-off key leg's credit stop still names its key" "$LANES_HANDOFF" "KEY: REVIEWS credit-stop (1 of 1)"
assert_contains "lanes: a handed-off key leg still counts in SPEND" "$LANES_HANDOFF" "SPEND: REVIEWS cost not recorded (n=1)"
cat >"$TMP/lane-runs-legacy.json" <<'EOF'
{
  "pr-verify.yml": [
    {"id": 95, "html_url": "http://x/runs/95", "event": "workflow_run", "display_title": "PR L", "head_sha": "beef1234", "status": "completed", "conclusion": "failure", "created_at": "2026-07-18T00:00:00Z"}
  ]
}
EOF
cat >"$TMP/lane-annotations-legacy.json" <<'EOF'
{
  "95": "pr-verify exited with: failure class=rate-limit turns=3 max-turns=30 models=claude-opus-5-5 profile=standard"
}
EOF
LANES_LEGACY="$(section "$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
  --lane-runs-json "$TMP/lane-runs-legacy.json" --lane-annotations-json "$TMP/lane-annotations-legacy.json" "${CLEAR_COST_ARGS[@]}" 2>&1)" "== Lanes")"
assert_contains "lanes: legacy tokens alone class no run" "$LANES_LEGACY" \
  "pr-verify.yml  runs=1  failed=1 [rate-limit 0, max-turns 0, auth 0, other 1]  limit-stops=0  restarts=0"
assert_not_contains "lanes: legacy tokens alone give no turns" "$LANES_LEGACY" "turns: max="
assert_contains "lanes: legacy tokens alone are no lane record" "$LANES_LEGACY" "    1 run(s) left out: no lane record was read"
cat >"$TMP/lane-runs-classes.json" <<'EOF'
{
  "pr-review-main.yml": [
    {"id": 96, "html_url": "http://x/runs/96", "event": "workflow_run", "display_title": "PR U", "head_sha": "c0de1234", "status": "completed", "conclusion": "failure", "created_at": "2026-07-18T00:00:00Z"},
    {"id": 97, "html_url": "http://x/runs/97", "event": "workflow_run", "display_title": "PR V", "head_sha": "c0de5678", "status": "completed", "conclusion": "success", "created_at": "2026-07-18T01:00:00Z"},
    {"id": 98, "html_url": "http://x/runs/98", "event": "workflow_run", "display_title": "PR W", "head_sha": "c0de9abc", "status": "completed", "conclusion": "failure", "created_at": "2026-07-18T02:00:00Z"}
  ]
}
EOF
cat >"$TMP/lane-annotations-classes.json" <<'EOF'
{
  "96": "pr-review concluded: failure. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"failure\",\"class\":\"review-unposted\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"}}",
  "97": "pr-review completed. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"shellFailed\":true,\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"}}",
  "98": "pr-review exited with: failure. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"failure\",\"class\":\"shell-failed\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"}}"
}
EOF
LANES_CLASSES="$(section "$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
  --lane-runs-json "$TMP/lane-runs-classes.json" --lane-annotations-json "$TMP/lane-annotations-classes.json" "${CLEAR_COST_ARGS[@]}" 2>&1)" "== Lanes")"
assert_contains "lanes: review-unposted is shown as its own class, and shell-failed runs are counted" "$LANES_CLASSES" \
  "pr-review-main.yml  runs=3  failed=2 [rate-limit 0, max-turns 0, auth 0, other 1, review-unposted 1]  limit-stops=0  restarts=0  shell-failed=2"
assert_exit "lanes: a fully read brief with lanes exits 0" 0 "$(
  bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" --decisions-json "$TMP/decisions.json" \
    --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
    --lane-runs-json "$TMP/lane-runs.json" --lane-annotations-json "$TMP/lane-annotations.json" "${CLEAR_COST_ARGS[@]}" >/dev/null 2>&1
  echo $?
)"
printf '[1,2]\n' >"$TMP/lane-runs-bad.json"
OUT_LANES_BAD="$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
  --lane-runs-json "$TMP/lane-runs-bad.json" 2>&1)"
assert_contains "lanes: a runs file that is not an object is UNREADABLE" "$(section "$OUT_LANES_BAD" "== Lanes")" "UNREADABLE:"
assert_contains "models: a pr-verify record with models and no profile gets its row" "$LANES" \
  "    pr-verify  profile=unknown  runs=3  pass=0/3  median-turns=-  max-turns-hits=0  models=claude-opus-5-5"
assert_contains "models: a lane whose records carry no models still gets a row" "$LANES" \
  "    work-resolve-issue  profile=unknown  runs=5  pass=1/5  median-turns=4  max-turns-hits=0  models=none recorded"
assert_not_contains "keys: runs with no lane-outcome record print no KEY line" "$LANES" "KEY:"

cat >"$TMP/key-runs.json" <<'EOF'
{
  "pr-review-hosted.yml": [
    {"id": 50, "html_url": "http://x/runs/50", "event": "pull_request", "display_title": "PR K", "head_sha": "k1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"},
    {"id": 51, "html_url": "http://x/runs/51", "event": "pull_request", "display_title": "PR L", "head_sha": "l1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T11:00:00Z"}
  ],
  "intake-triage.yml": [
    {"id": 60, "html_url": "http://x/runs/60", "event": "issues", "display_title": "Issue K", "head_sha": "m1", "status": "completed", "conclusion": "failure", "created_at": "2026-07-19T10:00:00Z"}
  ],
  "pr-verify.yml": [
    {"id": 70, "html_url": "http://x/runs/70", "event": "workflow_run", "display_title": "PR M", "head_sha": "n1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"},
    {"id": 71, "html_url": "http://x/runs/71", "event": "workflow_run", "display_title": "PR N", "head_sha": "n2", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T11:00:00Z"},
    {"id": 72, "html_url": "http://x/runs/72", "event": "workflow_run", "display_title": "PR O", "head_sha": "n3", "status": "completed", "conclusion": "failure", "created_at": "2026-07-19T12:00:00Z"}
  ],
  "pr-unblock.yml": [
    {"id": 80, "html_url": "http://x/runs/80", "event": "workflow_dispatch", "display_title": "Fix #3", "head_sha": "p1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"},
    {"id": 81, "html_url": "http://x/runs/81", "event": "workflow_dispatch", "display_title": "Fix #4", "head_sha": "p2", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T11:00:00Z"},
    {"id": 82, "html_url": "http://x/runs/82", "event": "workflow_dispatch", "display_title": "Fix #6", "head_sha": "p4", "status": "completed", "conclusion": "failure", "created_at": "2026-07-19T11:10:00Z"},
    {"id": 83, "html_url": "http://x/runs/83", "event": "workflow_dispatch", "display_title": "Fix #7", "head_sha": "p5", "status": "completed", "conclusion": "failure", "created_at": "2026-07-19T11:20:00Z"},
    {"id": 84, "html_url": "http://x/runs/84", "event": "workflow_dispatch", "display_title": "Fix #8", "head_sha": "p6", "status": "completed", "conclusion": "failure", "created_at": "2026-07-19T11:30:00Z"},
    {"id": 90, "html_url": "http://x/runs/90", "event": "workflow_dispatch", "display_title": "Fix #5", "head_sha": "p3", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T12:00:00Z"}
  ]
}
EOF
cat >"$TMP/key-annotations.json" <<'EOF'
{
  "50": "pr-review completed: credential=REVIEWS_CLAUDE_CODE_OAUTH_TOKEN fallback=auth turns=9 max-turns=30 models=claude-opus-5-5. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"credential\":{\"secret\":\"REVIEWS_CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\",\"role\":\"REVIEWS\"},\"fallback\":{\"reason\":\"auth\"},\"turns\":9,\"models\":[\"claude-opus-5-5\"]} Findings (if any) are in the PR comments.",
  "51": "pr-review completed: credential=REVIEWS_CLAUDE_API_KEY turns=7 max-turns=30 models=claude-opus-5-5. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"credential\":{\"secret\":\"REVIEWS_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"REVIEWS\"},\"turns\":7,\"models\":[\"claude-opus-5-5\"]} Findings (if any) are in the PR comments.",
  "60": "Claude intake triage exited with: failure class=auth credential=INTAKE_CLAUDE_API_KEY. lane-outcome {\"v\":1,\"lane\":\"intake-triage\",\"outcome\":\"failure\",\"class\":\"auth\",\"credential\":{\"secret\":\"INTAKE_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"INTAKE\"},\"error\":{\"type\":\"permission_error\"}} Last SDK result: {\"is_error\":true}",
  "70": "pr-verify exited with: failure class=rate-limit credential=AUTOMATIONS_CLAUDE_API_KEY. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"failure\",\"class\":\"rate-limit\",\"credential\":{\"secret\":\"AUTOMATIONS_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"AUTOMATIONS\"}}\npr-verify completed: credential=AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN fallback=credit-stop turns=4 max-turns=60 models=claude-opus-5-5. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"success\",\"credential\":{\"secret\":\"AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\",\"role\":\"AUTOMATIONS\"},\"fallback\":{\"reason\":\"credit-stop\"},\"turns\":4,\"maxTurns\":60,\"models\":[\"claude-opus-5-5\"]} Findings (if any) are in the PR comments.",
  "71": "pr-verify completed: credential=AUTOMATIONS_CLAUDE_API_KEY turns=5 max-turns=60 models=claude-opus-5-5. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"success\",\"credential\":{\"secret\":\"AUTOMATIONS_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"AUTOMATIONS\"},\"turns\":5,\"maxTurns\":60,\"models\":[\"claude-opus-5-5\"]} Findings (if any) are in the PR comments.",
  "72": "pr-verify exited with: failure class=credit-stop credential=CREDIT_CLAUDE_API_KEY. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"failure\",\"class\":\"credit-stop\",\"credential\":{\"secret\":\"CREDIT_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"CREDIT\"},\"error\":{\"type\":\"billing_error\"}} Last SDK result: {\"is_error\":true}",
  "80": "pr-unblock completed: credential=PR_UNBLOCK_CLAUDE_API_KEY turns=6 max-turns=40 models=claude-sonnet-5. lane-outcome {\"v\":1,\"lane\":\"fix-ci\",\"outcome\":\"success\",\"credential\":{\"secret\":\"PR_UNBLOCK_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"PR_UNBLOCK\"},\"turns\":6}\nactivity=fix-ci",
  "81": "pr-unblock completed: credential=PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN fallback=no-key turns=6 max-turns=40 models=claude-sonnet-5. lane-outcome {\"v\":1,\"lane\":\"fix-ci\",\"outcome\":\"success\",\"credential\":{\"secret\":\"PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\",\"role\":\"PR_UNBLOCK\"},\"fallback\":{\"reason\":\"no-key\"},\"turns\":6}\nactivity=fix-ci",
  "82": "pr-unblock exited with: failure class=auth credential=PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN. lane-outcome {\"v\":1,\"lane\":\"fix-ci\",\"outcome\":\"failure\",\"class\":\"auth\",\"credential\":{\"secret\":\"PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\",\"role\":\"PR_UNBLOCK\"}}",
  "83": "pr-unblock exited with: failure class=auth. lane-outcome {\"v\":1,\"credential\":\"PR_UNBLOCK_CLAUDE_API_KEY\",\"class\":\"auth\"}\npr-unblock exited. lane-outcome {\"v\":1,\"credential\":{\"role\":\"PR_UNBLOCK\"},\"fallback\":\"auth\"}\npr-unblock exited. lane-outcome {\"v\":1,\"credential\":{\"role\":\"BAD\\n\",\"kind\":\"api-key\"},\"class\":\"auth\"}",
  "84": "fix-ci completed. lane-outcome {\"v\":1,\"lane\":\"fix-ci\",\"outcome\":\"success\",\"credential\":{\"secret\":\"TWO_A_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"TWO_A\"}}\nfix-docs exited with: failure class=auth. lane-outcome {\"v\":1,\"lane\":\"fix-docs\",\"outcome\":\"failure\",\"class\":\"auth\",\"credential\":{\"secret\":\"TWO_B_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"TWO_B\"}}",
  "90": "pr-unblock completed: credential=ZED_CLAUDE_CODE_OAUTH_TOKEN fallback=auth turns=6. lane-outcome {\"v\":2,\"lane\":\"fix-ci\",\"outcome\":\"success\",\"credential\":{\"secret\":\"ZED_CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\",\"role\":\"ZED\"},\"fallback\":{\"reason\":\"auth\"}}"
}
EOF
KEYS="$(section "$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
  --lane-runs-json "$TMP/key-runs.json" --lane-annotations-json "$TMP/key-annotations.json" "${CLEAR_COST_ARGS[@]}" 2>&1)" "== Lanes")"
assert_contains "keys: a successful run with fallback=auth flags the role and names its key secret" "$KEYS" \
  "  KEY: REVIEWS auth (fallback on 1 of 2 runs read) — replace REVIEWS_CLAUDE_API_KEY"
assert_not_contains "keys: the auth line never names the subscription token" "$KEYS" "replace REVIEWS_CLAUDE_CODE_OAUTH_TOKEN"
assert_contains "keys: a failing key leg with class=auth is flagged" "$KEYS" \
  "  KEY: INTAKE auth (fallback on 1 of 1 runs read) — replace INTAKE_CLAUDE_API_KEY"
assert_contains "keys: pr-verify's class=rate-limit with fallback=credit-stop is a credit stop" "$KEYS" \
  "  KEY: AUTOMATIONS credit-stop (1 of 2) — rotate a spare key into AUTOMATIONS"
assert_not_contains "keys: a credit stop is not read as auth" "$KEYS" "KEY: AUTOMATIONS auth"
assert_contains "keys: a key leg that failed with class=credit-stop and no fallback is a credit stop" "$KEYS" \
  "  KEY: CREDIT credit-stop (1 of 1) — rotate a spare key into CREDIT"
assert_not_contains "keys: a key leg's credit stop is not read as auth" "$KEYS" "KEY: CREDIT auth"
assert_not_contains "keys: a healthy key leg and a no-key fallback print no KEY line" "$KEYS" "KEY: PR_UNBLOCK"
assert_not_contains "keys: a record version this reader does not know is not read" "$KEYS" "KEY: ZED"
assert_not_contains "keys: malformed records leave the section readable" "$KEYS" "UNREADABLE"
assert_not_contains "keys: a role name with a trailing newline is not a role" "$KEYS" "KEY: BAD"
assert_contains "keys: each role in a run is judged by its own records" "$KEYS" \
  "  KEY: TWO_B auth (fallback on 1 of 1 runs read) — replace TWO_B_CLAUDE_API_KEY"
assert_not_contains "keys: a healthy role beside a failing one is not flagged" "$KEYS" "KEY: TWO_A"
assert_contains "keys: the model-usage table still renders" "$KEYS" "model usage by activity and profile"
assert_eq "keys: one line per role and problem" "5" "$(grep -c "^  KEY: " <<<"$KEYS")"

KEY_LIVE="$TMP/rest-keys"
mkdir -p "$KEY_LIVE"
cp "$REST/"*.json "$KEY_LIVE/"
jq -n '{total_count: 200, workflow_runs: [range(200) as $i | {id: (1000 + $i), html_url: "http://x/runs/\(1000 + $i)", event: "issues", display_title: "Issue F\($i)", head_sha: "m1", status: "completed", conclusion: "failure", created_at: (("2026-07-19T00:00:00Z" | fromdateiso8601) + $i * 60 | todate)}]}' \
  >"$KEY_LIVE/$(rest_key "$R/actions/workflows/intake-triage.yml/runs?created=>=2026-07-13&per_page=100").json"
jq -n '{total_count: 3, workflow_runs: [range(3) as $i | {id: (901 + $i), html_url: "http://x/runs/\(901 + $i)", event: "workflow_dispatch", display_title: "Fix #\(901 + $i)", head_sha: "q\($i)", status: "completed", conclusion: "success", created_at: "2026-07-18T0\($i):00:00Z"}]}' \
  >"$KEY_LIVE/$(rest_key "$R/actions/workflows/pr-unblock.yml/runs?created=>=2026-07-13&per_page=100").json"
printf '{"total_count": 0, "workflow_runs": []}\n' \
  >"$KEY_LIVE/$(rest_key "$R/actions/workflows/pr-review-main.yml/runs?created=>=2026-07-13&per_page=100").json"
for key_run in $(seq 1000 1199); do
  printf '{"total_count": 1, "jobs": [{"id": 5555}]}\n' >"$KEY_LIVE/$(rest_key "$R/actions/runs/$key_run/jobs?per_page=100").json"
done
printf '%s\n' '[{"message": "intake-triage exited with: failure. lane-outcome {\"v\":1,\"lane\":\"intake-triage\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"rate-limit\"}"}]' >"$KEY_LIVE/$(rest_key "$R/check-runs/5555/annotations?per_page=100").json"
for key_run in 901 902 903; do
  printf '{"total_count": 1, "jobs": [{"id": %s0, "name": "fix-ci / run"}]}\n' "$key_run" \
    >"$KEY_LIVE/$(rest_key "$R/actions/runs/$key_run/jobs?per_page=100").json"
  cat >"$KEY_LIVE/$(rest_key "$R/check-runs/${key_run}0/annotations?per_page=100").json" <<'EOF'
[{"message": "pr-unblock completed: credential=PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN fallback=credit-stop turns=6 max-turns=40 models=claude-sonnet-5. lane-outcome {\"v\":1,\"lane\":\"fix-ci\",\"outcome\":\"success\",\"credential\":{\"secret\":\"PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\",\"role\":\"PR_UNBLOCK\"},\"fallback\":{\"reason\":\"credit-stop\"},\"turns\":6} Last SDK result: lane-outcome {\"v\":1,\"credential\":{\"role\":\"FORGED\",\"kind\":\"api-key\"},\"class\":\"auth\"}"}]
EOF
done
KEYS_LIVE="$(section "$(MB_GH_FIXTURES="$KEY_LIVE" run_stub rest)" "== Lanes")"
assert_contains "keys live: the newest 3 runs of a lane are read when failed runs fill the cap" "$KEYS_LIVE" \
  "  KEY: PR_UNBLOCK credit-stop (3 of 3) — rotate a spare key into PR_UNBLOCK"
assert_contains "keys live: the newest runs come out of the cap, not on top of it" "$KEYS_LIVE" \
  "intake-triage.yml  runs=200  failed=200 [rate-limit 197, max-turns 0, auth 0, other 0, unread 3]"
assert_not_contains "keys live: a record after the first in one message is not read" "$KEYS_LIVE" "KEY: FORGED"
assert_contains "keys live: a caller job named by its id still names the activity" "$KEYS_LIVE" \
  "    pr-unblock / fix-ci  profile=unknown  runs=3"
assert_not_contains "keys live: a later record in one message flags no role" "$KEYS_LIVE" "KEY: PR_UNBLOCK auth"
assert_contains "keys live: the cap's overflow is reported" "$KEYS_LIVE" \
  "  PARTIAL: annotations read for 200 runs, the newest 3 of each lane and then failed runs first; 3 more were not read (raise --lane-read-limit)"

cat >"$TMP/spend-runs.json" <<'EOF'
{
  "pr-verify.yml": [
    {"id": 100, "html_url": "http://x/runs/100", "event": "workflow_run", "display_title": "PR S1", "head_sha": "s1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"},
    {"id": 101, "html_url": "http://x/runs/101", "event": "workflow_run", "display_title": "PR S2", "head_sha": "s2", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T11:00:00Z"},
    {"id": 102, "html_url": "http://x/runs/102", "event": "workflow_run", "display_title": "PR S3", "head_sha": "s3", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T12:00:00Z"},
    {"id": 103, "html_url": "http://x/runs/103", "event": "workflow_run", "display_title": "PR S4", "head_sha": "s4", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T13:00:00Z"}
  ],
  "intake-triage.yml": [
    {"id": 110, "html_url": "http://x/runs/110", "event": "issues", "display_title": "Issue S", "head_sha": "t1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"},
    {"id": 111, "html_url": "http://x/runs/111", "event": "issues", "display_title": "Issue T", "head_sha": "t2", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T11:00:00Z"}
  ],
  "pr-review-hosted.yml": [
    {"id": 120, "html_url": "http://x/runs/120", "event": "pull_request", "display_title": "PR R", "head_sha": "r1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"},
    {"id": 121, "html_url": "http://x/runs/121", "event": "pull_request", "display_title": "PR R2", "head_sha": "r2", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T11:00:00Z"},
    {"id": 122, "html_url": "http://x/runs/122", "event": "pull_request", "display_title": "PR R3", "head_sha": "r3", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T12:00:00Z"}
  ],
  "pr-unblock.yml": [
    {"id": 130, "html_url": "http://x/runs/130", "event": "workflow_dispatch", "display_title": "Fix #9", "head_sha": "u1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"}
  ]
}
EOF
cat >"$TMP/spend-annotations.json" <<'EOF'
{
  "100": "pr-verify completed: credential=AUTOMATIONS_CLAUDE_API_KEY turns=5. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"success\",\"credential\":{\"secret\":\"AUTOMATIONS_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"AUTOMATIONS\"},\"turns\":5,\"costUsd\":1}",
  "101": "pr-verify completed: credential=AUTOMATIONS_CLAUDE_API_KEY turns=5. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"success\",\"credential\":{\"secret\":\"AUTOMATIONS_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"AUTOMATIONS\"},\"turns\":5,\"costUsd\":3}",
  "102": "pr-verify exited with: failure class=credit-stop credential=AUTOMATIONS_CLAUDE_API_KEY. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"failure\",\"class\":\"credit-stop\",\"credential\":{\"secret\":\"AUTOMATIONS_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"AUTOMATIONS\"},\"handoff\":true,\"costUsd\":4}\npr-verify completed: credential=AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN fallback=credit-stop turns=4. lane-outcome {\"v\":1,\"lane\":\"pr-verify\",\"outcome\":\"success\",\"credential\":{\"secret\":\"AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\",\"role\":\"AUTOMATIONS\"},\"fallback\":{\"reason\":\"credit-stop\"},\"turns\":4,\"costUsd\":9}",
  "110": "Claude intake triage completed: credential=AUTOMATIONS_CLAUDE_API_KEY turns=3. lane-outcome {\"v\":1,\"lane\":\"intake-triage\",\"outcome\":\"success\",\"credential\":{\"secret\":\"AUTOMATIONS_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"AUTOMATIONS\"},\"turns\":3,\"costUsd\":2}",
  "120": "pr-review completed: credential=REVIEWS_CLAUDE_API_KEY turns=7. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"credential\":{\"secret\":\"REVIEWS_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"REVIEWS\"},\"turns\":7}",
  "121": "pr-review completed. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"credential\":{\"secret\":\"EVEN_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"EVEN\"},\"costUsd\":1}\nother leg. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"credential\":{\"secret\":\"bad_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"bad\"},\"costUsd\":1}\nother leg. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"credential\":{\"secret\":\"HUGE_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"HUGE\"},\"costUsd\":1e17}",
  "122": "pr-review completed. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"credential\":{\"secret\":\"EVEN_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"EVEN\"},\"costUsd\":4}\nother leg. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"credential\":{\"secret\":\"EVEN_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"EVEN\"},\"class\":\"credit-stop\",\"costUsd\":100}\nother leg. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"credential\":{\"secret\":\"EVEN_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"EVEN\"},\"costUsd\":-1}\nother leg. lane-outcome {\"v\":1,\"lane\":\"pr-review\",\"outcome\":\"success\",\"credential\":{\"secret\":\"EVEN_CLAUDE_API_KEY\",\"kind\":\"api-key\",\"role\":\"EVEN\"},\"costUsd\":\"2\"}",
  "130": "pr-unblock completed: credential=PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN fallback=no-key turns=6. lane-outcome {\"v\":1,\"lane\":\"fix-ci\",\"outcome\":\"success\",\"credential\":{\"secret\":\"PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\",\"role\":\"PR_UNBLOCK\"},\"fallback\":{\"reason\":\"no-key\"},\"turns\":6,\"costUsd\":5}\nactivity=fix-ci"
}
EOF
SPEND="$(section "$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
  --lane-runs-json "$TMP/spend-runs.json" --lane-annotations-json "$TMP/spend-annotations.json" "${CLEAR_COST_ARGS[@]}" 2>&1)" "== Lanes")"
assert_contains "spend: the median successful key leg, scaled by the role's lane runs per day, labeled a list-price estimate" "$SPEND" \
  "  SPEND: AUTOMATIONS ~\$1.71/day (list price, n=4) — estimate: median \$2.00 per successful key leg × 6 runs over 7d; \$10.00 summed over the legs read"
assert_eq "spend: one line per role prefix, across lanes and secrets" "1" "$(grep -c "^  SPEND: AUTOMATIONS " <<<"$SPEND")"
assert_not_contains "spend: never grouped by lane id" "$SPEND" "SPEND: pr-verify"
assert_contains "spend: a key leg with no costUsd says so" "$SPEND" "  SPEND: REVIEWS cost not recorded (n=1)"
assert_not_contains "spend: a role with only token legs prints no spend line" "$SPEND" "SPEND: PR_UNBLOCK"
assert_contains "spend: an even count takes the mean of the middle two; a successful credit-stop leg and a negative or string cost are left out" "$SPEND" \
  "  SPEND: EVEN ~\$1.07/day (list price, n=5) — estimate: median \$2.50 per successful key leg × 3 runs over 7d; \$105.00 summed over the legs read"
assert_contains "spend: a cost past the bound is not a cost" "$SPEND" "  SPEND: HUGE cost not recorded (n=1)"
assert_not_contains "spend: a role outside the role pattern prints nothing" "$SPEND" "SPEND: bad"
assert_not_contains "spend: the section stays readable" "$SPEND" "UNREADABLE"
assert_contains "spend: legs without costUsd elsewhere print cost not recorded" "$KEYS" "  SPEND: INTAKE cost not recorded (n=1)"

cat >"$TMP/model-runs.json" <<'EOF'
{
  "pr-unblock.yml": [
    {"id": 30, "html_url": "http://x/runs/30", "event": "pull_request", "display_title": "PR A", "head_sha": "a1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"},
    {"id": 31, "html_url": "http://x/runs/31", "event": "pull_request", "display_title": "PR A", "head_sha": "a2", "status": "completed", "conclusion": "failure", "created_at": "2026-07-19T11:00:00Z"},
    {"id": 32, "html_url": "http://x/runs/32", "event": "pull_request", "display_title": "PR B", "head_sha": "b1", "status": "completed", "conclusion": "success", "created_at": "2026-07-18T10:00:00Z"},
    {"id": 33, "html_url": "http://x/runs/33", "event": "pull_request", "display_title": "PR C", "head_sha": "c1", "status": "completed", "conclusion": "success", "created_at": "2026-07-18T11:00:00Z"},
    {"id": 34, "html_url": "http://x/runs/34", "event": "pull_request", "display_title": "PR D", "head_sha": "d1", "status": "completed", "conclusion": "failure", "created_at": "2026-07-17T10:00:00Z"},
    {"id": 35, "html_url": "http://x/runs/35", "event": "pull_request", "display_title": "PR E", "head_sha": "e1", "status": "completed", "conclusion": "failure", "created_at": "2026-07-17T11:00:00Z"},
    {"id": 36, "html_url": "http://x/runs/36", "event": "pull_request", "display_title": "PR F", "head_sha": "f1", "status": "completed", "conclusion": "success", "created_at": "2026-07-16T10:00:00Z"},
    {"id": 37, "html_url": "http://x/runs/37", "event": "pull_request", "display_title": "PR G", "head_sha": "g1", "status": "completed", "conclusion": "cancelled", "created_at": "2026-07-16T11:00:00Z"}
  ],
  "intake-triage.yml": [
    {"id": 40, "html_url": "http://x/runs/40", "event": "issues", "display_title": "Issue Q", "head_sha": "m1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T09:00:00Z"}
  ]
}
EOF
cat >"$TMP/model-annotations.json" <<'EOF'
{
  "30": "pr-unblock completed. lane-outcome {\"v\":1,\"lane\":\"resolve-conflicts\",\"outcome\":\"success\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"turns\":8,\"maxTurns\":40,\"models\":[\"claude-sonnet-5\"]} Findings (if any) are in the PR comments.\nactivity=resolve-conflicts",
  "31": "pr-unblock exited with: failure. lane-outcome {\"v\":1,\"lane\":\"resolve-conflicts\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"max-turns\",\"turns\":40,\"maxTurns\":40,\"models\":[\"claude-sonnet-5\",\"claude-haiku-5\"]} (infrastructure error)\nactivity=resolve-conflicts",
  "32": "pr-unblock completed: profile=standard. lane-outcome {\"v\":1,\"lane\":\"fix-docs\",\"outcome\":\"success\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"turns\":12,\"maxTurns\":40,\"models\":[\"claude-opus-5\"]} Findings (if any) are in the PR comments.\nactivity=fix-docs",
  "33": "activity=address-feedback\npr-unblock completed. lane-outcome {\"v\":1,\"lane\":\"address-feedback\",\"outcome\":\"success\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"turns\":5,\"maxTurns\":40,\"models\":[\"claude-sonnet-5\"]}",
  "34": "pr-unblock exited with: failure. lane-outcome {\"v\":1,\"lane\":\"resolve-conflicts\",\"outcome\":\"failure\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"class\":\"max-turns\",\"turns\":40,\"maxTurns\":40,\"models\":[\"claude-sonnet-5\"]}\nactivity=resolve-conflicts",
  "36": "pr-unblock completed. lane-outcome {\"v\":1,\"lane\":\"resolve-conflicts\",\"outcome\":\"success\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"turns\":10,\"maxTurns\":40,\"models\":[\"claude-sonnet-5\"]}\nactivity=resolve-conflicts",
  "37": "The run was canceled by @someone.\nactivity=resolve-conflicts",
  "40": "Claude intake triage completed. lane-outcome {\"v\":1,\"lane\":\"intake-triage\",\"outcome\":\"success\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"turns\":3,\"maxTurns\":10,\"models\":[\"claude-sonnet-5\"]} Findings (if any) are in the PR comments."
}
EOF
models_brief() {
  bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
    --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
    --lane-runs-json "$TMP/model-runs.json" --lane-annotations-json "$TMP/model-annotations.json" "$@" 2>&1
}
MODELS="$(section "$(models_brief)" "== Lanes")"
assert_contains "models: a lane with no activity= is its own activity" "$MODELS" \
  "    intake-triage  profile=unknown  runs=1  pass=1/1  median-turns=3  max-turns-hits=0  models=claude-sonnet-5"
assert_contains "models: a pipeline activity gets its own row" "$MODELS" \
  "    pr-unblock / address-feedback  profile=unknown  runs=1  pass=1/1  median-turns=5  max-turns-hits=0  models=claude-sonnet-5"
assert_contains "models: each pipeline activity gets its own row" "$MODELS" \
  "    pr-unblock / fix-docs  profile=unknown  runs=1  pass=1/1  median-turns=12  max-turns-hits=0  models=claude-opus-5"
assert_not_contains "models: a profile= token in free text is not read" "$MODELS" "profile=standard"
assert_contains "models: pass count, even-count median, max-turns hits and the union of models" "$MODELS" \
  "    pr-unblock / resolve-conflicts  profile=unknown  runs=4  pass=2/4  median-turns=25  max-turns-hits=2  models=claude-haiku-5,claude-sonnet-5"
assert_contains "models: runs with no lane record read, unread or recordless, are left out and counted" "$MODELS" \
  "    2 run(s) left out: no lane record was read"
assert_contains "models: no threshold set prints no RECOMMENDED line" "$MODELS" \
  "    no threshold set: pass --max-turns-hits N for RECOMMENDED lines"
assert_not_contains "models: no RECOMMENDED line without a threshold" "$MODELS" "RECOMMENDED:"
MODELS_T1="$(section "$(models_brief --max-turns-hits 1)" "== Lanes")"
assert_contains "models: hits over the threshold print RECOMMENDED for that cell" "$MODELS_T1" \
  "    RECOMMENDED: pr-unblock / resolve-conflicts profile=unknown hit max-turns 2 times, over the threshold of 1;"
assert_eq "models: only the cell over the threshold is RECOMMENDED" "1" "$(grep -c "RECOMMENDED:" <<<"$MODELS_T1")"
assert_not_contains "models: a set threshold drops the no-threshold line" "$MODELS_T1" "no threshold set"
MODELS_T2="$(section "$(models_brief --max-turns-hits 2)" "== Lanes")"
assert_not_contains "models: hits equal to the threshold do not exceed it" "$MODELS_T2" "RECOMMENDED:"
assert_exit "models: a non-numeric threshold is an invalid argument" 3 "$(
  models_brief --max-turns-hits many >/dev/null
  echo $?
)"

cost_brief() {
  bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" --behind-json "$TMP/behind.json" \
    --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
    --lane-runs-json "$TMP/lanes-empty.json" "$@" 2>&1
}

OUT_COST_CLEAR="$(cost_brief "${CLEAR_COST_ARGS[@]}")"
RC_COST_CLEAR=$?
COST_CLEAR="$(section "$OUT_COST_CLEAR" "== Cost")"
assert_exit "cost: an all-clear brief exits 0" 0 "$RC_COST_CLEAR"
assert_contains "cost: a product's month net sums its SKUs" "$COST_CLEAR" "OK         GitHub usage 2026-07 actions: net 0"
assert_contains "cost: every product used this month gets a line" "$COST_CLEAR" "OK         GitHub usage 2026-07 git_lfs: net 0"
assert_not_contains "cost: an earlier month's charge is not this month's" "$COST_CLEAR" "12.34"
assert_contains "cost: a zero budget that stops at its limit is OK" "$COST_CLEAR" "OK         GitHub budget ai_credits: amount 0, stop at limit on"
assert_contains "cost: the subscription read is named" "$COST_CLEAR" "INFO       Azure subscription: sub-example (Enabled)"
assert_contains "cost: an Azure budget under its amount and forecast is OK, with the data date and the read time" "$COST_CLEAR" \
  "OK         Azure budget budget-example: spent 1.5, forecast 3.25 (alert above 100), of 100 USD; usage data through 2026-07-19; read 2026-07-20T08:00Z UTC"
assert_contains "cost: private minutes against the included minutes, public repos left out" "$COST_CLEAR" \
  "OK         GitHub Actions minutes 2026-07, private repos: 400 of 3000 minutes included (13%)"
assert_contains "cost: private artifact storage against the month's included GB-hours" "$COST_CLEAR" \
  "OK         GitHub Actions storage 2026-07, private repos: 100 of 1488 GB-hours included (7%)"
assert_contains "cost: org admins are not reported as collaborators; archived repos are not judged" "$COST_CLEAR" \
  "OK         GitHub collaborators: no direct collaborator besides org admins on 2 repos"
assert_contains "cost: a Claude secret on pull_request and a workflow_run without one are clear" "$COST_CLEAR" \
  "OK         GitHub fork-triggered workflows: none reads a _CLAUDE_ secret or passes every secret (2 files on 2 repos)"
assert_contains "cost: a required budget far from its end is OK" "$COST_CLEAR" \
  "OK         Azure budget and anomaly alerts: budget budget-example ends 2030-01-01"
assert_contains "cost: an enabled anomaly alert far from its end is OK" "$COST_CLEAR" \
  "OK         Azure budget and anomaly alerts: anomaly alert anomaly-example ends 2030-01-01"
assert_contains "cost: a workspace's peak day under half its cap is OK" "$COST_CLEAR" \
  "OK         Azure Log Analytics log-example: peak 0.2 GB on 2026-07-10 of a 1 GB daily cap (20%)"
assert_contains "cost: all-Free Defender plans are informational" "$COST_CLEAR" "INFO       Azure Defender plans: 3 plans, all Free"
assert_contains "cost: a Defender cost row at 0 beside another service's charge is OK" "$COST_CLEAR" \
  "OK         Azure Defender charges, month to date: 0 USD"
assert_contains "cost: an unrelated write in the activity log is not an alert" "$COST_CLEAR" \
  "OK         Azure activity, last 24h: no Defender plan, policy assignment or role assignment writes"
assert_contains "cost: the secure score is informational" "$COST_CLEAR" "INFO       Azure secure score: ASC score 30/60"
assert_contains "cost: Advisor security counts are informational" "$COST_CLEAR" "INFO       Azure Advisor security: 0 recommendation(s)"
assert_contains "cost: Advisor cost counts are informational" "$COST_CLEAR" "INFO       Azure Advisor cost: 0 recommendation(s)"
assert_not_contains "cost: an all-clear section carries no ALERT" "$COST_CLEAR" "ALERT"
assert_not_contains "cost: an all-clear brief counts no lost section" "$OUT_COST_CLEAR" "sections unreadable"

ALERT_CONFIG=(--actions-included-minutes 3000 --actions-included-storage-gb 2 --forecast-alert 50
  --required-budgets "under-cap, missing-budget,ending-soon" --anomaly-alert anomaly-example)
cat >"$TMP/billing-usage-alert.json" <<'EOF'
{"usageItems": [
  {"date": "2026-07-01T00:00:00Z", "product": "actions", "sku": "Actions Linux", "unitType": "Minutes", "quantity": 1600, "repositoryName": "app-private", "grossAmount": 5, "discountAmount": 1.544, "netAmount": 3.456},
  {"date": "2026-07-01T00:00:00Z", "product": "actions", "sku": "Actions storage", "unitType": "GigabyteHours", "quantity": 800, "repositoryName": "app-private", "grossAmount": 1, "discountAmount": 1, "netAmount": 0},
  {"date": "2026-07-01T00:00:00Z", "product": "git_lfs", "sku": "Git LFS Storage", "unitType": "GigabyteHours", "quantity": 4, "repositoryName": "app-private", "grossAmount": 0.2, "discountAmount": 0.2, "netAmount": 0}
]}
EOF
cat >"$TMP/billing-budgets-alert.json" <<'EOF'
{"budgets": [
  {"id": "b1", "budget_product_sku": "actions", "budget_amount": 25, "prevent_further_usage": true},
  {"id": "b2", "budget_product_sku": "codespaces", "budget_amount": 0, "prevent_further_usage": false},
  {"id": "b3", "budget_product_sku": "packages", "budget_amount": 0, "prevent_further_usage": true}
], "has_next_page": true}
EOF
cat >"$TMP/org-scan-alert.json" <<'EOF'
{"admins": ["owner-example"], "partial": 0, "repos": [
  {"name": "app-private", "visibility": "private", "archived": false, "collaborators": ["owner-example", "contractor-example"],
   "workflows": [{"path": ".github/workflows/merge.yml", "text": "on:\n  pull_request_target: # reviewed\njobs:\n  t:\n    steps:\n      - env:\n          K: ${{ secrets.EXAMPLE_CLAUDE_KEY }}\n"},
                 {"path": ".github/workflows/after.yml", "text": "on: [workflow_run]\njobs:\n  t:\n    steps:\n      - run: echo ${{ secrets['OTHER_CLAUDE_TOKEN'] }}\n"},
                 {"path": ".github/workflows/commented.yml", "text": "on:\n  push:\n# on: pull_request_target\njobs:\n  t:\n    steps:\n      - run: echo ${{ secrets.THIRD_CLAUDE_KEY }} ${{ github.event.workflow_run.id }}\n"}]}
]}
EOF
jq '.budgets.value = [
      {"name": "at-cap", "properties": {"amount": 50, "currentSpend": {"amount": 50, "unit": "USD"}, "forecastSpend": {"amount": 50, "unit": "USD"},
       "timePeriod": {"endDate": "2030-01-01T00:00:00Z"}}},
      {"name": "under-cap", "properties": {"amount": 50, "currentSpend": {"amount": 49.99, "unit": "USD"}, "forecastSpend": {"amount": 49.99, "unit": "USD"},
       "timePeriod": {"endDate": "2030-01-01T00:00:00Z"}}},
      {"name": "forecast-high", "properties": {"amount": 200, "currentSpend": {"amount": 10, "unit": "USD"}, "forecastSpend": {"amount": 60, "unit": "USD"},
       "timePeriod": {"endDate": "2030-01-01T00:00:00Z"}}},
      {"name": "ending-soon", "properties": {"amount": 200, "currentSpend": {"amount": 1, "unit": "USD"}, "forecastSpend": {"amount": 2, "unit": "USD"},
       "timePeriod": {"endDate": "2026-08-01T00:00:00Z"}}}]
  | .scheduledActions.value[0].properties.status = "Disabled"
  | .workspaces = [{"name": "log-busy", "customerId": "22222222-2222-2222-2222-222222222222", "workspaceCapping": {"dailyQuotaGb": 1.0}},
                   {"name": "log-uncapped", "customerId": "33333333-3333-3333-3333-333333333333", "workspaceCapping": {"dailyQuotaGb": -1}}]
  | .laUsage = {"22222222-2222-2222-2222-222222222222": [{"Day": "2026-07-12T00:00:00Z", "GB": "0.6"}],
                "33333333-3333-3333-3333-333333333333": [{"Day": "2026-07-13T00:00:00Z", "GB": "0.1"}]}
  | .pricings.value[0].pricingTier = "Standard"
  | .defenderCost.properties.rows += [[4.2, "Microsoft Defender for Cloud", "Microsoft Defender for Servers", "USD"],
                                       [1.3, "Other", "Security Center", "USD"]]
  | .activity += [
      {"operationName": {"value": "Microsoft.Authorization/roleAssignments/write"}, "caller": "a@example.invalid", "eventTimestamp": "2026-07-20T01:00:00Z"},
      {"operationName": {"value": "Microsoft.Authorization/roleAssignments/write"}, "caller": "b@example.invalid", "eventTimestamp": "2026-07-20T03:05:00Z"},
      {"operationName": {"value": "microsoft.security/pricings/write"}, "caller": "c@example.invalid", "eventTimestamp": "2026-07-19T23:00:00Z"},
      {"operationName": {"value": "Microsoft.Authorization/policyAssignments/write"}, "caller": "d@example.invalid", "eventTimestamp": "2026-07-19T22:00:00Z"}]' \
  "$TMP/azure-clear.json" >"$TMP/azure-alert.json"
OUT_COST_ALERT="$(cost_brief --billing-usage-json "$TMP/billing-usage-alert.json" --billing-budgets-json "$TMP/billing-budgets-alert.json" \
  --org-scan-json "$TMP/org-scan-alert.json" --azure-json "$TMP/azure-alert.json" "${ALERT_CONFIG[@]}")"
RC_COST_ALERT=$?
COST_ALERT="$(section "$OUT_COST_ALERT" "== Cost")"
assert_exit "cost: an ALERT is data, not a lost section (exit 0)" 0 "$RC_COST_ALERT"
assert_contains "cost: a product charging this month is an ALERT" "$COST_ALERT" "ALERT      GitHub usage 2026-07 actions: net 3.46"
assert_contains "cost: a product at net 0 beside it stays OK" "$COST_ALERT" "OK         GitHub usage 2026-07 git_lfs: net 0"
assert_contains "cost: a budget above 0 is an ALERT" "$COST_ALERT" "ALERT      GitHub budget actions: amount 25, stop at limit on"
assert_contains "cost: a budget that does not stop at its limit is an ALERT" "$COST_ALERT" "ALERT      GitHub budget codespaces: amount 0, stop at limit off"
assert_contains "cost: a zero budget that stops is OK beside them" "$COST_ALERT" "OK         GitHub budget packages: amount 0, stop at limit on"
assert_contains "cost: a budget page that says more follow is PARTIAL" "$COST_ALERT" "PARTIAL: GitHub budgets: more than one page; the rest were not read"
assert_contains "cost: an Azure budget whose spend reached its amount is an ALERT" "$COST_ALERT" \
  "ALERT      Azure budget at-cap: spent 50, forecast 50 (alert above 50), of 50 USD"
assert_contains "cost: an Azure budget a cent under its amount and its forecast threshold is OK" "$COST_ALERT" \
  "OK         Azure budget under-cap: spent 49.99, forecast 49.99 (alert above 50), of 50 USD"
assert_contains "cost: a forecast above --forecast-alert is an ALERT" "$COST_ALERT" \
  "ALERT      Azure budget forecast-high: spent 10, forecast 60 (alert above 50), of 200 USD"
assert_contains "cost: private minutes at half the included amount are an ALERT" "$COST_ALERT" \
  "ALERT      GitHub Actions minutes 2026-07, private repos: 1600 of 3000 minutes included (53%)"
assert_contains "cost: private storage at half the included amount is an ALERT" "$COST_ALERT" \
  "ALERT      GitHub Actions storage 2026-07, private repos: 800 of 1488 GB-hours included (54%)"
assert_contains "cost: a direct collaborator who is not an org admin is an ALERT" "$COST_ALERT" \
  "ALERT      GitHub collaborators: app-private: direct collaborator contractor-example"
assert_contains "cost: a pull_request_target workflow reading a _CLAUDE_ secret is an ALERT" "$COST_ALERT" \
  "ALERT      GitHub fork-triggered workflows: app-private .github/workflows/merge.yml: pull_request_target reads EXAMPLE_CLAUDE_KEY"
assert_contains "cost: a workflow_run workflow reading one by index is an ALERT" "$COST_ALERT" \
  "ALERT      GitHub fork-triggered workflows: app-private .github/workflows/after.yml: workflow_run reads OTHER_CLAUDE_TOKEN"
assert_not_contains "cost: a commented-out trigger or an event expression is not a fork trigger" "$COST_ALERT" "commented.yml"
assert_contains "cost: a required budget that does not exist is an ALERT" "$COST_ALERT" \
  "ALERT      Azure budget and anomaly alerts: budget missing-budget is missing"
assert_contains "cost: a required budget ending within 30 days is an ALERT" "$COST_ALERT" \
  "ALERT      Azure budget and anomaly alerts: budget ending-soon ends 2026-08-01, within 30 days"
assert_contains "cost: a disabled anomaly alert is an ALERT" "$COST_ALERT" \
  "ALERT      Azure budget and anomaly alerts: anomaly alert anomaly-example is Disabled"
assert_contains "cost: a workspace peak at half its cap is an ALERT" "$COST_ALERT" \
  "ALERT      Azure Log Analytics log-busy: peak 0.6 GB on 2026-07-12 of a 1 GB daily cap (60%)"
assert_contains "cost: a workspace with no daily cap is an ALERT" "$COST_ALERT" \
  "ALERT      Azure Log Analytics log-uncapped: no daily cap; peak 0.1 GB on 2026-07-13"
assert_contains "cost: a Defender plan off the Free tier is listed, never an ALERT" "$COST_ALERT" "INFO       Azure Defender plans: not Free: VirtualMachines (Standard)"
assert_contains "cost: Defender and Security Center charges this month are an ALERT" "$COST_ALERT" \
  "ALERT      Azure Defender charges, month to date: 5.5 USD"
assert_contains "cost: role assignment writes are an ALERT with the latest event" "$COST_ALERT" \
  "ALERT      Azure activity, last 24h: Microsoft.Authorization/roleAssignments/write: 2 event(s), latest 2026-07-20T03:05Z UTC by b@example.invalid"
assert_contains "cost: a Defender plan write is matched whatever its case" "$COST_ALERT" \
  "ALERT      Azure activity, last 24h: microsoft.security/pricings/write: 1 event(s)"
assert_contains "cost: a policy assignment write is an ALERT" "$COST_ALERT" \
  "ALERT      Azure activity, last 24h: Microsoft.Authorization/policyAssignments/write: 1 event(s)"
assert_not_contains "cost: an unrelated write stays out of the alerts" "$COST_ALERT" "storageAccounts/write"

cat >"$TMP/billing-403.json" <<'EOF'
{"message": "Must have admin rights to the organization.", "documentation_url": "https://example.invalid/docs", "status": "403"}
EOF
OUT_COST_403="$(cost_brief --billing-usage-json "$TMP/billing-403.json" --billing-budgets-json "$TMP/billing-403.json" \
  --org-scan-json "$TMP/org-scan-clear.json" --azure-json "$TMP/azure-clear.json")"
RC_COST_403=$?
COST_403="$(section "$OUT_COST_403" "== Cost")"
assert_exit "cost 403: a billing read refused for want of an org admin counts the section as lost" 6 "$RC_COST_403"
assert_contains "cost 403: the header counts the cost section" "$OUT_COST_403" "1 of 10 sections unreadable: cost"
assert_contains "cost 403: the usage line is UNREADABLE with the fix" "$COST_403" \
  "UNREADABLE GitHub usage 2026-07: org admin needed: run gh auth login with an org admin account"
assert_contains "cost 403: the minutes line is UNREADABLE too" "$COST_403" \
  "UNREADABLE GitHub Actions minutes 2026-07, private repos: org admin needed: run gh auth login with an org admin account"
assert_contains "cost 403: the storage line is UNREADABLE too" "$COST_403" \
  "UNREADABLE GitHub Actions storage 2026-07, private repos: org admin needed: run gh auth login with an org admin account"
assert_contains "cost 403: the budgets line is UNREADABLE with the fix" "$COST_403" \
  "UNREADABLE GitHub budgets: org admin needed: run gh auth login with an org admin account"
assert_eq "cost 403: no line is SKIPPED" "0" "$(grep -c SKIPPED <<<"$COST_403")"
COST_ARGS=(--azure-json "$TMP/azure-clear.json" --org-scan-json "$TMP/org-scan-clear.json")
OUT_COST_403_LIVE="$(run_stub forbidden --org example --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" --behind-json "$TMP/behind.json" \
  --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
  --lane-runs-json "$TMP/lanes-empty.json")"
RC_COST_403_LIVE=$?
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_exit "cost 403 live: a gh 403 on billing counts the cost section as lost" 6 "$RC_COST_403_LIVE"
assert_contains "cost 403 live: the live refusal reads as a missing org admin" "$(section "$OUT_COST_403_LIVE" "== Cost")" \
  "UNREADABLE GitHub usage 2026-07: org admin needed: run gh auth login with an org admin account"

jq 'del(.account)' "$TMP/azure-clear.json" >"$TMP/azure-no-account.json"
OUT_COST_NOAZ="$(cost_brief --billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" \
  --azure-json "$TMP/azure-no-account.json")"
RC_COST_NOAZ=$?
COST_NOAZ="$(section "$OUT_COST_NOAZ" "== Cost")"
assert_exit "logged out: the cost section counts as lost" 6 "$RC_COST_NOAZ"
assert_eq "logged out: all ten Azure lines are UNREADABLE and name az login" "10" "$(grep -c "^  UNREADABLE Azure .*run az login$" <<<"$COST_NOAZ")"
assert_eq "logged out: no other Azure line prints" "10" "$(grep -c "^  [A-Z]* *Azure" <<<"$COST_NOAZ")"
assert_contains "logged out: the Log Analytics line names az login" "$COST_NOAZ" \
  "UNREADABLE Azure Log Analytics: no account in --azure-json; run az login"
assert_contains "logged out: the GitHub lines still print" "$COST_NOAZ" "OK         GitHub usage 2026-07 actions: net 0"

jq 'del(.pricings)' "$TMP/azure-clear.json" >"$TMP/azure-no-pricings.json"
OUT_COST_ONE="$(cost_brief --billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" \
  --azure-json "$TMP/azure-no-pricings.json")"
RC_COST_ONE=$?
COST_ONE="$(section "$OUT_COST_ONE" "== Cost")"
assert_exit "cost one unreadable: the brief exits 6" 6 "$RC_COST_ONE"
assert_contains "cost one unreadable: the header names the cost section" "$OUT_COST_ONE" "1 of 10 sections unreadable: cost"
assert_contains "cost one unreadable: the failed read is its own UNREADABLE line" "$COST_ONE" "UNREADABLE Azure Defender plans: no pricings in --azure-json"
assert_contains "cost one unreadable: the reads beside it still print" "$COST_ONE" "OK         Azure budget budget-example: spent 1.5, forecast 3.25"
printf '{"usageItems": "not a list"}\n' >"$TMP/billing-usage-bad.json"
COST_BAD="$(section "$(cost_brief --billing-usage-json "$TMP/billing-usage-bad.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" \
  --azure-json "$TMP/azure-clear.json")" "== Cost")"
assert_contains "cost unparsable: a usage response of the wrong shape is UNREADABLE" "$COST_BAD" \
  "UNREADABLE GitHub usage 2026-07: could not parse the billing usage"

OUT_COST_ONLY="$(run_stub blocked)"
RC_COST_ONLY=$?
assert_exit "cost only: a brief whose cost lines read is never exit 5" 6 "$RC_COST_ONLY"
assert_contains "cost only: the header counts the nine lost sections" "$OUT_COST_ONLY" \
  "9 of 10 sections unreadable: queues stuck merge-ready decisions telemetry stranded landed lanes touches"

OUT_FIXTURE_RUN="$(cost_brief)"
RC_FIXTURE_RUN=$?
COST_FIXTURE_RUN="$(section "$OUT_FIXTURE_RUN" "== Cost")"
assert_exit "cost fixture run: an unread cost section exits non-zero" 6 "$RC_FIXTURE_RUN"
assert_contains "cost fixture run: no org is resolved for GitHub billing" "$COST_FIXTURE_RUN" \
  "UNREADABLE GitHub usage 2026-07: no org resolved; pass --org"
assert_eq "cost fixture run: every GitHub line is UNREADABLE" "6" "$(grep -c "^  UNREADABLE GitHub .*: no org resolved; pass --org$" <<<"$COST_FIXTURE_RUN")"
assert_eq "cost fixture run: every Azure line is UNREADABLE" "10" \
  "$(grep -c "^  UNREADABLE Azure .*: not read live in a fixture run; pass --subscription or --azure-json$" <<<"$COST_FIXTURE_RUN")"
assert_eq "cost fixture run: no line is SKIPPED" "0" "$(grep -c SKIPPED <<<"$COST_FIXTURE_RUN")"

COST_LIVE="$TMP/rest-cost"
mkdir -p "$COST_LIVE"
cp "$REST/"*.json "$COST_LIVE/"
cp "$TMP/billing-usage-alert.json" "$COST_LIVE/$(rest_key "orgs/example/settings/billing/usage?year=2026&month=7").json"
cp "$TMP/billing-budgets-alert.json" "$COST_LIVE/$(rest_key "orgs/example/settings/billing/budgets?per_page=100").json"
jq '[.repos[] | {name, visibility, archived, default_branch: "main"}]' "$TMP/org-scan-alert.json" \
  >"$COST_LIVE/$(rest_key "orgs/example/repos?per_page=100&type=all").json"
jq '[.admins[] | {login: .}]' "$TMP/org-scan-alert.json" >"$COST_LIVE/$(rest_key "orgs/example/members?role=admin&per_page=100").json"
while IFS= read -r scan_repo; do
  jq --arg r "$scan_repo" '[.repos[] | select(.name == $r) | .collaborators[] | {login: .}]' "$TMP/org-scan-alert.json" \
    >"$COST_LIVE/$(rest_key "repos/example/$scan_repo/collaborators?affiliation=direct&per_page=100").json"
  jq --arg r "$scan_repo" '[.repos[] | select(.name == $r) | .workflows[] | {name: (.path | sub(".*/"; "")), type: "file"}]' \
    "$TMP/org-scan-alert.json" >"$COST_LIVE/$(rest_key "repos/example/$scan_repo/contents/.github/workflows?ref=main").json"
  while IFS= read -r scan_file; do
    jq -j --arg r "$scan_repo" --arg f "$scan_file" '.repos[] | select(.name == $r) | .workflows[] | select(.path | endswith("/" + $f)) | .text' \
      "$TMP/org-scan-alert.json" >"$COST_LIVE/$(rest_key "repos/example/$scan_repo/contents/.github/workflows/$scan_file?ref=main").json"
  done < <(jq -r --arg r "$scan_repo" '.repos[] | select(.name == $r) | .workflows[].path | sub(".*/"; "")' "$TMP/org-scan-alert.json")
done < <(jq -r '.repos[].name' "$TMP/org-scan-alert.json")
COST_ARGS=("${ALERT_CONFIG[@]}")
OUT_COST_LIVE="$(MB_GH_FIXTURES="$COST_LIVE" MB_AZ_MODE=serve MB_AZ_FIXTURE="$TMP/azure-alert.json" MB_AZ_LOG="$TMP/az-log" run_stub rest)"
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
if [[ "$(section "$OUT_COST_LIVE" "== Cost")" == "$COST_ALERT" ]]; then
  pass "cost live: gh and az reads render the cost section as the fixtures do"
else
  fail "cost live: gh and az reads render the cost section as the fixtures do" "$COST_ALERT" "$(section "$OUT_COST_LIVE" "== Cost")"
fi
AZ_LOG="$(cat "$TMP/az-log")"
assert_eq "cost live: one account read and eleven subscription reads" "12" "$(grep -c . <<<"$AZ_LOG")"
assert_eq "cost live: the one POST is the Cost Management query" \
  "rest --method post --url https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.CostManagement/query?api-version=2023-11-01" \
  "$(grep -- "--method post" <<<"$AZ_LOG" | sed 's/ --body .*//')"
assert_contains "cost live: the query sums month-to-date actual cost by service and meter category" "$AZ_LOG" \
  '--body {"type":"ActualCost","timeframe":"MonthToDate","dataset":{"granularity":"Daily","aggregation":{"cost":{"name":"Cost","function":"Sum"}},"grouping":[{"type":"Dimension","name":"ServiceName"},{"type":"Dimension","name":"MeterCategory"}]}}'
assert_eq "cost live: every read after account show names its subscription" "11" \
  "$(grep -c -- "--subscription 00000000-0000-0000-0000-000000000001 --only-show-errors -o json" <<<"$AZ_LOG")"
assert_contains "cost live: the activity log is read for the last day" "$AZ_LOG" "monitor activity-log list --offset 1d --max-events 1000"
assert_not_contains "cost live: Advisor is never refreshed" "$AZ_LOG" "--refresh"
assert_not_contains "cost live: Resource Graph is never called" "$AZ_LOG" "graph"
assert_contains "cost live: budgets with their forecast are read with a GET" "$AZ_LOG" \
  "rest --method get --url https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Consumption/budgets?api-version=2024-08-01"
assert_contains "cost live: each workspace's Usage table is queried for its peak day" "$AZ_LOG" \
  "monitor log-analytics query --workspace 22222222-2222-2222-2222-222222222222 --analytics-query Usage | where TimeGenerated > ago(31d)"

jq '.pricings.value[0].pricingTier = "Standard" | .defenderCost.properties.rows = [[7, "Storage", "Storage", "USD"]]' \
  "$TMP/azure-clear.json" >"$TMP/azure-plan-no-charge.json"
OUT_PLAN="$(cost_brief --billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" \
  --azure-json "$TMP/azure-plan-no-charge.json")"
COST_PLAN="$(section "$OUT_PLAN" "== Cost")"
assert_exit "defender: a plan off Free with no charge fails nothing" 0 "$(
  cost_brief --billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" \
    --org-scan-json "$TMP/org-scan-clear.json" --azure-json "$TMP/azure-plan-no-charge.json" >/dev/null
  echo $?
)"
assert_contains "defender: the plan off Free is listed as INFO" "$COST_PLAN" "INFO       Azure Defender plans: not Free: VirtualMachines (Standard)"
assert_contains "defender: no Defender cost rows is OK" "$COST_PLAN" "OK         Azure Defender charges, month to date: no Defender cost rows"
assert_not_contains "defender: a plan off Free with no charge raises no ALERT" "$COST_PLAN" "ALERT"
assert_contains "data date: rows with no usage date never read as no usage rows" "$COST_PLAN" \
  "of 100 USD; usage data date unread; read 2026-07-20T08:00Z UTC"
jq '.defenderCost.properties.rows = []' "$TMP/azure-clear.json" >"$TMP/azure-no-rows.json"
assert_contains "data date: a query with no rows says so" "$(section "$(cost_brief --azure-json "$TMP/azure-no-rows.json")" "== Cost")" \
  "of 100 USD; no usage rows this month; read 2026-07-20T08:00Z UTC"

jq '.defenderCost = {"__error": "Too Many Requests(Too many requests. Please retry.)"}' "$TMP/azure-clear.json" >"$TMP/azure-429.json"
COST_ARGS=(--billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json")
OUT_429="$(MB_GH_FIXTURES="$COST_LIVE" MB_AZ_MODE=serve MB_AZ_FIXTURE="$TMP/azure-429.json" run_stub rest)"
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_contains "defender: a throttled cost query is UNREADABLE with the error" "$(section "$OUT_429" "== Cost")" \
  "UNREADABLE Azure Defender charges, month to date: Too Many Requests(Too many requests. Please retry.)"
assert_contains "defender: a throttled query counts the cost section as lost" "$OUT_429" "5 of 10 sections unreadable: stuck stranded landed touches cost"
jq '.defenderCost = {"properties": {"columns": [{"name": "ServiceName"}], "rows": []}}' "$TMP/azure-clear.json" >"$TMP/azure-cost-bad.json"
assert_contains "defender: a cost response without its columns is UNREADABLE" "$(section "$(cost_brief --billing-usage-json "$TMP/billing-usage-clear.json" \
  --billing-budgets-json "$TMP/billing-budgets-clear.json" --azure-json "$TMP/azure-cost-bad.json")" "== Cost")" \
  "UNREADABLE Azure Defender charges, month to date: could not parse the defenderCost response"

jq '.usageItems[1] |= del(.netAmount)' "$TMP/billing-usage-clear.json" >"$TMP/billing-usage-no-net.json"
jq '.budgets.value[0].properties |= del(.currentSpend)' "$TMP/azure-clear.json" >"$TMP/azure-no-spend.json"
COST_MISSING="$(section "$(cost_brief --billing-usage-json "$TMP/billing-usage-no-net.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" \
  --azure-json "$TMP/azure-no-spend.json")" "== Cost")"
assert_contains "fail closed: a usage item with no netAmount is UNREADABLE" "$COST_MISSING" \
  "UNREADABLE GitHub usage 2026-07: could not parse the billing usage"
assert_contains "fail closed: an Azure budget with no currentSpend is UNREADABLE" "$COST_MISSING" \
  "UNREADABLE Azure budgets: could not parse the budgets response"

printf '{"message": "Resource protected by organization SAML enforcement. You must grant your Personal Access token access to this organization.", "documentation_url": "https://example.invalid/docs", "status": "403"}\n' >"$TMP/billing-403-sso.json"
printf '{"message": "API rate limit exceeded for user ID 1.", "documentation_url": "https://example.invalid/docs", "status": "403"}\n' >"$TMP/billing-403-rate.json"
COST_403_OTHER="$(section "$(cost_brief --billing-usage-json "$TMP/billing-403-sso.json" --billing-budgets-json "$TMP/billing-403-rate.json" \
  --azure-json "$TMP/azure-clear.json")" "== Cost")"
assert_contains "403: SAML enforcement is UNREADABLE" "$COST_403_OTHER" \
  "UNREADABLE GitHub usage 2026-07: Resource protected by organization SAML enforcement."
assert_contains "403: a rate limit is UNREADABLE" "$COST_403_OTHER" "UNREADABLE GitHub budgets: API rate limit exceeded for user ID 1."
assert_not_contains "403: neither reads as a missing org admin" "$COST_403_OTHER" "org admin needed"

COST_SUB_FAIL="$(section "$(PATH="$GH_STUB_DIR:$PATH" cost_brief --subscription 00000000-0000-0000-0000-000000000009 \
  --billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json")" "== Cost")"
assert_contains "subscription: a named subscription az cannot read is UNREADABLE" "$COST_SUB_FAIL" \
  "UNREADABLE Azure subscription 00000000-0000-0000-0000-000000000009: Please run 'az login' to setup account."
assert_not_contains "subscription: a named subscription is never skipped" "$COST_SUB_FAIL" "SKIPPED    Azure"

jq 'del(.account)' "$TMP/azure-clear.json" >"$TMP/azure-skip.json"
COST_ARGS=(--billing-usage-json "$TMP/billing-403.json" --billing-budgets-json "$TMP/billing-403.json" --azure-json "$TMP/azure-skip.json")
OUT_ALL_SKIP="$(run_stub blocked)"
RC_ALL_SKIP=$?
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_exit "no data: seven lost sections beside a cost section of UNREADABLE lines exit 5" 5 "$RC_ALL_SKIP"
assert_contains "no data: the refused billing lines carry no data" "$(section "$OUT_ALL_SKIP" "== Cost")" \
  "UNREADABLE GitHub usage 2026-07: org admin needed"

jq '.budgets[1] |= del(.prevent_further_usage)' "$TMP/billing-budgets-clear.json" >"$TMP/billing-budgets-no-stop.json"
jq '.activity += [{"caller": "x@example.invalid", "eventTimestamp": "2000-01-01T00:00:00Z"}]
  | .defenderCost.properties.rows += [[9, null, null, "USD"]]' "$TMP/azure-clear.json" >"$TMP/azure-unclassified.json"
COST_UNCLASSIFIED="$(section "$(cost_brief --billing-usage-json "$TMP/billing-usage-clear.json" \
  --billing-budgets-json "$TMP/billing-budgets-no-stop.json" --azure-json "$TMP/azure-unclassified.json")" "== Cost")"
assert_contains "fail closed: a budget with no prevent_further_usage is UNREADABLE" "$COST_UNCLASSIFIED" \
  "UNREADABLE GitHub budgets: could not parse the billing budgets"
assert_not_contains "fail closed: a missing stop flag never reads as off" "$COST_UNCLASSIFIED" "stop at limit off"
assert_contains "fail closed: an activity event with no operation is UNREADABLE" "$COST_UNCLASSIFIED" \
  "UNREADABLE Azure activity, last 24h: could not parse the activity response"
assert_contains "fail closed: a cost row naming no service or meter category is UNREADABLE" "$COST_UNCLASSIFIED" \
  "UNREADABLE Azure Defender charges, month to date: could not parse the defenderCost response"

jq '.activity += [{"operationName": {"value": ""}, "caller": "x@example.invalid", "eventTimestamp": "2000-01-01T00:00:00Z"}]
  | .defenderCost.properties.rows += [[9, [3, 5, 7], 4, "USD"]]' "$TMP/azure-clear.json" >"$TMP/azure-wrong-types.json"
COST_WRONG_TYPES="$(section "$(cost_brief --billing-usage-json "$TMP/billing-usage-clear.json" \
  --billing-budgets-json "$TMP/billing-budgets-clear.json" --azure-json "$TMP/azure-wrong-types.json")" "== Cost")"
assert_contains "fail closed: a cost row whose names are not strings is UNREADABLE" "$COST_WRONG_TYPES" \
  "UNREADABLE Azure Defender charges, month to date: could not parse the defenderCost response"
assert_not_contains "fail closed: such a row never reads as no Defender cost rows" "$COST_WRONG_TYPES" "no Defender cost rows"
assert_contains "fail closed: an activity event with an empty operation is UNREADABLE" "$COST_WRONG_TYPES" \
  "UNREADABLE Azure activity, last 24h: could not parse the activity response"

NO_AZ_PATH="$TMP/no-az-bin"
mkdir -p "$NO_AZ_PATH"
IFS=: read -ra _path_dirs <<<"$PATH"
for _d in "${_path_dirs[@]}"; do
  for _f in "$_d"/*; do
    [[ "${_f##*/}" != az && -x "$_f" && ! -e "$NO_AZ_PATH/${_f##*/}" ]] && ln -s "$_f" "$NO_AZ_PATH/${_f##*/}"
  done
done
if PATH="$NO_AZ_PATH" command -v az >/dev/null 2>&1; then
  fail "no az: a PATH without az could be built" "az absent" "$(PATH="$NO_AZ_PATH" command -v az)"
else
  COST_NO_AZ_BIN="$(section "$(PATH="$NO_AZ_PATH" cost_brief --org example --org-scan-json "$TMP/org-scan-clear.json" \
    --billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json")" "== Cost")"
  assert_eq "no az: without --subscription every Azure line is UNREADABLE" "10" \
    "$(grep -c "^  UNREADABLE Azure .*: az not installed; install az$" <<<"$COST_NO_AZ_BIN")"
  assert_eq "no az: no Azure line is SKIPPED" "0" "$(grep -c SKIPPED <<<"$COST_NO_AZ_BIN")"
  COST_NO_AZ_SUB="$(section "$(PATH="$NO_AZ_PATH" cost_brief --subscription 00000000-0000-0000-0000-000000000009 \
    --billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json")" "== Cost")"
  assert_contains "no az: with --subscription Azure is UNREADABLE" "$COST_NO_AZ_SUB" \
    "UNREADABLE Azure subscription 00000000-0000-0000-0000-000000000009: az not installed; install az"
  assert_eq "no az: with --subscription every Azure line is UNREADABLE" "10" "$(grep -c "^  UNREADABLE Azure " <<<"$COST_NO_AZ_SUB")"
fi

jq '.account.name = "sub\u001b]0;title\u0007-example\u001b[31m" | .pricings = {"__error": "boom\u001b[2Jcleared"}' \
  "$TMP/azure-clear.json" >"$TMP/azure-escapes.json"
COST_ARGS=(--billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json")
COST_ESC="$(section "$(MB_GH_FIXTURES="$COST_LIVE" MB_AZ_MODE=serve MB_AZ_FIXTURE="$TMP/azure-escapes.json" run_stub rest)" "== Cost")"
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_contains "escapes: the subscription name prints without its control characters" "$COST_ESC" \
  "INFO       Azure subscription: sub ]0;title -example [31m (Enabled)"
assert_contains "escapes: an error message prints without its control characters" "$COST_ESC" \
  "UNREADABLE Azure Defender plans: boom [2Jcleared"
assert_eq "escapes: no ESC or BEL reaches the cost section" "0" "$(grep -c $'[\x1b\x07]' <<<"$COST_ESC")"

jq '.usageItems[1] |= del(.unitType)' "$TMP/billing-usage-clear.json" >"$TMP/billing-usage-no-unit.json"
jq '.budgets.value[0].properties |= del(.forecastSpend) | del(.scheduledActions)
  | .laUsage = {}' "$TMP/azure-clear.json" >"$TMP/azure-new-reads-fail.json"
COST_NEW_FAIL="$(section "$(cost_brief --billing-usage-json "$TMP/billing-usage-no-unit.json" \
  --billing-budgets-json "$TMP/billing-budgets-clear.json" --org-scan-json "$TMP/org-scan-clear.json" \
  --azure-json "$TMP/azure-new-reads-fail.json" --actions-included-minutes 3000)" "== Cost")"
assert_contains "unreadable: an Actions item with no unit makes the minutes line UNREADABLE" "$COST_NEW_FAIL" \
  "UNREADABLE GitHub Actions minutes 2026-07, private repos: could not parse the billing usage"
assert_contains "unreadable: and the storage line" "$COST_NEW_FAIL" \
  "UNREADABLE GitHub Actions storage 2026-07, private repos: could not parse the billing usage"
assert_contains "unreadable: a budget with no forecast is UNREADABLE" "$COST_NEW_FAIL" \
  "UNREADABLE Azure budgets: could not parse the budgets response"
assert_contains "unreadable: no scheduled actions read is UNREADABLE" "$COST_NEW_FAIL" \
  "UNREADABLE Azure budget and anomaly alerts: no scheduledActions in --azure-json"
assert_contains "unreadable: a workspace whose query failed is UNREADABLE by name" "$COST_NEW_FAIL" \
  "UNREADABLE Azure Log Analytics log-example: no laUsage/11111111-1111-1111-1111-111111111111 in --azure-json"
jq 'del(.workspaces)' "$TMP/azure-clear.json" >"$TMP/azure-no-workspaces.json"
assert_contains "unreadable: no workspace list is UNREADABLE" "$(section "$(cost_brief --azure-json "$TMP/azure-no-workspaces.json")" "== Cost")" \
  "UNREADABLE Azure Log Analytics: no workspaces in --azure-json"
printf '{"admins": "owner-example", "repos": []}\n' >"$TMP/org-scan-bad.json"
COST_SCAN_BAD="$(section "$(cost_brief --org-scan-json "$TMP/org-scan-bad.json")" "== Cost")"
assert_contains "unreadable: an org scan of the wrong shape makes both scan lines UNREADABLE" "$COST_SCAN_BAD" \
  "UNREADABLE GitHub collaborators: could not parse the org scan"
assert_contains "unreadable: the workflow line too" "$COST_SCAN_BAD" \
  "UNREADABLE GitHub fork-triggered workflows: could not parse the org scan"
SCAN_FAIL="$TMP/rest-scan-fail"
mkdir -p "$SCAN_FAIL"
cp "$COST_LIVE/"*.json "$SCAN_FAIL/"
rm "$SCAN_FAIL/$(rest_key "repos/example/app-private/collaborators?affiliation=direct&per_page=100").json"
COST_ARGS=(--azure-json "$TMP/azure-clear.json")
COST_SCAN_FAIL="$(section "$(MB_GH_FIXTURES="$SCAN_FAIL" run_stub rest)" "== Cost")"
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_contains "unreadable: a failed collaborator read names the repo" "$COST_SCAN_FAIL" \
  "UNREADABLE GitHub collaborators: app-private collaborators: Not Found (HTTP 404)"
assert_contains "unreadable: the live usage lines still print beside it" "$COST_SCAN_FAIL" \
  "ALERT      GitHub usage 2026-07 actions: net 3.46"

jq -n '{admins: ["owner-example"], partial: 0, repos: [{name: "app-forms", visibility: "private", archived: false, collaborators: [],
  workflows: [
    {path: ".github/workflows/flow-seq.yml", text: "on: [\"pull_request_target\"]\njobs:\n  t:\n    steps:\n      - run: echo ${{ secrets.SEQ_CLAUDE_KEY }}\n"},
    {path: ".github/workflows/flow-map.yml", text: "on: {pull_request_target: {}}\njobs:\n  t:\n    steps:\n      - run: echo ${{ secrets.MAP_CLAUDE_KEY }}\n"},
    {path: ".github/workflows/quoted-key.yml", text: "on:\n  \"pull_request_target\":\n    types: [opened]\njobs:\n  t:\n    steps:\n      - run: echo ${{ secrets.QUOTED_CLAUDE_KEY }}\n"},
    {path: ".github/workflows/inherit.yml", text: "on: pull_request_target\njobs:\n  call:\n    uses: example/shared/.github/workflows/review.yml@main\n    secrets: inherit\n"},
    {path: ".github/workflows/tojson.yml", text: "on:\n  workflow_run:\n    workflows: [ci]\njobs:\n  t:\n    steps:\n      - run: echo \u0027${{ toJSON(secrets) }}\u0027\n"},
    {path: ".github/workflows/computed.yml", text: "on: pull_request_target\njobs:\n  t:\n    steps:\n      - run: echo ${{ secrets[format(\u0027{0}_KEY\u0027, matrix.p)] }}\n"},
    {path: ".github/workflows/inherit-dq.yml", text: "on: pull_request_target\njobs:\n  call:\n    uses: example/shared/.github/workflows/review.yml@main\n    secrets: \"inherit\"\n"},
    {path: ".github/workflows/inherit-sq.yml", text: "on: pull_request_target\njobs:\n  call:\n    uses: example/shared/.github/workflows/review.yml@main\n    secrets: \u0027inherit\u0027 # all of them\n"},
    {path: ".github/workflows/comment-scalar.yml", text: "on: pull_request_target # forks\njobs:\n  call:\n    uses: example/shared/.github/workflows/review.yml@main\n    secrets: inherit # all of them\n"},
    {path: ".github/workflows/comment-list.yml", text: "on:\n  - pull_request_target   # forks\njobs:\n  t:\n    steps:\n      - run: echo ${{ secrets.LIST_CLAUDE_KEY }} # note\n"},
    {path: ".github/workflows/inherit-pr.yml", text: "on: pull_request\njobs:\n  call:\n    uses: example/shared/.github/workflows/review.yml@main\n    secrets: inherit\n"},
    {path: ".github/workflows/plain-index.yml", text: "on: pull_request_target\njobs:\n  t:\n    steps:\n      - run: echo ${{ secrets[\u0027PLAIN_TOKEN\u0027] }}\n"}]}]}' >"$TMP/org-scan-forms.json"
COST_FORMS="$(section "$(cost_brief --org-scan-json "$TMP/org-scan-forms.json" --azure-json "$TMP/azure-clear.json")" "== Cost")"
assert_contains "fork forms: a quoted event in a flow sequence is a fork trigger" "$COST_FORMS" \
  "ALERT      GitHub fork-triggered workflows: app-forms .github/workflows/flow-seq.yml: pull_request_target reads SEQ_CLAUDE_KEY"
assert_contains "fork forms: an event key in a flow mapping is a fork trigger" "$COST_FORMS" \
  "ALERT      GitHub fork-triggered workflows: app-forms .github/workflows/flow-map.yml: pull_request_target reads MAP_CLAUDE_KEY"
assert_contains "fork forms: a quoted block key is a fork trigger" "$COST_FORMS" \
  "ALERT      GitHub fork-triggered workflows: app-forms .github/workflows/quoted-key.yml: pull_request_target reads QUOTED_CLAUDE_KEY"
assert_contains "fork forms: a reusable-workflow call with secrets: inherit passes every secret" "$COST_FORMS" \
  "ALERT      GitHub fork-triggered workflows: app-forms .github/workflows/inherit.yml: pull_request_target reads every secret (secrets: inherit)"
assert_contains "fork forms: a double-quoted inherit passes every secret" "$COST_FORMS" \
  "ALERT      GitHub fork-triggered workflows: app-forms .github/workflows/inherit-dq.yml: pull_request_target reads every secret (secrets: inherit)"
assert_contains "fork forms: a single-quoted inherit with a comment passes every secret" "$COST_FORMS" \
  "ALERT      GitHub fork-triggered workflows: app-forms .github/workflows/inherit-sq.yml: pull_request_target reads every secret (secrets: inherit)"
assert_contains "fork forms: a scalar event with a trailing comment is a fork trigger" "$COST_FORMS" \
  "ALERT      GitHub fork-triggered workflows: app-forms .github/workflows/comment-scalar.yml: pull_request_target reads every secret (secrets: inherit)"
assert_contains "fork forms: a list event with a trailing comment is a fork trigger" "$COST_FORMS" \
  "ALERT      GitHub fork-triggered workflows: app-forms .github/workflows/comment-list.yml: pull_request_target reads LIST_CLAUDE_KEY"
assert_contains "fork forms: toJSON(secrets) passes every secret" "$COST_FORMS" \
  "ALERT      GitHub fork-triggered workflows: app-forms .github/workflows/tojson.yml: workflow_run reads every secret (toJSON(secrets))"
assert_contains "fork forms: a computed secrets index can read any secret" "$COST_FORMS" \
  "ALERT      GitHub fork-triggered workflows: app-forms .github/workflows/computed.yml: pull_request_target reads a secret by computed name (secrets[...])"
assert_not_contains "fork forms: secrets: inherit on pull_request is not a fork trigger" "$COST_FORMS" "inherit-pr.yml"
assert_not_contains "fork forms: a literal index without _CLAUDE_ keeps the name filter" "$COST_FORMS" "plain-index.yml"
assert_not_contains "fork forms: no OK line beside the alerts" "$COST_FORMS" "OK         GitHub fork-triggered workflows"

printf '{"admins": ["owner-example"], "partial": 0, "repos": []}\n' >"$TMP/org-scan-empty.json"
COST_SCAN_EMPTY="$(section "$(cost_brief --org-scan-json "$TMP/org-scan-empty.json" --azure-json "$TMP/azure-clear.json")" "== Cost")"
assert_contains "scan counts: no repo listed makes the collaborators line UNREADABLE" "$COST_SCAN_EMPTY" \
  "UNREADABLE GitHub collaborators: the org scan listed 0 repos; check that gh auth status can read the org's repos"
assert_contains "scan counts: and the workflows line" "$COST_SCAN_EMPTY" \
  "UNREADABLE GitHub fork-triggered workflows: the org scan listed 0 repos; check that gh auth status can read the org's repos"
assert_not_contains "scan counts: no repo listed is never OK" "$COST_SCAN_EMPTY" "OK         GitHub collaborators"
jq '.partial = 4' "$TMP/org-scan-clear.json" >"$TMP/org-scan-capped.json"
COST_SCAN_CAPPED="$(section "$(cost_brief --org-scan-json "$TMP/org-scan-capped.json" --azure-json "$TMP/azure-clear.json")" "== Cost")"
assert_contains "scan counts: a capped workflow read is UNREADABLE with its counts" "$COST_SCAN_CAPPED" \
  "UNREADABLE GitHub fork-triggered workflows: read 2 workflow files on 2 repos; 4 more not read (raise --workflow-read-limit)"
assert_not_contains "scan counts: a capped workflow read is never OK" "$COST_SCAN_CAPPED" "OK         GitHub fork-triggered workflows"

jq '.defenderCost.properties.nextLink = "https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.CostManagement/Query?api-version=2023-11-01&$skiptoken=2"
  | .defenderCost_2 = {properties: {nextLink: null, columns: .defenderCost.properties.columns,
      rows: [[3, "Microsoft Defender for Cloud", "Microsoft Defender for Servers", "USD", 20260720]]}}' \
  "$TMP/azure-clear.json" >"$TMP/azure-paged.json"
COST_PAGED="$(section "$(cost_brief --azure-json "$TMP/azure-paged.json")" "== Cost")"
assert_contains "pages: a charge on the cost query's second page is read" "$COST_PAGED" \
  "ALERT      Azure Defender charges, month to date: 3 USD"
assert_contains "pages: the data date comes from every page" "$COST_PAGED" "; usage data through 2026-07-20; read 2026-07-20T08:00Z UTC"
COST_ARGS=(--billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" --org-scan-json "$TMP/org-scan-clear.json")
: >"$TMP/az-log-paged"
COST_PAGED_LIVE="$(section "$(MB_GH_FIXTURES="$COST_LIVE" MB_AZ_MODE=serve MB_AZ_FIXTURE="$TMP/azure-paged.json" MB_AZ_LOG="$TMP/az-log-paged" run_stub rest)" "== Cost")"
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_contains "pages live: the next page is read with az" "$COST_PAGED_LIVE" "ALERT      Azure Defender charges, month to date: 3 USD"
assert_eq "pages live: one POST per page" "2" "$(grep -c -- "rest --method post" "$TMP/az-log-paged")"
Q_URL="https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.CostManagement/query?api-version=2023-11-01"
BAD_NEXT=(
  "vm-start=https://management.azure.com/subscriptions/00000000-0000-0000-0000-000000000001/providers/Microsoft.Compute/virtualMachines/vm/start?api-version=2024-07-01&\$skiptoken=2"
  "traversal=${Q_URL/query\?/query/../../Microsoft.Compute/virtualMachines/vm/start?}&\$skiptoken=2"
  "double-slash=${Q_URL/providers\//providers//}&\$skiptoken=2"
  "backslash=$Q_URL&x=\\evil&\$skiptoken=2"
  "encoded-dot=${Q_URL/query\?/query%2F%2E%2E%2fstart?}&\$skiptoken=2"
  "newline=$Q_URL&x=1"$'\n'"https://management.azure.com/start&\$skiptoken=2"
  "other-host=https://attacker.example.invalid/query?\$skiptoken=2"
)
for _bad in "${BAD_NEXT[@]}"; do
  jq --arg n "${_bad#*=}" '.defenderCost.properties.nextLink = $n' "$TMP/azure-paged.json" >"$TMP/azure-paged-bad.json"
  COST_BAD_NEXT="$(section "$(cost_brief --azure-json "$TMP/azure-paged-bad.json")" "== Cost")"
  assert_contains "pages: a next page that is not the query endpoint is never read (${_bad%%=*})" "$COST_BAD_NEXT" \
    "UNREADABLE Azure Defender charges, month to date: the cost query's next page is not the query endpoint; it was not read"
done
assert_contains "pages: the budget line still prints, its data date unread" "$COST_BAD_NEXT" \
  "of 100 USD; usage data date unread; read 2026-07-20T08:00Z UTC"
jq --arg n "$Q_URL&\$skiptoken=AB%2FC%2BD%3D" \
  '.defenderCost.properties.nextLink = $n | .["defenderCost_AB%2FC%2BD%3D"] = .defenderCost_2' \
  "$TMP/azure-paged.json" >"$TMP/azure-paged-token.json"
COST_ARGS=(--billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" --org-scan-json "$TMP/org-scan-clear.json")
: >"$TMP/az-log-token"
COST_TOKEN_LIVE="$(section "$(MB_GH_FIXTURES="$COST_LIVE" MB_AZ_MODE=serve MB_AZ_FIXTURE="$TMP/azure-paged-token.json" MB_AZ_LOG="$TMP/az-log-token" run_stub rest)" "== Cost")"
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_contains "pages live: a skiptoken with encoded / + = is followed" "$COST_TOKEN_LIVE" "ALERT      Azure Defender charges, month to date: 3 USD"
assert_eq "pages live: a skiptoken with encoded / + = gets one POST per page" "2" "$(grep -c -- "rest --method post" "$TMP/az-log-token")"
jq --arg n "${Q_URL/subscriptions/subscr$'\xc4\xb0'ptions}&\$skiptoken=2" '.defenderCost.properties.nextLink = $n' \
  "$TMP/azure-paged.json" >"$TMP/azure-paged-nonascii.json"
COST_NONASCII="$(section "$(LC_ALL=C.UTF-8 cost_brief --azure-json "$TMP/azure-paged-nonascii.json")" "== Cost")"
assert_contains "pages: a next page with a non-ASCII byte is never read" "$COST_NONASCII" \
  "UNREADABLE Azure Defender charges, month to date: the cost query's next page is not the query endpoint; it was not read"

cost_brief --org 'bad/org' >/dev/null
assert_exit "validation: an --org that is not a GitHub owner name exits 3" 3 "$?"
cost_brief --usage-alert-percent 150 >/dev/null
assert_exit "validation: a --usage-alert-percent above 100 exits 3" 3 "$?"
cost_brief --log-cap-alert-percent 101 >/dev/null
assert_exit "validation: a --log-cap-alert-percent above 100 exits 3" 3 "$?"
cost_brief --usage-alert-percent 100 "${CLEAR_COST_ARGS[@]}" >/dev/null
assert_exit "validation: a percent of 100 is accepted" 0 "$?"

if have git; then
  CFG="$TMP/cfg-repo"
  mkdir -p "$CFG/docs/conventions"
  git -C "$CFG" init -q 2>/dev/null
  cat >"$CFG/docs/conventions/work-items.yaml" <<'EOF'
ai_disclaimer: false
work_priority_order:
  - "priority: high"
  - "priority: low"
tracker:
  schema_version: "1.0"
  provider: github
  config:
    lease_ttl_hours: 4
morning_brief:
  org: team-org
  actions_included_minutes: 3000
  actions_included_storage_gb: 2
  usage_alert_percent: 10
  forecast_alert: 50
  required_budgets:
    - budget-example
  anomaly_alert: anomaly-example
  expiry_days: 30
EOF
  CFG_BRIEF=(--now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" --behind-json "$TMP/behind.json"
    --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json"
    --lane-runs-json "$TMP/lanes-empty.json" --billing-usage-json "$TMP/billing-usage-clear.json"
    --billing-budgets-json "$TMP/billing-budgets-clear.json" --org-scan-json "$TMP/org-scan-clear.json" --azure-json "$TMP/azure-clear.json")
  COST_TEAM="$(section "$(cd "$CFG" && bash "$BRIEF" "${CFG_BRIEF[@]}" 2>&1)" "== Cost")"
  assert_contains "settings: the team file's values apply" "$COST_TEAM" \
    "ALERT      GitHub Actions minutes 2026-07, private repos: 400 of 3000 minutes included (13%)"
  assert_contains "settings: a team list applies" "$COST_TEAM" \
    "OK         Azure budget and anomaly alerts: budget budget-example ends 2030-01-01"
  assert_contains "settings: the layer of each value is reported" "$COST_TEAM" \
    "settings: org=team-org (work-items.yaml) actions_included_minutes=3000 (work-items.yaml)"
  cat >"$CFG/docs/conventions/work-items.local.yaml" <<'EOF'
morning_brief:
  usage_alert_percent: 90
  actions_included_minutes: lots
EOF
  OUT_LOCAL="$(cd "$CFG" && bash "$BRIEF" "${CFG_BRIEF[@]}" 2>&1)"
  COST_LOCAL="$(section "$OUT_LOCAL" "== Cost")"
  assert_contains "settings: the personal file beats the team file" "$COST_LOCAL" \
    "OK         GitHub Actions storage 2026-07, private repos: 100 of 1488 GB-hours included (7%)"
  assert_contains "settings: an invalid personal value is named" "$OUT_LOCAL" \
    "morning-brief: work-items.local.yaml: morning_brief.actions_included_minutes has an invalid value (lots); the default is used"
  assert_contains "settings: an invalid value takes the default, never the team file's" "$COST_LOCAL" \
    "INFO       GitHub Actions minutes 2026-07, private repos: 400 minutes used; included amount not configured"
  COST_FLAG="$(section "$(cd "$CFG" && bash "$BRIEF" "${CFG_BRIEF[@]}" --usage-alert-percent 5 --actions-included-minutes 4000 2>&1)" "== Cost")"
  assert_contains "settings: a flag beats both files" "$COST_FLAG" \
    "ALERT      GitHub Actions minutes 2026-07, private repos: 400 of 4000 minutes included (10%)"
  assert_contains "settings: a flag is reported with its value as the flag" "$COST_FLAG" "usage_alert_percent=5 (flag)"
  printf 'morning_brief:\n  org: [unclosed\n' >"$CFG/docs/conventions/work-items.local.yaml"
  OUT_BROKEN="$(cd "$CFG" && bash "$BRIEF" "${CFG_BRIEF[@]}" 2>&1)"
  assert_contains "settings: a file that cannot be parsed is named and skipped" "$OUT_BROKEN" \
    "work-items.local.yaml could not be parsed"
  assert_contains "settings: the team file still applies beside it" "$(section "$OUT_BROKEN" "== Cost")" \
    "of 3000 minutes included"
  rm "$CFG/docs/conventions/work-items.local.yaml"
  printf 'morning_brief:\n  actions_included_minutes: 9999\n' >"$TMP/cfg-outside.yaml"
  ln -s "$TMP/cfg-outside.yaml" "$CFG/docs/conventions/work-items.local.yaml"
  OUT_LINK="$(cd "$CFG" && bash "$BRIEF" "${CFG_BRIEF[@]}" 2>&1)"
  assert_contains "settings: a symlinked layer is named and skipped" "$OUT_LINK" "work-items.local.yaml is a symlink; that layer is skipped"
  assert_not_contains "settings: a symlinked layer's target is never read" "$(section "$OUT_LINK" "== Cost")" "of 9999 minutes included"
  rm "$CFG/docs/conventions/work-items.local.yaml"
  printf 'morning_brief:\n  required_budgets: budget-example\n' >"$TMP/cfg-scalar.yaml"
  mkdir -p "$TMP/cfg-home"
  cp "$TMP/cfg-scalar.yaml" "$TMP/cfg-home/work-items.yaml"
  OUT_SCALAR="$(bash "$BRIEF" "${CFG_BRIEF[@]}" --config-home "$TMP/cfg-home" 2>&1)"
  assert_contains "settings: a list key given a scalar is invalid" "$OUT_SCALAR" \
    "morning_brief.required_budgets has an invalid value"
  assert_contains "settings: --config-home names the home" "$(section "$(bash "$BRIEF" "${CFG_BRIEF[@]}" --config-home "$CFG/docs/conventions" 2>&1)" "== Cost")" \
    "settings: org=team-org (work-items.yaml)"
  OUT_BARE="$(cd "${BRIEF%/*}" && bash "${BRIEF##*/}" "${CFG_BRIEF[@]}" --config-home "$CFG/docs/conventions" 2>&1)"
  assert_contains "settings: a bare-filename run reads the team file" "$(section "$OUT_BARE" "== Cost")" \
    "settings: org=team-org (work-items.yaml)"
  assert_not_contains "settings: a bare-filename run parses the team file" "$OUT_BARE" "could not be parsed"
  assert_contains "settings: outside a checkout no file is read" "$(section "$(bash "$BRIEF" "${CFG_BRIEF[@]}" 2>&1)" "== Cost")" \
    "settings: defaults (no morning_brief cost key in work-items.yaml or work-items.local.yaml)"
  NET_BIN="$TMP/net-bin"
  mkdir -p "$NET_BIN"
  for _tool in gh az; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >>"%s"\nexit 1\n' "$_tool" "$TMP/net-log" >"$NET_BIN/$_tool"
    chmod +x "$NET_BIN/$_tool"
  done
  printf 'morning_brief:\n  org: team-org\n  subscription: 00000000-0000-0000-0000-000000000009\n' >"$TMP/cfg-net.yaml"
  mkdir -p "$TMP/cfg-net"
  cp "$TMP/cfg-net.yaml" "$TMP/cfg-net/work-items.yaml"
  : >"$TMP/net-log"
  OUT_NET="$(PATH="$NET_BIN:$PATH" bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" --behind-json "$TMP/behind.json" \
    --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
    --lane-runs-json "$TMP/lanes-empty.json" --config-home "$TMP/cfg-net" 2>&1)"
  assert_eq "settings: a team-file org and subscription make no gh or az call in a fixture run" "" "$(cat "$TMP/net-log")"
  assert_contains "settings: the GitHub lines say the run was not live" "$(section "$OUT_NET" "== Cost")" \
    "UNREADABLE GitHub usage 2026-07: not read live in a fixture run; pass --org or the billing and org-scan fixtures"
  printf 'morning_brief:\n  org: "bad org;x"\n  log_cap_alert_percent: 101\n' >"$TMP/cfg-net/work-items.yaml"
  OUT_BAD_VALUES="$(bash "$BRIEF" "${CFG_BRIEF[@]}" --config-home "$TMP/cfg-net" 2>&1)"
  assert_contains "settings: an org that is not a GitHub owner name is invalid" "$OUT_BAD_VALUES" \
    "morning_brief.org has an invalid value"
  assert_contains "settings: a percent above 100 is invalid" "$OUT_BAD_VALUES" \
    "morning_brief.log_cap_alert_percent has an invalid value"
  printf 'morning_brief:\n  "org\033[2J":1\n' >"$TMP/cfg-net/work-items.yaml"
  OUT_ESC_KEY="$(bash "$BRIEF" "${CFG_BRIEF[@]}" --config-home "$TMP/cfg-net" 2>&1)"
  assert_contains "settings: a parse error quoting a key is reported" "$OUT_ESC_KEY" "work-items.yaml could not be parsed"
  assert_eq "settings: no ESC from a key reaches the terminal" "0" "$(grep -c $'\x1b' <<<"$OUT_ESC_KEY")"
  mkdir -p "$TMP/cfg-decision"
  printf 'tracker:\n  config:\n    role_labels:\n      owner-decision: awaiting-owner\n' >"$TMP/cfg-decision/work-items.yaml"
  assert_contains "decision label: the binding's owner-decision role label names it" \
    "$(bash "$BRIEF" "${CFG_BRIEF[@]}" --config-home "$TMP/cfg-decision" 2>&1)" \
    "== Parked decisions (awaiting-owner) with RECOMMENDED lines =="
  assert_contains "decision label: the flag beats the binding" \
    "$(bash "$BRIEF" "${CFG_BRIEF[@]}" --config-home "$TMP/cfg-decision" --decision-label decide 2>&1)" \
    "== Parked decisions (decide) with RECOMMENDED lines =="
fi

MODEL_JSON='{"field-id": "48484079",
  "options": {"1": "needs-triage", "2": "needs-owner-decision", "3": "ready", "4": "agent-ready", "5": "needs-human", "6": "confirmed"},
  "labels": {"needs-triage": ["needs-triage"], "needs-owner-decision": ["needs-owner-decision"],
             "ready": ["status: ready"], "agent-ready": ["agent-ready"], "needs-human": ["needs-human"], "confirmed": ["status: confirmed"]}}'
cat >"$TMP/status-pages.json" <<'EOF'
[{"data": {"repository": {"issues": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [
  {"number": 401, "title": "ready over triage", "url": "http://x/i/401", "labels": {"nodes": [{"name": "needs-triage"}]},
   "issueFieldValues": {"pageInfo": {"hasNextPage": false}, "nodes": [{"name": "ready", "field": {"fullDatabaseId": "48484079"}}, {"name": "High", "field": {"fullDatabaseId": "999"}}]},
   "labelEvents": {"nodes": [{"__typename": "LabeledEvent", "createdAt": "2026-06-30T00:00:00Z", "label": {"name": "needs-triage"}}]},
   "fieldEvents": {"nodes": [
     {"__typename": "IssueFieldAddedEvent", "createdAt": "2026-06-30T00:00:00Z", "value": "High", "actor": {"__typename": "User", "login": "op-user"}, "issueField": {"fullDatabaseId": "999"}},
     {"__typename": "IssueFieldChangedEvent", "createdAt": "2026-07-01T00:00:00Z", "previousValue": "needs-triage", "newValue": "ready", "actor": {"__typename": "Bot", "login": "lanes-app"}, "issueField": {"fullDatabaseId": "48484079"}}]}},
  {"number": 402, "title": "held on the field", "url": "http://x/i/402", "labels": {"nodes": []},
   "issueFieldValues": {"pageInfo": {"hasNextPage": false}, "nodes": [{"name": "needs-human", "field": {"fullDatabaseId": "48484079"}}]},
   "labelEvents": {"nodes": []},
   "fieldEvents": {"nodes": [{"__typename": "IssueFieldAddedEvent", "createdAt": "2026-07-10T08:00:00Z", "value": "needs-human", "actor": {"__typename": "User", "login": "op-user"}, "issueField": {"fullDatabaseId": "48484079"}}]}},
  {"number": 403, "title": "held on the label", "url": "http://x/i/403", "labels": {"nodes": [{"name": "needs-human"}]},
   "issueFieldValues": {"pageInfo": {"hasNextPage": false}, "nodes": [{"name": "confirmed", "field": {"fullDatabaseId": "48484079"}}]},
   "labelEvents": {"nodes": [{"__typename": "LabeledEvent", "createdAt": "2026-07-05T08:00:00Z", "label": {"name": "needs-human"}}]},
   "fieldEvents": {"nodes": []}},
  {"number": 404, "title": "agent-ready", "url": "http://x/i/404", "labels": {"nodes": [{"name": "agent-ready"}, {"name": "status: ready"}]},
   "issueFieldValues": {"pageInfo": {"hasNextPage": false}, "nodes": [{"name": "agent-ready", "field": {"fullDatabaseId": "48484079"}}]},
   "labelEvents": {"nodes": []}, "fieldEvents": {"nodes": []}},
  {"number": 405, "title": "label only", "url": "http://x/i/405", "labels": {"nodes": [{"name": "needs-triage"}]},
   "issueFieldValues": {"pageInfo": {"hasNextPage": false}, "nodes": []},
   "labelEvents": {"nodes": []}, "fieldEvents": {"nodes": []}},
  {"number": 406, "title": "parked on the field", "url": "http://x/i/406", "labels": {"nodes": []},
   "body": "Which store?\nRECOMMENDED: the field-only option.", "comments": [],
   "issueFieldValues": {"pageInfo": {"hasNextPage": false}, "nodes": [{"name": "needs-owner-decision", "field": {"fullDatabaseId": "48484079"}}]},
   "labelEvents": {"nodes": []},
   "fieldEvents": {"nodes": [{"__typename": "IssueFieldAddedEvent", "createdAt": "2026-07-18T08:00:00Z", "value": "needs-owner-decision", "actor": {"__typename": "User", "login": "op-user"}, "issueField": {"fullDatabaseId": "48484079"}}]}},
  {"number": 407, "title": "parked on the label", "url": "http://x/i/407", "labels": {"nodes": [{"name": "needs-owner-decision"}]},
   "issueFieldValues": {"pageInfo": {"hasNextPage": false}, "nodes": [{"name": "confirmed", "field": {"fullDatabaseId": "48484079"}}]},
   "labelEvents": {"nodes": [{"__typename": "LabeledEvent", "createdAt": "2026-07-12T08:00:00Z", "label": {"name": "needs-owner-decision"}}]},
   "fieldEvents": {"nodes": []}}
]}}}}]
EOF
jq -n --argjson m "$MODEL_JSON" --slurpfile p "$TMP/status-pages.json" '{model: $m, pages: $p[0]}' >"$TMP/status.json"
cat >"$TMP/decisions-407.json" <<'EOF'
[{"number": 407, "title": "parked on the label", "url": "http://x/i/407", "body": "RECOMMENDED: the labeled option.", "comments": []}]
EOF

run_status() {
  bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/empty.json" \
    --decisions-json "$TMP/decisions-407.json" --telemetry-json "$TMP/empty.json" --merged-json "$TMP/merged-clean.json" \
    --lane-runs-json "$TMP/lanes-empty.json" "${CLEAR_COST_ARGS[@]}" --stuck-json "$TMP/stuck.json" \
    --touch-json "$TMP/touch-empty.json" --status-json "$TMP/status.json" "$@" 2>&1
}
OUT_STATUS="$(run_status)"
assert_exit "status: a fully fixtured brief with a model exits 0" 0 "$?"
STATUS_Q="$(section "$OUT_STATUS" "== Queues")"
assert_contains "status: a field value moves an issue off its queue label" "$STATUS_Q" "  needs-triage             1"
assert_contains "status: ready over a needs-triage label; agent-ready leaves status: ready" "$STATUS_Q" "  status: ready            1"
assert_contains "status: a field-only decision and a labeled one both count" "$STATUS_Q" "  needs-owner-decision     2"
assert_contains "status: a hold on the field and a hold label both count" "$STATUS_Q" "  needs-human              2"
assert_not_contains "status: the model replaces --counts-json" "$STATUS_Q" "44"

STATUS_S="$(section "$OUT_STATUS" "== Stuck")"
assert_contains "status stuck: days in stage from the field event that set the state" "$STATUS_S" \
  "  #401 issue  ready over triage  (status: ready, 19d in stage)"
assert_contains "status stuck: a field-only hold is stuck under its label" "$STATUS_S" "  #402 issue  held on the field  (needs-human, 10d in stage)"
assert_contains "status stuck: a hold label keeps its own age" "$STATUS_S" "  #403 issue  held on the label  (needs-human, 15d in stage)"
assert_contains "status stuck: an issue with no event is days unknown" "$STATUS_S" "  #405 issue  label only  (needs-triage, days unknown)"
assert_contains "status stuck: the label search keeps its pull requests" "$STATUS_S" "  #204 PR  boundary item  (needs-human, 8d in stage)"
assert_eq "status stuck: oldest first; the search's issues give way to the status read" "#401#403#402#204#407#405" "$(stuck_order "$STATUS_S")"

STATUS_P="$(section "$OUT_STATUS" "== Parked")"
assert_contains "status parked: the labeled decision stays" "$STATUS_P" "#407 parked on the label"
assert_contains "status parked: a decision only on the field joins" "$STATUS_P" "#406 parked on the field"
assert_contains "status parked: the field-only decision carries its RECOMMENDED line" "$STATUS_P" "RECOMMENDED: the field-only option."

jq '{model, pages: [.pages[0] | .data.repository.issues.nodes |= [.[] | select(.number == 402)]]}' "$TMP/status.json" >"$TMP/status-held.json"
assert_contains "status: an issue held only on the field is a needs-human row of 1" \
  "$(section "$(run_status --status-json "$TMP/status-held.json")" "== Queues")" "  needs-human              1"

jq '{model, pages: [.pages[0] | .data.repository.issues.nodes |= ([.[] | select(.number == 405)][0] as $n
     | [$n + {subIssuesSummary: {total: 2, completed: 0}}, $n + {number: 408}, $n + {number: 409}])]}' \
  "$TMP/status.json" >"$TMP/status-parents.json"
STATUS_PARENTS_Q="$(section "$(run_status --status-json "$TMP/status-parents.json")" "== Queues")"
assert_contains "status parents: one parent and two open children count 2, the parent listed beside them" "$STATUS_PARENTS_Q" \
  "$(printf '  %-24s %s' needs-triage '2 (+1 with open sub-issues)')"
assert_not_contains "status parents: the parent is not in the count" "$STATUS_PARENTS_Q" "$(printf '  %-24s %s' needs-triage 3)"
jq '.pages[0].data.repository.issues.nodes[0].subIssuesSummary.completed = 2' "$TMP/status-parents.json" >"$TMP/status-parents-done.json"
assert_contains "status parents: a parent whose sub-issues are all completed counts as an open item" \
  "$(section "$(run_status --status-json "$TMP/status-parents-done.json")" "== Queues")" "$(printf '  %-24s %s' needs-triage 3)"

printf '{"model": null, "pages": []}\n' >"$TMP/status-none.json"
assert_eq "status: no model renders exactly as no --status-json" \
  "$(run_status --status-json "$TMP/status-none.json")" \
  "$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/empty.json" \
    --decisions-json "$TMP/decisions-407.json" --telemetry-json "$TMP/empty.json" --merged-json "$TMP/merged-clean.json" \
    --lane-runs-json "$TMP/lanes-empty.json" "${CLEAR_COST_ARGS[@]}" --stuck-json "$TMP/stuck.json" \
    --touch-json "$TMP/touch-empty.json" 2>&1)"

jq '.pages[0].data.repository.issues.nodes[0].issueFieldValues.nodes[0].name = "bogus"' "$TMP/status.json" >"$TMP/status-unmapped.json"
OUT_UNMAPPED="$(run_status --status-json "$TMP/status-unmapped.json")"
assert_exit "status: an unmapped value exits 6" 6 "$?"
assert_contains "status: a value the model has no option for is UNREADABLE" "$(section "$OUT_UNMAPPED" "== Queues")" \
  "UNREADABLE: Work status: #401: Work status \`bogus\` is no option of the model"
jq '.pages[0].data.repository.issues.nodes[1].fieldEvents.nodes[0].value = "bogus"' "$TMP/status.json" >"$TMP/status-unmapped-event.json"
assert_contains "status: a field event the model has no option for is UNREADABLE" \
  "$(section "$(run_status --status-json "$TMP/status-unmapped-event.json")" "== Stuck")" "UNREADABLE: Work status: #402:"
jq '.pages = [{errors: [{message: "boom status"}]}]' "$TMP/status.json" >"$TMP/status-error.json"
OUT_STATUS_ERR="$(run_status --status-json "$TMP/status-error.json")"
assert_contains "status: a failed field read makes Queues UNREADABLE" "$(section "$OUT_STATUS_ERR" "== Queues")" "UNREADABLE: Work status: boom status"
assert_contains "status: a failed field read makes Parked UNREADABLE" "$(section "$OUT_STATUS_ERR" "== Parked")" "UNREADABLE: Work status: boom status"
printf '{"errors": [{"message": "boom model"}]}\n' >"$TMP/status-doc-error.json"
assert_contains "status: an error document for the fixture is UNREADABLE" \
  "$(section "$(run_status --status-json "$TMP/status-doc-error.json")" "== Queues")" "UNREADABLE: boom model"
assert_not_contains "status: a failed field read never falls back to label counts" "$(section "$OUT_STATUS_ERR" "== Queues")" "needs-human"
jq '.pages[0].data.repository.issues.pageInfo = {hasNextPage: true, endCursor: "c"}' "$TMP/status.json" >"$TMP/status-capped.json"
assert_contains "status: a read that stops at its cap is PARTIAL" "$(section "$(run_status --status-json "$TMP/status-capped.json")" "== Queues")" \
  "PARTIAL: the open-issue read reached its 1000-issue cap; counts may be low"
assert_contains "status: a capped read makes Stuck PARTIAL too" "$(section "$(run_status --status-json "$TMP/status-capped.json")" "== Stuck")" \
  "PARTIAL: the open-issue read reached its 1000-issue cap; a stuck issue past it is not shown"

cat >"$TMP/touch-field.json" <<'EOF'
{"owner": "op-user", "pages": [{"data": {"search": {"issueCount": 1, "pageInfo": {"hasNextPage": false}, "nodes": [
  {"__typename": "Issue", "number": 309, "acts": {"pageInfo": {"hasNextPage": false}, "nodes": []},
   "labels": {"pageInfo": {"hasPreviousPage": false}, "nodes": []},
   "fields": {"nodes": [
     {"__typename": "IssueFieldAddedEvent", "createdAt": "2026-07-19T09:00:00Z", "value": "needs-human", "actor": {"__typename": "User", "login": "someone"}, "issueField": {"fullDatabaseId": "48484079"}},
     {"__typename": "IssueFieldChangedEvent", "createdAt": "2026-07-19T11:00:00Z", "previousValue": "needs-human", "newValue": "ready", "actor": {"__typename": "User", "login": "op-user"}, "issueField": {"fullDatabaseId": "48484079"}}]}}
]}}}]}
EOF
TOUCH_FIELD_SEC="$(section "$(run_status --touch-json "$TMP/touch-field.json")" "== Owner touches")"
assert_contains "status touches: a hold set and lifted on the field counts" "$TOUCH_FIELD_SEC" \
  "$(printf '  2026-07-19  %9s%9s%9s%9s%9s%9s%22s' 0 0 0 1 1 0 1)"
assert_contains "status touches: the field hold's wait is measured" "$TOUCH_FIELD_SEC" "n=1, median 2h 0m, max 2h 0m"
TOUCH_NOFIELD_SEC="$(section "$(run_status --touch-json "$TMP/touch-field.json" --status-json "$TMP/status-none.json")" "== Owner touches")"
assert_contains "status touches: with no model the field events are not read" "$TOUCH_NOFIELD_SEC" "hold waits: no hold lifted in the window"
jq '.model["field-events-since"] = "2026-07-19T10:00:00Z"' "$TMP/status.json" >"$TMP/status-since.json"
jq '.pages[0].data.search.nodes[0].fields.nodes[0].actor = {"__typename": "Bot", "login": "lanes-app"}' "$TMP/touch-field.json" >"$TMP/touch-field-bot.json"
TOUCH_SINCE_SEC="$(section "$(run_status --touch-json "$TMP/touch-field-bot.json" --status-json "$TMP/status-since.json")" "== Owner touches")"
assert_contains "status touches: a bot field event before field-events-since is dropped" "$TOUCH_SINCE_SEC" \
  "$(printf '  2026-07-19  %9s%9s%9s%9s%9s%9s%22s' 0 0 0 0 1 0 1)"
assert_contains "status touches: a lift whose bot apply was dropped has no wait" "$TOUCH_SINCE_SEC" "n=0, 1 with no apply event read"

cp -R "$REST" "$TMP/rest-model"
printf 'models:\n  issue-status:\n    field-id: 48484079\n    options:\n      "1": ready\n    labels:\n      ready:\n        - "status: ready"\n' \
  >"$TMP/rest-model/$(rest_key "$R/contents/docs/conventions/pr-pipeline.yaml").json"
OUT_REST_MODEL="$(MB_GH_FIXTURES="$TMP/rest-model" run_stub rest)"
assert_contains "status rest: the label count still prints" "$(section "$OUT_REST_MODEL" "== Queues")" "status: ready            2"
assert_contains "status rest: Queues says the field was unread" "$(section "$OUT_REST_MODEL" "== Queues")" \
  "PARTIAL: the Work status field needs GraphQL, which this session does not serve; counts are by label alone"
assert_contains "status rest: Parked says a field-only decision is not shown" "$(section "$OUT_REST_MODEL" "== Parked")" \
  "PARTIAL: the Work status field needs GraphQL, which this session does not serve; an issue parked only on the field is not shown"
assert_not_contains "status rest: with no model there is no Work status line" "$(section "$OUT_REST" "== Queues")" "Work status"

echo
if ((FAILED > 0)); then
  printf 'morning-brief.test.sh: %d case(s) FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'morning-brief.test.sh: all %d cases passed\n' "$CASE_NUM"
