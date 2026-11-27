#!/usr/bin/env bash
# test-scope: docs/conventions/work-items.yaml
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE GIT_COMMON_DIR
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

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
printf '[{"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false}, "nodes": []}}}}]\n' >"$TMP/merged.json"
printf '{"pr-unblock.yml": [{"id": 30, "html_url": "http://x/runs/30", "event": "pull_request", "display_title": "PR A", "head_sha": "a1", "status": "completed", "conclusion": "success", "created_at": "2026-07-19T10:00:00Z"}]}\n' >"$TMP/lane-runs.json"
cat >"$TMP/lane-ann.json" <<'EOF'
{"30": "pr-unblock completed. lane-outcome {\"v\":1,\"lane\":\"resolve-conflicts\",\"outcome\":\"success\",\"credential\":{\"secret\":\"CLAUDE_CODE_OAUTH_TOKEN\",\"kind\":\"oauth-token\"},\"turns\":8,\"maxTurns\":40,\"models\":[\"claude-sonnet-5\"]}\nactivity=resolve-conflicts"}
EOF
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

raw_template="$(<"$SCRIPT_DIR/templates/brief.html")"
check "the template defines no literal palette color" "$([[ ! "$raw_template" =~ \#[0-9a-fA-F]{3,8} ]] && echo 1 || echo 0)"
check "default page embeds shipped token layer, toggle, comment box and focus floor" "$([[ "$page" == *"--ivory: #FAF9F5;"* && "$page" != *'class="rv-brand"'* && "$page" == *'data-rv-theme="system" aria-pressed="true"'* && "$page" == *'data-rv-note="comment"'* && "$page" == *"outline: 3px solid var(--focus)"* ]] && echo 1 || echo 0)"

mkdir -p "$TMP/brand-repo/docs/conventions" "$TMP/empty-home"
git init -q "$TMP/brand-repo"
cat >"$TMP/brand-repo/docs/conventions/rendered-views.yaml" <<'YAML'
branding:
  palette:
    light:
      bg: "#F8F4EC"
      muted: "#595954"
      link: "#1A4D8F"
      fg: "#CCCCCC"
  type:
    sans: "IBM Plex Sans, sans-serif"
  logo:
    svg: '<svg viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg"><circle cx="8" cy="8" r="6" fill="#1A4D8F"/></svg>'
    label: "Acme Brief"
YAML
NODE_BIN="$(node -p 'process.execPath')"
if CLAUDE_PROJECT_DIR="$TMP/brand-repo" HOME="$TMP/empty-home" USERPROFILE="$TMP/empty-home" CLAUDE_PLUGIN_OPTION_BRANDING="" "$NODE_BIN" "$BUILDER" --out "$TMP/branded.html" <"$TMP/brief.txt" >/dev/null 2>"$TMP/branded.err" && "$NODE_BIN" "$LIB" --check "$TMP/branded.html" >/dev/null; then
  pass "branded brief builds and passes interactive profile"
else
  fail "branded brief builds and passes interactive profile"
fi
branded_err="$(<"$TMP/branded.err")"
branded_page="$(<"$TMP/branded.html")"
check "branded brief emits contrast-floor notice on stderr" "$([[ "$branded_err" == *"notice:"* && "$branded_err" == *"fg"* ]] && echo 1 || echo 0)"
branded_style="${branded_page#*<style>}"
branded_style="${branded_style%%</style>*}"
check "branded brief strips all leading token header comments" "$([[ "$branded_style" != *"GENERATED"* && "$branded_style" != *"Provenance:"* ]] && echo 1 || echo 0)"
check "branded brief applies palette, type, logo slot and enforces contrast floor" "$([[ "$branded_page" == *"--bg: #F8F4EC;"* && "$branded_page" == *"--link: #1A4D8F;"* && "$branded_page" != *"--fg: #CCCCCC;"* && "$branded_page" == *"--sans: IBM Plex Sans, sans-serif;"* && "$branded_page" == *'<div class="rv-bar"><div class="rv-brand"><svg viewBox="0 0 16 16"'* && "$branded_page" == *'<span class="rv-brand-label">Acme Brief</span>'* && "$branded_page" == *'data-rv-theme="dark"'* && "$branded_page" == *'data-rv-note="comment"'* && "$branded_page" == *"outline: 3px solid var(--focus)"* ]] && echo 1 || echo 0)"
if CLAUDE_PROJECT_DIR="$TMP/empty-home" HOME="$TMP/empty-home" USERPROFILE="$TMP/empty-home" CLAUDE_PLUGIN_OPTION_BRANDING="" "$NODE_BIN" "$BUILDER" --out "$TMP/opt.html" --branding-option '{"logo":{"label":"CLI Brief"}}' <"$TMP/brief.txt" >/dev/null; then
  opt_page="$(<"$TMP/opt.html")"
  check "--branding-option passes userConfig branding into brief" "$([[ "$opt_page" == *'<span class="rv-brand-label">CLI Brief</span>'* ]] && echo 1 || echo 0)"
else
  fail "--branding-option passes userConfig branding into brief"
fi

if [[ -z "$chrome" ]]; then
  echo "SKIP: browser check, no Chrome or Chromium found (set CHROME to run it)"
else
  dom="$("$chrome" --headless --no-sandbox --disable-gpu --dump-dom "file://$TMP/brief.html" 2>/dev/null)"
  check "browser: the runtime runs under the page's policy from file://" "$([[ "$dom" == *'class="rv-ready"'* ]] && echo 1 || echo 0)"
  check "browser: sections render as collapsible blocks" "$([[ "$dom" == *'<details open'* && "$dom" == *'id="sections-1-lines-1"'* ]] && echo 1 || echo 0)"
  check "browser: hostile markup stays text" "$([[ "$dom" != *"<title>pwned"* && "$dom" != *"<img"* && "$dom" == *"&lt;img src=x"* ]] && echo 1 || echo 0)"
fi

exit "$((FAILED > 0))"
