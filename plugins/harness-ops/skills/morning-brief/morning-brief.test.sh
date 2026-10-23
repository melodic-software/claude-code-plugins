#!/usr/bin/env bash
# Regression tests for the morning-brief script's pure rendering logic.
# Every data source is fed as a fixture (no network, no gh required); the clock
# is pinned with --now so staleness is deterministic. Self-contained and
# cwd-independent per the plugin-test runner contract.

set -uo pipefail

# The git-remote fallback case builds a throwaway repository. An inherited
# absolute GIT_DIR would redirect that fixture's writes into the caller's
# clone, so the inherited git environment is cleared before anything runs.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

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
# The brief reads cost settings from the checkout it runs in. The suite runs
# outside any checkout, so no repository's own settings reach a case; the
# settings cases build their own.
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
  # section OUTPUT "== heading prefix" — the lines of one section, heading included.
  printf '%s\n' "$1" | awk -v h="$2" 'index($0, h) == 1 {p = 1; print; next} /^== / {p = 0} p'
}

# --- Fixtures -----------------------------------------------------------------
NOW="2026-07-20T08:00Z"
FIXTURE_REPO="example/test-repo"

printf '{}\n' >"$TMP/lanes-empty.json"

cat >"$TMP/counts.json" <<'EOF'
{"needs-triage": 28, "status: ready": 44, "status: needs-decision": 3, "needs-human": 7}
EOF

# One clean non-draft (#10, kept), one draft-but-clean (#11, excluded), one
# non-draft BLOCKED (#12, excluded), one clean non-draft with a review (#13).
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

# #10's head contains the base tip; #13's is four commits behind it.
cat >"$TMP/behind.json" <<'EOF'
{"10": 0, "13": 4}
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
# flags; a lane comment without the sentinel and a scope-note comment are skipped.
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

# A stuck-section read that finds no label holding anything, for every run that
# gives the brief a repo but is not about the Stuck section.
printf '{}\n' >"$TMP/stuck-empty.json"

# Stuck-section fixture: label -> search page documents. NOW is 2026-07-20T08:00Z.
#   #201 issue — "status: ready" since 07-01 (19d); an older labeled event and a
#                newer event for ANOTHER label must not move it   -> listed
#   #202 PR    — "status: ready" since 07-18 (2d)                  -> under 7d, not listed
#   #203 issue — "status: ready", no labeled event in its timeline -> days unknown
#   #204 PR    — "needs-human" since 07-12 (8d)                    -> listed
#   #205 PR    — "needs-human" labeled 06-01 and again 07-19 (1d)  -> newest event wins, not listed
#   #206 issue — "needs-triage" since 07-10 (10d)                  -> listed
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

# Severity classification and ranking edge cases:
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

# Cost fixtures with nothing charging, all values synthetic. The billing usage
# (a June item beside July's) and budgets fixtures follow the response schemas
# at https://docs.github.com/en/rest/billing/usage and
# https://docs.github.com/en/rest/billing/budgets. The Azure fixtures follow no
# published schema: they carry only the fields the script reads, except the
# cost query's UsageDate column, a YYYYMMDD number per the Cost Management
# Query - Usage reference's Daily example; its latest date here is 2026-07-19.
# Every fixture run feeds these, so a run reads the cost section in full.
# July 2026 has 744 hours, so 2 GB included is 1488 GB-hours. app-private uses
# 300 + 100 minutes of 3000 (13%) and 100 GB-hours of 1488 (7%); lib-public's
# 9000 minutes are free and never counted.
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
# The org scan: one org admin, no other direct collaborator, a pull_request
# workflow that reads a _CLAUDE_ secret (not fork-triggered), a workflow_run
# workflow that reads none, and an archived repo whose state is never judged.
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

# --- Full render --------------------------------------------------------------
OUT="$(bash "$BRIEF" --now "$NOW" --stale-hours 6 \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --behind-json "$TMP/behind.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --merged-json "$TMP/merged.json" "${CLEAR_COST_ARGS[@]}" 2>&1)"
RC=$?

assert_exit "renders successfully" 0 "$RC"

# Queues
assert_contains "queue: needs-triage count" "$OUT" "needs-triage"
assert_contains "queue: ready count 44" "$OUT" "44"

# Merge-ready — only clean non-drafts, sorted; excludes draft + blocked
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

# Freshness that was never read is UNVERIFIED, never silently fresh.
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

# The compare read costs one GET per clean PR, so it shares the --pr-limit cap;
# a clean PR past the cap is UNVERIFIED with the cap as its reason.
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
assert_not_contains "telemetry skips a lane comment without the sentinel" "$OUT" "unmarked"

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
  --repo "$FIXTURE_REPO" --stuck-json "$TMP/stuck-empty.json" \
  --repo-labels-json "$TMP/repo-labels-alternate.json" \
  --counts-json "$TMP/empty.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
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
  --repo "$FIXTURE_REPO" --stuck-json "$TMP/stuck-empty.json" \
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
  --repo "$FIXTURE_REPO" --stuck-json "$TMP/stuck-empty.json" \
  --repo-labels-json "$TMP/repo-labels-alternate.json" \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "missing decision label degrades gracefully" "$OUT_NO_DEC" "decision label not found in this repo"

OUT_EMPTY_LABELS="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" --stuck-json "$TMP/stuck-empty.json" \
  --repo-labels-json "$TMP/repo-labels-empty.json" \
  --counts-json "$TMP/empty.json" \
  --pr-json "$TMP/empty.json" \
  --decisions-json "$TMP/empty.json" \
  --telemetry-json "$TMP/empty.json" \
  --merged-json "$TMP/merged-clean.json" 2>&1)"
assert_contains "empty label inventory degrades queue section" "$OUT_EMPTY_LABELS" "no queue labels found in this repo"

OUT_EMPTY_LABELS_DEC="$(bash "$BRIEF" --now "$NOW" \
  --repo "$FIXTURE_REPO" --stuck-json "$TMP/stuck-empty.json" \
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
    --telemetry-json "$TMP/telemetry.json" "${CLEAR_COST_ARGS[@]}" 2>&1)"
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
  --merged-json "$TMP/merged-apierror.json" "${CLEAR_COST_ARGS[@]}" 2>&1)"
assert_not_contains "stranded: an API error is NEVER reported as clear" "$OUT_ERR" "every merged PR in the window is clear"
assert_contains "stranded: an API error renders the section UNREADABLE" "$OUT_ERR" "UNREADABLE: API rate limit"
assert_contains "stranded: the API error message is surfaced" "$OUT_ERR" "rate limit already exceeded"
assert_contains "stranded: the header counts the unreadable section" "$OUT_ERR" "1 of 8 sections unreadable: stranded"

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

# --- Stuck: open items past --stuck-days in a queue label ----------------------
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
assert_contains "stuck: the header counts the unreadable section" "$OUT_STUCK_ERR" "1 of 8 sections unreadable: stuck"
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

