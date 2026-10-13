#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# list-items: offline contract tests. Pagination, state filtering, and the scope
# boundary are driven through a mocked curl — no live Linear call.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-items.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" --state
assert_usage_error "$S" --state sideways
assert_usage_error "$S" --repo

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

# --repo is caller text that reaches a request variable, so it faces the same anchored
# allowlist the binding's own scopes did, then the scope list itself.
rc="$(lin_run "$S" --repo "ENG")"
assert_eq "--repo without a workspace → exit 2" "2" "$rc"
rc="$(lin_run "$S" --repo "acme/eng")"
assert_eq "lowercase team key → exit 2" "2" "$rc"
rc="$(lin_run "$S" --repo "acme/OPS")"
assert_eq "undeclared team → exit 2" "2" "$rc"
assert_contains "refusal names the declared scope" "$(lin_err)" "config.linear.scopes"
assert_eq "and nothing was requested" "" "$(lin_requests)"

# seed_page <nodes-json> [has-next] [cursor]
seed_page() {
  lin_data 'issues(filter:' "$(jq -cn --argjson n "$1" --argjson h "${2:-false}" --arg c "${3:-}" \
    '{issues: {nodes: $n, pageInfo: {hasNextPage: $h, endCursor: $c}}}')"
}

# --- the declared scope is the default target ---
lin_reset
seed_page "[$(lin_issue_json 12 started)]"
rc="$(lin_run "$S")"
assert_eq "listing → exit 0" "0" "$rc"
assert_eq "envelope schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
assert_eq "one item" "1" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_eq "item id is fully qualified" "linear:acme/ENG#12" "$(jq -r '.items[0].id' <<<"$(lin_out)")"
# The filter travels as a VARIABLE, never interpolated into the query text.
assert_contains "teams travel in the filter variable" "$(lin_bodies)" '"team":{"key":{"in":["ENG"]}}'
assert_contains "an explicit page size is sent" "$(lin_bodies)" '"first":50'
assert_not_contains "no label filter unless asked" "$(lin_bodies)" '"labels"'

# --- the state and label filters travel in the query ---
# Built from done_state_types, the set the normalizer classifies with.
lin_reset
seed_page '[]'
lin_run "$S" --state open >/dev/null
assert_contains "--state open excludes the done types in the query" "$(lin_bodies)" \
  '"state":{"type":{"nin":["completed","canceled","duplicate"]}}' # spellchecker:disable-line
lin_reset
seed_page '[]'
lin_run "$S" --state closed >/dev/null
assert_contains "--state closed asks for the done types" "$(lin_bodies)" \
  '"state":{"type":{"in":["completed","canceled","duplicate"]}}'
lin_reset
seed_page '[]'
lin_run "$S" --state all >/dev/null
assert_not_contains "--state all sends no state filter" "$(lin_bodies)" '"state"'
lin_reset
seed_page '[]'
lin_run "$S" --label "area: ci" >/dev/null
assert_contains "--label asks for issues carrying that label" "$(lin_bodies)" \
  '"labels":{"some":{"name":{"eq":"area: ci"}}}'
assert_usage_error "$S" --label
assert_usage_error "$S" --label ""

# --- the normalized state is still checked after the query ---
lin_reset
seed_page "$(jq -cn --argjson o "$(lin_issue_json 12 started)" --argjson c "$(lin_issue_json 13 completed)" '[$o, $c]')"
rc="$(lin_run "$S" --state open)"
assert_eq "--state open → exit 0" "0" "$rc"
assert_eq "only the open item" "1" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_eq "and it is the open one" "linear:acme/ENG#12" "$(jq -r '.items[0].id' <<<"$(lin_out)")"

lin_reset
seed_page "$(jq -cn --argjson o "$(lin_issue_json 12 started)" --argjson c "$(lin_issue_json 13 completed)" '[$o, $c]')"
lin_run "$S" --state closed >/dev/null
assert_eq "--state closed returns only the closed item" "linear:acme/ENG#13" "$(jq -r '.items[0].id' <<<"$(lin_out)")"

lin_reset
seed_page "$(jq -cn --argjson o "$(lin_issue_json 12 started)" --argjson c "$(lin_issue_json 13 completed)" '[$o, $c]')"
lin_run "$S" --state all >/dev/null
assert_eq "--state all returns both" "2" "$(jq -r '.items | length' <<<"$(lin_out)")"

