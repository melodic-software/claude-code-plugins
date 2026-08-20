# shellcheck shell=bash
# shellcheck disable=SC2034  # LIN_FIX/LIN_MOCK are read by the sourcing test files
# Offline fixture harness shared by this adapter's verb tests. Sourced, never run.
#
# Every verb path is exercised against a MOCK curl injected through WIT_LINEAR_CURL, so
# no test in this adapter touches the network. That is not merely convenient: no Linear
# workspace is reachable from the environment this adapter was built in, and the
# alternative to mocked coverage is no coverage — see README.md "Recorded deferrals".
#
# Linear has ONE endpoint, so unlike a REST mock this cannot route on the URL. It routes
# on a substring of the GraphQL DOCUMENT instead (`viewer`, `issueCreate`, `comments(`),
# which is what distinguishes one operation from another here. Responses are seeded with
# lin_seed <document-substring> <data-json>; first match wins, so seed the most specific
# pattern first.

LIN_FIX=""
LIN_MOCK=""

lin_fixture_init() {
  LIN_FIX="$(mktemp -d)"
  LIN_MOCK="$LIN_FIX/bin"
  mkdir -p "$LIN_MOCK"
  : >"$LIN_FIX/routes"
  : >"$LIN_FIX/requests"

  cat >"$LIN_MOCK/curl" <<'MOCK'
#!/usr/bin/env bash
# Mock curl for Linear's single GraphQL endpoint. The request body arrives via --data,
# so argv carries it; the stdin config carries only the URL and the Authorization
# header, which is the separation the real adapter depends on.
d="$(cd "$(dirname "$0")" && pwd)"
fix="$(dirname "$d")"
cfg="$(cat)"
url="$(printf '%s' "$cfg" | sed -n 's/^url = "\(.*\)"$/\1/p')"
body=""
prev=""
for a in "$@"; do
  if [[ "$prev" == "--data" ]]; then body="$a"; fi
  prev="$a"
done
query="$(printf '%s' "$body" | jq -r '.query // ""' 2>/dev/null)"
printf '%s\t%s\n' "$url" "$(printf '%s' "$query" | tr '\n' ' ')" >>"$fix/requests"
printf '%s\n' "$body" >>"$fix/bodies"

# Routes sharing a pattern form a SEQUENCE: the first matching call takes the first,
# the second the second, and the last route repeats from then on. That is what lets a
# test model a race — the same comments query answering "no lease yet" on the
# pre-check and "a rival appeared" on the arbitration re-read. A single static response
# per pattern cannot express that, and a race test written against one is really
# testing the pre-check twice.
matched=""
idx=0
want=""
while IFS=$'\t' read -r pat status payload; do
  [[ -n "$pat" ]] || continue
  [[ "$query" == *"$pat"* ]] || continue
  if [[ -z "$matched" ]]; then
    matched="$pat"
    # How many times this pattern has already answered.
    key="$(printf '%s' "$pat" | tr -c 'A-Za-z0-9' '_')"
    want="$(cat "$fix/hits.$key" 2>/dev/null || echo 0)"
    printf '%s' "$((want + 1))" >"$fix/hits.$key"
  fi
  [[ "$pat" == "$matched" ]] || continue
  # Remember every route for this pattern; the one at index `want` wins, and an index
  # past the end falls back to the last (so a single route repeats, as before).
  if ((idx <= want)); then
    chosen_status="$status"
    chosen_payload="$payload"
  fi
  idx=$((idx + 1))
done <"$fix/routes"
if [[ -n "$matched" ]]; then
  printf '%s\n%s' "$chosen_payload" "$chosen_status"
  exit 0
fi
# An unseeded operation is a test bug, not a provider condition: answer with a GraphQL
# error so the verb fails loudly rather than reading an empty data object as success.
printf '%s\n%s' '{"errors":[{"message":"unseeded operation in mock"}]}' '200'
MOCK
  chmod +x "$LIN_MOCK/curl"

  lin_write_binding
}

