import assert from "node:assert/strict";
import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, test } from "node:test";
import { fileURLToPath } from "node:url";

import { main } from "./report-check-run.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SCHEMA_REL = "docs/conventions/pr-pipeline/pr-pipeline.schema.json";
const LIVE_SCHEMA = path.join(HERE, "..", "..", "..", SCHEMA_REL);
const REPOSITORY = "melodic-software/claude-code-plugins";
const HEAD = "d".repeat(40);
const FALLBACK = "f".repeat(40);

let dir;
let basePath;
beforeEach(() => {
  dir = mkdtempSync(path.join(tmpdir(), "report-check-run-"));
  basePath = path.join(dir, "base");
  mkdirSync(path.dirname(path.join(basePath, SCHEMA_REL)), { recursive: true });
  cpSync(LIVE_SCHEMA, path.join(basePath, SCHEMA_REL));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

const fixture = (name) => path.join(HERE, "fixtures", name);

function fakeFetch(status = 201) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({
      url,
      init,
      body: init.body === undefined ? undefined : JSON.parse(init.body),
    });
    return { ok: status < 300, status, json: async () => ({ id: 1 }) };
  };
  fetchImpl.calls = calls;
  return fetchImpl;
}

async function run(env = {}, status) {
  const fetchImpl = fakeFetch(status);
  const lines = [];
  const code = await main({
    env: {
      LANE: "pr-refine",
      ACTIVITY: "simplify",
      RUN_RESULT: "success",
      ACT_OUTCOME: "success",
      CAN_COMMIT: "false",
      ALL_VERIFIED: "",
      GATE_REASON: "",
      HEAD_SHA: HEAD,
      HEAD_SHA_FALLBACK: FALLBACK,
      VERDICT_PATH: fixture("verdict-success.json"),
      BASE_PATH: basePath,
      GITHUB_REPOSITORY: REPOSITORY,
      GITHUB_TOKEN: "test-token",
      GITHUB_API_URL: "https://api.example.test",
      GITHUB_SERVER_URL: "https://github.com",
      GITHUB_RUN_ID: "123",
      ...env,
    },
    fetchImpl,
    log: (line) => lines.push(line),
  });
  return { code, calls: fetchImpl.calls, lines };
}

test("a valid verdict POSTs one completed check run with the contract body", async () => {
  const { code, calls } = await run();
  assert.equal(code, 0);
  assert.equal(calls.length, 1);
  const [call] = calls;
  assert.equal(
    call.url,
    `https://api.example.test/repos/${REPOSITORY}/check-runs`,
  );
  assert.equal(call.init.method, "POST");
  assert.equal(call.init.headers.Authorization, "Bearer test-token");
  assert.deepEqual(Object.keys(call.body).sort(), [
    "conclusion",
    "details_url",
    "head_sha",
    "name",
    "output",
    "status",
  ]);
  assert.equal(call.body.name, "pr-refine / simplify");
  assert.equal(call.body.head_sha, HEAD);
  assert.equal(call.body.status, "completed");
  assert.equal(call.body.conclusion, "success");
  assert.equal(typeof call.body.output.title, "string");
  assert.equal(typeof call.body.output.summary, "string");
  assert.equal(
    call.body.details_url,
    `https://github.com/${REPOSITORY}/actions/runs/123`,
  );
});

test("an absent verdict file POSTs failure on the env head", async () => {
  const { code, calls } = await run({
    VERDICT_PATH: path.join(dir, "missing.json"),
  });
  assert.equal(code, 0);
  assert.equal(calls[0].body.conclusion, "failure");
  assert.equal(calls[0].body.head_sha, HEAD);
});

test("an absent verdict with no env head POSTs failure on the fallback head", async () => {
  const { calls } = await run({
    VERDICT_PATH: path.join(dir, "missing.json"),
    HEAD_SHA: "",
  });
  assert.equal(calls[0].body.conclusion, "failure");
  assert.equal(calls[0].body.head_sha, FALLBACK);
});

test("an empty verdict path POSTs failure", async () => {
  const { calls } = await run({ VERDICT_PATH: "" });
  assert.equal(calls[0].body.conclusion, "failure");
});

test("a malformed verdict file POSTs failure on the env head", async () => {
  const bad = path.join(dir, "verdict.json");
  writeFileSync(bad, "{ not json");
  const { code, calls } = await run({ VERDICT_PATH: bad });
  assert.equal(code, 0);
  assert.equal(calls[0].body.conclusion, "failure");
  assert.equal(calls[0].body.head_sha, HEAD);
});

test("the head SHA comes from env: a verdict head-sha that differs POSTs failure on the env SHA", async () => {
  const envHead = "e".repeat(40);
  const { calls } = await run({ HEAD_SHA: envHead });
  assert.equal(calls[0].body.conclusion, "failure");
  assert.equal(calls[0].body.head_sha, envHead);
});

test("a verdict claiming a no-pr gate while the env reason is empty POSTs failure", async () => {
  const { code, calls } = await run({
    VERDICT_PATH: fixture("verdict-no-pr.json"),
    HEAD_SHA: "",
    ACT_OUTCOME: "skipped",
  });
  assert.equal(code, 0);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].body.conclusion, "failure");
  assert.equal(calls[0].body.head_sha, FALLBACK);
});

