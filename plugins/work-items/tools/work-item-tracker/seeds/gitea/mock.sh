# shellcheck shell=bash
# shellcheck disable=SC2034  # GITEA_OUT/GITEA_ERR/GITEA_FIX/GITEA_MOCK are read by the sourcing test files, not within this helper

GITEA_FIX=""
GITEA_MOCK=""

gitea_fixture_init() {
  GITEA_FIX="$(mktemp -d)"
  GITEA_MOCK="$GITEA_FIX/bin"
  mkdir -p "$GITEA_MOCK"
  : >"$GITEA_FIX/routes"
  : >"$GITEA_FIX/requests"

  cat >"$GITEA_MOCK/curl" <<'MOCK'
#!/usr/bin/env bash
# Mock curl. Reads the -K stdin config to recover the request URL (that is where the
# real adapter puts it, so this also proves the URL never traveled in argv), records
# the request, and replies from the seeded route table.
fix="$(cd "$(dirname "$0")/.." && pwd)"
url="$(sed -n 's/^url = "\(.*\)"$/\1/p')"
method="GET"
dumpfile=""
prev=""
for a in "$@"; do
  if [[ "$prev" == "-X" ]]; then method="$a"; fi
  # The adapter passes -D <file> to capture response headers; honor it so the
  # X-Total-Count path is exercised rather than silently falling back.
  if [[ "$prev" == "-D" ]]; then dumpfile="$a"; fi
  prev="$a"
done
printf '%s %s\n' "$method" "$url" >>"$fix/requests"
while IFS=$'\t' read -r pat status body headers; do
  [[ -n "$pat" ]] || continue
  if [[ "$url" == *"$pat"* ]]; then
    if [[ -n "$dumpfile" ]]; then
      {
        printf 'HTTP/1.1 %s\r\n' "$status"
        [[ -z "$headers" ]] || printf '%s\r\n' "$headers"
        printf '\r\n'
      } >"$dumpfile"
    fi
    printf '%s\n%s' "$body" "$status"
    exit 0
  fi
done <"$fix/routes"
# Even an unseeded URL must leave a well-formed header dump, or the adapter would read
# a stale file from a previous call.
[[ -z "$dumpfile" ]] || printf 'HTTP/1.1 599\r\n\r\n' >"$dumpfile"
# An unseeded URL is a test bug, not a provider condition: answer 599 so the verb
# fails loudly rather than treating an empty body as a valid response.
printf '%s\n%s' '{"message":"unseeded url in mock"}' '599'
MOCK
  chmod +x "$GITEA_MOCK/curl"

  gitea_write_binding
}

gitea_write_binding() {
  jq -cn --argjson extra "${1:-{\}}" \
    '{schema_version:"1.0", provider:"gitea",
      config:{lease_ttl_hours:24,
        gitea:({host:"git.example.invalid", scopes:["acme/webapp"],
          auth_env:"WIT_GITEA_TEST_TOKEN"} + $extra)}}' \
    >"$GITEA_FIX/binding.json"
}

gitea_seed() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >>"$GITEA_FIX/routes"
}

gitea_seed_total() {
  gitea_seed "$1" "$2" "$3" "X-Total-Count: $4"
}

gitea_reset_routes() {
  : >"$GITEA_FIX/routes"
  : >"$GITEA_FIX/requests"
}

gitea_requests() { cat "$GITEA_FIX/requests"; }

gitea_run() {
  WORK_ITEM_TRACKER_BINDING="$GITEA_FIX/binding.json" \
    WIT_GITEA_CURL="$GITEA_MOCK/curl" \
    WIT_GITEA_TEST_TOKEN="mock-token" \
    bash "$@" >"$GITEA_FIX/stdout" 2>"$GITEA_FIX/stderr"
  printf '%s' "$?"
}

gitea_out() { cat "$GITEA_FIX/stdout" 2>/dev/null; }
gitea_err() { cat "$GITEA_FIX/stderr" 2>/dev/null; }

GITEA_FIX_ADAPTER=""
GITEA_SEAM_LIB=""
gitea_fixture_adapter() {
  local src f
  src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  GITEA_FIX_ADAPTER="$GITEA_FIX/adapter"
  GITEA_SEAM_LIB="${WIT_SEAM_LIB_DIR:-$src/../../lib}"
  rm -rf "$GITEA_FIX_ADAPTER"
  mkdir -p "$GITEA_FIX_ADAPTER"
  for f in "$src"/*.sh; do
    case "$f" in
    *.test.sh | */mock.sh) ;;
    *) cp "$f" "$GITEA_FIX_ADAPTER/" ;;
    esac
  done
  jq --argjson max "$1" '.limits.list_items_max = $max' "$src/capabilities.json" \
    >"$GITEA_FIX_ADAPTER/capabilities.json"
}

gitea_issue_json() {
  local number="${1:-12}" state="${2:-open}" title="${3:-a real issue}"
  jq -cn --argjson n "$number" --arg s "$state" --arg t "$title" \
    '{id: 9001, number: $n, state: $s, title: $t,
      html_url: ("https://git.example.invalid/acme/webapp/issues/" + ($n|tostring)),
      created_at: "2026-03-01T18:30:00+08:00",
      assignees: [{login: "kyle"}], labels: [{id: 3, name: "type: fix"}],
      repository: {id: 7, name: "webapp", owner: "acme", full_name: "acme/webapp"},
      pull_request: null, body: "not carried by the seam"}'
}
