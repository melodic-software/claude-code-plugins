// Runs the action's `run:` script with a curl stand-in that answers the OIDC
// request and the broker, and records the broker request body. The expected
// body is the broker contract: `{lane, activity, pr_number?, issue_number?, dispatcher_run_id?}`,
// numbers as JSON integers (pr-run-activity.md, run job step 6; the broker's
// parseBody).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { after, before, test } from "node:test";

const ACTION = new URL("./action.yml", import.meta.url);
const REPO_ID = "1277265216";

// The step's `run: |` block, dedented.
function runScript() {
  const lines = readFileSync(ACTION, "utf8").split("\n");
  const start = lines.findIndex((line) => /^\s+run: \|$/.test(line));
  assert.notEqual(start, -1, "action.yml has a run: | block");
  const keyIndent = lines[start].search(/\S/);
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && line.search(/\S/) <= keyIndent) break;
    body.push(line);
  }
  const indent = Math.min(...body.filter((l) => l.trim()).map((l) => l.search(/\S/)));
  return body.map((l) => l.slice(indent)).join("\n");
}

// curl: the broker POST (it has -w) logs its --data-binary body to $BODY_LOG,
// writes $FAKE_RESPONSE to its -o file and prints 200; the OIDC GET prints a
// token; anything else (a revoke) prints 204.
const FAKE_CURL = `#!/usr/bin/env bash
cat >/dev/null
out="" data="" write=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift ;;
    -w) write=1; shift ;;
    --data-binary) data=$2; shift ;;
  esac
  shift
done
if [ -n "$data" ]; then
  printf '%s' "$data" >"$BODY_LOG"
  cat "$FAKE_RESPONSE" >"$out"
  printf '%s' "\${FAKE_STATUS:-200}"
elif [ -n "$write" ]; then
  printf 204
else
  printf '{"value":"oidc-token"}'
fi
`;

let root;
let bin;

before(() => {
  root = mkdtempSync(path.join(tmpdir(), "request-lane-token-"));
  bin = path.join(root, "bin");
  mkdirSync(bin);
  writeFileSync(path.join(bin, "curl"), FAKE_CURL);
  chmodSync(path.join(bin, "curl"), 0o755);
});

after(() => rmSync(root, { recursive: true, force: true }));

// `denial` makes the broker answer that HTTP status with that JSON body.
function request(inputs, denial) {
  const dir = mkdtempSync(path.join(root, "run-"));
  const files = Object.fromEntries(
    ["output", "summary", "response.json"].map((name) => [name, path.join(dir, name)]),
  );
  writeFileSync(files.output, "");
  writeFileSync(files.summary, "");
  const env = {
    // The action's `mode` input defaults to token.
    MODE: "token",
    BROKER_URL: "https://broker.example.net/api/token",
    AUDIENCE: "melodic-lanes-token-broker",
    LANE: "pr-unblock",
    ACTIVITY: "resolve-conflicts",
    PR_NUMBER: "42",
    ISSUE_NUMBER: "",
    DISPATCHER_RUN_ID: "",
    EFFECT: "mutate-branch",
    CONTENTS: "write",
    PULL_REQUESTS: "read",
    ISSUES: "read",
    SUPERSEDED_OK: "false",
    ...inputs,
  };
  writeFileSync(
    files["response.json"],
    JSON.stringify(denial?.body ?? {
      token: "ghs_lane",
      expires_at: "2026-10-11T13:00:00Z",
      mint_id: "5550001-1",
      effect: env.EFFECT,
      permissions: { contents: env.CONTENTS, pull_requests: env.PULL_REQUESTS, issues: env.ISSUES },
      lane: env.LANE,
      activity: env.ACTIVITY,
      repository_ids: [Number(REPO_ID)],
    }),
  );
  const bodyLog = path.join(dir, "body.json");
  const result = spawnSync("bash", ["-e", "-c", runScript()], {
    encoding: "utf8",
    env: {
      PATH: `${bin}:${process.env.PATH}`,
      ...env,
      ACTIONS_ID_TOKEN_REQUEST_URL: "https://oidc.example.net/token?api-version=2.0",
      ACTIONS_ID_TOKEN_REQUEST_TOKEN: "request-token",
      GITHUB_API_URL: "https://api.github.com",
      GITHUB_REPOSITORY_ID: REPO_ID,
      GITHUB_OUTPUT: files.output,
      GITHUB_STEP_SUMMARY: files.summary,
      RUNNER_TEMP: dir,
      BODY_LOG: bodyLog,
      FAKE_RESPONSE: files["response.json"],
      FAKE_STATUS: denial?.status ?? "200",
    },
  });
  return {
    status: result.status,
    stdout: result.stdout,
    body: existsSync(bodyLog) ? readFileSync(bodyLog, "utf8") : null,
    output: readFileSync(files.output, "utf8"),
  };
}