# The override reaches list filtering too, not just get-item.
lin_write_binding '{"done_state_types":["canceled"]}'
lin_reset
seed_page "[$(lin_issue_json 13 completed)]"
lin_run "$S" --state open >/dev/null
assert_eq "done_state_types override reclassifies for listing" "1" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_contains "and reaches the query filter" "$(lin_bodies)" '"state":{"type":{"nin":["canceled"]}}' # spellchecker:disable-line
lin_write_binding

# --- pagination follows the cursor ---
lin_reset
seed_page "[$(lin_issue_json 12 started)]" true "cursor-1"
seed_page "[$(lin_issue_json 13 started)]" false ""
rc="$(lin_run "$S")"
assert_eq "paged listing → exit 0" "0" "$rc"
assert_eq "both pages collected" "2" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_contains "the cursor is sent on the second call" "$(lin_bodies)" '"after":"cursor-1"'
assert_eq "a listing whose last page arrived carries truncated:false" "false" "$(jq -c '.truncated' <<<"$(lin_out)")"

# --- the declared ceiling ends the walk and the envelope says so ---
# A fixture copy of the adapter declares a ceiling of 2, so two one-item pages reach it
# and the third page, asked for one node past the ceiling, proves more exist.
FIX_ADAPTER="$LIN_FIX/adapter"
mkdir -p "$FIX_ADAPTER"
cp "$D"/*.sh "$FIX_ADAPTER/"
jq '.limits.list_items_max = 2' "$D/capabilities.json" >"$FIX_ADAPTER/capabilities.json"
lin_reset
seed_page "[$(lin_issue_json 12 started)]" true "cursor-1"
seed_page "[$(lin_issue_json 13 started)]" true "cursor-2"
seed_page "[$(lin_issue_json 14 started)]" true "cursor-3"
rc="$(WIT_SEAM_LIB_DIR="$D/../../lib" lin_run "$FIX_ADAPTER/list-items.sh")"
assert_eq "a walk stopped at the ceiling → exit 0 (documented truncation)" "0" "$rc"
assert_eq "the ceiling's worth of items" "2" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_eq "and the envelope carries truncated:true" "true" "$(jq -c '.truncated' <<<"$(lin_out)")"
assert_contains "and stderr announces it" "$(lin_err)" "ceiling of 2 items"
assert_contains "the page after the ceiling asks for one node" "$(lin_bodies)" '"first":1'

# --- a ceiling below the page size bounds one page too ---
# Ceiling 25, 30 issues: the request asks for 26, and a provider that returns all 30 on
# one last page still yields 25 items and truncated:true, never 30 and false.
jq '.limits.list_items_max = 25' "$D/capabilities.json" >"$FIX_ADAPTER/capabilities.json"
THIRTY="$(for n in $(seq 1 30); do lin_issue_json "$n" started; done | jq -cs '.')"
lin_reset
seed_page "$THIRTY"
rc="$(WIT_SEAM_LIB_DIR="$D/../../lib" lin_run "$FIX_ADAPTER/list-items.sh")"
assert_eq "ceiling 25, 30 issues → exit 0" "0" "$rc"
assert_eq "ceiling 25, 30 issues: 25 items" "25" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_eq "ceiling 25, 30 issues: truncated:true" "true" "$(jq -c '.truncated' <<<"$(lin_out)")"
assert_contains "the first page asks for one node past the ceiling" "$(lin_bodies)" '"first":26'
TWENTY_FIVE="$(jq -c '.[:25]' <<<"$THIRTY")"
lin_reset
seed_page "$TWENTY_FIVE"
rc="$(WIT_SEAM_LIB_DIR="$D/../../lib" lin_run "$FIX_ADAPTER/list-items.sh")"
assert_eq "exactly the ceiling: 25 items" "25" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_eq "exactly the ceiling: truncated:false" "false" "$(jq -c '.truncated' <<<"$(lin_out)")"

# --- the ceiling counts only issues the filter matches (#7173) ---
# A server that applies whatever filter it is sent, over a team holding three closed
# issues (more than a ceiling of 2) and one open one. Fetching the whole team and
# dropping closed issues afterward hits the ceiling and reports truncated:true; sending
# the filter lists the one open issue, complete.
SERVER="$LIN_FIX/server"
mkdir -p "$SERVER"
jq -cn --argjson a "$(lin_issue_json 1 completed)" --argjson b "$(lin_issue_json 2 canceled)" \
  --argjson c "$(lin_issue_json 3 completed)" --argjson d "$(lin_issue_json 4 started)" \
  '[$a, $b, $c, $d] | .[3].labels.nodes = [{name: "area: ci"}]' >"$SERVER/team.json"
cat >"$SERVER/curl" <<'SERVER_CURL'
#!/usr/bin/env bash
cat >/dev/null
body=""
prev=""
for a in "$@"; do
  [[ "$prev" == "--data" ]] && body="$a"
  prev="$a"
done
d="$(cd "$(dirname "$0")" && pwd)"
jq -c --argjson v "$(jq -c '.variables' <<<"$body")" '
  ($v.filter // {}) as $f
  | [.[] | .state.type as $t | [.labels.nodes[].name] as $names
         | select(($f.state.type.nin // null) as $nin | $nin == null or ($nin | index($t)) == null) # spellchecker:disable-line
         | select(($f.state.type.in // null) as $in | $in == null or ($in | index($t)) != null)
         | select(($f.labels.some.name.eq // null) as $l | $l == null or ($names | index($l)) != null)]
  | (($v.after // "0") | tonumber) as $from
  | {data: {issues: {nodes: .[$from:$from + $v.first],
      pageInfo: {hasNextPage: (length > $from + $v.first), endCursor: (($from + $v.first) | tostring)}}}}
' "$d/team.json"
printf '200'
SERVER_CURL
chmod +x "$SERVER/curl"
jq '.limits.list_items_max = 2' "$D/capabilities.json" >"$FIX_ADAPTER/capabilities.json"
rc="$(WIT_SEAM_LIB_DIR="$D/../../lib" WIT_LINEAR_CURL="$SERVER/curl" \
  WORK_ITEM_TRACKER_BINDING="$LIN_FIX/binding.json" WIT_LINEAR_TEST_KEY="mock-key" \
  bash "$FIX_ADAPTER/list-items.sh" --state open >"$LIN_FIX/stdout" 2>"$LIN_FIX/stderr"; echo $?)"
assert_eq "closed issues past the ceiling, one open → exit 0" "0" "$rc"
assert_eq "the open issue is listed" "linear:acme/ENG#4" "$(jq -r '[.items[].id] | join(",")' <<<"$(lin_out)")"
assert_eq "and the listing is complete" "false" "$(jq -c '.truncated' <<<"$(lin_out)")"
rc="$(WIT_SEAM_LIB_DIR="$D/../../lib" WIT_LINEAR_CURL="$SERVER/curl" \
  WORK_ITEM_TRACKER_BINDING="$LIN_FIX/binding.json" WIT_LINEAR_TEST_KEY="mock-key" \
  bash "$FIX_ADAPTER/list-items.sh" --state all --label "area: ci" >"$LIN_FIX/stdout" 2>"$LIN_FIX/stderr"; echo $?)"
assert_eq "a label carried by one of four issues, ceiling 2 → complete" "linear:acme/ENG#4 false" \
  "$(jq -r '([.items[].id] | join(",")) + " " + (.truncated | tostring)' <<<"$(lin_out)")"

# An empty result is an empty envelope, never an error.
lin_reset
seed_page '[]'
rc="$(lin_run "$S")"
assert_eq "no issues → exit 0" "0" "$rc"
assert_eq "empty items array" "0" "$(jq -r '.items | length' <<<"$(lin_out)")"

# --- multiple declared teams are all listed, and --repo narrows ---
lin_write_binding '{"scopes":["acme/ENG","acme/OPS"]}'
lin_reset
seed_page '[]'
lin_run "$S" >/dev/null
assert_contains "both declared teams are queried" "$(lin_bodies)" '"in":["ENG","OPS"]'
lin_reset
seed_page '[]'
lin_run "$S" --repo "acme/OPS" >/dev/null
assert_contains "--repo narrows to one team" "$(lin_bodies)" '"team":{"key":{"in":["OPS"]}}'
lin_write_binding

# --- a scopes list spanning two workspaces is a config error ---
# One API key reaches exactly one workspace, so such a binding describes something it
# cannot address — better refused than half-working.
lin_write_binding '{"scopes":["acme/ENG","other/OPS"]}'
lin_reset
rc="$(lin_run "$S")"
assert_eq "scopes across two workspaces → exit 3" "3" "$rc"
assert_contains "and says why" "$(lin_err)" "one workspace"
lin_write_binding

# --- GraphQL errors inside a 200 still fail ---
lin_reset
lin_seed 'issues(filter:' 200 '{"errors":[{"message":"nope","extensions":{"type":"AuthenticationError"}}]}'
rc="$(lin_run "$S")"
assert_eq "GraphQL auth error → exit 4" "4" "$rc"

[[ $FAILED -eq 0 ]] || exit 1