# --- Degraded-mode contract: an unreadable source is never an all-clear -------
# A `gh` test double on PATH stands in for the network. MB_GH_MODE selects the
# host's behavior:
#   blocked  every call is refused with the proxy's GraphQL 403 shape (body on
#            stdout, message on stderr, exit 1) — the cloud-session shape
#   fail     every call fails with an unrelated error
#   forbidden
#            every call is refused with GitHub's REST 403 for a caller who is
#            not an org admin
#   rest     GraphQL-backed subcommands are refused as in `blocked`; `gh api
#            repos/...` and `gh api orgs/...` are served from
#            MB_GH_FIXTURES/<sanitized path>.json, a missing fixture answering 404
#   gql      the gh subcommands are served from MB_GH_FIXTURES/<key>.json, as gh
#            would: a list read keeps its first --limit items (gh's default
#            limit of 30 when none is given) and -q applies as a jq filter.
#            Keys: label-list, pr-list, issue-list-label-<sanitized label>,
#            issue-list-search, issue-view-<n>, and api-graphql-<cursor> (first
#            page: api-graphql-first), and api-graphql-stuck-<sanitized label>-
#            <cursor> for a label search. `api graphql --paginate` follows the
#            cursors to the last page, as gh does. Every key served is logged
#            to MB_GH_LOG when set; a missing fixture fails the call.
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

# An `az` double beside it, so no live run reaches the real Azure CLI. By
# default it answers as a logged-out az. MB_AZ_MODE=serve answers each read
# from the matching key of MB_AZ_FIXTURE, an --azure-json-shaped object, a
# missing key failing the call; a key holding {"__error": MSG} fails it with
# MSG. Every call's arguments go to MB_AZ_LOG when set.
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

# The cost reads run_stub feeds by default; a case that drives the cost reads
# live sets COST_ARGS to fewer fixtures, then restores it.
COST_ARGS=("${CLEAR_COST_ARGS[@]}")

run_stub() {
  # run_stub MODE args... — runs the brief with the gh and az doubles on PATH.
  # The gql double serves the stranded fixtures by cursor alone, so a gql run
  # takes its stuck read from an empty fixture unless MB_STUCK_LIVE is set; a
  # later --stuck-json in "$@" wins.
  local mode="$1" stuck=()
  shift
  [[ "$mode" == gql && -z "${MB_STUCK_LIVE:-}" ]] && stuck=(--stuck-json "$TMP/stuck-empty.json")
  PATH="$GH_STUB_DIR:$PATH" MB_GH_MODE="$mode" MB_GH_FIXTURES="${MB_GH_FIXTURES:-$TMP/rest}" \
    bash "$BRIEF" --now "$NOW" --stale-hours 6 --repo "$FIXTURE_REPO" --data-dir "${MB_DATA_DIR:-$TMP/data}" \
    "${COST_ARGS[@]}" ${stuck[@]+"${stuck[@]}"} "$@" 2>&1
}

# Every section live, every call refused: nothing may read as clear or absent.
# The cost reads go live too, against a logged-out az.
COST_ARGS=()
OUT_BLOCKED="$(run_stub blocked)"
RC_BLOCKED=$?
OUT_FAIL="$(run_stub fail)"
RC_FAIL=$?
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_exit "blocked: every live section unreadable exits 5" 5 "$RC_BLOCKED"
assert_contains "blocked: header counts every section" "$OUT_BLOCKED" "8 of 8 sections unreadable"
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

# An unrelated failure degrades the same way; the shape of the error does not
# decide whether a section is readable.
assert_exit "fail: every live section unreadable exits 5" 5 "$RC_FAIL"
assert_contains "fail: the error is surfaced" "$OUT_FAIL" "UNREADABLE: boom, the upstream fell over"
assert_not_contains "fail: no REST transport claimed for an unrelated error" "$OUT_FAIL" "transport: REST"

# One live section among fixtures: a partial brief still renders, exits 6 so a
# caller cannot take it for a full one, and the header says which section was
# lost.
OUT_ONE="$(run_stub blocked \
  --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/pr.json" \
  --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" \
  --stuck-json "$TMP/stuck-empty.json" \
  --lane-runs-json "$TMP/lanes-empty.json")"
RC_ONE=$?
assert_exit "partial: one unreadable section among fixtures exits 6" 6 "$RC_ONE"
assert_contains "partial: header names the lost section" "$OUT_ONE" "1 of 8 sections unreadable: stranded"
assert_contains "partial: the fixture sections still render" "$OUT_ONE" "#10 clean pr"

# A `message`-shaped error body (the REST/403 shape, no `errors` key) fed as a
# fixture is an unreadable source, exactly like the GraphQL `errors` shape.
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
    --decisions-json "$TMP/decisions.json" \
    --stuck-json "$TMP/stuck-empty.json" 2>&1)"
  RC_REMOTE=$?
  assert_exit "git remote fallback: renders (exit 6, four of eight unreadable)" 6 "$RC_REMOTE"
  assert_contains "git remote fallback: owner/repo taken from origin" "$OUT_REMOTE" "Morning brief — $FIXTURE_REPO —"
  assert_contains "git remote fallback: the header names the source" "$OUT_REMOTE" "repo resolved from the git origin remote"
  assert_contains "git remote fallback: live sections still degrade honestly" "$OUT_REMOTE" "4 of 8 sections unreadable: telemetry stranded lanes cost"
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
{"number": 7, "title": "clean one", "html_url": "http://x/7", "draft": false, "mergeable": true, "mergeable_state": "clean",
 "base": {"ref": "release/1.x"}, "head": {"sha": "7777777777777777777777777777777777777777"}}
EOF
# The base name carries a slash, which the compare path must percent-encode.
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
# Lanes, live: only intake-triage.yml of the default lane set exists; one run
# in the window, failed on the limit, read through its job's annotations.
cat >"$REST/$(rest_key "$R/actions/workflows?per_page=100").json" <<'EOF'
{"total_count": 3, "workflows": [{"path": ".github/workflows/intake-triage.yml"}, {"path": ".github/workflows/ci.yml"}, {"path": ".github/workflows/pr-unblock.yml"}]}
EOF
# pr-unblock: one run whose first job, a reusable-workflow job with no
# annotations, must not name the activity; the second job carries the record.
cat >"$REST/$(rest_key "$R/actions/workflows/pr-unblock.yml/runs?created=>=2026-07-13&per_page=100").json" <<'EOF'
{"total_count": 1, "workflow_runs": [{"id": 88, "html_url": "http://x/runs/88", "event": "pull_request", "display_title": "PR R", "head_sha": "r1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T00:00:00Z"}]}
EOF
cat >"$REST/$(rest_key "$R/actions/runs/88/jobs?per_page=100").json" <<'EOF'
{"total_count": 2, "jobs": [{"id": 881, "name": "publish-feedback / run"}, {"id": 880, "name": "resolve-conflicts / run"}]}
EOF
cat >"$REST/$(rest_key "$R/check-runs/881/annotations?per_page=100").json" <<'EOF'
[]
EOF
cat >"$REST/$(rest_key "$R/check-runs/880/annotations?per_page=100").json" <<'EOF'
[{"message": "pr-unblock completed: turns=7 max-turns=40 models=claude-sonnet-5. Findings (if any) are in the PR comments."}]
EOF
cat >"$REST/$(rest_key "$R/actions/workflows/intake-triage.yml/runs?created=>=2026-07-13&per_page=100").json" <<'EOF'
{"total_count": 1, "workflow_runs": [{"id": 77, "html_url": "http://x/runs/77", "event": "issues", "display_title": "Issue R", "head_sha": "m1", "status": "completed", "conclusion": "failure", "created_at": "2026-07-19T00:00:00Z"}]}
EOF
cat >"$REST/$(rest_key "$R/actions/runs/77/jobs?per_page=100").json" <<'EOF'
{"total_count": 1, "jobs": [{"id": 770}]}
EOF
cat >"$REST/$(rest_key "$R/check-runs/770/annotations?per_page=100").json" <<'EOF'
[{"message": "Process completed with exit code 1."}, {"message": "failure class=rate-limit"}]
EOF

