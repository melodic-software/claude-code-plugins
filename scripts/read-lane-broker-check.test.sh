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
  'const want = "${{ needs.resolve-issue-fallback.result != '"'skipped'"' && needs.resolve-issue-fallback.outputs.lease-comment-id || needs.resolve-issue-fallback.result == '"'skipped'"' && needs.resolve-issue-subscription.result != '"'skipped'"' && needs.resolve-issue-subscription.outputs.lease-comment-id || needs.resolve-issue-fallback.result == '"'skipped'"' && needs.resolve-issue-subscription.result == '"'skipped'"' && needs.resolve-issue.outputs.lease-comment-id || '"''"' }}"; const selected = want.replace(/^\$\{\{ /, "").replace(/ \|\| '"''"' \}\}$/, ""); d.jobs["report-outcome"].with["lease-comment-id"] === "${{ needs.resolve-issue-stale.outputs.stale != '"'true'"' && (" + selected + ") || '"''"' }}" && d.jobs["apply-issue-patch"].with["lease-comment-id"] === want'

# Who releases (#9791), and whether the caller's report-outcome runs. Every
# gate is the real YAML: the run job's issue-prior `if`, its go step's shell
# and issue-run-started output, both report jobs' `if`, and the caller's
# apply-issue-patch and report-outcome `if` and lease-comment-id inputs, with
# resolve-issue as the selected call (its later calls skipped).
# who <label> <expected: read|write|both|none> <expected report-outcome: yes|no>
#     <lease> <caller-releases-lease> <handed-off> <prior: none|stop|branch> <patch-state> <apply-skip>
who() {
  local got
  # shellcheck disable=SC2016  # node source with JS template expressions, never shell-expanded
  got="$(node -e '
    const { createRequire } = require("node:module");
    const yaml = createRequire(process.argv[1] + "/package.json")("yaml");
    const fs = require("node:fs");
    const { spawnSync } = require("node:child_process");
    const [, , readYml, writeYml, callerYml, lease, crl, handedOff, prior, patchState, applySkip] = process.argv;
    const load = (f) => yaml.parse(fs.readFileSync(f, "utf8"));
    const read = load(readYml), write = load(writeYml), caller = load(callerYml);
    const expr = (src, ctx) => {
      const js = String(src).replace(/^\s*\$\{\{([\s\S]*)\}\}\s*$/, "$1").replace(/\s+/g, " ") // portability-ok: JS regex in node -e, not a shell tool
        .replace(/\b(inputs|needs|github|vars|steps)(\.[\w-]+)+/g, (m) => { if (!(m in ctx)) throw new Error(`an unresolved context reference: ${m}`); return JSON.stringify(ctx[m]); }) // portability-ok: JS regex in node -e, not a shell tool
        .replace(/always\(\)/g, "true").replace(/cancelled\(\)/g, "false")
        .replace(/==/g, "===").replace(/!=(?!=)/g, "!==");
      const format = (f, a) => String(a);
      return eval(js);
    };
    const on = (src, ctx) => Boolean(expr(src, ctx));
    const step = (pred) => read.jobs.run.steps.find(pred);
    const leaseId = lease === "held" ? "41" : "";
    const runCtx = {
      "inputs.issue-number": "7", "steps.config.outputs.applies": "true", "steps.config.outputs.kind": "skill",
      "steps.workflow-current.outputs.stale": "", "needs.broker-check.outputs.lease": lease,
    };
    const priorRuns = on(step((s) => s.id === "issue-prior").if, runCtx);
    const reuse = priorRuns && prior === "branch" ? "work-resolve-issue/issue-7-1-1" : "";
    const proceed = !priorRuns ? "" : prior === "none" ? "true" : "false";
    const out = `${process.env.WORK}/who-go`;
    fs.writeFileSync(out, "");
    spawnSync("bash", ["-c", step((s) => s.id === "go").run], {
      env: { ...process.env, PRIOR: proceed, STALE: "", LEASE: lease, GITHUB_OUTPUT: out },
    });
    const go = (fs.readFileSync(out, "utf8").match(/^run=(.*)$/m) ?? [])[1] ?? "";
    const started = String(expr(read.jobs.run.outputs["issue-run-started"], { ...runCtx, "steps.go.outputs.run": go }));
    const readReleases = on(read.jobs.report.if, {
      "github.event_name": "issues", "github.event.pull_request.head.repo.full_name": "", "github.repository": "acme/widgets", "github.event.sender.id": "", "vars.AUTOMATION_LANES_APP_SENDER_ID": "987654", "inputs.issue-number": "7", "inputs.caller-releases-lease": crl === "true",
      "needs.broker-check.outputs.lease": lease, "needs.broker-check.outputs.lease-comment-id": leaseId,
      "needs.run.outputs.handed-off": handedOff, "needs.issue-fields.outputs.issue-run-started": started,
      "needs.issue-fields.outputs.reuse-branch": reuse,
    });
    const callerCtx = {
      "needs.resolve-issue-fallback.result": "skipped", "needs.resolve-issue-subscription.result": "skipped",
      "needs.resolve-issue.result": "success", "needs.resolve-issue.outputs.scan-issue-run-started": started,
      "needs.resolve-issue.outputs.scan-reuse-branch": reuse, "needs.resolve-issue.outputs.scan-patch-state": patchState,
      "needs.resolve-issue.outputs.lease-comment-id": leaseId, "needs.resolve-issue-stale.outputs.stale": "",
    };
    // The skipped later calls output nothing.
    for (const call of ["resolve-issue-subscription", "resolve-issue-fallback"]) {
      for (const name of ["scan-issue-run-started", "scan-reuse-branch", "scan-patch-state", "lease-comment-id"]) {
        callerCtx[`needs.${call}.outputs.${name}`] = "";
      }
    }
    const apply = caller.jobs["apply-issue-patch"], report = caller.jobs["report-outcome"];
    const applyRuns = on(apply.if, callerCtx);
    const skip = applyRuns ? applySkip : "";
    const reportRuns = on(report.if, { ...callerCtx, "needs.apply-issue-patch.outputs.skip-reason": skip });
    const writeReleases = (job, activity, sk) => on(write.jobs.report.if, {
      "github.event_name": "issues", "github.event.pull_request.head.repo.full_name": "", "github.repository": "acme/widgets", "github.event.sender.id": "", "vars.AUTOMATION_LANES_APP_SENDER_ID": "987654", "inputs.issue-number": "7", "inputs.activity": activity, "needs.run.outputs.skip-reason": sk,
      "inputs.lease-comment-id": String(expr(job.with["lease-comment-id"], callerCtx)),
    });
    const writes = (applyRuns && writeReleases(apply, "apply-issue-patch", skip)) || (reportRuns && writeReleases(report, "report-outcome", ""));
    console.log(`${readReleases && writes ? "both" : readReleases ? "read" : writes ? "write" : "none"} ${reportRuns ? "yes" : "no"}`);
  ' "$POLICY_DIR" "$READ_YML" "$ROOT/.github/workflows/pr-run-activity-write.yml" "$CALLER_YML" "${@:4}")"
  if [[ $got == "$2 $3" ]]; then ok "$1"; else fail "$1: got '$got', expected '$2 $3'"; fi
}
export WORK
who "a go=false call (an earlier run's PR) releases its own lease" read no held true false stop none ""
who "a started run leaves the lease to report-outcome, after the PR opens" write yes held true false none written ""
who "a reused branch leaves the lease to report-outcome" write yes held true false branch none ""
who "a kill-switch stop in apply-issue-patch releases there" write no held true false none written kill-switch
who "a started run whose apply-issue-patch failed still releases in report-outcome" write yes held true false none written patch-failed
who "an already-leased run releases nothing and reports nothing" none no already-leased true false none none ""
who "an already-leased run with a lane branch opens no PR from it" none no already-leased true false branch none ""
who "caller-releases-lease=false: the read run releases, and report-outcome's release is a no-op" both yes held false false none written ""
who "a broker-check that posted no lease releases nothing" none yes "" true false none written ""
who "a handed-off call that started: both sides release, the second a no-op" both yes held true true none written ""