# lin_write_binding [<extra-linear-config-json>] — a valid linear binding.
lin_write_binding() {
  jq -cn --argjson extra "${1:-{\}}" \
    '{schema_version:"1.0", provider:"linear",
      config:{lease_ttl_hours:24,
        linear:({host:"api.linear.app", scopes:["acme/ENG"],
          auth_env:"WIT_LINEAR_TEST_KEY"} + $extra)}}' \
    >"$LIN_FIX/binding.json"
}

# lin_seed <document-substring> <status> <response-json> — add a route.
lin_seed() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$LIN_FIX/routes"; }

# lin_data <document-substring> <data-json> — the common case: HTTP 200 with a data
# object.
lin_data() { lin_seed "$1" 200 "$(jq -cn --argjson d "$2" '{data: $d}')"; }

lin_reset() {
  : >"$LIN_FIX/routes"
  : >"$LIN_FIX/requests"
  : >"$LIN_FIX/bodies"
  rm -f "$LIN_FIX"/hits.* 2>/dev/null || true
}

# lin_comments <nodes-json>… — seed the comments query, one response per call in order.
# Two arguments model a race: what the pre-check sees, then what the arbitration re-read
# sees after a rival's lease has landed.
lin_comments() {
  local nodes
  for nodes in "$@"; do
    lin_data 'comments(' "$(jq -cn --argjson n "$nodes" \
      '{issue: {comments: {nodes: $n, pageInfo: {hasNextPage: false}}}}')"
  done
}

lin_requests() { cat "$LIN_FIX/requests" 2>/dev/null; }
lin_bodies() { cat "$LIN_FIX/bodies" 2>/dev/null; }

# lin_run <script> <args…> — run a verb against the fixture and ECHO its exit code.
# Streams go to files because this is called inside a command substitution; read them
# with lin_out / lin_err.
lin_run() {
  local script="$1"
  shift
  local rc
  WORK_ITEM_TRACKER_BINDING="$LIN_FIX/binding.json" \
    WIT_LINEAR_CURL="$LIN_MOCK/curl" \
    WIT_LINEAR_TEST_KEY="mock-key" \
    bash "$script" "$@" >"$LIN_FIX/stdout" 2>"$LIN_FIX/stderr"
  rc=$?
  printf '%s' "$rc"
}

lin_out() { cat "$LIN_FIX/stdout" 2>/dev/null; }
lin_err() { cat "$LIN_FIX/stderr" 2>/dev/null; }

# A stock Linear issue node, selected the way WIT_LINEAR_ISSUE_FIELDS selects. Field
# names are the real ones from Linear's published schema, so an upstream rename shows up
# here as a failing test rather than as a silently empty normalized field.
lin_issue_json() {
  local number="${1:-12}" state_type="${2:-started}" title="${3:-a real issue}"
  jq -cn --argjson n "$number" --arg st "$state_type" --arg t "$title" \
    '{id: ("uuid-issue-" + ($n|tostring)),
      identifier: ("ENG-" + ($n|tostring)),
      number: $n, title: $t,
      url: ("https://linear.app/acme/issue/ENG-" + ($n|tostring)),
      state: {type: $st, name: "In Progress"},
      assignee: {displayName: "kyle", email: "kyle@example.invalid"},
      labels: {nodes: [{name: "type: fix"}]},
      parent: null,
      team: {key: "ENG"},
      inverseRelations: {nodes: []}}'
}

# lin_seed_issue <number> [state-type] — the by-(team,number) fetch the verbs use.
lin_seed_issue() {
  lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json "$1" "${2:-started}")" \
    '{issues: {nodes: [$i]}}')"
}

# lin_lease_body <handle> <holder> <renewed-at> [ttl-hours] [superseded-at] — a comment
# body carrying a lease marker.
lin_lease_body() {
  local marker
  marker="$(jq -cn --argjson h "$1" --arg holder "$2" --arg t "$3" \
    --argjson ttl "${4:-24}" --arg sup "${5:-}" \
    '{schema_version: "1.0", holder: $holder, acquired_at: $t, renewed_at: $t,
      ttl_hours: $ttl, ttl_minutes: 0, lease_comment_id: $h}
     + (if ($sup | length) > 0 then {superseded_at: $sup} else {} end)')"
  printf '<!-- work-item-lease v1 %s -->' "$marker"
}