OUT_REST="$(run_stub rest)"
RC_REST=$?
assert_contains "rest: lanes read live, keeping only lane workflows that exist" "$(section "$OUT_REST" "== Lanes")" \
  "intake-triage.yml  runs=1  failed=1 [rate-limit 1, max-turns 0, auth 0, other 0]  limit-stops=1  restarts=0"
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
assert_contains "rest: header counts the two lost sections" "$OUT_REST" "2 of 8 sections unreadable: stuck stranded"

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
  --stuck-json "$TMP/stuck-empty.json" \
  --repo-labels-json "$TMP/same-labels.json" \
  --counts-json "$TMP/same-counts.json" \
  --pr-json "$TMP/same-pr.json" \
  --behind-json "$TMP/same-behind.json" \
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

# A compare read that fails leaves the clean PR listed, flagged unverified with
# the error, never as fresh.
NO_COMPARE="$TMP/rest-no-compare"
mkdir -p "$NO_COMPARE"
cp "$REST/"*.json "$NO_COMPARE/"
rm "$NO_COMPARE/$(rest_key "$R/compare/release%2F1.x...7777777777777777777777777777777777777777?per_page=1").json"
OUT_NO_COMPARE="$(MB_GH_FIXTURES="$NO_COMPARE" run_stub rest)"
assert_contains "rest: a failed compare read flags the clean PR unverified" "$(section "$OUT_NO_COMPARE" "== Merge-ready")" \
  "    http://x/7  review=n/a
    UNVERIFIED: base freshness unread: Not Found"

# The per-PR merge-state read is capped, and a capped read says so.
OUT_CAP="$(run_stub rest --pr-limit 1)"
assert_contains "rest: a capped merge-state read is reported as PARTIAL" "$OUT_CAP" "PARTIAL: 3 open PRs; merge state read for the first 1 only"
bash "$BRIEF" --pr-limit x --repo "$FIXTURE_REPO" >/dev/null 2>&1
assert_exit "non-numeric --pr-limit exits 3" 3 "$?"

# --- A response that cannot be parsed is UNREADABLE, never an empty state -----
# Each section's empty-state line is what a swallowed parse failure used to
# print; the fixture is not JSON at all.
printf 'not json\n' >"$TMP/garbage.json"
OUT_BAD="$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" \
  --pr-json "$TMP/garbage.json" --decisions-json "$TMP/garbage.json" \
  --telemetry-json "$TMP/garbage.json" --merged-json "$TMP/garbage.json" "${CLEAR_COST_ARGS[@]}" 2>&1)"
RC_BAD=$?
assert_exit "unparsable: a brief with unreadable sections exits 6" 6 "$RC_BAD"
assert_contains "unparsable: the header counts the four lost sections" "$OUT_BAD" "4 of 8 sections unreadable: merge-ready decisions telemetry stranded"
assert_contains "unparsable: merge-ready is UNREADABLE" "$(section "$OUT_BAD" "== Merge-ready")" "UNREADABLE: could not parse the PR list"
assert_not_contains "unparsable: merge-ready never renders as none clean" "$OUT_BAD" "(none clean right now)"
assert_contains "unparsable: decisions are UNREADABLE" "$(section "$OUT_BAD" "== Parked")" "UNREADABLE: could not parse the decision issues"
assert_not_contains "unparsable: decisions never render as none parked" "$OUT_BAD" "(none parked)"
assert_contains "unparsable: telemetry is UNREADABLE" "$(section "$OUT_BAD" "== Lane telemetry")" "UNREADABLE: could not parse the telemetry comments"
assert_not_contains "unparsable: telemetry never renders as no lanes" "$OUT_BAD" "(no per-lane comments found"
assert_contains "unparsable: stranded is UNREADABLE" "$(section "$OUT_BAD" "== Findings stranded")" "UNREADABLE: could not parse the merged-PR pages"
assert_not_contains "unparsable: stranded never renders an all-clear" "$OUT_BAD" "every merged PR in the window is clear"

# Well-formed JSON holding no page document is not a clean window either.
OUT_NO_PAGE="$(bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --behind-json "$TMP/behind.json" --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/empty.json" 2>&1)"
assert_contains "no page: stranded is UNREADABLE" "$(section "$OUT_NO_PAGE" "== Findings stranded")" "UNREADABLE: could not parse the merged-PR pages"
assert_not_contains "no page: stranded never renders an all-clear" "$OUT_NO_PAGE" "every merged PR in the window is clear"

# --- A list read that reaches its cap says PARTIAL ----------------------------
# Every capped read is one past its cap here, so gh hands back exactly the cap.
# The caps are the script's: labels 500, counts 1000, open PRs 200, decisions
# 200, telemetry search 100.
CAPS="$TMP/gql-caps"
mkdir -p "$CAPS"
jq -n '[range(501) | {name: "label-\(.)"}]' >"$CAPS/label-list.json"
printf '[{"number": 1}]\n' >"$CAPS/issue-list-label-needs-triage.json"
jq -n '[range(1001) | {number: .}]' >"$CAPS/issue-list-label-status__ready.json"
printf '[]\n' >"$CAPS/issue-list-label-needs-human.json"
jq -n '[range(201) | {number: (. + 1), title: "decision \(.)", url: "http://x/d", body: "RECOMMENDED: go", comments: []}]' \
  >"$CAPS/issue-list-label-status__needs-decision.json"
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

# --- Stranded: paging stops at the cutoff; the bookmark widens the window ----
# Pages are newest-updated first. NOW is 2026-07-20T08:00Z, so the 3-day floor
# is 2026-07-17T08:00Z. Page c1's oldest PR was updated before both the floor
# and the bookmark below, so page c2 must never be requested.
#   #500  merged 07-19, post-merge P1      -> inside the floor
#   #501  merged 07-14, post-merge P2      -> only inside the 07-10 bookmark
#   #502  merged 07-08, post-merge P1      -> before the bookmark too
#   #503  on page c2                       -> never read
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

mkdir -p "$TMP/data-mark/morning-brief/$FIXTURE_REPO"
printf '2026-07-10T08:00Z\n' >"$TMP/data-mark/morning-brief/$FIXTURE_REPO/stranded-cutoff"
OUT_MARK="$(MB_GH_FIXTURES="$STR" MB_GH_LOG="$TMP/log-mark" MB_DATA_DIR="$TMP/data-mark" run_stub gql "${FIX_ARGS[@]}")"
STR_MARK="$(section "$OUT_MARK" "== Findings stranded")"
assert_contains "bookmark: an older bookmark widens the window" "$STR_MARK" "merged since 2026-07-10T08:00Z UTC"
assert_contains "bookmark: a merge after the bookmark is reported" "$STR_MARK" "[P2] #501"
assert_not_contains "bookmark: a merge before the bookmark is not reported" "$STR_MARK" "#502"
assert_not_contains "bookmark: paging still stops at the cutoff" "$(cat "$TMP/log-mark")" "api-graphql-c2"
assert_eq "bookmark: a full read advances it to this run's floor" "2026-07-17T08:00Z" "$(bookmark_of "$TMP/data-mark")"

