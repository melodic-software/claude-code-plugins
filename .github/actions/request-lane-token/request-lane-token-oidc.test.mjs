// The OIDC token request inside the action's `run:` script: a transient
// failure (HTTP 5xx or 429 under --fail, a timeout, a connection error) is
// retried inside the broker retries' budget of 3 requests and 60 s of waiting,
// and a last transient failure is titled "GitHub server error". The curl
// stand-in answers the Mth OIDC GET from $OIDC/M.exit and $OIDC/M.headers
// (absent: a token), and every broker POST from $BROKER/N.status and
// $BROKER/N.json (past the last: the last).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { after, before, test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";

const ACTION = new URL("./action.yml", import.meta.url);
const REPO_ID = "1277265216";
const REQUEST_TOKEN = "request-token-must-not-leak";
const ERROR_BODY = "oidc-error-body-must-not-leak";

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

// An HTTP error answer is written to the -D file and, as real curl does
// without --fail, its body to stdout; with --fail it prints only curl's
// "(22)" line to stderr.
const FAKE_CURL = `#!/usr/bin/env bash
stdin=$(cat)
out="" data="" dump="" write="" fail=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out=$2; shift ;;
    -D) dump=$2; shift ;;
    -w) write=1; shift ;;
    --fail) fail=1 ;;
    --data-binary) data=$2; shift ;;
  esac
  shift
done
if [ -n "$data" ]; then
  printf '%s\\n' "$stdin" >>"$AUTH_LOG"
  n=$(($(wc -l <"$AUTH_LOG")))
  [ -e "$BROKER/$n.status" ] || n=$(ls "$BROKER" | grep -c '\\.status$')
  cat "$BROKER/$n.json" >"$out"
  if [ -e "$BROKER/$n.headers" ]; then cat "$BROKER/$n.headers" >"$dump"; else printf 'HTTP/2 %s\\r\\n\\r\\n' "$(cat "$BROKER/$n.status")" >"$dump"; fi
  cat "$BROKER/$n.status"
elif [ -n "$write" ]; then
  printf 204
else
  echo x >>"$OIDC_LOG"
  m=$(($(wc -l <"$OIDC_LOG")))
  if [ -e "$OIDC/$m.exit" ]; then
    code=$(cat "$OIDC/$m.exit")
    if [ -e "$OIDC/$m.headers" ]; then
      [ -n "$dump" ] && cat "$OIDC/$m.headers" >"$dump"
      if [ -z "$fail" ]; then printf '{"message":"%s"}' "$ERROR_BODY"; exit 0; fi
      echo "curl: (22) The requested URL returned error" >&2
    else
      echo "curl: ($code) transfer failed" >&2
    fi
    exit "$code"
  fi
  printf '{"value":"oidc-token-%s"}' "$m"
fi
`;

const FAKE_SLEEP = `#!/usr/bin/env bash
printf '%s\\n' "$1" >>"$SLEEP_LOG"
`;

let root;
let bin;

before(() => {
  root = tempDir("request-lane-token-oidc-");
  bin = path.join(root, "bin");
  mkdirSync(bin);
  writeFileSync(path.join(bin, "curl"), FAKE_CURL);
  chmodSync(path.join(bin, "curl"), 0o755);
  writeFileSync(path.join(bin, "sleep"), FAKE_SLEEP);
  chmodSync(path.join(bin, "sleep"), 0o755);
});

after(() => rmSync(root, { recursive: true, force: true }));

const MINT = {
  token: "ghs_lane",
  expires_at: "2026-10-11T13:00:00Z",
  mint_id: "5550001-1",
  effect: "mutate-branch",
  permissions: { contents: "write", pull_requests: "read", issues: "read" },
  lane: "work-resolve-issue",
  activity: "resolve-issue",
  repository_ids: [Number(REPO_ID)],
};

// An OIDC answer: an HTTP status (curl --fail exit 22, with that status line
// and an optional Retry-After in the -D file), or a bare curl exit code.
const http = (status, extra = "") => ({ exit: 22, headers: `HTTP/2 ${status}\r\n${extra}content-type: application/json\r\n\r\n` });
const curlExit = (code) => ({ exit: code });
const OK = null;

