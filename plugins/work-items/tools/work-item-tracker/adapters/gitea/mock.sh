# shellcheck shell=bash
# shellcheck disable=SC2034  # GITEA_OUT/GITEA_ERR/GITEA_FIX/GITEA_MOCK are read by the sourcing test files, not within this helper
# Offline fixture harness shared by this adapter's verb tests. Sourced, never run.
#
# Every verb path is exercised against a MOCK curl injected through WIT_GITEA_CURL, so
# no test in this adapter touches the network. That is not merely convenient: no live
# Gitea instance is reachable from the environment this adapter was built in, and the
# alternative to mocked coverage is no coverage — see README.md "Recorded deferrals".
#
# The mock answers by REQUEST URL rather than by call count, because Gitea's verbs
# interleave several endpoints (issues, dependencies, labels) and a count-indexed mock
# would silently pass while answering the wrong endpoint. Responses are seeded with
# gitea_seed <url-substring> <status> <body-json>; the first seeded substring that the
# requested URL contains wins, so more specific patterns must be seeded first.

GITEA_FIX=""
GITEA_MOCK=""

# gitea_fixture_init — a temp dir holding the mock curl, a valid binding, and the
# response table. Call once per test file; pair with a trap that removes GITEA_FIX.
gitea_fixture_init() {
  GITEA_FIX="$(mktemp -d)"
  GITEA_MOCK="$GITEA_FIX/bin"
  mkdir -p "$GITEA_MOCK"
  : >"$GITEA_FIX/routes"
  : >"$GITEA_FIX/requests"

  cat >"$GITEA_MOCK/curl" <<'MOCK'
#!/usr/bin/env bash
# Mock curl. Reads the -K stdin config to recover the request URL (that is where the
# real adapter puts it, so this also proves the URL never travelled in argv), records
# the request, and replies from the seeded route table.
d="$(cd "$(dirname "$0")" && pwd)"
fix="$(dirname "$d")"
cfg="$(cat)"
url="$(printf '%s' "$cfg" | sed -n 's/^url = "\(.*\)"$/\1/p')"
method="GET"
prev=""
for a in "$@"; do
  if [[ "$prev" == "-X" ]]; then method="$a"; fi
  prev="$a"
done
printf '%s %s\n' "$method" "$url" >>"$fix/requests"
while IFS=$'\t' read -r pat status body; do
  [[ -n "$pat" ]] || continue
  if [[ "$url" == *"$pat"* ]]; then
    printf '%s\n%s' "$body" "$status"
    exit 0
  fi
done <"$fix/routes"
# An unseeded URL is a test bug, not a provider condition: answer 599 so the verb
# fails loudly rather than treating an empty body as a valid response.
printf '%s\n%s' '{"message":"unseeded url in mock"}' '599'
MOCK
  chmod +x "$GITEA_MOCK/curl"

  gitea_write_binding
}

# gitea_write_binding [<extra-config-json>] — a valid gitea binding, optionally merged
# with extra keys for the case under test.
gitea_write_binding() {
  jq -cn --argjson extra "${1:-{\}}" \
    '{schema_version:"1.0", provider:"gitea",
      config:{lease_ttl_hours:24,
        gitea:({host:"git.example.invalid", scopes:["acme/webapp"],
          auth_env:"WIT_GITEA_TEST_TOKEN"} + $extra)}}' \
    >"$GITEA_FIX/binding.json"
}

# gitea_seed <url-substring> <status> <body-json> — add a route. Seeded order is match
# order, so seed the most specific substring first.
gitea_seed() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$GITEA_FIX/routes"
}

# gitea_reset_routes — drop every seeded route and the recorded request log.
gitea_reset_routes() {
  : >"$GITEA_FIX/routes"
  : >"$GITEA_FIX/requests"
}

# gitea_requests — the recorded "<METHOD> <URL>" lines, one per request.
gitea_requests() { cat "$GITEA_FIX/requests"; }

# gitea_run <script> <args…> — run a verb against the fixture and ECHO its exit code,
# so it reads as `rc="$(gitea_run ...)"`. That makes it a subshell, which is why the
# captured streams go to FILES rather than to variables: an assignment here would not
# survive back to the caller. Read them with gitea_out / gitea_err.
gitea_run() {
  local script="$1"
  shift
  local rc
  WORK_ITEM_TRACKER_BINDING="$GITEA_FIX/binding.json" \
    WIT_GITEA_CURL="$GITEA_MOCK/curl" \
    WIT_GITEA_TEST_TOKEN="mock-token" \
    bash "$script" "$@" >"$GITEA_FIX/stdout" 2>"$GITEA_FIX/stderr"
  rc=$?
  printf '%s' "$rc"
}

# gitea_out / gitea_err — the streams the most recent gitea_run captured.
gitea_out() { cat "$GITEA_FIX/stdout" 2>/dev/null; }
gitea_err() { cat "$GITEA_FIX/stderr" 2>/dev/null; }

# A stock Gitea issue payload, parameterized enough for the cases that need variation.
# Field names are the real ones (modules/structs/issue.go), so a rename upstream shows
# up here as a failing test rather than as a silently empty normalized field.
gitea_issue_json() {
  local number="${1:-12}" state="${2:-open}" title="${3:-a real issue}"
  jq -cn --argjson n "$number" --arg s "$state" --arg t "$title" \
    '{id: 9001, number: $n, state: $s, title: $t,
      html_url: ("https://git.example.invalid/acme/webapp/issues/" + ($n|tostring)),
      assignees: [{login: "kyle"}], labels: [{id: 3, name: "type: fix"}],
      repository: {id: 7, name: "webapp", owner: "acme", full_name: "acme/webapp"},
      pull_request: null, body: "not carried by the seam"}'
}