mkdir -p "$TMP/gql-none" "$TMP/data-fail/morning-brief/$FIXTURE_REPO"
printf '2026-07-10T08:00Z\n' >"$TMP/data-fail/morning-brief/$FIXTURE_REPO/stranded-cutoff"
OUT_MARK_FAIL="$(MB_GH_FIXTURES="$TMP/gql-none" MB_DATA_DIR="$TMP/data-fail" run_stub gql "${FIX_ARGS[@]}")"
assert_contains "bookmark: a failed read renders UNREADABLE" "$(section "$OUT_MARK_FAIL" "== Findings stranded")" "UNREADABLE:"
assert_eq "bookmark: a failed read leaves it where it was" "2026-07-10T08:00Z" "$(bookmark_of "$TMP/data-fail")"

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

# --data-dir is the one write destination a pre-approved run takes from its
# arguments: only an absolute, literal path is accepted, and nothing is written
# when it is refused.
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

# A page that claims more results but carries no cursor is not a full read.
mkdir -p "$TMP/gql-nocursor" "$TMP/data-nocursor/morning-brief/$FIXTURE_REPO"
jq '.data.repository.pullRequests.pageInfo.endCursor = null' "$STR/api-graphql-first.json" >"$TMP/gql-nocursor/api-graphql-first.json"
printf '2026-07-10T08:00Z\n' >"$TMP/data-nocursor/morning-brief/$FIXTURE_REPO/stranded-cutoff"
OUT_NOCURSOR="$(MB_GH_FIXTURES="$TMP/gql-nocursor" MB_DATA_DIR="$TMP/data-nocursor" run_stub gql "${FIX_ARGS[@]}")"
STR_NOCURSOR="$(section "$OUT_NOCURSOR" "== Findings stranded")"
assert_contains "paging: a next page without a cursor is UNREADABLE" "$STR_NOCURSOR" "UNREADABLE: a merged-PR page reported more results but no cursor to them"
assert_not_contains "paging: a next page without a cursor never reads as clear" "$STR_NOCURSOR" "every merged PR in the window is clear"
assert_eq "paging: a next page without a cursor leaves the bookmark" "2026-07-10T08:00Z" "$(bookmark_of "$TMP/data-nocursor")"

# --- Stuck: the live read is one paged search per queue label -----------------
# status: ready spans two pages (cursor p2); the other labels hold nothing.
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
for stk_label in needs-triage status__needs-decision needs-human; do
  cat >"$STK/api-graphql-stuck-$stk_label-first.json" <<'EOF'
{"data": {"search": {"issueCount": 0, "pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": []}}}
EOF
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

mkdir -p "$TMP/gql-stuck-none"
OUT_STUCK_FAIL="$(MB_STUCK_LIVE=1 MB_GH_FIXTURES="$TMP/gql-stuck-none" run_stub gql "${FIX_ARGS[@]}" --merged-json "$TMP/merged-clean.json")"
assert_contains "stuck live: a failed search renders UNREADABLE, never empty" "$(section "$OUT_STUCK_FAIL" "== Stuck")" "UNREADABLE: needs-triage: no fixture"

# --- Lanes: failures by class, limit stops, restarts, turn headroom -----------
# The window is 2026-07-13T08:00Z to NOW. intake-triage: three runs in the
# window (a fourth is older, a fifth skipped); run 2 carries the annotations
# of intake-triage run 39038437240, which classify marked class=other while
# the action reported the turn cap. Turns 10, 16, 12 against a cap of 15:
# nearest-rank p90 of three is the third, 16; 80% of 15 is 12, so runs 2 and
# 3 are linked. work-resolve-issue: the item whose titles end "#7" stops on
# the limit three times, then succeeds, so three restarts and one repeat line,
# its title changing midway; the one ending "#8", with the same first title,
# fails on auth and then with no annotations read. pr-verify: three limit
# stops on one head.
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
  "1": "lane outcome class=success turns=10 max-turns=15",
  "2": "failure-class=other job=success; read the job log.\nClaude intake triage exited with: failure class=other (infrastructure error, not a code-quality signal — e.g. usage limit, OIDC failure, SDK crash, is_error result, or max-turns exhaustion). Last SDK result: {\"subtype\":\"success\",\"is_error\":false,\"num_turns\":16,\"class\":\"other\"}\nClaude reported a successful result after 16 turns, exceeding the configured maximum of 15",
  "3": "turns=12 max-turns=15",
  "4": "class=rate-limit",
  "10": "failure class=rate-limit resets=2026-07-15T05:00:00Z",
  "11": "failure class=rate-limit",
  "12": "failure class=rate-limit",
  "13": "turns=4 max-turns=50",
  "14": "failure class=auth",
  "20": "pr-verify exited with: failure class=rate-limit credential=CLAUDE_CODE_OAUTH_TOKEN models=claude-opus-5-5",
  "21": "pr-verify exited with: failure class=rate-limit credential=CLAUDE_CODE_OAUTH_TOKEN models=claude-opus-5-5",
  "22": "pr-verify exited with: failure class=rate-limit credential=CLAUDE_CODE_OAUTH_TOKEN models=claude-opus-5-5"
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
assert_contains "models: a pr-verify record with models= and no profile= gets its row" "$LANES" \
  "    pr-verify  profile=unknown  runs=3  pass=0/3  median-turns=-  max-turns-hits=0  models=claude-opus-5-5"
assert_contains "models: a lane whose records carry no models= still gets a row" "$LANES" \
  "    work-resolve-issue  profile=unknown  runs=5  pass=1/5  median-turns=4  max-turns-hits=0  models=none recorded"
assert_not_contains "keys: runs with no lane-outcome record print no KEY line" "$LANES" "KEY:"