// `oidc` lists the OIDC answers in order (OK, or beyond the list: a token);
// `broker` lists the broker answers (absent: one mint).
function request({ oidc = [], broker = [{ status: "200", body: MINT }], inputs = {} } = {}) {
  const dir = mkdtempSync(path.join(root, "run-"));
  const files = Object.fromEntries(["output", "summary", "auth", "oidc", "sleep"].map((name) => [name, path.join(dir, name)]));
  for (const file of Object.values(files)) writeFileSync(file, "");
  const oidcDir = path.join(dir, "oidc-answers");
  const brokerDir = path.join(dir, "broker-answers");
  mkdirSync(oidcDir);
  mkdirSync(brokerDir);
  oidc.forEach((answer, i) => {
    if (!answer) return;
    writeFileSync(path.join(oidcDir, `${i + 1}.exit`), String(answer.exit));
    if (answer.headers) writeFileSync(path.join(oidcDir, `${i + 1}.headers`), answer.headers);
  });
  broker.forEach((answer, i) => {
    writeFileSync(path.join(brokerDir, `${i + 1}.status`), answer.status);
    writeFileSync(path.join(brokerDir, `${i + 1}.json`), JSON.stringify(answer.body));
    if (answer.headers) writeFileSync(path.join(brokerDir, `${i + 1}.headers`), answer.headers);
  });
  const result = spawnSync("bash", ["-e", "-c", runScript()], {
    encoding: "utf8",
    env: {
      PATH: `${bin}:${process.env.PATH}`,
      MODE: "token",
      BROKER_URL: "https://broker.example.net/api/token",
      AUDIENCE: "melodic-lanes-token-broker",
      LANE: "work-resolve-issue",
      ACTIVITY: "resolve-issue",
      PR_NUMBER: "",
      ISSUE_NUMBER: "77",
      DISPATCHER_RUN_ID: "",
      EFFECT: "mutate-branch",
      CONTENTS: "write",
      PULL_REQUESTS: "read",
      ISSUES: "read",
      ...inputs,
      ACTIONS_ID_TOKEN_REQUEST_URL: "https://oidc.example.net/token?api-version=2.0",
      ACTIONS_ID_TOKEN_REQUEST_TOKEN: REQUEST_TOKEN,
      GITHUB_API_URL: "https://api.github.com",
      GITHUB_REPOSITORY: "melodic-software/claude-code-plugins",
      GITHUB_REPOSITORY_ID: REPO_ID,
      GITHUB_OUTPUT: files.output,
      GITHUB_STEP_SUMMARY: files.summary,
      RUNNER_TEMP: dir,
      AUTH_LOG: files.auth,
      OIDC_LOG: files.oidc,
      SLEEP_LOG: files.sleep,
      OIDC: oidcDir,
      BROKER: brokerDir,
      ERROR_BODY,
    },
  });
  const lines = (file) => readFileSync(file, "utf8").split("\n").filter(Boolean);
  return {
    status: result.status,
    log: result.stdout + result.stderr,
    stdout: result.stdout,
    output: readFileSync(files.output, "utf8"),
    oidcRequests: lines(files.oidc).length,
    brokerRequests: lines(files.auth).length,
    sleeps: lines(files.sleep).map(Number),
    leftovers: ["lane-token-oidc-headers.txt", "lane-token-response.json", "lane-token-headers.txt"].filter((f) => existsSync(path.join(dir, f))),
  };
}

const errors = (run) => run.stdout.split("\n").filter((line) => line.startsWith("::error"));
const warnings = (run) => run.stdout.split("\n").filter((line) => line.startsWith("::warning::"));

