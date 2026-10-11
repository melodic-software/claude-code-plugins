#!/usr/bin/env bash
# test-scope: .github/workflows/pr-run-activity-read.yml .github/actions/request-lane-token/action.yml
# Runs the shell of two read-lane broker-check steps, lifted from their YAML,
# against the cases the contract states
# (docs/conventions/pr-pipeline/pr-run-activity.md, "The broker-check job"):
#   - the run job's "Assert the broker allowed this attempt" step passes only
#     when broker-check allowed this same run attempt;
#   - request-lane-token's check mode accepts only an https URL whose last path
#     segment is /token.
# Needs node and the yaml package (npm ci --prefix .github/standards/runner-policy).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
POLICY_DIR="$ROOT/.github/standards/runner-policy"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# lift <yaml-file> <js-path-expression> <out>: writes the run block found at
# the expression (evaluated on the parsed document `d`) as a bash script.
lift() {
  node -e '
    const { createRequire } = require("node:module");
    const req = createRequire(process.argv[1] + "/package.json");
    const yaml = req("yaml");
    const fs = require("node:fs");
    const d = yaml.parse(fs.readFileSync(process.argv[2], "utf8"));
    const run = eval(process.argv[3]);
    if (typeof run !== "string") process.exit(1);
    fs.writeFileSync(process.argv[4], "#!/usr/bin/env bash\n" + run);
  ' "$POLICY_DIR" "$1" "$2" "$3"
}

GATE="$WORK/gate.sh"
ACTION="$WORK/action.sh"
lift "$ROOT/.github/workflows/pr-run-activity-read.yml" \
  'd.jobs.run.steps.find((s) => s.name === "Assert the broker allowed this attempt")?.run' "$GATE" ||
  fail "the run job has no 'Assert the broker allowed this attempt' step"
lift "$ROOT/.github/actions/request-lane-token/action.yml" 'd.runs.steps[0].run' "$ACTION" ||
  fail "request-lane-token has no run block"

# gate_case <label> <expected-rc> <allowed> <allowed-attempt> <run-attempt>
gate_case() {
  local out rc
  out="$(ALLOWED="$3" ALLOWED_ATTEMPT="$4" RUN_ATTEMPT="$5" bash "$GATE" 2>&1)"
  rc=$?
  if [[ $rc -ne $2 ]]; then
    fail "$1: expected rc=$2, got rc=$rc: $out"
  elif [[ $2 -ne 0 && $out != *"::error::kill-switch:"* ]]; then
    fail "$1: the failure is not reported as kill-switch: $out"
  else
    ok "$1"
  fi
}

gate_case "an allow from this attempt proceeds" 0 true 1 1
gate_case "an allow reused from an earlier attempt fails" 1 true 1 2
gate_case "no allow (the broker was skipped) fails" 1 false 2 2
gate_case "no broker-check outputs at all fails" 1 "" "" 1

# url_case <label> <url> <must-name>: runs check mode with no OIDC grant, so
# a URL that passes validation stops at the OIDC check instead.
url_case() {
  local out
  out="$(MODE=check BROKER_URL="$2" AUDIENCE=aud LANE=pr-review ACTIVITY=claude \
    EFFECT='' CONTENTS='' PULL_REQUESTS='' ISSUES='' PR_NUMBER='' \
    ACTIONS_ID_TOKEN_REQUEST_URL='' ACTIONS_ID_TOKEN_REQUEST_TOKEN='' \
    GITHUB_STEP_SUMMARY="$WORK/summary" RUNNER_TEMP="$WORK" bash "$ACTION" 2>&1)"
  if [[ $out == *"$3"* ]]; then
    ok "$1"
  else
    fail "$1: '$3' not in output: $out"
  fi
}

REFUSED="does not end in a /token path segment"
ACCEPTED="it needs permissions id-token: write"
url_case "check mode refuses https://token" "https://token" "$REFUSED"
url_case "check mode refuses a host with no path" "https://h.example" "$REFUSED"
url_case "check mode refuses a last segment that only ends in token" "https://h.example/api/xtoken" "$REFUSED"
url_case "check mode accepts https://<host>/api/token" "https://h.example/api/token" "$ACCEPTED"
url_case "check mode accepts https://<host>/token" "https://h.example/token" "$ACCEPTED"

test_harness::report
