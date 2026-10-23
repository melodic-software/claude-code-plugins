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

// curl: the Nth broker POST (it has --data-binary) logs its body to $BODY_LOG
// and its Authorization line to $AUTH_LOG, writes $ANSWERS/N.json to its -o
// file and $ANSWERS/N.headers to its -D file, and prints $ANSWERS/N.status;
// past the last answer it repeats the last one. A GET of a /compare/ URL logs
// the URL and its Authorization line to $COMPARE_LOG and writes $COMPARE to
// its -o file, or exits 22 (curl --fail on an HTTP error) when $COMPARE is
// absent. The Mth OIDC GET prints token oidc-token-M; anything else (a
// revoke) prints 204.
const FAKE_CURL = `#!/usr/bin/env bash
stdin=$(cat)
out="" data="" write="" dump="" url=""
while [ $# -gt 0 ]; do
  case "$1" in
    https://*) url=$1 ;;
    -o) out=$2; shift ;;
    -D) dump=$2; shift ;;
    -w) write=1; shift ;;
    --data-binary) data=$2; shift ;;
  esac
  shift
done
if [ -n "$data" ]; then
  printf '%s\\n' "$stdin" >>"$AUTH_LOG"
  printf '%s' "$data" >"$BODY_LOG"
  n=$(($(wc -l <"$AUTH_LOG")))
  [ -e "$ANSWERS/$n.status" ] || n=$(ls "$ANSWERS" | grep -c '\\.status$')
  cat "$ANSWERS/$n.json" >"$out"
  if [ -n "$dump" ]; then cat "$ANSWERS/$n.headers" >"$dump"; fi
  cat "$ANSWERS/$n.status"
elif [[ $url == */compare/* ]]; then
  printf '%s %s\\n' "$url" "$stdin" >>"$COMPARE_LOG"
  [ -e "$COMPARE" ] || exit 22
  cat "$COMPARE" >"$out"
elif [ -n "$write" ]; then
  printf 204
else
  echo x >>"$OIDC_LOG"
  printf '{"value":"oidc-token-%s"}' "$(($(wc -l <"$OIDC_LOG")))"
fi
`;

// sleep: logs its argument and returns at once.
const FAKE_SLEEP = `#!/usr/bin/env bash
printf '%s\\n' "$1" >>"$SLEEP_LOG"
`;

let root;
let bin;

before(() => {
  root = mkdtempSync(path.join(tmpdir(), "request-lane-token-"));
  bin = path.join(root, "bin");
  mkdirSync(bin);
  writeFileSync(path.join(bin, "curl"), FAKE_CURL);
  chmodSync(path.join(bin, "curl"), 0o755);
  writeFileSync(path.join(bin, "sleep"), FAKE_SLEEP);
  chmodSync(path.join(bin, "sleep"), 0o755);
});

after(() => rmSync(root, { recursive: true, force: true }));

