# shellcheck shell=bash
# shellcheck disable=SC2034  # JIRA_FIX/OUT/ERR/RC are read by the sourcing test files, not within this helper

JIRA_FIX=""

jira_fixture_init() {
  JIRA_FIX="$(mktemp -d)"
  cat >"$JIRA_FIX/curl" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null 2>&1  # drain the -K - config on stdin
d="$(cd "$(dirname "$0")" && pwd)"
n=$(( $(cat "$d/.counter" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" >"$d/.counter"
printf '%s\n' "$@" >"$d/$n.args"  # record argv so tests can assert the sent payload
st="$(cat "$d/$n.status" 2>/dev/null || echo 200)"
b="$(cat "$d/$n.body" 2>/dev/null || echo '{}')"
printf '%s\n%s' "$b" "$st"
MOCK
  chmod +x "$JIRA_FIX/curl"
}

jira_write_binding() {
  local extra="${2:-}"
  [[ -n "$extra" ]] || extra='{}'
  jq -cn --argjson pk "$1" --argjson extra "$extra" \
    '{schema_version:"1.0", provider:"jira",
      config:{lease_ttl_hours:24,
        jira:({site:"test.atlassian.net", project_keys:$pk,
          auth_email:"ci@test.example", auth_env:"JIRA_TEST_TOKEN"} + $extra)}}' \
    >"$JIRA_FIX/binding.json"
}

jira_run() {
  local script="$1"
  shift
  rm -f "$JIRA_FIX/.counter"
  OUT="$(WORK_ITEM_TRACKER_BINDING="$JIRA_FIX/binding.json" WIT_JIRA_CURL="$JIRA_FIX/curl" \
    JIRA_TEST_TOKEN="dummy-token" bash "$script" "$@" 2>"$JIRA_FIX/stderr")"
  RC=$?
  ERR="$(cat "$JIRA_FIX/stderr")"
}