test("a malformed env head SHA exits non-zero with no API call", async () => {
  const { code, calls } = await run({ HEAD_SHA: "abc" });
  assert.equal(code, 1);
  assert.equal(calls.length, 0);
});

test("lane and activity come from env: a mismatch with the verdict POSTs failure", async () => {
  const { calls } = await run({ ACTIVITY: "explain" });
  assert.equal(calls[0].body.name, "pr-refine / explain");
  assert.equal(calls[0].body.conclusion, "failure");
});

test("a cancelled run POSTs neutral superseded-sha from env, whatever the verdict says", async () => {
  const { calls } = await run({ RUN_RESULT: "cancelled" });
  assert.equal(calls[0].body.conclusion, "neutral");
  assert.match(calls[0].body.output.summary, /superseded-sha/);
});

test("a ci-status lane exits non-zero with no API call", async () => {
  const { code, calls } = await run({ LANE: "ci-status" });
  assert.equal(code, 1);
  assert.equal(calls.length, 0);
});

test("a ci-status activity exits non-zero with no API call", async () => {
  const { code, calls } = await run({ ACTIVITY: "ci-status" });
  assert.equal(code, 1);
  assert.equal(calls.length, 0);
});

test("an env gate reason no-pr with an empty env head SHA exits 0 with no API call", async () => {
  const { code, calls } = await run({
    VERDICT_PATH: fixture("verdict-no-pr.json"),
    GATE_REASON: "no-pr",
    HEAD_SHA: "",
    ACT_OUTCOME: "skipped",
  });
  assert.equal(code, 0);
  assert.equal(calls.length, 0);
});

test("a skip reason in the base schema's enum POSTs neutral", async () => {
  const { calls } = await run({
    VERDICT_PATH: fixture("verdict-skipped.json"),
    ACT_OUTCOME: "skipped",
  });
  assert.equal(calls[0].body.conclusion, "neutral");
  assert.match(calls[0].body.output.summary, /not-applicable-paths/);
});

test("the enum is read from base-path: a base schema without the reason POSTs failure", async () => {
  const schemaPath = path.join(basePath, SCHEMA_REL);
  const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
  schema.$defs["skip-reason"].enum = schema.$defs["skip-reason"].enum.filter(
    (reason) => reason !== "not-applicable-paths",
  );
  writeFileSync(schemaPath, JSON.stringify(schema));
  const { calls } = await run({
    VERDICT_PATH: fixture("verdict-skipped.json"),
    ACT_OUTCOME: "skipped",
  });
  assert.equal(calls[0].body.conclusion, "failure");
});

test("an unreadable base schema turns a skip into failure", async () => {
  rmSync(path.join(basePath, SCHEMA_REL));
  const { calls } = await run({
    VERDICT_PATH: fixture("verdict-skipped.json"),
    ACT_OUTCOME: "skipped",
  });
  assert.equal(calls[0].body.conclusion, "failure");
});

test("a signed-commit check that should have run and left no result POSTs failure", async () => {
  const { calls } = await run({ CAN_COMMIT: "", ALL_VERIFIED: "" });
  assert.equal(calls[0].body.conclusion, "failure");
});

test("an unverified commit POSTs failure", async () => {
  const { calls } = await run({ CAN_COMMIT: "true", ALL_VERIFIED: "false" });
  assert.equal(calls[0].body.conclusion, "failure");
});

test("every commit verified POSTs success", async () => {
  const { calls } = await run({ CAN_COMMIT: "true", ALL_VERIFIED: "true" });
  assert.equal(calls[0].body.conclusion, "success");
});

test("an API error exits non-zero", async () => {
  const { code, calls } = await run({}, 403);
  assert.equal(code, 1);
  assert.equal(calls.length, 1);
});

test("a malformed repository exits non-zero with no API call", async () => {
  const { code, calls } = await run({ GITHUB_REPOSITORY: "../x" });
  assert.equal(code, 1);
  assert.equal(calls.length, 0);
});

test("a malformed fallback head SHA exits non-zero with no API call", async () => {
  const { code, calls } = await run({ HEAD_SHA_FALLBACK: "" });
  assert.equal(code, 1);
  assert.equal(calls.length, 0);
});

test("a gate stop reason from env posts neutral through the shipped mapping", async () => {
  const forked = path.join(dir, "verdict-fork.json");
  const v = JSON.parse(readFileSync(fixture("verdict-no-pr.json"), "utf8"));
  v.gates.trigger.reason = "fork";
  v["head-sha"] = HEAD;
  writeFileSync(forked, JSON.stringify(v));
  const { code, calls } = await run({
    VERDICT_PATH: forked,
    GATE_REASON: "fork",
    ACT_OUTCOME: "skipped",
  });
  assert.equal(code, 0);
  assert.equal(calls[0].body.conclusion, "neutral");
  assert.equal(calls[0].body.head_sha, HEAD);
  assert.equal(calls[0].body.output.summary, "Skip reason: untrusted-trigger");
});

test("a malformed run id omits details_url", async () => {
  const { calls } = await run({ GITHUB_RUN_ID: "1/../../x" });
  assert.equal("details_url" in calls[0].body, false);
});