// Each answer makes the broker's next reply that HTTP status, with that JSON
// body (the mint below when absent) and that header block; the last repeats.
// No answer is one 200 mint.
// A `compare` input is the GitHub compare response the action reads; absent,
// the compare request fails.
function request({ compare, ...inputs }, ...answers) {
  const dir = mkdtempSync(path.join(root, "run-"));
  const files = Object.fromEntries(["output", "summary"].map((name) => [name, path.join(dir, name)]));
  writeFileSync(files.output, "");
  writeFileSync(files.summary, "");
  const answersDir = path.join(dir, "answers");
  mkdirSync(answersDir);
  const logs = Object.fromEntries(["auth", "oidc", "sleep", "compare"].map((name) => [name, path.join(dir, `${name}.log`)]));
  for (const log of Object.values(logs)) writeFileSync(log, "");
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
    ACTIONS: "",
    SUPERSEDED_OK: "false",
    PR_WORKFLOW_CHANGE_OK: "false",
    HEAD_SHA: "",
    DEFAULT_BRANCH: "",
    API_TOKEN: "",
    ...inputs,
  };
  const mint = {
    token: "ghs_lane",
    expires_at: "2026-10-11T13:00:00Z",
    mint_id: "5550001-1",
    effect: env.EFFECT,
    permissions: {
      contents: env.CONTENTS,
      pull_requests: env.PULL_REQUESTS,
      issues: env.ISSUES,
      ...(env.ACTIONS ? { actions: env.ACTIONS } : {}),
    },
    lane: env.LANE,
    activity: env.ACTIVITY,
    repository_ids: [Number(REPO_ID)],
  };
  (answers.length ? answers : [{}]).forEach((answer, i) => {
    const base = path.join(answersDir, String(i + 1));
    writeFileSync(`${base}.status`, answer.status ?? "200");
    writeFileSync(`${base}.json`, JSON.stringify(answer.body ?? mint));
    writeFileSync(`${base}.headers`, answer.headers ?? "HTTP/2 200\r\ncontent-type: application/json\r\n\r\n");
  });
  const compareFile = path.join(dir, "compare.json");
  if (compare !== undefined) writeFileSync(compareFile, JSON.stringify(compare));
  const bodyLog = path.join(dir, "body.json");
  const result = spawnSync("bash", ["-e", "-c", runScript()], {
    encoding: "utf8",
    env: {
      PATH: `${bin}:${process.env.PATH}`,
      ...env,
      ACTIONS_ID_TOKEN_REQUEST_URL: "https://oidc.example.net/token?api-version=2.0",
      ACTIONS_ID_TOKEN_REQUEST_TOKEN: "request-token",
      GITHUB_API_URL: "https://api.github.com",
      GITHUB_REPOSITORY: "melodic-software/claude-code-plugins",
      GITHUB_REPOSITORY_ID: REPO_ID,
      GITHUB_OUTPUT: files.output,
      GITHUB_STEP_SUMMARY: files.summary,
      RUNNER_TEMP: dir,
      BODY_LOG: bodyLog,
      AUTH_LOG: logs.auth,
      OIDC_LOG: logs.oidc,
      SLEEP_LOG: logs.sleep,
      COMPARE_LOG: logs.compare,
      COMPARE: compareFile,
      ANSWERS: answersDir,
    },
  });
  const lines = (log) => readFileSync(log, "utf8").split("\n").filter(Boolean);
  return {
    status: result.status,
    stdout: result.stdout,
    body: existsSync(bodyLog) ? readFileSync(bodyLog, "utf8") : null,
    output: readFileSync(files.output, "utf8"),
    summary: readFileSync(files.summary, "utf8"),
    auth: lines(logs.auth),
    compares: lines(logs.compare),
    sleeps: lines(logs.sleep).map(Number),
  };
}

// The 503 run 39092207020 logged when about 40 issue lanes asked at once.
const GITHUB_UNAVAILABLE = {
  status: "503",
  body: { error: "unavailable", reason: "github-unavailable", detail: "GET /repos/melodic-software/claude-code-plugins failed with status 403" },
};
const ISSUE_LANE = { LANE: "work-resolve-issue", ACTIVITY: "resolve-issue", PR_NUMBER: "", ISSUE_NUMBER: "77" };
// The brief's backoff: 60 s, 120 s and 240 s, each with up to 20 s of jitter,
// at most 8 minutes of waiting in all.
const BACKOFF = [60, 120, 240];
const JITTER = 20;
const BUDGET = 480;

function assertBackoff(sleeps, count) {
  assert.equal(sleeps.length, count, `sleeps: ${sleeps}`);
  sleeps.forEach((s, i) => {
    assert.ok(s >= BACKOFF[i] && s <= BACKOFF[i] + JITTER, `sleep ${i + 1} is ${s}`);
  });
  assert.ok(sleeps.reduce((a, b) => a + b, 0) <= BUDGET);
}

test("a 503 github-unavailable is retried after backoff, with a fresh OIDC token, until the mint", () => {
  const run = request(ISSUE_LANE, GITHUB_UNAVAILABLE, GITHUB_UNAVAILABLE, {});
  assert.equal(run.status, 0, run.stdout);
  assert.equal(run.auth.length, 3);
  assert.deepEqual(run.auth, ["Authorization: Bearer oidc-token-1", "Authorization: Bearer oidc-token-2", "Authorization: Bearer oidc-token-3"]);
  assertBackoff(run.sleeps, 2);
  assert.match(run.output, /^mint-id=5550001-1$/m);
  assert.doesNotMatch(run.stdout, /::error::/);
});

