#!/usr/bin/env bash
# The morning-brief status report page: a fixture-fed brief goes through the builder, and
# hostile issue and pull-request titles must reach the page only as escaped JSON data. When a
# Chrome or Chromium binary is found the page is also opened from file:// and read back.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIEF="$SCRIPT_DIR/scripts/morning-brief.sh"
BUILDER="$SCRIPT_DIR/scripts/build-brief-view.mjs"
LIB="$SCRIPT_DIR/../../lib/view-builder.mjs"

have() { command -v "$1" >/dev/null 2>&1; }
if ! have jq || ! have node; then
  echo "SKIP: jq and node are required" >&2
  exit 0
fi
if ! date -u -d "2026-01-01T00:00Z" +%s >/dev/null 2>&1 && ! date -u -j -f "%Y-%m-%dT%H:%MZ" "2026-01-01T00:00Z" +%s >/dev/null 2>&1; then # portability-ok: probes GNU date then falls back to BSD date
  echo "SKIP: no supported date dialect" >&2
  exit 0
fi

chrome="${CHROME:-}"
if [[ -z "$chrome" ]]; then
  for candidate in google-chrome google-chrome-stable chromium chromium-browser \
    "$HOME"/.cache/ms-playwright/chromium_headless_shell-*/chrome-*/chrome-headless-shell; do
    if [[ -x "$candidate" ]] || have "$candidate"; then
      chrome="$candidate"
      break
    fi
  done
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILED=$((FAILED + 1))
}
check() { if [[ "$2" == 1 ]]; then pass "$1"; else fail "$1"; fi; }

HOSTILE='<script>globalThis.pwned = 1</script><img src=x onerror="document.title=pwned">'

printf '{"needs-triage": 28, "needs-human": 7}\n' >"$TMP/counts.json"
jq -n --arg t "$HOSTILE" '[{number: 10, title: $t, url: "http://x/10", isDraft: false, mergeStateStatus: "CLEAN", reviewDecision: "", baseRefName: "main", headRefOid: "1010101010101010101010101010101010101010"}]' >"$TMP/pr.json"
printf '{"10": 0}\n' >"$TMP/behind.json"
jq -n --arg t "$HOSTILE" '[{number: 100, title: $t, url: "http://x/i/100", body: ("RECOMMENDED: " + $t), comments: []}]' >"$TMP/decisions.json"
printf '[]\n' >"$TMP/empty.json"
# A merged-PR read always carries a page document; a bare [] is UNREADABLE.
printf '[{"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false}, "nodes": []}}}}]\n' >"$TMP/merged.json"
printf '{"pr-unblock.yml": [{"id": 30, "html_url": "http://x/runs/30", "event": "pull_request", "display_title": "PR A", "head_sha": "a1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"}]}\n' >"$TMP/lane-runs.json"
printf '{"30": "pr-unblock completed: turns=8 max-turns=40 models=claude-sonnet-5.\\nactivity=resolve-conflicts"}\n' >"$TMP/lane-ann.json"
# The cost reads, all clear, so the fixture brief reads every section.
printf '{"usageItems": []}\n' >"$TMP/usage.json"
printf '{"budgets": [], "has_next_page": false}\n' >"$TMP/budgets.json"
printf '{"admins": ["owner-example"], "partial": 0, "repos": [{"name": "app", "visibility": "private", "archived": false, "collaborators": [], "workflows": []}]}\n' >"$TMP/scan.json"
jq -n '{account: {id: "00000000-0000-0000-0000-000000000001", name: "sub-example", state: "Enabled"},
  budgets: {value: []}, scheduledActions: {value: []}, pricings: {value: []}, workspaces: [], activity: [],
  defenderCost: {properties: {nextLink: null, columns: [{name: "Cost"}, {name: "ServiceName"}, {name: "MeterCategory"}, {name: "UsageDate"}], rows: []}},
  secureScores: [], advisorSecurity: [], advisorCost: []}' >"$TMP/azure.json"

if bash "$BRIEF" --now "2026-07-20T08:00Z" --counts-json "$TMP/counts.json" --pr-json "$TMP/pr.json" \
  --behind-json "$TMP/behind.json" --decisions-json "$TMP/decisions.json" \
  --telemetry-json "$TMP/empty.json" --merged-json "$TMP/merged.json" \
  --lane-runs-json "$TMP/lane-runs.json" --lane-annotations-json "$TMP/lane-ann.json" \
  --billing-usage-json "$TMP/usage.json" --billing-budgets-json "$TMP/budgets.json" --org-scan-json "$TMP/scan.json" \
  --azure-json "$TMP/azure.json" >"$TMP/brief.txt" 2>&1; then
  pass "the fixture brief renders"
else
  fail "the fixture brief renders"
fi

if node "$BUILDER" --out "$TMP/brief.html" <"$TMP/brief.txt" >/dev/null && [[ -s "$TMP/brief.html" ]]; then
  pass "the builder writes the page"
else
  fail "the builder writes the page"
fi

if node "$LIB" --check "$TMP/brief.html" >/dev/null; then
  pass "the page passes the interactive profile"
else
  fail "the page passes the interactive profile"
fi

page="$(<"$TMP/brief.html")"
outside="$(grep -v 'id="rv-data"' "$TMP/brief.html")"
check "the page carries exactly two scripts" "$([[ "$(grep -o '<script' "$TMP/brief.html" | wc -l)" == 2 ]] && echo 1 || echo 0)"
check "no hostile markup reaches the page outside the data block" "$([[ "$outside" != *"pwned"* && "$outside" != *"onerror"* && "$outside" != *"<img"* ]] && echo 1 || echo 0)"
check "the hostile title is in the data block with < escaped" "$([[ "$page" == *'003cscript>globalThis.pwned'* ]] && echo 1 || echo 0)"
check "the brief's sections are all in the data block" "$([[ "$(grep -c '^== ' "$TMP/brief.txt")" == "$(grep -o '"name":' "$TMP/brief.html" | wc -l)" ]] && echo 1 || echo 0)"
check "the lanes model-usage row is in the data block" "$([[ "$page" == *'pr-unblock / resolve-conflicts  profile=unknown  runs=1  pass=1/1  median-turns=8'* ]] && echo 1 || echo 0)"
check "the title is the brief's first line" "$([[ "$page" == *'"title":"Morning brief'* ]] && echo 1 || echo 0)"

if printf 'not a brief\n' | node "$BUILDER" --out "$TMP/odd.html" >/dev/null; then
  pass "text with no sections still builds"
else
  fail "text with no sections still builds"
fi
rc=0
node "$BUILDER" </dev/null >/dev/null 2>&1 || rc=$?
check "no --out exits 2" "$([[ $rc -eq 2 ]] && echo 1 || echo 0)"

if [[ -z "$chrome" ]]; then
  echo "SKIP: browser check, no Chrome or Chromium found (set CHROME to run it)"
else
  dom="$("$chrome" --headless --no-sandbox --disable-gpu --dump-dom "file://$TMP/brief.html" 2>/dev/null)"
  check "browser: the runtime runs under the page's policy from file://" "$([[ "$dom" == *'class="rv-ready"'* ]] && echo 1 || echo 0)"
  check "browser: sections render as collapsible blocks" "$([[ "$dom" == *'<details open'* && "$dom" == *'id="sections-1-lines-1"'* ]] && echo 1 || echo 0)"
  check "browser: hostile markup stays text" "$([[ "$dom" != *"<title>pwned"* && "$dom" != *"<img"* && "$dom" == *"&lt;img src=x"* ]] && echo 1 || echo 0)"
fi

exit "$((FAILED > 0))"
