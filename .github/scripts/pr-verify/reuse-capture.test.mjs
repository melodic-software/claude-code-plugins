/**
 * reuse-capture.mjs, which pr-verify-capture.yml runs before any credential
 * step: a finished capture of the same pull request and head, made under the
 * same key, stands in for a new one; a changed head or config, a blocked
 * capture, or one from any other workflow captures again.
 */
import assert from "node:assert/strict";
import { existsSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { CAPTURE_PATH } from "./find-capture.mjs";
import { findEarlier, main, reuseKey, takeEarlier } from "./reuse-capture.mjs";

const REPO = "melodic-software/claude-code-plugins";
const PR = "41";
const HEAD = "a".repeat(40);
const OTHER_HEAD = "b".repeat(40);
const BASE = "c".repeat(40);
const INPUTS = ".github/workflows/pr-verify-capture.yml 1111111111111111111111111111111111111111\n";
const KEY_INPUTS = { pr: PR, headSha: HEAD, baseSha: BASE, app: "demo", inputs: INPUTS };
const NAME = `pr-capture-${PR}-${HEAD}`;

const run = (overrides = {}) => ({
  id: 900,
  path: CAPTURE_PATH,
  event: "workflow_run",
  head_branch: "main",
  repository: { full_name: REPO },
  display_title: `pr-verify-capture 777 ${HEAD}`,
  status: "completed",
  conclusion: "success",
  ...overrides,
});
const artifact = (overrides = {}) => ({ id: 5001, name: NAME, expired: false, workflow_run: { id: 900 }, ...overrides });

const fake = ({ artifacts = [artifact()], runs = { 900: run() }, fail = false } = {}) => {
  const calls = [];
  const github = async (method, apiPath) => {
    calls.push(`${method} ${apiPath}`);
    if (fail) throw new Error("HTTP 502");
    if (apiPath.startsWith(`/repos/${REPO}/actions/artifacts?`)) return { artifacts };
    return runs[/\/runs\/(\d+)$/.exec(apiPath)[1]];
  };
  return { github, calls };
};

/** A downloaded capture: its summary and one publishable file. */
function earlier({ status = "ran", key = reuseKey(KEY_INPUTS), madeBy = "900" } = {}) {
  const dir = tempDir("reuse-earlier-");
  writeFileSync(path.join(dir, "e2e-summary.json"), JSON.stringify({ app: "demo", capture: { status, reason: null, count: 1 }, affected: ["f"], provenance: { key, run_id: madeBy } }));
  mkdirSync(path.join(dir, "shots"));
  writeFileSync(path.join(dir, "shots", "one.png"), "png");
  return dir;
}

const outputs = (file) => (existsSync(file) ? readFileSync(file, "utf8") : "");

test("an earlier green capture run of the same head is found by its artifact", async () => {
  const { github, calls } = fake();
  assert.deepEqual(await findEarlier(github, { repository: REPO, pr: PR, headSha: HEAD, runId: "950" }), { runId: "900", artifactId: "5001" });
  assert.deepEqual(calls, [`GET /repos/${REPO}/actions/artifacts?name=${NAME}&per_page=20`, `GET /repos/${REPO}/actions/runs/900`]);
});

test("an artifact of the capture's name from anything but a green capture run of this head on main is passed over", async () => {
  for (const [why, record] of [
    ["another workflow", run({ path: ".github/workflows/pr-other.yml" })],
    ["a pull request run", run({ event: "pull_request" })],
    ["a branch other than main", run({ head_branch: "feature" })],
    ["another repository", run({ repository: { full_name: "someone/fork" } })],
    ["a red run", run({ conclusion: "failure" })],
    ["a run of another head", run({ display_title: `pr-verify-capture 777 ${OTHER_HEAD}` })],
  ]) {
    const { github } = fake({ runs: { 900: record } });
    assert.equal(await findEarlier(github, { repository: REPO, pr: PR, headSha: HEAD, runId: "950" }), undefined, why);
  }
  const { github, calls } = fake({
    artifacts: [artifact({ id: 5003, workflow_run: { id: 950 } }), artifact({ id: 5002, expired: true, workflow_run: { id: 920 } }), artifact()],
  });
  assert.deepEqual(
    await findEarlier(github, { repository: REPO, pr: PR, headSha: HEAD, runId: "950" }),
    { runId: "900", artifactId: "5001" },
    "this run's own artifact and an expired one are passed over for the next older one",
  );
  assert.equal(calls.length, 2, "only the one candidate's run record is read");
});

test("the same head under the same key reuses the capture, naming the run that made it", () => {
  const out = path.join(tempDir("reuse-out-"), "pr-capture");
  const taken = takeEarlier({ dir: earlier({ madeBy: "800" }), out, key: reuseKey(KEY_INPUTS) });
  assert.deepEqual(taken, { madeBy: "800" }, "run 900's capture was itself a reuse of run 800's, and 800 stays its maker");
  assert.equal(JSON.parse(readFileSync(path.join(out, "e2e-summary.json"), "utf8")).provenance.run_id, "800");
  assert.equal(readFileSync(path.join(out, "shots", "one.png"), "utf8"), "png");
});

test("a changed head, base, app or config captures again", () => {
  const key = reuseKey(KEY_INPUTS);
  for (const [why, changed] of [
    ["head", { headSha: OTHER_HEAD }],
    ["base", { baseSha: "d".repeat(40) }],
    ["app", { app: "other" }],
    ["config", { inputs: INPUTS.replace("1111", "2222") }],
    ["pull request", { pr: "42" }],
  ]) {
    const now = reuseKey({ ...KEY_INPUTS, ...changed });
    assert.notEqual(now, key, why);
    const out = path.join(tempDir("reuse-out-"), "pr-capture");
    assert.ok(takeEarlier({ dir: earlier({ key }), out, key: now }).refused, why);
    assert.equal(existsSync(out), false, `${why}: nothing is copied`);
  }
});

test("a blocked earlier capture, or one with no stamp, captures again", () => {
  const key = reuseKey(KEY_INPUTS);
  const out = path.join(tempDir("reuse-out-"), "pr-capture");
  assert.ok(takeEarlier({ dir: earlier({ status: "blocked" }), out, key }).refused);
  const unstamped = earlier();
  writeFileSync(path.join(unstamped, "e2e-summary.json"), JSON.stringify({ capture: { status: "ran", reason: null, count: 1 } }));
  assert.ok(takeEarlier({ dir: unstamped, out, key }).refused);
  assert.equal(existsSync(out), false);
});

test("a link in the downloaded capture is not copied", () => {
  const dir = earlier();
  symlinkSync("/etc/passwd", path.join(dir, "shots", "link.png"));
  const out = path.join(tempDir("reuse-out-"), "pr-capture");
  assert.deepEqual(takeEarlier({ dir, out, key: reuseKey(KEY_INPUTS) }), { madeBy: "900" });
  assert.equal(existsSync(path.join(out, "shots", "link.png")), false);
  assert.equal(existsSync(path.join(out, "shots", "one.png")), true);
});

test("find writes the key and the earlier run, and a failed read still writes the key so the capture is stamped", async () => {
  const env = { GITHUB_REPOSITORY: REPO, GITHUB_RUN_ID: "950", PR_NUMBER: PR, HEAD_SHA: HEAD, BASE_SHA: BASE, APP: "demo", INPUTS };
  const found = path.join(tempDir("reuse-gh-"), "out");
  await main({ ...env, GITHUB_OUTPUT: found }, "find", fake());
  assert.equal(outputs(found), `key=${reuseKey(KEY_INPUTS)}\nrun-id=900\nartifact-id=5001\n`);
  const failed = path.join(tempDir("reuse-gh-"), "out");
  await main({ ...env, GITHUB_OUTPUT: failed }, "find", fake({ fail: true }));
  assert.equal(outputs(failed), `key=${reuseKey(KEY_INPUTS)}\n`);
});

test("take marks the run reused only when the capture stands in", async () => {
  const key = reuseKey(KEY_INPUTS);
  const reused = path.join(tempDir("reuse-gh-"), "out");
  await main({ GITHUB_OUTPUT: reused, KEY: key, EARLIER: earlier(), OUT: path.join(tempDir("reuse-out-"), "pr-capture") }, "take");
  assert.equal(outputs(reused), "reused=true\nmade-by=900\n");
  const refused = path.join(tempDir("reuse-gh-"), "out");
  await main({ GITHUB_OUTPUT: refused, KEY: key, EARLIER: earlier({ status: "blocked" }), OUT: path.join(tempDir("reuse-out-"), "pr-capture") }, "take");
  assert.equal(outputs(refused), "");
});