test("a 503 github-unavailable on every attempt fails red after three retries", () => {
  const run = request(ISSUE_LANE, GITHUB_UNAVAILABLE);
  assert.equal(run.status, 1);
  assert.equal(run.auth.length, 4);
  assertBackoff(run.sleeps, 3);
  assert.equal(
    run.output,
    "failure-reason=lane-token-denied: the broker answered 503 with reason github-unavailable: GET /repos/melodic-software/claude-code-plugins failed with status 403\n",
  );
});

test("a Retry-After header longer than the backoff sets the wait", () => {
  const run = request(ISSUE_LANE, { ...GITHUB_UNAVAILABLE, headers: "HTTP/2 503\r\nRetry-After: 200\r\n\r\n" }, {});
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.sleeps, [200]);
});

test("a Retry-After with a leading zero is read as decimal seconds", () => {
  const run = request(ISSUE_LANE, { ...GITHUB_UNAVAILABLE, headers: "HTTP/2 503\r\nRetry-After: 090\r\n\r\n" }, {});
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.sleeps, [90]);
});

test("a Retry-After past the 8-minute budget fails red at once", () => {
  const run = request(ISSUE_LANE, { ...GITHUB_UNAVAILABLE, headers: "HTTP/2 503\r\nretry-after: 600\r\n\r\n" }, {});
  assert.equal(run.status, 1);
  assert.equal(run.auth.length, 1);
  assert.deepEqual(run.sleeps, []);
  assert.match(run.output, /^failure-reason=lane-token-denied: the broker answered 503 with reason github-unavailable/m);
});

// The broker's github-rate-limited answer (deny.mjs, http.mjs in azure-iac
// src/lanes-token-broker): a Retry-After header of GitHub's wait, clamped to
// 1-3600 s, and the limit, resource and retry_after in the body.
const rateLimited = (retryAfter) => ({
  status: "503",
  body: {
    error: "unavailable",
    reason: "github-rate-limited",
    detail: "GET /repos/melodic-software/claude-code-plugins failed with status 403",
    limit: "secondary",
    resource: "core",
    retry_after: retryAfter,
  },
  headers: `HTTP/2 503\r\nRetry-After: ${retryAfter}\r\ncontent-type: application/json\r\n\r\n`,
});

// GitHub: with a retry-after header, do not retry until that many seconds
// have passed. Below the 60 s ladder step, so the ladder would wait longer.
test("a 503 github-rate-limited waits its Retry-After plus jitter, not the backoff ladder", () => {
  const run = request(ISSUE_LANE, rateLimited(30), {});
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.auth, ["Authorization: Bearer oidc-token-1", "Authorization: Bearer oidc-token-2"]);
  assert.equal(run.sleeps.length, 1);
  assert.ok(run.sleeps[0] >= 30 && run.sleeps[0] <= 30 + JITTER, `sleep is ${run.sleeps[0]}`);
  assert.match(run.output, /^mint-id=5550001-1$/m);
});

test("a 503 github-rate-limited on every attempt fails red after three retries", () => {
  const run = request(ISSUE_LANE, rateLimited(30));
  assert.equal(run.status, 1);
  assert.equal(run.auth.length, 4);
  assert.equal(run.sleeps.length, 3);
  assert.match(run.output, /^failure-reason=lane-token-denied: the broker answered 503 with reason github-rate-limited: GET \/repos/m);
});

// GitHub's guidance without a retry-after header: wait at least one minute.
test("a 503 github-rate-limited with no Retry-After waits a minute plus jitter", () => {
  const run = request(ISSUE_LANE, { ...rateLimited(30), headers: "HTTP/2 503\r\n\r\n" }, {});
  assert.equal(run.status, 0, run.stdout);
  assert.equal(run.sleeps.length, 1);
  assert.ok(run.sleeps[0] >= 60 && run.sleeps[0] <= 60 + JITTER, `sleep is ${run.sleeps[0]}`);
});

test("a github-rate-limited wait that ends inside the 8-minute budget is taken, its jitter cut to fit", () => {
  const run = request(ISSUE_LANE, rateLimited(470), {});
  assert.equal(run.status, 0, run.stdout);
  assert.equal(run.sleeps.length, 1);
  assert.ok(run.sleeps[0] >= 470 && run.sleeps[0] <= BUDGET, `sleep is ${run.sleeps[0]}`);
});

