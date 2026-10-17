// Expected values come from issue #7702 (Scope): only a successful
// pr-require-checks pull_request run of this repository starts a verdict, for
// exactly one open same-repository PR into main whose head is the run's head
// SHA; the head is the run's, and the base SHA is the PR's. Response shapes
// follow GET /actions/runs/{id}, /commits/{sha}/pulls and /actions/artifacts.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { DEPENDABOT_ID, main, resolvePull } from "./resolve-pr.mjs";

const REPO = "example-org/example-repo";
const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const RUN = 5551;

const upstream = (overrides = {}) => ({
  id: RUN,
  path: ".github/workflows/pr-require-checks.yml",
  event: "pull_request",
  status: "completed",
  conclusion: "success",
  head_sha: HEAD,
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  ...overrides,
});

const pull = (overrides = {}) => ({
  number: 41,
  state: "open",
  draft: false,
  user: { id: 337595936 },
  head: { sha: HEAD, repo: { full_name: REPO } },
  base: { ref: "main", sha: BASE },
  ...overrides,
});

function fake({ run = upstream(), pulls = [pull()], artifacts = {}, runs = {} } = {}) {
  const calls = [];
  const github = async (method, apiPath) => {
    calls.push(apiPath);
    if (apiPath === `/repos/${REPO}/actions/runs/${RUN}`) return run;
    if (apiPath === `/repos/${REPO}/commits/${HEAD}/pulls`) return pulls;
    const listing = /\/actions\/artifacts\?name=([^&]+)&/.exec(apiPath);
    if (listing) return { artifacts: artifacts[listing[1]] ?? [] };
    const other = /\/actions\/runs\/(\d+)$/.exec(apiPath);
    if (other && runs[other[1]]) return runs[other[1]];
    throw new Error(`unexpected ${method} ${apiPath}`);
  };
  return { github, calls };
}

const resolve = (setup) => resolvePull({ github: fake(setup).github, repository: REPO, upstreamRunId: String(RUN) });

test("a passing same-repository run resolves its one PR at the run's head", async () => {
  assert.deepEqual(await resolve(), { proceed: true, reason: "ok", prNumber: 41, headSha: HEAD, baseSha: BASE });
});

test("a run that is not a passing pr-require-checks pull_request run of this repository starts nothing", async () => {
  for (const overrides of [
    { path: ".github/workflows/pr-review-hosted.yml" },
    { event: "merge_group" },
    { event: "workflow_dispatch" },
    { conclusion: "failure" },
    { status: "in_progress", conclusion: null },
    { repository: { full_name: "someone/fork" } },
    { head_repository: { full_name: "someone/fork" } },
    { id: RUN + 1 },
    { head_sha: "nothex" },
  ]) {
    assert.deepEqual(await resolve({ run: upstream(overrides) }), { proceed: false, reason: "not-a-passing-run" }, JSON.stringify(overrides));
  }
});

test("anything but exactly one open same-repository PR into main at that head starts nothing", async () => {
  for (const pulls of [
    [],
    [pull(), pull({ number: 42 })],
    [pull({ state: "closed" })],
    [pull({ head: { sha: BASE, repo: { full_name: REPO } } })],
    [pull({ head: { sha: HEAD, repo: { full_name: "someone/fork" } } })],
    [pull({ base: { ref: "release", sha: BASE } })],
  ]) {
    assert.equal((await resolve({ pulls })).reason, "no-single-pr", JSON.stringify(pulls));
  }
});

test("a draft and a dependency manager's PR start nothing", async () => {
  assert.equal((await resolve({ pulls: [pull({ draft: true })] })).reason, "draft");
  assert.equal((await resolve({ pulls: [pull({ user: { id: DEPENDABOT_ID } })] })).reason, "dependency-manager");
});

test("a head that already has a counted verdict starts nothing", async () => {
  const name = `pr-verify-41-${HEAD}-fail`;
  const verifyRun = {
    path: ".github/workflows/pr-verify.yml",
    event: "workflow_run",
    head_branch: "main",
    conclusion: "success",
    repository: { full_name: REPO },
  };
  const artifacts = { [name]: [{ name, expired: false, workflow_run: { id: 77 } }] };
  assert.equal((await resolve({ artifacts, runs: { 77: verifyRun } })).reason, "already-judged");
});

test("a verdict another workflow uploaded, or an expired one, does not stop a new one", async () => {
  const name = `pr-verify-41-${HEAD}-pass`;
  const forged = { path: ".github/workflows/pr-require-checks.yml", event: "pull_request", head_branch: "feat", conclusion: "success", repository: { full_name: REPO } };
  const artifacts = { [name]: [{ name, expired: false, workflow_run: { id: 78 } }] };
  assert.equal((await resolve({ artifacts, runs: { 78: forged } })).reason, "ok");
  const expired = { [name]: [{ name, expired: true, workflow_run: { id: 79 } }] };
  assert.equal((await resolve({ artifacts: expired })).reason, "ok");
});

test("a malformed run id throws", async () => {
  await assert.rejects(resolvePull({ github: fake().github, repository: REPO, upstreamRunId: "1;x" }));
});

test("main writes the outputs the workflow reads", async () => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-verify-"));
  const output = path.join(dir, "out");
  await main(
    { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: REPO, GITHUB_OUTPUT: output, UPSTREAM_RUN_ID: String(RUN) },
    { github: fake().github },
  );
  assert.equal(
    readFileSync(output, "utf8"),
    `proceed=true\nreason=ok\npr-number=41\nhead-sha=${HEAD}\nbase-sha=${BASE}\n`,
  );
});