// The 403 shape pr-merge run 39074050115 logged when pr-merge.yml changed on
// main while it was queued.
const SUPERSEDED = {
  status: "403",
  body: { reason: "workflow-modified", detail: ".github/workflows/pr-merge.yml differs from refs/heads/main" },
};
const MERGE = { LANE: "pr-merge", ACTIVITY: "merge-pr", PR_NUMBER: "", EFFECT: "merge-pr", CONTENTS: "write", PULL_REQUESTS: "write" };

test("with superseded-ok, a 403 workflow-modified ends green with a warning and no token", () => {
  const run = request({ ...MERGE, SUPERSEDED_OK: "true" }, SUPERSEDED);
  assert.equal(run.status, 0, run.stdout);
  assert.match(run.stdout, /^::warning::lane-token-superseded: pr-merge\.yml changed on the default branch/m);
  assert.doesNotMatch(run.stdout, /::error::/);
  assert.equal(run.output, "");
});

test("with superseded-ok, any other denial reason still fails red", () => {
  const run = request({ ...MERGE, SUPERSEDED_OK: "true" }, { status: "403", body: { reason: "already-minted" } });
  assert.equal(run.status, 1);
  assert.match(run.stdout, /::error::lane-token-denied: the broker answered 403 with reason already-minted/);
  assert.equal(run.output, "failure-reason=lane-token-denied: the broker answered 403 with reason already-minted\n");
});

test("without superseded-ok, a 403 workflow-modified still fails red", () => {
  const run = request(MERGE, SUPERSEDED);
  assert.equal(run.status, 1);
  assert.match(run.stdout, /::error::lane-token-denied: the broker answered 403 with reason workflow-modified: \.github\/workflows\/pr-merge\.yml differs/);
  assert.equal(
    run.output,
    "failure-reason=lane-token-denied: the broker answered 403 with reason workflow-modified: .github/workflows/pr-merge.yml differs from refs/heads/main\n",
  );
});

test("a superseded-ok other than true or false fails before the broker request", () => {
  const run = request({ SUPERSEDED_OK: "yes" });
  assert.equal(run.status, 1);
  assert.match(run.stdout, /::error::superseded-ok must be true or false/);
  assert.equal(run.body, null);
});

test("a dispatcher run id is sent as dispatcher_run_id, an integer", () => {
  const run = request({ DISPATCHER_RUN_ID: "38155572048" });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(JSON.parse(run.body), {
    lane: "pr-unblock",
    activity: "resolve-conflicts",
    pr_number: 42,
    dispatcher_run_id: 38155572048,
  });
  assert.match(run.output, /^mint-id=5550001-1$/m);
});

test("an expected upstream head rides with the dispatcher run id as expected_upstream_head", () => {
  const head = "9".repeat(40);
  const run = request({ DISPATCHER_RUN_ID: "38155572048", EXPECTED_UPSTREAM_HEAD: head });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(JSON.parse(run.body), {
    lane: "pr-unblock",
    activity: "resolve-conflicts",
    pr_number: 42,
    dispatcher_run_id: 38155572048,
    expected_upstream_head: head,
  });
});