test("a github-rate-limited Retry-After past the 8-minute budget fails at once, naming the limit and its reset", () => {
  const before = Math.floor(Date.now() / 1000);
  const run = request(ISSUE_LANE, rateLimited(BUDGET + 1), {});
  const afterRun = Math.ceil(Date.now() / 1000);
  assert.equal(run.status, 1);
  assert.equal(run.auth.length, 1);
  assert.deepEqual(run.sleeps, []);
  const match =
    /^failure-reason=lane-token-denied: the broker answered 503 with reason github-rate-limited: GET \/repos\/melodic-software\/claude-code-plugins failed with status 403; GitHub's secondary rate limit \(core\) resets at (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ), past the 8-minute retry budget$/m.exec(
      run.output,
    );
  assert.ok(match, run.output);
  const reset = Date.parse(match[1]) / 1000;
  assert.ok(reset >= before + BUDGET + 1 && reset <= afterRun + BUDGET + 1, `reset ${match[1]}`);
});

// mint-unavailable comes after the broker reserved the job's one mint.
test("a 503 mint-unavailable is not retried and fails red saying it is final", () => {
  const run = request(ISSUE_LANE, { status: "503", body: { error: "unavailable", reason: "mint-unavailable", detail: "d" } }, {});
  assert.equal(run.status, 1);
  assert.equal(run.auth.length, 1);
  assert.deepEqual(run.sleeps, []);
  assert.match(
    run.output,
    /^failure-reason=lane-token-denied: the broker answered 503 with reason mint-unavailable: d; final: the broker had reserved this job's one mint, so no retry can mint it$/m,
  );
});

// The broker reserves the job's mint before it mints, so any retry after the
// reservation is denied already-minted. The failure keeps the 503 that started it.
test("an already-minted after a retried github-unavailable fails red naming both", () => {
  const run = request(ISSUE_LANE, GITHUB_UNAVAILABLE, { status: "403", body: { error: "denied", reason: "already-minted", detail: "check run 1 already received its mint" } });
  assert.equal(run.status, 1);
  assert.equal(run.auth.length, 2);
  assert.match(
    run.output,
    /^failure-reason=lane-token-denied: the broker answered 403 with reason already-minted: check run 1 already received its mint, after 503 with reason github-unavailable: GET \/repos/m,
  );
});

for (const [status, reason] of [
  ["503", "store-unavailable"],
  ["503", "key-unavailable"],
  ["403", "github-unavailable"],
  ["403", "workflow-modified"],
  ["403", "untrusted-actor"],
  ["403", "lane-mismatch"],
  ["500", "internal"],
]) {
  test(`a ${status} ${reason} is not retried`, () => {
    const run = request(ISSUE_LANE, { status, body: { reason, detail: "d" } }, {});
    assert.equal(run.status, 1);
    assert.equal(run.auth.length, 1);
    assert.deepEqual(run.sleeps, []);
    assert.match(run.output, new RegExp(`^failure-reason=lane-token-denied: the broker answered ${status} with reason ${reason}: d$`, "m"));
  });
}

test("check mode retries a 503 github-unavailable too", () => {
  const run = request(
    { MODE: "check", EFFECT: "", CONTENTS: "", PULL_REQUESTS: "", ISSUES: "", PR_NUMBER: "" },
    GITHUB_UNAVAILABLE,
    { body: { decision: "allow", lane: "pr-unblock", activity: "resolve-conflicts" } },
  );
  assert.equal(run.status, 0, run.stdout);
  assert.equal(run.auth.length, 2);
  assertBackoff(run.sleeps, 1);
});

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

// #7732: the refusal fix-docs got on #7717, a PR that changes a workflow file.
// The detail's shape is the broker's, as SUPERSEDED above records it.
const HEAD = "a".repeat(40);
const REFINE_MODIFIED = {
  status: "403",
  body: { reason: "workflow-modified", detail: ".github/workflows/pr-refine.yml differs from refs/heads/main" },
};
const PR_CHANGE = {
  LANE: "pr-refine",
  ACTIVITY: "fix-docs",
  PR_WORKFLOW_CHANGE_OK: "true",
  HEAD_SHA: HEAD,
  DEFAULT_BRANCH: "main",
  API_TOKEN: "ghs_job",
};
// GitHub's compare response: `files[]` with `filename`, and `previous_filename`
// on a rename (docs.github.com/en/rest/commits/commits#compare-two-commits).
const changes = (...files) => ({ status: "ahead", files });
const COMPARE_URL = `https://api.github.com/repos/melodic-software/claude-code-plugins/compare/main...${HEAD}`;