function assertNoSecret(run) {
  assert.doesNotMatch(run.log, new RegExp(REQUEST_TOKEN), "the OIDC request token never reaches the log");
  assert.doesNotMatch(run.log, new RegExp(ERROR_BODY), "an OIDC error body never reaches the log");
  const unmasked = run.log.split("\n").filter((line) => !line.startsWith("::add-mask::"));
  assert.doesNotMatch(unmasked.join("\n"), /oidc-token-\d/, "an OIDC token reaches the log only in its ::add-mask:: command");
  assert.doesNotMatch(run.output, /oidc-token-\d|request-token/, "no OIDC token reaches the step outputs");
}

for (const [label, answer, why] of [
  ["an HTTP 500", http(500), "HTTP 500"],
  ["an HTTP 502", http(502), "HTTP 502"],
  ["an HTTP 503", http(503), "HTTP 503"],
  ["an HTTP 504", http(504), "HTTP 504"],
  ["an HTTP 429", http(429), "HTTP 429"],
  ["a timeout (curl exit 28)", curlExit(28), "curl exit 28"],
  ["a refused connection (curl exit 7)", curlExit(7), "curl exit 7"],
  ["an unresolved host (curl exit 6)", curlExit(6), "curl exit 6"],
  ["a reset connection (curl exit 56)", curlExit(56), "curl exit 56"],
]) {
  test(`an OIDC token request that fails with ${label} is retried with backoff and then mints`, () => {
    const run = request({ oidc: [answer, OK] });
    assert.equal(run.status, 0, run.log);
    assert.equal(run.oidcRequests, 2, "a second OIDC request follows the failure");
    assert.equal(run.brokerRequests, 1, "the broker is asked once, with the second OIDC token");
    assert.equal(run.sleeps.length, 1, "one wait before the retry");
    assert.ok(run.sleeps[0] >= 0 && run.sleeps[0] <= 20, `the first wait is full jitter up to 20 s, got ${run.sleeps[0]}`);
    assert.deepEqual(warnings(run), [`::warning::lane-token-retry: the OIDC token request failed: ${why}; retry 1 of 2 in ${run.sleeps[0]}s`]);
    assert.deepEqual(errors(run), [], "a retried success annotates no error");
    assert.match(run.output, /^mint-id=5550001-1$/m);
    assertNoSecret(run);
  });
}

test("an OIDC 503 with a Retry-After longer than the backoff waits the Retry-After", () => {
  const run = request({ oidc: [http(503, "Retry-After: 45\r\n"), OK] });
  assert.equal(run.status, 0, run.log);
  assert.deepEqual(run.sleeps, [45]);
});

test("an OIDC 429 on every attempt fails red after three requests, titled GitHub server error", () => {
  const run = request({ oidc: [http(429), http(429), http(429)] });
  assert.equal(run.status, 1);
  assert.equal(run.oidcRequests, 3, "at most three OIDC requests");
  assert.equal(run.brokerRequests, 0, "the broker is never asked without an OIDC token");
  assert.equal(run.sleeps.length, 2);
  assert.ok(run.sleeps[0] <= 20 && run.sleeps[1] <= 40, `waits ${run.sleeps}`);
  assert.deepEqual(errors(run), ["::error title=GitHub server error::the OIDC token request failed: HTTP 429 on attempt 3 of 3"]);
  assert.equal(run.output, "failure-reason=the OIDC token request failed: HTTP 429 on attempt 3 of 3\n");
  assertNoSecret(run);
});

test("an OIDC timeout on every attempt fails red after three requests, naming the curl exit", () => {
  const run = request({ oidc: [curlExit(28), curlExit(28), curlExit(28)] });
  assert.equal(run.status, 1);
  assert.equal(run.oidcRequests, 3);
  assert.deepEqual(errors(run), ["::error title=GitHub server error::the OIDC token request failed: curl exit 28 on attempt 3 of 3"]);
  assert.deepEqual(run.leftovers, [], "the step leaves no response or header file behind");
});

test("an OIDC Retry-After past the 1-minute budget is not waited and fails red at once, titled GitHub server error", () => {
  const run = request({ oidc: [http(503, "retry-after: 61\r\n")] });
  assert.equal(run.status, 1);
  assert.equal(run.oidcRequests, 1);
  assert.deepEqual(run.sleeps, []);
  assert.deepEqual(errors(run), [
    "::error title=GitHub server error::the OIDC token request failed: HTTP 503 on attempt 1 of 3; the next wait would pass the 1-minute retry budget",
  ]);
});