# --- Lanes: dead and credit-stopped API keys ----------------------------------
# One lane-outcome record per credential attempt, after the marker. REVIEWS:
# run 50 handed off on auth, so only the subscription leg's record names the
# role and the line names the key secret derived from it; run 51 is a healthy
# key leg. INTAKE: run 60 is a key leg that failed with class=auth (a 403
# hands nothing off). AUTOMATIONS: pr-verify run 70 carries the key leg's
# class=rate-limit record and the subscription leg's fallback=credit-stop;
# run 71 is healthy, in the live shape. PR_UNBLOCK: run 80 is a healthy key
# leg and run 81 a no-key fallback, neither a key problem; run 82's
# subscription token failed with class auth, which is no key problem either,
# and run 83's records are malformed. ZED: run 90's auth fallback is in a
# record version this reader does not know. Run 84 names two roles: TWO_A is
# healthy and TWO_B's key failed with class auth.
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
    {"id": 71, "html_url": "http://x/runs/71", "event": "workflow_run", "display_title": "PR N", "head_sha": "n2", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T11:00:00Z"}
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
assert_not_contains "keys: a healthy key leg and a no-key fallback print no KEY line" "$KEYS" "KEY: PR_UNBLOCK"
assert_not_contains "keys: a record version this reader does not know is not read" "$KEYS" "KEY: ZED"
assert_not_contains "keys: malformed records leave the section readable" "$KEYS" "UNREADABLE"
assert_not_contains "keys: a role name with a trailing newline is not a role" "$KEYS" "KEY: BAD"
assert_contains "keys: each role in a run is judged by its own records" "$KEYS" \
  "  KEY: TWO_B auth (fallback on 1 of 1 runs read) — replace TWO_B_CLAUDE_API_KEY"
assert_not_contains "keys: a healthy role beside a failing one is not flagged" "$KEYS" "KEY: TWO_A"
assert_contains "keys: the model-usage table still renders" "$KEYS" "model usage by activity and profile"
assert_eq "keys: one line per role and problem" "4" "$(grep -c "^  KEY: " <<<"$KEYS")"

# Live: 200 failed intake-triage runs, newer than pr-unblock's three
# successes, fill the default read cap. The newest 3 runs of every lane are
# read first, inside the cap, so the credit-stop handoffs still show.
KEY_LIVE="$TMP/rest-keys"
mkdir -p "$KEY_LIVE"
cp "$REST/"*.json "$KEY_LIVE/"
jq -n '{total_count: 200, workflow_runs: [range(200) as $i | {id: (1000 + $i), html_url: "http://x/runs/\(1000 + $i)", event: "issues", display_title: "Issue F\($i)", head_sha: "m1", status: "completed", conclusion: "failure", created_at: (("2026-07-19T00:00:00Z" | fromdateiso8601) + $i * 60 | todate)}]}' \
  >"$KEY_LIVE/$(rest_key "$R/actions/workflows/intake-triage.yml/runs?created=>=2026-07-13&per_page=100").json"
jq -n '{total_count: 3, workflow_runs: [range(3) as $i | {id: (901 + $i), html_url: "http://x/runs/\(901 + $i)", event: "workflow_dispatch", display_title: "Fix #\(901 + $i)", head_sha: "q\($i)", status: "completed", conclusion: "success", created_at: "2026-07-18T0\($i):00:00Z"}]}' \
  >"$KEY_LIVE/$(rest_key "$R/actions/workflows/pr-unblock.yml/runs?created=>=2026-07-13&per_page=100").json"
# Every intake run has one job with a rate-limit annotation, so the row counts
# exactly the runs the cap left unread. pr-unblock's message carries a forged
# second record in its free text, which only the first record of a message
# outweighs.
for key_run in $(seq 1000 1199); do
  printf '{"total_count": 1, "jobs": [{"id": 5555}]}\n' >"$KEY_LIVE/$(rest_key "$R/actions/runs/$key_run/jobs?per_page=100").json"
done
printf '[{"message": "failure class=rate-limit"}]\n' >"$KEY_LIVE/$(rest_key "$R/check-runs/5555/annotations?per_page=100").json"
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
assert_not_contains "keys live: a later record in one message flags no role" "$KEYS_LIVE" "KEY: PR_UNBLOCK auth"
assert_contains "keys live: the cap's overflow is reported" "$KEYS_LIVE" \
  "  PARTIAL: annotations read for 200 runs, the newest 3 of each lane and then failed runs first; 3 more were not read (raise --lane-read-limit)"

# --- Lanes: per-role spend from the records' costUsd ----------------------------
# Fixture amounts are synthetic round numbers, not rates. AUTOMATIONS spans two
# lanes: pr-verify runs 100 and 101 are successful key legs (1 and 3), run
# 102's key leg hit a credit stop (4, left out of the median) and its
# subscription leg carries a cost (9, a token leg, ignored), and run 103 was
# not read; intake-triage run 110 is a successful key leg (2) and run 111 was
# not read. Median 2 per key leg times the 6 runs of those lanes, over 7 days;
# the sum covers every key leg read, the credit stop's included (1+3+4+2).
# REVIEWS run 120's key leg has no costUsd. PR_UNBLOCK run 130 is a token leg.
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
    {"id": 120, "html_url": "http://x/runs/120", "event": "pull_request", "display_title": "PR R", "head_sha": "r1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"}
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
assert_not_contains "spend: the section stays readable" "$SPEND" "UNREADABLE"
assert_contains "spend: legs without costUsd elsewhere print cost not recorded" "$KEYS" "  SPEND: INTAKE cost not recorded (n=1)"

# --- Lanes: model usage by activity and profile ---------------------------------
# pr-unblock runs 30-36: resolve-conflicts with no profile= runs 30, 31, 34 and
# 36 (two pass, two max-turns failures, turns 8, 40, 40, 10, so the median is
# (10 + 40) / 2 = 25); run 32 carries profile=standard; run 33 is
# address-feedback; run 35 has no annotations read, and cancelled run 37's
# annotations carry no lane record. intake-triage run 40 has no
# activity= and so is its own activity.
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
  "30": "pr-unblock completed: turns=8 max-turns=40 models=claude-sonnet-5. Findings (if any) are in the PR comments.\nactivity=resolve-conflicts",
  "31": "pr-unblock exited with: failure class=max-turns turns=40 max-turns=40 models=claude-sonnet-5,claude-haiku-5 (infrastructure error)\nactivity=resolve-conflicts",
  "32": "pr-unblock completed: turns=12 max-turns=40 profile=standard models=claude-opus-5. Findings (if any) are in the PR comments.\nactivity=resolve-conflicts",
  "33": "activity=address-feedback\npr-unblock completed: turns=5 max-turns=40 models=claude-sonnet-5.",
  "34": "pr-unblock exited with: failure class=max-turns turns=40 max-turns=40 models=claude-sonnet-5\nactivity=resolve-conflicts",
  "36": "pr-unblock completed: turns=10 max-turns=40 models=claude-sonnet-5.\nactivity=resolve-conflicts",
  "37": "The run was canceled by @someone.\nactivity=resolve-conflicts",
  "40": "Claude intake triage completed: turns=3 max-turns=10 models=claude-sonnet-5. Findings (if any) are in the PR comments."
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
assert_contains "models: a profile= token splits the activity's row" "$MODELS" \
  "    pr-unblock / resolve-conflicts  profile=standard  runs=1  pass=1/1  median-turns=12  max-turns-hits=0  models=claude-opus-5"
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

# --- Cost: what on GitHub or Azure is charging or could start charging ---------
# NOW is 2026-07-20, so the billing month is 2026-07. The rules under test, from
# the plan's acceptance criteria: a product whose month net is above 0, a budget
# whose amount is above 0 or whose stop at limit is off, an Azure budget whose
# spend reached its amount, a month-to-date Defender charge above 0, and any
# Defender plan, policy assignment or role assignment write in the last day are
# each an ALERT. A Defender plan off the Free tier is INFO.
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

# Alerts: private minutes 1600 of 3000 (53%) and storage 800 of 1488 GB-hours
# (54%) reach the 50% flag. A direct collaborator who is not an org admin, a
# pull_request_target workflow and a workflow_run workflow that read _CLAUDE_
# secrets (the second in index form) are each an ALERT. Budget forecast-high
# forecasts 60 against --forecast-alert 50; ending-soon ends within 30 days;
# missing-budget does not exist; the anomaly alert is disabled; one workspace
# peaked at 60% of its cap and another has no cap.
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

# GitHub billing needs an org admin. A refusal for want of one prints each
# billing line UNREADABLE with the fix, and counts the section as lost.
cat >"$TMP/billing-403.json" <<'EOF'
{"message": "Must have admin rights to the organization.", "documentation_url": "https://example.invalid/docs", "status": "403"}
EOF
OUT_COST_403="$(cost_brief --billing-usage-json "$TMP/billing-403.json" --billing-budgets-json "$TMP/billing-403.json" \
  --org-scan-json "$TMP/org-scan-clear.json" --azure-json "$TMP/azure-clear.json")"
RC_COST_403=$?
COST_403="$(section "$OUT_COST_403" "== Cost")"
assert_exit "cost 403: a billing read refused for want of an org admin counts the section as lost" 6 "$RC_COST_403"
assert_contains "cost 403: the header counts the cost section" "$OUT_COST_403" "1 of 8 sections unreadable: cost"
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

# az logged out: every Azure line is UNREADABLE and names az login; the
# GitHub lines still print.
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

# One read that failed is an UNREADABLE line beside the lines that read; the
# section counts as lost (exit 6), never as all-clear.
jq 'del(.pricings)' "$TMP/azure-clear.json" >"$TMP/azure-no-pricings.json"
OUT_COST_ONE="$(cost_brief --billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" \
  --azure-json "$TMP/azure-no-pricings.json")"
