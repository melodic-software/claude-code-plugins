#!/usr/bin/env bash
# test-scope: .github/workflows/pr-run-activity-read.yml .github/actions/request-lane-token/action.yml .github/standards/runner-policy/package.json plugins/work-items/tools/work-item-tracker/adapters/github/claim.sh plugins/work-items/tools/work-item-tracker/work-item-tracker.sh .work-item-tracker.json .github/workflows/work-resolve-issue.yml .github/workflows/pr-run-activity-write.yml
# Runs the shell of two read-lane broker-check steps, lifted from their YAML,
# against the cases the contract states
# (docs/conventions/pr-pipeline/pr-run-activity.md, "The broker-check job"):
#   - the run job's "Assert the broker allowed this attempt" step passes only
#     when broker-check allowed this same run attempt;
#   - request-lane-token's check mode accepts only an https URL whose last path
#     segment is /token;
#   - broker-check's issue lease step backs off as already-leased on a live
#     lease older than its own, and the run job's go step then runs no model;
#   - exactly one of the read runner's report job and the caller's write runner
#     report job releases each lease, the write side after the PR opens.
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
*"-f body="*) echo "POST $*" >>"$STUB_LOG"; echo 2 ;;
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
    GITHUB_SERVER_URL=https://github.com GITHUB_STEP_SUMMARY=/dev/null \
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
  fail "an already-leased run hands no lease handle to a release"
else
  ok "an already-leased run hands no lease handle to a release"
fi
if grep -q 'POST .*body=already-leased: another session holds a live lease on #1, so run https://github.com/acme/widgets/actions/runs/5 ran no model' "$WORK/stub.log"; then
  ok "an already-leased run says so in a comment on the issue"
else
  fail "an already-leased run posted no back-off comment: $(cat "$WORK/stub.log")"
fi
lease_case "a claimed run posts no back-off comment" "$OURS" held true
if grep -q 'already-leased' "$WORK/stub.log"; then fail "a claimed run posted a back-off comment"; else ok "a claimed run posts no back-off comment (log)"; fi

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
holds "every read call of work-resolve-issue.yml runs in caller-releases mode" "$CALLER_YML" \
  'Object.values(d.jobs).filter((j) => /pr-run-activity-read\.yml/.test(j.uses ?? "")).every((j) => j.with["caller-releases-lease"] === true)'
holds "work-resolve-issue.yml has no job of its own that releases" "$CALLER_YML" '!("release-lease" in d.jobs)'
holds "the read runner has no separate release job" "$READ_YML" '!("lease-release" in d.jobs)'
# shellcheck disable=SC2016 # the ${{ }} text is a literal the workflow must hold
holds "report-outcome and apply-issue-patch pass the selected read call's lease handle" "$CALLER_YML" \
  'const want = "${{ needs.resolve-issue-fallback.result != '"'skipped'"' && needs.resolve-issue-fallback.outputs.lease-comment-id || needs.resolve-issue-fallback.result == '"'skipped'"' && needs.resolve-issue-subscription.result != '"'skipped'"' && needs.resolve-issue-subscription.outputs.lease-comment-id || needs.resolve-issue-fallback.result == '"'skipped'"' && needs.resolve-issue-subscription.result == '"'skipped'"' && needs.resolve-issue.outputs.lease-comment-id || '"''"' }}"; d.jobs["report-outcome"].with["lease-comment-id"] === want && d.jobs["apply-issue-patch"].with["lease-comment-id"] === want'

# Who releases (#9791). The rule: the caller's write runner releases the
# selected call's lease exactly when report-outcome runs on it (that call did
# not hand off and set issue-run-started or reuse-branch), or apply-issue-patch
# stopped on the kill switch; the read runner's report job releases in every
# other case. Each row evaluates both report jobs' real `if`.
# who <label> <expected: read|write|none> <handed-off> <run-started> <reuse> <write-activity> <write-skip>
who() {
  local got
  got="$(node -e '
    const { createRequire } = require("node:module");
    const yaml = createRequire(process.argv[1] + "/package.json")("yaml");
    const fs = require("node:fs");
    const [, , readYml, writeYml, handedOff, started, reuse, activity, skip] = process.argv;
    const evalIf = (expr, ctx) => {
      const js = expr.replace(/\s+/g, " ")
        .replace(/\b(inputs|needs|github|vars)(\.[\w-]+)+/g, (m) => JSON.stringify(ctx[m] ?? ""))
        .replace(/always\(\)/g, "true").replace(/==/g, "===").replace(/!=(?!=)/g, "!==");
      const format = (f, a) => String(a);
      return Boolean(eval(js));
    };
    const read = yaml.parse(fs.readFileSync(readYml, "utf8")).jobs.report.if;
    const write = yaml.parse(fs.readFileSync(writeYml, "utf8")).jobs.report.if;
    const r = evalIf(read, {
      "inputs.issue-number": "7", "inputs.caller-releases-lease": true,
      "needs.broker-check.outputs.lease": "held", "needs.broker-check.outputs.lease-comment-id": "41",
      "needs.run.outputs.handed-off": handedOff, "needs.issue-fields.outputs.issue-run-started": started,
      "needs.issue-fields.outputs.reuse-branch": reuse,
    });
    // The caller runs report-outcome on a non-handed-off call that started or reused.
    const reportOutcome = handedOff !== "true" && (started === "true" || reuse !== "") && skip !== "kill-switch";
    const w = (act, sk) => evalIf(write, {
      "inputs.issue-number": "7", "inputs.lease-comment-id": "41", "inputs.activity": act,
      "needs.run.outputs.skip-reason": sk,
    });
    const writes = (activity === "apply-issue-patch" && w("apply-issue-patch", skip)) || (reportOutcome && w("report-outcome", ""));
    console.log(r && writes ? "both" : r ? "read" : writes ? "write" : "none");
  ' "$POLICY_DIR" "$READ_YML" "$ROOT/.github/workflows/pr-run-activity-write.yml" "$3" "$4" "$5" "$6" "$7")"
  if [[ $got == "$2" ]]; then ok "$1"; else fail "$1: got $got, expected $2"; fi
}
who "a handed-off call releases its own lease" read true true "" apply-issue-patch ""
who "a go=false call (stale files or prior work) releases its own lease" read false false "" apply-issue-patch ""
who "a started run leaves the lease to report-outcome, after the PR opens" write false true "" apply-issue-patch ""
who "a reused branch leaves the lease to report-outcome" write false false work-resolve-issue/issue-7-1-1 none ""
who "a kill-switch stop in apply-issue-patch releases there" write false true "" apply-issue-patch kill-switch
who "a started run whose apply-issue-patch failed still releases in report-outcome" write false true "" apply-issue-patch patch-failed

test_harness::report
