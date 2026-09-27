# shellcheck shell=bash
# shellcheck disable=SC2034  # JIRA_FIX/OUT/RC are read by the sourcing test files, not within this helper
# Offline fixture harness shared by this adapter's verb tests. Sourced, never run.
#
# Every verb path is exercised against a MOCK curl injected through WIT_JIRA_CURL, so no
# test in this adapter touches the network.
#
# The mock answers by CALL COUNT rather than by URL, because this adapter's read verbs
# issue one request per page in a fixed order: the Nth call gets the seeded
# "$JIRA_FIX/<n>.body" and "$JIRA_FIX/<n>.status", defaulting to `{}` and 200. Each
# call's argv is recorded to "$JIRA_FIX/<n>.args" so a test can assert the payload that
# was actually sent, and the absence of "$JIRA_FIX/.counter" proves no call was made.

JIRA_FIX=""

# jira_fixture_init: a temp dir holding the mock curl. Call once per test file; pair
# with a trap that removes JIRA_FIX.
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

# jira_write_binding <project-keys-json>: a valid jira binding declaring those keys as
# the read scope.
jira_write_binding() {
  jq -cn --argjson pk "$1" \
    '{schema_version:"1.0", provider:"jira",
      config:{lease_ttl_hours:24,
        jira:{site:"test.atlassian.net", project_keys:$pk,
          auth_email:"ci@test.example", auth_env:"JIRA_TEST_TOKEN"}}}' \
    >"$JIRA_FIX/binding.json"
}

# jira_run <script> <args…>: run a verb against the fixture from a cleared call
# counter, setting OUT to its stdout and RC to its exit code.
jira_run() {
  local script="$1"
  shift
  rm -f "$JIRA_FIX/.counter"
  OUT="$(WORK_ITEM_TRACKER_BINDING="$JIRA_FIX/binding.json" WIT_JIRA_CURL="$JIRA_FIX/curl" \
    JIRA_TEST_TOKEN="dummy-token" bash "$script" "$@" 2>/dev/null)"
  RC=$?
}