RC_COST_ONE=$?
COST_ONE="$(section "$OUT_COST_ONE" "== Cost")"
assert_exit "cost one unreadable: the brief exits 6" 6 "$RC_COST_ONE"
assert_contains "cost one unreadable: the header names the cost section" "$OUT_COST_ONE" "1 of 8 sections unreadable: cost"
assert_contains "cost one unreadable: the failed read is its own UNREADABLE line" "$COST_ONE" "UNREADABLE Azure Defender plans: no pricings in --azure-json"
assert_contains "cost one unreadable: the reads beside it still print" "$COST_ONE" "OK         Azure budget budget-example: spent 1.5, forecast 3.25"
printf '{"usageItems": "not a list"}\n' >"$TMP/billing-usage-bad.json"
COST_BAD="$(section "$(cost_brief --billing-usage-json "$TMP/billing-usage-bad.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" \
  --azure-json "$TMP/azure-clear.json")" "== Cost")"
assert_contains "cost unparsable: a usage response of the wrong shape is UNREADABLE" "$COST_BAD" \
  "UNREADABLE GitHub usage 2026-07: could not parse the billing usage"

# Every other section lost while the cost section read: the brief still carries
# data, so it exits 6, not 5.
OUT_COST_ONLY="$(run_stub blocked)"
RC_COST_ONLY=$?
assert_exit "cost only: a brief whose cost lines read is never exit 5" 6 "$RC_COST_ONLY"
assert_contains "cost only: the header counts the seven lost sections" "$OUT_COST_ONLY" \
  "7 of 8 sections unreadable: queues stuck merge-ready decisions telemetry stranded lanes"

# A fixture run with no cost fixtures reads nothing live: every cost line is
# UNREADABLE with the fix, six GitHub lines and ten Azure lines.
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

# Live reads: gh billing endpoints for the repo owner's org and this month, and
# az reads that render as the --azure-json fixture does. Every az call is a read
# that names the subscription account show resolved, and none refreshes.
COST_LIVE="$TMP/rest-cost"
mkdir -p "$COST_LIVE"
cp "$REST/"*.json "$COST_LIVE/"
cp "$TMP/billing-usage-alert.json" "$COST_LIVE/$(rest_key "orgs/example/settings/billing/usage?year=2026&month=7").json"
cp "$TMP/billing-budgets-alert.json" "$COST_LIVE/$(rest_key "orgs/example/settings/billing/budgets?per_page=100").json"
# The org scan's REST reads, built from the same org scan the fixture run reads.
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

# The Defender charge rule: a plan off Free with no charge is INFO only; no
# Defender cost rows is OK; a failed or throttled query is UNREADABLE.
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
assert_contains "defender: a throttled query counts the cost section as lost" "$OUT_429" "3 of 8 sections unreadable: stuck stranded cost"
jq '.defenderCost = {"properties": {"columns": [{"name": "ServiceName"}], "rows": []}}' "$TMP/azure-clear.json" >"$TMP/azure-cost-bad.json"
assert_contains "defender: a cost response without its columns is UNREADABLE" "$(section "$(cost_brief --billing-usage-json "$TMP/billing-usage-clear.json" \
  --billing-budgets-json "$TMP/billing-budgets-clear.json" --azure-json "$TMP/azure-cost-bad.json")" "== Cost")" \
  "UNREADABLE Azure Defender charges, month to date: could not parse the defenderCost response"

# Fail closed: a missing amount is a line that could not be read, never OK.
jq '.usageItems[1] |= del(.netAmount)' "$TMP/billing-usage-clear.json" >"$TMP/billing-usage-no-net.json"
jq '.budgets.value[0].properties |= del(.currentSpend)' "$TMP/azure-clear.json" >"$TMP/azure-no-spend.json"
COST_MISSING="$(section "$(cost_brief --billing-usage-json "$TMP/billing-usage-no-net.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" \
  --azure-json "$TMP/azure-no-spend.json")" "== Cost")"
assert_contains "fail closed: a usage item with no netAmount is UNREADABLE" "$COST_MISSING" \
  "UNREADABLE GitHub usage 2026-07: could not parse the billing usage"
assert_contains "fail closed: an Azure budget with no currentSpend is UNREADABLE" "$COST_MISSING" \
  "UNREADABLE Azure budgets: could not parse the budgets response"

# A 403 is a missing org admin only when its message says so; a rate limit or
# SAML enforcement is a failed read.
printf '{"message": "Resource protected by organization SAML enforcement. You must grant your Personal Access token access to this organization.", "documentation_url": "https://example.invalid/docs", "status": "403"}\n' >"$TMP/billing-403-sso.json"
printf '{"message": "API rate limit exceeded for user ID 1.", "documentation_url": "https://example.invalid/docs", "status": "403"}\n' >"$TMP/billing-403-rate.json"
COST_403_OTHER="$(section "$(cost_brief --billing-usage-json "$TMP/billing-403-sso.json" --billing-budgets-json "$TMP/billing-403-rate.json" \
  --azure-json "$TMP/azure-clear.json")" "== Cost")"
assert_contains "403: SAML enforcement is UNREADABLE" "$COST_403_OTHER" \
  "UNREADABLE GitHub usage 2026-07: Resource protected by organization SAML enforcement."
assert_contains "403: a rate limit is UNREADABLE" "$COST_403_OTHER" "UNREADABLE GitHub budgets: API rate limit exceeded for user ID 1."
assert_not_contains "403: neither reads as a missing org admin" "$COST_403_OTHER" "org admin needed"

# A named subscription that az cannot read is a failed read, not a skip.
COST_SUB_FAIL="$(section "$(PATH="$GH_STUB_DIR:$PATH" cost_brief --subscription 00000000-0000-0000-0000-000000000009 \
  --billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json")" "== Cost")"
