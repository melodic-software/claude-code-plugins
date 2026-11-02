#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# test-scope: plugins/work-items/tools/work-item-tracker/adapters/github/* plugins/work-items/tools/work-item-tracker/lib/* docs/conventions/work-items.yaml
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-items.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --state bogus

# --- the envelope reports truncation at the declared ceiling ---
# Runs a fixture copy of the adapter whose manifest declares a ceiling of 2, so a
# three-row listing is past it. The stub logs gh's argv: the adapter must ask for
# one row past the ceiling, or it cannot tell "exactly 2" from "more than 2".
if command -v jq >/dev/null 2>&1; then
  FIX="$(mktemp -d)"
  trap 'rm -rf "$FIX"' EXIT
  mkdir -p "$FIX/adapters" "$FIX/bin"
  cp -R "$(dirname "$S")" "$FIX/adapters/github"
  cp -R "$(dirname "$S")/../../lib" "$FIX/lib"
  jq '.limits.list_items_max = 2' "$(dirname "$S")/capabilities.json" >"$FIX/adapters/github/capabilities.json"
  cat >"$FIX/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_ARGV"
if [[ -n "${GH_STUB_LIST_FILE:-}" ]]; then cat "$GH_STUB_LIST_FILE"; else printf '%s\n' "${GH_STUB_LIST:?}"; fi
EOF
  chmod +x "$FIX/bin/gh"
  row() { printf '{"number":%s,"title":"t","state":"OPEN","assignees":[],"labels":[],"issueType":null,"blockedBy":{"nodes":[]},"url":"https://github.com/o/r/issues/%s","createdAt":"2026-03-0%sT10:00:00Z"}' "$1" "$1" "$1"; }

  OUT="$(PATH="$FIX/bin:$PATH" GH_STUB_ARGV="$FIX/argv" GH_STUB_LIST="[$(row 1),$(row 2),$(row 3)]" \
    bash "$FIX/adapters/github/list-items.sh" --repo o/r)"
  assert_eq "a listing past the ceiling → exit 0 (documented truncation)" "0" "$?"
  assert_eq "past the ceiling: truncated is true" "true" "$(jq -c '.truncated' <<<"$OUT")"
  assert_eq "past the ceiling: only the ceiling's worth of rows" \
    "github:o/r#1,github:o/r#2" "$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
  assert_contains "the request asks for one row past the ceiling" "$(cat "$FIX/argv")" "--limit 3"

  OUT="$(PATH="$FIX/bin:$PATH" GH_STUB_ARGV="$FIX/argv" GH_STUB_LIST="[$(row 1),$(row 2)]" \
    bash "$FIX/adapters/github/list-items.sh" --repo o/r)"
  assert_eq "exactly the ceiling's worth of rows: truncated is false" "false" "$(jq -c '.truncated' <<<"$OUT")"
  assert_eq "exactly the ceiling: every row kept" "2" "$(jq '.items | length' <<<"$OUT")"
  assert_eq "each row carries its createdAt as created_at" "2026-03-01T10:00:00Z,2026-03-02T10:00:00Z" \
    "$(jq -r '[.items[].created_at] | join(",")' <<<"$OUT")"
  assert_contains "createdAt is requested" "$(cat "$FIX/argv")" "url,createdAt"

  # --label goes to gh, so GitHub filters before the ceiling counts.
  : >"$FIX/argv"
  PATH="$FIX/bin:$PATH" GH_STUB_ARGV="$FIX/argv" GH_STUB_LIST="[$(row 1)]" \
    bash "$FIX/adapters/github/list-items.sh" --repo o/r --label "area: ci" >/dev/null
  assert_contains "--label reaches gh issue list" "$(cat "$FIX/argv")" "--label area: ci --limit 3"
  assert_usage_error "$S" --label

  # A labeled read goes through GitHub search, which returns at most 1000 results, so
  # 1000 labeled rows cannot prove the listing complete; 1000 unlabeled rows can.
  jq '.limits.list_items_max = 1000' "$(dirname "$S")/capabilities.json" >"$FIX/adapters/github/capabilities.json"
  jq -cn '[range(1; 1001) | {number: ., title: "t", state: "OPEN", assignees: [], labels: [],
    issueType: null, blockedBy: {nodes: []}, url: "https://github.com/o/r/issues/\(.)"}]' >"$FIX/thousand.json"
  OUT="$(PATH="$FIX/bin:$PATH" GH_STUB_ARGV="$FIX/argv" GH_STUB_LIST_FILE="$FIX/thousand.json" \
    bash "$FIX/adapters/github/list-items.sh" --repo o/r --label "area: ci")"
  assert_eq "1000 labeled rows (the search cap) → truncated:true" "true" "$(jq -c '.truncated' <<<"$OUT")"
  OUT="$(PATH="$FIX/bin:$PATH" GH_STUB_ARGV="$FIX/argv" GH_STUB_LIST_FILE="$FIX/thousand.json" \
    bash "$FIX/adapters/github/list-items.sh" --repo o/r)"
  assert_eq "1000 unlabeled rows at a 1000 ceiling → truncated:false" "false" "$(jq -c '.truncated' <<<"$OUT")"

  # --- a session that refuses GraphQL (CLAUDE_CODE_REMOTE=true) reads REST ---
  # The stub serves page N of the issues endpoint from page-N.json and an item's
  # blockers from deps-<n>.json, and logs every call.
  REST="$FIX/rest"
  mkdir -p "$REST/bin"
  cat >"$REST/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_STUB_ARGV"
if [[ "$*" =~ issues/([0-9]+)/dependencies/blocked_by ]]; then
  cat "$GH_STUB_REST/deps-${BASH_REMATCH[1]}.json"
