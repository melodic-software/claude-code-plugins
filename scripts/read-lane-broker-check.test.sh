#!/usr/bin/env bash
# test-scope: .github/workflows/pr-run-activity-read.yml .github/actions/request-lane-token/action.yml .github/standards/runner-policy/package.json plugins/work-items/tools/work-item-tracker/adapters/github/claim.sh plugins/work-items/tools/work-item-tracker/work-item-tracker.sh .work-item-tracker.json .github/workflows/work-resolve-issue.yml
# Runs the shell of two read-lane broker-check steps, lifted from their YAML,
# against the cases the contract states
# (docs/conventions/pr-pipeline/pr-run-activity.md, "The broker-check job"):
#   - the run job's "Assert the broker allowed this attempt" step passes only
#     when broker-check allowed this same run attempt;
#   - request-lane-token's check mode accepts only an https URL whose last path
#     segment is /token;
#   - broker-check's issue lease step backs off as already-leased on a live
#     lease older than its own, and the run job's go step then runs no model;
#   - in caller-releases mode the read runner's lease-release skips unless the
#     call handed off, and work-resolve-issue.yml releases every held handle
#     after it opened the PR and reported, on pass and fail alike.
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

# url_case <label> <url> <must-name> [dispatcher-run-id]: runs check mode with no OIDC grant, so
# a URL that passes validation stops at the OIDC check instead.
url_case() {
  local out
  out="$(MODE=check BROKER_URL="$2" AUDIENCE=aud LANE=pr-review ACTIVITY=claude \
    EFFECT='' CONTENTS='' PULL_REQUESTS='' ISSUES='' PR_NUMBER='' ISSUE_NUMBER='' DISPATCHER_RUN_ID="${4:-}" \
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
url_case "check mode refuses a dispatcher run id" "https://h.example/api/token" \
  "check mode takes no effect, grant, PR or issue number, or dispatcher run id" 123

# --- Issue lease (#9791): broker-check's claim step against a stub gh. ---
LEASE_STEP="$WORK/lease.sh"
GO_STEP="$WORK/go.sh"
lift "$ROOT/.github/workflows/pr-run-activity-read.yml" \
  'd.jobs["broker-check"].steps.find((s) => s.name === "Claim the issue with a lane lease")?.run' "$LEASE_STEP" ||
  fail "broker-check has no 'Claim the issue with a lane lease' step"
lift "$ROOT/.github/workflows/pr-run-activity-read.yml" \
  'd.jobs.run.steps.find((s) => s.id === "go")?.run' "$GO_STEP" ||
  fail "the run job has no go step"

STUB_BIN="$WORK/bin"
mkdir -p "$STUB_BIN"
# The lease list this stub returns is $LEASES; a POST returns comment id 2, and
# `gh api user` is recorded so the test can show the step never needs it.
cat >"$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
*"api user"*) echo API_USER >>"$STUB_LOG"; echo someone ;;
*"--method PATCH"*) echo "PATCH" >>"$STUB_LOG"; echo 2 ;;
*"--paginate"*) printf '%s\n' "$LEASES" ;;
*"-f body="*) echo POST >>"$STUB_LOG"; echo 2 ;;
*) echo "gh-stub: unhandled: $*" >&2; exit 90 ;;
esac
STUB
chmod +x "$STUB_BIN/gh"

lease_body() {
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '<!-- work-item-lease v1 {"schema_version":"1.0","holder":"%s","acquired_at":"%s","renewed_at":"%s","ttl_hours":2} -->' "$1" "$now" "$now"
}

# lease_case <label> <leases-json> <expected-lease> <expected-go-run>
lease_case() {
  local out rc
  : >"$WORK/output" && : >"$WORK/stub.log"
  out="$(PATH="$STUB_BIN:$PATH" STUB_LOG="$WORK/stub.log" LEASES="$2" WIT_WRITE_SPACING_S=0 \
    GH_TOKEN=x REPO=acme/widgets ISSUE_NUMBER=1 HOLDER=987654 TIMEOUT_MINUTES=40 GITHUB_RUN_ID=5 \
    TRACKER="$ROOT/plugins/work-items/tools/work-item-tracker/work-item-tracker.sh" \
    WORK_ITEM_TRACKER_BINDING="$ROOT/.work-item-tracker.json" \
    GITHUB_OUTPUT="$WORK/output" bash "$LEASE_STEP" 2>&1)"
  rc=$?
  local lease
  lease="$(sed -n 's/^lease=//p' "$WORK/output")"
  if [[ $rc -ne 0 || $lease != "$3" ]] || grep -q API_USER "$WORK/stub.log"; then
    fail "$1: rc=$rc lease=$lease, expected $3 with no gh api user: $out"
    return
  fi
  : >"$WORK/go-output"
  PRIOR='' STALE='' LEASE="$lease" GITHUB_OUTPUT="$WORK/go-output" bash "$GO_STEP"
  if [[ "$(cat "$WORK/go-output")" == "run=$4" ]]; then
    ok "$1"
  else
    fail "$1: go wrote '$(cat "$WORK/go-output")', expected run=$4"
  fi
}