test("a proxy's CONNECT 200 before the OIDC answer's 503 reads as the 503", () => {
  const run = request({ oidc: [{ exit: 22, headers: "HTTP/1.1 200 Connection established\r\n\r\nHTTP/2 503\r\n\r\n" }, OK] });
  assert.equal(run.status, 0, run.log);
  assert.deepEqual(warnings(run), [`::warning::lane-token-retry: the OIDC token request failed: HTTP 503; retry 1 of 2 in ${run.sleeps[0]}s`]);
});

for (const [label, answer] of [
  ["an HTTP 400", http(400)],
  ["an HTTP 401", http(401)],
  ["an HTTP 403", http(403)],
  ["an HTTP 404", http(404)],
  ["an HTTP 408", http(408)],
  ["an HTTP error with no status line", { exit: 22, headers: "\r\n" }],
  ["a malformed URL (curl exit 3)", curlExit(3)],
  ["a local write error (curl exit 23)", curlExit(23)],
]) {
  test(`an OIDC token request that fails with ${label} is final, with today's plain message and no title`, () => {
    const run = request({ oidc: [answer, OK] });
    assert.equal(run.status, 1);
    assert.equal(run.oidcRequests, 1, "no retry");
    assert.equal(run.brokerRequests, 0);
    assert.deepEqual(run.sleeps, []);
    assert.deepEqual(errors(run), ["::error::the OIDC token request failed"]);
    assert.equal(run.output, "failure-reason=the OIDC token request failed\n");
    assertNoSecret(run);
  });
}

const GITHUB_UNAVAILABLE = { status: "503", body: { error: "unavailable", reason: "github-unavailable", detail: "d" } };

test("an OIDC retry spends the same three requests as a broker retry: a broker 503 then two OIDC 503s fail on attempt 3", () => {
  const run = request({ oidc: [OK, http(503), http(503)], broker: [GITHUB_UNAVAILABLE, { status: "200", body: MINT }] });
  assert.equal(run.status, 1);
  assert.equal(run.oidcRequests, 3, "three OIDC requests in all, not three after the broker's retry");
  assert.equal(run.brokerRequests, 1);
  assert.equal(run.sleeps.length, 2);
  assert.ok(run.sleeps.reduce((a, b) => a + b, 0) <= 60, `waits ${run.sleeps} stay within the 60 s budget`);
  assert.deepEqual(errors(run), ["::error title=GitHub server error::the OIDC token request failed: HTTP 503 on attempt 3 of 3"]);
});

test("an OIDC retry spends the same 60 s as a broker retry: after a 45 s broker wait a 30 s OIDC Retry-After is not waited", () => {
  const run = request({
    oidc: [OK, http(503, "Retry-After: 30\r\n")],
    broker: [{ ...GITHUB_UNAVAILABLE, headers: "HTTP/2 503\r\nRetry-After: 45\r\n\r\n" }, { status: "200", body: MINT }],
  });
  assert.equal(run.status, 1);
  assert.deepEqual(run.sleeps, [45], "only the broker's wait is taken");
  assert.equal(run.oidcRequests, 2);
  assert.deepEqual(errors(run), [
    "::error title=GitHub server error::the OIDC token request failed: HTTP 503 on attempt 2 of 3; the next wait would pass the 1-minute retry budget",
  ]);
});

test("a broker failure after an OIDC retry names the OIDC failure it followed", () => {
  const run = request({ oidc: [http(502), OK], broker: [{ status: "403", body: { error: "denied", reason: "lane-mismatch", detail: "d" } }] });
  assert.equal(run.status, 1);
  assert.equal(run.output, "failure-reason=lane-token-denied: the broker answered 403 with reason lane-mismatch: d, after a failed OIDC token request (HTTP 502)\n");
});