test("an expected upstream head without a dispatcher run id, or not a SHA, fails before the broker request", () => {
  for (const env of [{ EXPECTED_UPSTREAM_HEAD: "9".repeat(40) }, { DISPATCHER_RUN_ID: "38155572048", EXPECTED_UPSTREAM_HEAD: "main" }]) {
    const run = request(env);
    assert.notEqual(run.status, 0);
    assert.match(run.stdout, /::error::the expected upstream head must be a commit SHA and ride with a dispatcher run id/);
    assert.equal(run.body, null);
  }
});

// The run job maps this output, and report-check-run appends it to a failed
// run job's check summary.
test("a broker denial fails red and writes its reason as the failure-reason output", () => {
  const run = request(
    {},
    { status: "403", body: { reason: "workflow-modified", detail: "the workflow file changed" } },
  );
  assert.equal(run.status, 1);
  assert.match(
    run.output,
    /^failure-reason=lane-token-denied: the broker answered 403 with reason workflow-modified: the workflow file changed$/m,
  );
  assert.doesNotMatch(run.output, /^token=/m);
});

test("an empty dispatcher run id leaves the body as it was", () => {
  const run = request({ LANE: "pr-refine", ACTIVITY: "fix-docs" });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(JSON.parse(run.body), { lane: "pr-refine", activity: "fix-docs", pr_number: 42 });
});

for (const value of ["0", "0123", "12a", "-5", "1 2", "1234567890123456"]) {
  test(`a malformed dispatcher run id (${JSON.stringify(value)}) fails red before the broker request`, () => {
    const run = request({ DISPATCHER_RUN_ID: value });
    assert.equal(run.status, 1);
    assert.match(run.stdout, /::error::the dispatcher run id is malformed/);
    assert.equal(run.body, null);
  });
}

test("an issue number is sent as issue_number, an integer, with no pr_number", () => {
  const run = request({ LANE: "work-resolve-issue", ACTIVITY: "resolve-issue", PR_NUMBER: "", ISSUE_NUMBER: "77" });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(JSON.parse(run.body), { lane: "work-resolve-issue", activity: "resolve-issue", issue_number: 77 });
  assert.match(run.output, /^mint-id=5550001-1$/m);
});

for (const value of ["0", "0123", "12a", "-5", "1 2", "12345678901"]) {
  test(`a malformed issue number (${JSON.stringify(value)}) fails red before the broker request`, () => {
    const run = request({ PR_NUMBER: "", ISSUE_NUMBER: value });
    assert.equal(run.status, 1);
    assert.match(run.stdout, /::error::the issue number is malformed/);
    assert.equal(run.body, null);
  });
}

for (const [name, inputs] of [
  ["a PR number", { PR_NUMBER: "42" }],
  ["a dispatcher run id", { PR_NUMBER: "", DISPATCHER_RUN_ID: "38155572048" }],
]) {
  test(`an issue number with ${name} fails red before the broker request`, () => {
    const run = request({ ISSUE_NUMBER: "77", ...inputs });
    assert.equal(run.status, 1);
    assert.match(run.stdout, /::error::an issue number goes without a PR number or dispatcher run id/);
    assert.equal(run.body, null);
  });
}

test("check mode refuses an issue number before the broker request", () => {
  const run = request({ MODE: "check", EFFECT: "", CONTENTS: "", PULL_REQUESTS: "", ISSUES: "", PR_NUMBER: "", ISSUE_NUMBER: "77" });
  assert.equal(run.status, 1);
  assert.match(run.stdout, /::error::check mode takes no effect, grant, PR or issue number, or dispatcher run id/);
  assert.equal(run.body, null);
});