OURS="$(jq -cn --arg b "$(lease_body 987654)" '[{id:2, node_id:"x", body:$b, created_at:"x", author_association:"MEMBER"}]')"
LOCAL_FIRST="$(jq -cn --arg a "$(lease_body alice)" --arg b "$(lease_body 987654)" \
  '[{id:1, node_id:"x", body:$a, created_at:"x", author_association:"MEMBER"}, {id:2, node_id:"x", body:$b, created_at:"x", author_association:"MEMBER"}]')"
lease_case "an unleased issue is claimed lease-only and the model runs" "$OURS" held true
lease_case "a live local lease makes the run exit already-leased with no model turn" "$LOCAL_FIRST" already-leased false
if grep -q '^lease-comment-id=' "$WORK/output"; then
  fail "an already-leased run hands no lease handle to lease-release"
else
  ok "an already-leased run hands no lease handle to lease-release"
fi

# --- Caller-side release (#9791): the lease outlives the read run until the
# caller has opened the PR and reported. ---
# holds <label> <yaml-file> <js-boolean-expression on d>
holds() {
  if node -e '
    const { createRequire } = require("node:module");
    const yaml = createRequire(process.argv[1] + "/package.json")("yaml");
    const d = yaml.parse(require("node:fs").readFileSync(process.argv[2], "utf8"));
    process.exit(eval(process.argv[3]) === true ? 0 : 1);
  ' "$POLICY_DIR" "$2" "$3" 2>/dev/null; then
    ok "$1"
  else
    fail "$1"
  fi
}
READ_YML="$ROOT/.github/workflows/pr-run-activity-read.yml"
CALLER_YML="$ROOT/.github/workflows/work-resolve-issue.yml"
holds "the read runner takes caller-releases-lease, a boolean defaulting to false" "$READ_YML" \
  'const i = d.on.workflow_call.inputs["caller-releases-lease"]; i?.type === "boolean" && i.default === false'
# shellcheck disable=SC2016 # the ${{ }} text is a literal the workflow must hold, compared as a string
holds "the read runner hands its lease handle to the caller" "$READ_YML" \
  'const o = d.on.workflow_call.outputs; o.lease?.value === "${{ jobs.broker-check.outputs.lease }}" && o["lease-comment-id"]?.value === "${{ jobs.broker-check.outputs.lease-comment-id }}"'
# portability-ok: \s is in a JavaScript regex run by node, not a shell tool
holds "lease-release skips in caller-releases mode unless the call handed off (scan skipped)" "$READ_YML" \
  'const c = d.jobs["lease-release"].if.replace(/\s+/g, " "); c.includes("(!inputs.caller-releases-lease || needs.scan.result == '"'skipped'"')")'
holds "every read call of work-resolve-issue.yml runs in caller-releases mode" "$CALLER_YML" \
  'Object.values(d.jobs).filter((j) => /pr-run-activity-read\.yml/.test(j.uses ?? "")).every((j) => j.with["caller-releases-lease"] === true)'
holds "work-resolve-issue.yml releases after apply-issue-patch and report-outcome, on always()" "$CALLER_YML" \
  'const j = d.jobs["release-lease"]; ["resolve-issue", "resolve-issue-subscription", "resolve-issue-fallback", "apply-issue-patch", "report-outcome"].every((n) => j.needs.includes(n)) && /^always\(\)/.test(j.if.trim())'
holds "the caller release job holds contents read and issues write only" "$CALLER_YML" \
  'JSON.stringify(d.jobs["release-lease"].permissions) === JSON.stringify({ contents: "read", issues: "write" })'

RELEASE_STEP="$WORK/release.sh"
if lift "$CALLER_YML" 'd.jobs["release-lease"]?.steps.find((s) => s.name === "Release the lane leases")?.run' "$RELEASE_STEP"; then
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s"\n' "$WORK/tracker.log" >"$WORK/tracker.sh"
  # release_case <label> <expected-rc> <expected-calls> <L1> <ID1> <L2> <ID2> <L3> <ID3>
  release_case() {
    : >"$WORK/tracker.log"
    local rc=0 out
    out="$(TRACKER="$WORK/tracker.sh" REPO=o/r ISSUE_NUMBER=5 HOLDER=987654 \
      LEASE_1="$4" LEASE_COMMENT_ID_1="$5" LEASE_2="$6" LEASE_COMMENT_ID_2="$7" \
      LEASE_3="$8" LEASE_COMMENT_ID_3="$9" bash "$RELEASE_STEP" 2>&1)" || rc=$?
    local calls
    calls="$(cat "$WORK/tracker.log")"
    if [[ $rc -ne $2 || $calls != "$3" ]]; then
      fail "$1: rc=$rc calls=[$calls]: $out"
    else
      ok "$1"
    fi
  }
  release_case "a held lease is released under the lanes App holder" 0 \
    "release github:o/r#5 --lease-comment-id 41 --holder 987654" held 41 "" "" "" ""
  release_case "every held handle is released, the handed-off call's too" 0 \
    "release github:o/r#5 --lease-comment-id 41 --holder 987654
release github:o/r#5 --lease-comment-id 42 --holder 987654" held 41 held 42 "" ""
  release_case "an already-leased call releases nothing" 0 "" already-leased "" "" "" "" ""
  release_case "a held lease with a malformed id releases nothing and fails" 1 "" held "0x1" "" "" "" ""
else
  fail "work-resolve-issue.yml has no release-lease job with a 'Release the lane leases' step"
fi

test_harness::report