# The second release of one lease finds it superseded: exit 0, nothing written.
SUPERSEDED="$(jq -cn --arg b '<!-- work-item-lease v1 {"schema_version":"1.0","holder":"987654","acquired_at":"2026-01-01T00:00:00Z","renewed_at":"2026-01-01T00:00:00Z","ttl_hours":2,"superseded_at":"2026-01-01T00:10:00Z"} -->' '{body:$b, issue:"7"}')"
cat >"$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
*"--method PATCH"*) echo PATCH >>"$STUB_LOG"; echo 41 ;;
*"issues/comments/41"*) printf '%s\n' "$COMMENT" ;;
*) echo "gh-stub: unhandled: $*" >&2; exit 90 ;;
esac
STUB
: >"$WORK/stub.log"
out="$(PATH="$STUB_BIN:$PATH" STUB_LOG="$WORK/stub.log" COMMENT="$SUPERSEDED" GH_TOKEN=x WIT_WRITE_SPACING_S=0 \
  WORK_ITEM_TRACKER_BINDING="$ROOT/.work-item-tracker.json" \
  bash "$ROOT/plugins/work-items/tools/work-item-tracker/work-item-tracker.sh" release "github:acme/widgets#7" \
  --lease-comment-id 41 --holder 987654 2>&1)"
rc=$?
if [[ $rc -eq 0 && $out == *'"released":false'* ]] && ! grep -q PATCH "$WORK/stub.log"; then
  ok "releasing an already-released lease is a no-op"
else
  fail "releasing an already-released lease: rc=$rc out=$out log=$(cat "$WORK/stub.log")"
fi

holds "the read release step validates the handle, warns and stays green on failure" "$READ_YML" \
  'const r = Object.values(d.jobs).flatMap((j) => j.steps ?? []).find((s) => s.name === "Release the lane lease"); r?.["continue-on-error"] === true && /::warning::.*TTL/.test(r.run) && /\^\[1-9\]\[0-9\]\*\$/.test(r.run)'
holds "the write release step warns and stays green on failure" "$ROOT/.github/workflows/pr-run-activity-write.yml" \
  'const r = Object.values(d.jobs).flatMap((j) => j.steps ?? []).find((s) => s.name === "Release the lane lease"); r?.["continue-on-error"] === true && /::warning::.*TTL/.test(r.run) && /\^\[1-9\]\[0-9\]\*\$/.test(r.run)'

test_harness::report