elif [[ "$*" =~ -f\ page=([0-9]+) ]]; then
  cat "$GH_STUB_REST/page-${BASH_REMATCH[1]}.json"
else
  echo "graphql call in a REST session: $*" >&2
  exit 1
fi
EOF
  chmod +x "$REST/bin/gh"
  jq -cn '{schema_version: "1.0", provider: "github", config: {lease_ttl_hours: 24, github: {wont_do_labels: ["Wont-Fix"]}}}' \
    >"$REST/binding.json"
  rest_list() {
    : >"$REST/argv"
    CLAUDE_CODE_REMOTE=true WORK_ITEM_TRACKER_BINDING="$REST/binding.json" PATH="$REST/bin:$PATH" \
      GH_STUB_ARGV="$REST/argv" GH_STUB_REST="$REST" bash "$FIX/adapters/github/list-items.sh" --repo o/r "$@"
  }
  issue() { # <number> <total_blocked_by>
    jq -cn --argjson n "$1" --argjson b "$2" '{number: $n, title: "t\($n)", state: "open",
      assignees: [{login: "a"}], labels: [{name: "l"}], type: {name: "Bug"},
      html_url: "https://github.com/o/r/issues/\($n)", created_at: "2026-03-01T10:00:00Z",
      issue_dependencies_summary: {blocked_by: 0, total_blocked_by: $b}}'
  }
  blocker() { # <state> <state_reason or null> [<label>]
    jq -cn --arg s "$1" --argjson r "$2" --arg l "${3:-}" \
      '{state: $s, state_reason: $r, labels: (if $l == "" then [] else [{name: $l}] end)}'
  }
  jq '.limits.list_items_max = 10' "$(dirname "$S")/capabilities.json" >"$FIX/adapters/github/capabilities.json"
  jq -cn --argjson i1 "$(issue 1 0)" --argjson i2 "$(issue 2 1)" --argjson i4 "$(issue 4 1)" \
    --argjson i5 "$(issue 5 2)" --argjson i6 "$(issue 6 1)" \
    '[$i1, $i2, {number: 3, title: "pr", state: "open", pull_request: {url: "u"}}, $i4, $i5, $i6]' >"$REST/page-1.json"
  printf '[%s]\n' "$(blocker closed '"not_planned"')" >"$REST/deps-2.json"
  printf '[%s]\n' "$(blocker open null)" >"$REST/deps-4.json"
  printf '[%s][%s]\n' "$(blocker closed '"completed"')" "$(blocker closed null)" >"$REST/deps-5.json"
  printf '[%s]\n' "$(blocker closed '"completed"' wont-fix)" >"$REST/deps-6.json"

  OUT="$(rest_list)"
  assert_eq "REST session → exit 0" "0" "$?"
  assert_not_contains "REST session: no GraphQL-backed gh issue list" "$(cat "$REST/argv")" "issue list"
  assert_eq "REST session: pull requests are dropped" "github:o/r#1,github:o/r#2,github:o/r#4,github:o/r#5,github:o/r#6" \
    "$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
  assert_eq "REST session: blocked_by_count/wont_do per item (none, not_planned, open, completed, won't-do label)" \
    "0/0,1/1,1/0,0/0,1/1" \
    "$(jq -r '[.items[] | "\(.blocked_by_count)/\(.blocked_by_wont_do_count)"] | join(",")' <<<"$OUT")"
  assert_not_contains "REST session: an item whose summary counts no blocker costs no blocker read" \
    "$(cat "$REST/argv")" "issues/1/dependencies"
  assert_eq "REST session: the frontier fields map from the REST shape" \
    '{"state":"open","assignees":["a"],"labels":["l"],"type":"Bug","url":"https://github.com/o/r/issues/1","created_at":"2026-03-01T10:00:00Z"}' \
    "$(jq -c '.items[0] | {state, assignees, labels, type, url, created_at}' <<<"$OUT")"
  assert_eq "REST session: under the ceiling → truncated:false" "false" "$(jq -c '.truncated' <<<"$OUT")"

  # The label is a REST query parameter, so the 1000-result search cap does not apply.
  rest_list --label "area: ci" >/dev/null
  assert_contains "REST session: --label reaches the issues endpoint" "$(cat "$REST/argv")" "labels=area: ci"

  # A full page fetches the next; one row past the ceiling marks the listing truncated.
  # Each row carries a 2 KB body, so a page is past Linux's 128 KiB limit on one argument.
  jq '.limits.list_items_max = 150' "$(dirname "$S")/capabilities.json" >"$FIX/adapters/github/capabilities.json"
  jq -cn '[range(1; 101) | {number: ., title: "t", state: "open", assignees: [], labels: [], body: ("x" * 2048),
    html_url: "u", created_at: "2026-03-01T10:00:00Z", issue_dependencies_summary: {total_blocked_by: 0}}]' >"$REST/page-1.json"
  jq -cn '[range(101; 161) | {number: ., title: "t", state: "open", assignees: [], labels: [], body: ("x" * 2048),
    html_url: "u", created_at: "2026-03-01T10:00:00Z", issue_dependencies_summary: {total_blocked_by: 0}}]' >"$REST/page-2.json"
  OUT="$(rest_list)"
  assert_contains "REST session: a full page fetches page 2" "$(cat "$REST/argv")" "-f page=2"
  assert_eq "REST session: past the ceiling → truncated:true" "true" "$(jq -c '.truncated' <<<"$OUT")"
  assert_eq "REST session: past the ceiling keeps the ceiling's worth" "150" "$(jq '.items | length' <<<"$OUT")"
fi

[[ $FAILED -eq 0 ]] || exit 1