test("with pr-workflow-change-ok, a workflow-modified refusal of a file the PR changes skips green, naming the reason and file", () => {
  const run = request(
    { ...PR_CHANGE, compare: changes({ filename: "docs/a.md", status: "modified" }, { filename: ".github/workflows/pr-refine.yml", status: "modified" }) },
    REFINE_MODIFIED,
  );
  assert.equal(run.status, 0, run.stdout);
  assert.equal(run.output, "skip-reason=workflow-modified\n");
  assert.match(run.summary, /workflow-modified because this pull request changes \.github\/workflows\/pr-refine\.yml/);
  assert.doesNotMatch(run.stdout, /::error::/);
  assert.deepEqual(run.compares, [`${COMPARE_URL} Authorization: Bearer ghs_job`]);
});

test("with pr-workflow-change-ok, a PR that renamed the named file away also skips", () => {
  const run = request(
    { ...PR_CHANGE, compare: changes({ filename: ".github/workflows/pr-refine-old.yml", previous_filename: ".github/workflows/pr-refine.yml", status: "renamed" }) },
    REFINE_MODIFIED,
  );
  assert.equal(run.status, 0, run.stdout);
  assert.match(run.output, /^skip-reason=workflow-modified$/m);
});

test("with pr-workflow-change-ok, a workflow-modified refusal of a file the PR does not change fails red", () => {
  const run = request({ ...PR_CHANGE, compare: changes({ filename: ".github/workflows/pr-merge.yml", status: "modified" }) }, REFINE_MODIFIED);
  assert.equal(run.status, 1);
  assert.equal(
    run.output,
    `failure-reason=lane-token-denied: the broker answered 403 with reason workflow-modified: .github/workflows/pr-refine.yml differs from refs/heads/main; not skipped: the pull request's diff at ${HEAD} does not change .github/workflows/pr-refine.yml\n`,
  );
  assert.equal(run.compares.length, 1);
});

test("with pr-workflow-change-ok, a compare that cannot be read fails red", () => {
  const run = request(PR_CHANGE, REFINE_MODIFIED);
  assert.equal(run.status, 1);
  assert.match(run.output, new RegExp(`; not skipped: the compare of main\\.\\.\\.${HEAD} could not be read\\n$`));
  assert.doesNotMatch(run.output, /^skip-reason=/m);
});

for (const [name, detail] of [
  ["no detail", undefined],
  ["a detail that names no workflow file", "the workflow file changed"],
  ["a path outside .github/workflows", "scripts/x.yml differs from refs/heads/main"],
  ["another branch", ".github/workflows/pr-refine.yml differs from refs/heads/release"],
  ["trailing text", ".github/workflows/pr-refine.yml differs from refs/heads/main; and more"],
]) {
  test(`with pr-workflow-change-ok, a workflow-modified refusal with ${name} fails red without a compare`, () => {
    const run = request(
      { ...PR_CHANGE, compare: changes({ filename: ".github/workflows/pr-refine.yml", status: "modified" }) },
      { status: "403", body: { reason: "workflow-modified", ...(detail === undefined ? {} : { detail }) } },
    );
    assert.equal(run.status, 1);
    assert.match(run.output, /^failure-reason=lane-token-denied: the broker answered 403 with reason workflow-modified.*; not skipped: the refusal names no workflow file against refs\/heads\/main$/m);
    assert.deepEqual(run.compares, []);
  });
}

