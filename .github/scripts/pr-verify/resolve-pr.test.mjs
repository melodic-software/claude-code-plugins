// Expected values come from issue #7702 (Scope) and the review round on its
// pull request: only a successful pr-require-checks pull_request run of this
// repository starts a verdict, for exactly one open same-repository PR into
// main whose head is the run's head SHA; the head is the run's, and the base
// SHA is the PR's; a head with a counted verdict from a completed run (a FAIL
// under any PR number) is not judged again, but a run still going or one that
// uploaded nothing does not stop a new judgment. Response shapes follow GET
// /actions/runs/{id}, /commits/{sha}/pulls, /actions/artifacts and the
// closingIssuesReferences GraphQL field.
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

import { main, resolvePull } from "./resolve-pr.mjs";

const REPO = "example-org/example-repo";
const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);
const MAIN = "c".repeat(40);
const RUN = 5551;
const ISSUE = { number: 7, repository: { nameWithOwner: REPO }, author: { __typename: "User", login: "maintainer", databaseId: 100 } };

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
  user: { id: 337595936, login: "melodic-automation-lanes[bot]" },
  head: { sha: HEAD, ref: "feat/x", repo: { full_name: REPO } },
  base: { ref: "main", sha: BASE },
  ...overrides,
});

const verifyRun = (id, overrides = {}) => ({
  id,
  path: ".github/workflows/pr-verify.yml",
  event: "workflow_run",
  status: "completed",
  conclusion: "success",
  head_branch: "main",
  head_sha: MAIN,
  repository: { full_name: REPO },
  head_repository: { full_name: REPO },
  ...overrides,
});

const artifact = (name, runId, expired = false) => ({ name, expired, workflow_run: { id: runId } });

function fake({ run = upstream(), pulls = [pull()], artifacts = [], runs = {}, onMain = [MAIN], issues = [ISSUE] } = {}) {
  const github = async (method, apiPath) => {
    if (apiPath === `/repos/${REPO}/actions/runs/${RUN}`) return run;
    if (apiPath === `/repos/${REPO}/commits/${HEAD}/pulls`) return pulls;
    if (apiPath === "/graphql") {
      return { data: { repository: { pullRequest: { closingIssuesReferences: { totalCount: issues.length, nodes: issues } } } } };
    }
    const page = /\/actions\/artifacts\?per_page=100&page=(\d+)$/.exec(apiPath);
    if (page) return { artifacts: Number(page[1]) === 1 ? artifacts : [] };
    const other = /\/actions\/runs\/(\d+)$/.exec(apiPath);
    if (other && runs[other[1]]) return runs[other[1]];
    const compare = /\/compare\/([0-9a-f]+)\.\.\.main$/.exec(apiPath);
    if (compare) return { status: onMain.includes(compare[1]) ? "ahead" : "diverged" };
    throw new Error(`unexpected ${method} ${apiPath}`);
  };
  return github;
}

const resolve = (setup) => resolvePull({ github: fake(setup), repository: REPO, upstreamRunId: String(RUN) });
const reason = async (setup) => (await resolve(setup)).reason;

test("a passing same-repository run resolves its one PR at the run's head", async () => {
  assert.deepEqual(await resolve(), {
    proceed: true,
    reason: "ok",
    prNumber: 41,
    headSha: HEAD,
    baseSha: BASE,
    headRef: "feat/x",
    linkedIssues: [{ number: 7, author_login: "maintainer", author_id: 100, author_type: "User" }],
  });
});

test("a linked issue in another repository is left out", async () => {
  const foreign = { ...ISSUE, number: 9, repository: { nameWithOwner: "someone/else" } };
  assert.deepEqual((await resolve({ issues: [foreign] })).linkedIssues, []);
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
    assert.equal(await reason({ run: upstream(overrides) }), "not-a-passing-run", JSON.stringify(overrides));
  }
});

test("anything but exactly one open same-repository PR into main at that head starts nothing", async () => {
  for (const pulls of [
    [],
    [pull(), pull({ number: 42 })],
    [pull({ state: "closed" })],
    [pull({ head: { sha: BASE, ref: "feat/x", repo: { full_name: REPO } } })],
    [pull({ head: { sha: HEAD, ref: "feat/x", repo: { full_name: "someone/fork" } } })],
    [pull({ base: { ref: "release", sha: BASE } })],
  ]) {
    assert.equal(await reason({ pulls }), "no-single-pr", JSON.stringify(pulls));
  }
});