assert_contains "subscription: a named subscription az cannot read is UNREADABLE" "$COST_SUB_FAIL" \
  "UNREADABLE Azure subscription 00000000-0000-0000-0000-000000000009: Please run 'az login' to setup account."
assert_not_contains "subscription: a named subscription is never skipped" "$COST_SUB_FAIL" "SKIPPED    Azure"

# Every other section lost and every cost line UNREADABLE: the brief carries
# no data, so it exits 5.
jq 'del(.account)' "$TMP/azure-clear.json" >"$TMP/azure-skip.json"
COST_ARGS=(--billing-usage-json "$TMP/billing-403.json" --billing-budgets-json "$TMP/billing-403.json" --azure-json "$TMP/azure-skip.json")
OUT_ALL_SKIP="$(run_stub blocked)"
RC_ALL_SKIP=$?
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_exit "no data: seven lost sections beside a cost section of UNREADABLE lines exit 5" 5 "$RC_ALL_SKIP"
assert_contains "no data: the refused billing lines carry no data" "$(section "$OUT_ALL_SKIP" "== Cost")" \
  "UNREADABLE GitHub usage 2026-07: org admin needed"

# Fail closed on the fields that classify a line: a budget with no
# prevent_further_usage, an activity event with no operation, and a cost row
# naming neither service nor meter category are each an UNREADABLE line.
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

# A cost row whose service and meter category are not strings, and an activity
# event whose operation is an empty string, are UNREADABLE too.
jq '.activity += [{"operationName": {"value": ""}, "caller": "x@example.invalid", "eventTimestamp": "2000-01-01T00:00:00Z"}]
  | .defenderCost.properties.rows += [[9, [3, 5, 7], 4, "USD"]]' "$TMP/azure-clear.json" >"$TMP/azure-wrong-types.json"
COST_WRONG_TYPES="$(section "$(cost_brief --billing-usage-json "$TMP/billing-usage-clear.json" \
  --billing-budgets-json "$TMP/billing-budgets-clear.json" --azure-json "$TMP/azure-wrong-types.json")" "== Cost")"
assert_contains "fail closed: a cost row whose names are not strings is UNREADABLE" "$COST_WRONG_TYPES" \
  "UNREADABLE Azure Defender charges, month to date: could not parse the defenderCost response"
assert_not_contains "fail closed: such a row never reads as no Defender cost rows" "$COST_WRONG_TYPES" "no Defender cost rows"
assert_contains "fail closed: an activity event with an empty operation is UNREADABLE" "$COST_WRONG_TYPES" \
  "UNREADABLE Azure activity, last 24h: could not parse the activity response"

# az truly absent from PATH: every Azure line is UNREADABLE and names the fix,
# with or without --subscription. az can share a directory with bash and jq
# (/usr/bin on a CI runner), so the PATH is one directory linking every
# executable on PATH except az, the first of each name winning as PATH would.
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

# Control characters in an error message or a subscription name never reach
# the terminal.
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

# Each new line is UNREADABLE when its read fails or its response is the wrong
# shape: an Actions item with no unit, a budget with no forecast, no scheduled
# actions, no workspace list, and one workspace whose query failed.
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

# --- Cost: fork-triggered forms, scan counts, and the cost query's pages ------
# Each workflow below is fork-triggered in a form the YAML spec allows (a quoted
# event in a flow sequence, a flow mapping, a quoted block key) and reads a
# _CLAUDE_ secret, or passes every secret to a reusable workflow or a step.
# Two near misses stay clear: secrets: inherit on pull_request, and a literal
# index whose name has no _CLAUDE_.
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

# A scan that listed no repo, or stopped at its workflow-file cap, never reads
# as clear: each prints UNREADABLE with its counts.
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

# The cost query's next page is read and merged: page 2 holds a Defender charge
# and the month's latest usage date, 2026-07-20. The nextLink spells the path
# `Query`, as the Query - Usage reference's examples do
# (https://learn.microsoft.com/en-us/rest/api/cost-management/query/usage).
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
# A next page that is not the query endpoint is never POSTed: another ARM
# action; a traversal, a doubled slash, or an encoded dot or slash in the path;
# a backslash; an embedded newline; or another host. Page 2 would read as a charge.
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
# A $skiptoken is opaque and may hold an encoded `/`, `+` or `=`: after the `?`
# that next page is still the query endpoint, and it is POSTed.
jq --arg n "$Q_URL&\$skiptoken=AB%2FC%2BD%3D" \
  '.defenderCost.properties.nextLink = $n | .["defenderCost_AB%2FC%2BD%3D"] = .defenderCost_2' \
  "$TMP/azure-paged.json" >"$TMP/azure-paged-token.json"
COST_ARGS=(--billing-usage-json "$TMP/billing-usage-clear.json" --billing-budgets-json "$TMP/billing-budgets-clear.json" --org-scan-json "$TMP/org-scan-clear.json")
: >"$TMP/az-log-token"
COST_TOKEN_LIVE="$(section "$(MB_GH_FIXTURES="$COST_LIVE" MB_AZ_MODE=serve MB_AZ_FIXTURE="$TMP/azure-paged-token.json" MB_AZ_LOG="$TMP/az-log-token" run_stub rest)" "== Cost")"
COST_ARGS=("${CLEAR_COST_ARGS[@]}")
assert_contains "pages live: a skiptoken with encoded / + = is followed" "$COST_TOKEN_LIVE" "ALERT      Azure Defender charges, month to date: 3 USD"
assert_eq "pages live: a skiptoken with encoded / + = gets one POST per page" "2" "$(grep -c -- "rest --method post" "$TMP/az-log-token")"
# A non-ASCII byte is rejected in every locale: U+0130 folds to `i` under a
# UTF-8 locale, which would make subscr<U+0130>ptions match the prefix.
jq --arg n "${Q_URL/subscriptions/subscr$'\xc4\xb0'ptions}&\$skiptoken=2" '.defenderCost.properties.nextLink = $n' \
  "$TMP/azure-paged.json" >"$TMP/azure-paged-nonascii.json"
COST_NONASCII="$(section "$(LC_ALL=C.UTF-8 cost_brief --azure-json "$TMP/azure-paged-nonascii.json")" "== Cost")"
assert_contains "pages: a next page with a non-ASCII byte is never read" "$COST_NONASCII" \
  "UNREADABLE Azure Defender charges, month to date: the cost query's next page is not the query endpoint; it was not read"

# The org and the alert percents are validated.
cost_brief --org 'bad/org' >/dev/null
assert_exit "validation: an --org that is not a GitHub owner name exits 3" 3 "$?"
cost_brief --usage-alert-percent 150 >/dev/null
assert_exit "validation: a --usage-alert-percent above 100 exits 3" 3 "$?"
cost_brief --log-cap-alert-percent 101 >/dev/null
assert_exit "validation: a --log-cap-alert-percent above 100 exits 3" 3 "$?"
cost_brief --usage-alert-percent 100 "${CLEAR_COST_ARGS[@]}" >/dev/null
assert_exit "validation: a percent of 100 is accepted" 0 "$?"