for (const [status, reason] of [
  ["403", "already-minted"],
  ["403", "untrusted-actor"],
  ["503", "workflow-modified"],
  ["403", "Workflow-Modified"],
]) {
  test(`with pr-workflow-change-ok, a ${status} ${reason} still fails red without a compare`, () => {
    const run = request(
      { ...PR_CHANGE, compare: changes({ filename: ".github/workflows/pr-refine.yml", status: "modified" }) },
      { status, body: { reason, detail: ".github/workflows/pr-refine.yml differs from refs/heads/main" } },
    );
    assert.equal(run.status, 1);
    assert.match(run.output, /^failure-reason=lane-token-denied: the broker answered /m);
    assert.doesNotMatch(run.output, /^skip-reason=/m);
    assert.deepEqual(run.compares, []);
  });
}

test("a broker answer that is not JSON fails red even with pr-workflow-change-ok", () => {
  const run = request({ ...PR_CHANGE, compare: changes({ filename: ".github/workflows/pr-refine.yml" }) }, { status: "403", body: "not json" });
  assert.equal(run.status, 1);
  assert.match(run.output, /^failure-reason=lane-token-denied: the broker answered 403 with reason unknown/m);
  assert.deepEqual(run.compares, []);
});

for (const [name, inputs] of [
  ["no head SHA", { HEAD_SHA: "" }],
  ["a short head SHA", { HEAD_SHA: "abc123" }],
  ["no default branch", { DEFAULT_BRANCH: "" }],
  ["no token", { API_TOKEN: "" }],
  ["no PR number", { PR_NUMBER: "", ISSUE_NUMBER: "77" }],
]) {
  test(`pr-workflow-change-ok with ${name} fails before the broker request`, () => {
    const run = request({ ...PR_CHANGE, ...inputs });
    assert.equal(run.status, 1);
    assert.match(run.stdout, /::error::pr-workflow-change-ok needs token mode, a PR number, a head SHA, the default branch and a GitHub token/);
    assert.equal(run.body, null);
  });
}

test("a pr-workflow-change-ok other than true or false fails before the broker request", () => {
  const run = request({ PR_WORKFLOW_CHANGE_OK: "yes" });
  assert.equal(run.status, 1);
  assert.match(run.stdout, /::error::pr-workflow-change-ok must be true or false/);
  assert.equal(run.body, null);
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

// An activity grant of actions read (lane-rules.json activity-grants), as no live lane sets.
const PR_MERGE = { LANE: "pr-merge", ACTIVITY: "merge-pr", EFFECT: "merge", CONTENTS: "write", PULL_REQUESTS: "write", ISSUES: "write", PR_NUMBER: "" };
const grantedWith = (permissions) => ({
  token: "ghs_lane",
  expires_at: "2026-10-11T13:00:00Z",
  mint_id: "5550001-1",
  effect: "merge",
  permissions: { contents: "write", pull_requests: "write", issues: "write", ...permissions },
  lane: "pr-merge",
  activity: "merge-pr",
  repository_ids: [Number(REPO_ID)],
});

test("a resolved actions read grant the broker matches mints the token", () => {
  const run = request({ ...PR_MERGE, ACTIONS: "read" });
  assert.equal(run.status, 0, run.stdout);
  assert.match(run.output, /^token=ghs_lane$/m);
});

test("a broker grant whose actions differs from the resolved grant fails red as effect-mismatch", () => {
  for (const [resolved, granted] of [["read", {}], ["", { actions: "read" }], ["read", { actions: "write" }]]) {
    const run = request({ ...PR_MERGE, ACTIONS: resolved }, { body: grantedWith(granted) });
    assert.equal(run.status, 1, `${resolved} vs ${JSON.stringify(granted)}`);
    assert.match(run.stdout, /::error::effect-mismatch: /);
    assert.doesNotMatch(run.output, /^token=/m);
  }
});

test("an actions grant other than read or empty fails before the broker request", () => {
  const run = request({ ...PR_MERGE, ACTIONS: "write" });
  assert.equal(run.status, 1);
  assert.match(run.stdout, /::error::the resolved grant's actions must be read or empty/);
  assert.equal(run.body, null);
});

test("check mode refuses an actions grant before the broker request", () => {
  const run = request({ MODE: "check", EFFECT: "", CONTENTS: "", PULL_REQUESTS: "", ISSUES: "", PR_NUMBER: "", ACTIONS: "read" });
  assert.equal(run.status, 1);
  assert.match(run.stdout, /::error::check mode takes no effect, grant/);
  assert.equal(run.body, null);
});