test("a draft and a dependency manager's PR start nothing", async () => {
  assert.equal(await reason({ pulls: [pull({ draft: true })] }), "draft");
  for (const login of ["dependabot[bot]", "Renovate[bot]", "renovate-bot", "app/dependabot-preview"]) {
    assert.equal(await reason({ pulls: [pull({ user: { id: 1, login } })] }), "dependency-manager", login);
  }
});

test("a counted verdict at the head from a completed run stops a new judgment", async () => {
  const cases = {
    "this PR's pass": [artifact(`pr-verify-41-${HEAD}-pass`, 77), verifyRun(77)],
    "this PR's fail": [artifact(`pr-verify-41-${HEAD}-fail`, 77), verifyRun(77)],
    "another PR's fail": [artifact(`pr-verify-99-${HEAD}-fail`, 77), verifyRun(77)],
    "a fail from a run that failed later": [artifact(`pr-verify-41-${HEAD}-fail`, 77), verifyRun(77, { conclusion: "failure" })],
  };
  for (const [label, [item, record]] of Object.entries(cases)) {
    assert.equal(await reason({ artifacts: [item], runs: { 77: record } }), "already-judged", label);
  }
});

test("a run still going, or a run that uploaded nothing, does not stop a new judgment", async () => {
  const going = verifyRun(77, { status: "in_progress", conclusion: null });
  assert.equal(await reason({ artifacts: [artifact(`pr-verify-41-${HEAD}-fail`, 77)], runs: { 77: going } }), "ok");
  // A failed run with no artifact leaves nothing in the listing.
  assert.equal(await reason({ artifacts: [], runs: { 77: verifyRun(77, { conclusion: "failure" }) } }), "ok");
});

test("a verdict that would not count does not stop a new judgment", async () => {
  const name = `pr-verify-41-${HEAD}-pass`;
  const forgeries = {
    path: { path: ".github/workflows/pr-require-checks.yml" },
    event: { event: "pull_request" },
    head_branch: { head_branch: "feat/x" },
    repository: { repository: { full_name: "someone/fork" } },
    head_repository: { head_repository: { full_name: "someone/fork" } },
    status: { status: "queued" },
    conclusion: { conclusion: "cancelled" },
    id: { id: 78 },
    "head off main": { head_sha: "d".repeat(40) },
  };
  for (const [field, overrides] of Object.entries(forgeries)) {
    const runs = { 77: verifyRun(77, overrides) };
    assert.equal(await reason({ artifacts: [artifact(name, 77)], runs }), "ok", field);
  }
  assert.equal(await reason({ artifacts: [artifact(name, 77, true)], runs: { 77: verifyRun(77) } }), "ok", "expired");
  assert.equal(await reason({ artifacts: [artifact(name, 77)], runs: {} }), "ok", "unreadable run");
  const otherPass = `pr-verify-99-${HEAD}-pass`;
  assert.equal(await reason({ artifacts: [artifact(otherPass, 77)], runs: { 77: verifyRun(77) } }), "ok", "another PR's pass");
});

test("a malformed run id throws", async () => {
  await assert.rejects(resolvePull({ github: fake(), repository: REPO, upstreamRunId: "1;x" }));
});

test("main writes the outputs and the linked issues the workflow reads", async () => {
  const dir = mkdtempSync(path.join(tmpdir(), "pr-verify-"));
  const output = path.join(dir, "out");
  const spec = path.join(dir, "spec.json");
  await main(
    { GITHUB_TOKEN: "t", GITHUB_REPOSITORY: REPO, GITHUB_OUTPUT: output, UPSTREAM_RUN_ID: String(RUN), SPEC_FILE: spec },
    { github: fake() },
  );
  assert.equal(
    readFileSync(output, "utf8"),
    `proceed=true\nreason=ok\npr-number=41\nhead-sha=${HEAD}\nbase-sha=${BASE}\nhead-ref=feat/x\n`,
  );
  assert.deepEqual(JSON.parse(readFileSync(spec, "utf8")), [
    { number: 7, author_login: "maintainer", author_id: 100, author_type: "User" },
  ]);
});