# --- Cost settings: flag, personal file, team file, default ----------------------
# A checkout whose team file sets every key, a personal file that overrides two
# and holds one invalid value, and a flag that overrides one.
if have git; then
  CFG="$TMP/cfg-repo"
  mkdir -p "$CFG/docs/conventions"
  git -C "$CFG" init -q 2>/dev/null
  cat >"$CFG/docs/conventions/harness-ops.yaml" <<'EOF'
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
    "settings: org=team-org (harness-ops.yaml) actions_included_minutes=3000 (harness-ops.yaml)"
  cat >"$CFG/docs/conventions/harness-ops.local.yaml" <<'EOF'
morning_brief:
  usage_alert_percent: 90
  actions_included_minutes: lots
EOF
  OUT_LOCAL="$(cd "$CFG" && bash "$BRIEF" "${CFG_BRIEF[@]}" 2>&1)"
  COST_LOCAL="$(section "$OUT_LOCAL" "== Cost")"
  assert_contains "settings: the personal file beats the team file" "$COST_LOCAL" \
    "OK         GitHub Actions storage 2026-07, private repos: 100 of 1488 GB-hours included (7%)"
  assert_contains "settings: an invalid personal value is named" "$OUT_LOCAL" \
    "morning-brief: harness-ops.local.yaml: morning_brief.actions_included_minutes has an invalid value (lots); the default is used"
  assert_contains "settings: an invalid value takes the default, never the team file's" "$COST_LOCAL" \
    "INFO       GitHub Actions minutes 2026-07, private repos: 400 minutes used; included amount not configured"
  COST_FLAG="$(section "$(cd "$CFG" && bash "$BRIEF" "${CFG_BRIEF[@]}" --usage-alert-percent 5 --actions-included-minutes 4000 2>&1)" "== Cost")"
  assert_contains "settings: a flag beats both files" "$COST_FLAG" \
    "ALERT      GitHub Actions minutes 2026-07, private repos: 400 of 4000 minutes included (10%)"
  assert_contains "settings: a flag is reported with its value as the flag" "$COST_FLAG" "usage_alert_percent=5 (flag)"
  printf 'morning_brief:\n  org: [unclosed\n' >"$CFG/docs/conventions/harness-ops.local.yaml"
  OUT_BROKEN="$(cd "$CFG" && bash "$BRIEF" "${CFG_BRIEF[@]}" 2>&1)"
  assert_contains "settings: a file that cannot be parsed is named and skipped" "$OUT_BROKEN" \
    "harness-ops.local.yaml could not be parsed"
  assert_contains "settings: the team file still applies beside it" "$(section "$OUT_BROKEN" "== Cost")" \
    "of 3000 minutes included"
  rm "$CFG/docs/conventions/harness-ops.local.yaml"
  printf 'morning_brief:\n  required_budgets: budget-example\n' >"$TMP/cfg-scalar.yaml"
  mkdir -p "$TMP/cfg-home"
  cp "$TMP/cfg-scalar.yaml" "$TMP/cfg-home/harness-ops.yaml"
  OUT_SCALAR="$(bash "$BRIEF" "${CFG_BRIEF[@]}" --config-home "$TMP/cfg-home" 2>&1)"
  assert_contains "settings: a list key given a scalar is invalid" "$OUT_SCALAR" \
    "morning_brief.required_budgets has an invalid value"
  assert_contains "settings: --config-home names the home" "$(section "$(bash "$BRIEF" "${CFG_BRIEF[@]}" --config-home "$CFG/docs/conventions" 2>&1)" "== Cost")" \
    "settings: org=team-org (harness-ops.yaml)"
  # Run by bare filename from its own directory, the parser is still found.
  OUT_BARE="$(cd "${BRIEF%/*}" && bash "${BRIEF##*/}" "${CFG_BRIEF[@]}" --config-home "$CFG/docs/conventions" 2>&1)"
  assert_contains "settings: a bare-filename run reads the team file" "$(section "$OUT_BARE" "== Cost")" \
    "settings: org=team-org (harness-ops.yaml)"
  assert_not_contains "settings: a bare-filename run parses the team file" "$OUT_BARE" "could not be parsed"
  assert_contains "settings: outside a checkout no file is read" "$(section "$(bash "$BRIEF" "${CFG_BRIEF[@]}" 2>&1)" "== Cost")" \
    "settings: defaults (no harness-ops.yaml read)"
  # A settings file never turns a fixture run live: no gh or az call is made.
  NET_BIN="$TMP/net-bin"
  mkdir -p "$NET_BIN"
  for _tool in gh az; do
    printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "%s" "$*" >>"%s"\nexit 1\n' "$_tool" "$TMP/net-log" >"$NET_BIN/$_tool"
    chmod +x "$NET_BIN/$_tool"
  done
  printf 'morning_brief:\n  org: team-org\n  subscription: 00000000-0000-0000-0000-000000000009\n' >"$TMP/cfg-net.yaml"
  mkdir -p "$TMP/cfg-net"
  cp "$TMP/cfg-net.yaml" "$TMP/cfg-net/harness-ops.yaml"
  : >"$TMP/net-log"
  OUT_NET="$(PATH="$NET_BIN:$PATH" bash "$BRIEF" --now "$NOW" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" --behind-json "$TMP/behind.json" \
    --decisions-json "$TMP/decisions.json" --telemetry-json "$TMP/telemetry.json" --merged-json "$TMP/merged-clean.json" \
    --lane-runs-json "$TMP/lanes-empty.json" --config-home "$TMP/cfg-net" 2>&1)"
  assert_eq "settings: a team-file org and subscription make no gh or az call in a fixture run" "" "$(cat "$TMP/net-log")"
  assert_contains "settings: the GitHub lines say the run was not live" "$(section "$OUT_NET" "== Cost")" \
    "UNREADABLE GitHub usage 2026-07: not read live in a fixture run; pass --org or the billing and org-scan fixtures"
  # An org setting that is not a GitHub owner name, and a percent above 100, take the default.
  printf 'morning_brief:\n  org: "bad org;x"\n  log_cap_alert_percent: 101\n' >"$TMP/cfg-net/harness-ops.yaml"
  OUT_BAD_VALUES="$(bash "$BRIEF" "${CFG_BRIEF[@]}" --config-home "$TMP/cfg-net" 2>&1)"
  assert_contains "settings: an org that is not a GitHub owner name is invalid" "$OUT_BAD_VALUES" \
    "morning_brief.org has an invalid value"
  assert_contains "settings: a percent above 100 is invalid" "$OUT_BAD_VALUES" \
    "morning_brief.log_cap_alert_percent has an invalid value"
  # A parse error quoting a key with control characters prints them escaped.
  printf 'morning_brief:\n  "org\033[2J":1\n' >"$TMP/cfg-net/harness-ops.yaml"
  OUT_ESC_KEY="$(bash "$BRIEF" "${CFG_BRIEF[@]}" --config-home "$TMP/cfg-net" 2>&1)"
  assert_contains "settings: a parse error quoting a key is reported" "$OUT_ESC_KEY" "harness-ops.yaml could not be parsed"
  assert_eq "settings: no ESC from a key reaches the terminal" "0" "$(grep -c $'\x1b' <<<"$OUT_ESC_KEY")"
fi

# --- Summary ------------------------------------------------------------------
echo
if ((FAILED > 0)); then
  printf 'morning-brief.test.sh: %d case(s) FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'morning-brief.test.sh: all %d cases passed\n' "$CASE_NUM"
