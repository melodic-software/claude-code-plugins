import assert from "node:assert/strict";
import { test } from "node:test";

import { dispatchDependencyReviews } from "./dependency-dispatch.mjs";

const CHECK = "pr-unblock / review-dependency";

function pr(number, overrides = {}) {
  return {
    number,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: String(number).padStart(40, "c"),
    headRefName: `dependabot/npm_and_yarn/x-${number}`,
    author: { login: "dependabot[bot]" },
    title: "build(deps): bump x from 1.0.0 to 2.0.0",
    body: "",
    labels: { nodes: [{ name: "dependencies" }] },
    changedFiles: 0,
    commits: { totalCount: 1 },
    ...overrides,
  };
}

const DEPENDABOT_COMMIT_AUTHOR = { name: "dependabot[bot]", email: "49699333+dependabot[bot]@users.noreply.github.com" };
// GitHub verified and committed it, as it does Dependabot's commits.
const SIGNED = { committer: { email: "noreply@github.com" }, verification: { verified: true, reason: "valid" } };

function fakeApi({ nodes = [], checks = new Map(), ci = new Map(), files = new Map(), commits = new Map() } = {}) {
  const calls = { dispatch: [], checks: [] };
  return {
    calls,
    async listPullCommits(number) {
      return commits.get(number) ?? [{ sha: "d".repeat(40), commit: { message: "bump", author: DEPENDABOT_COMMIT_AUTHOR, ...SIGNED } }];
    },
    async getCommit(sha) {
      return { sha, files: [] };
    },
    async listPullFiles(number) {
      return files.get(number) ?? [];
    },
    async listOpenPulls() {
      return { nodes, pageInfo: { hasNextPage: false, endCursor: null } };
    },
    async listCheckRuns({ sha, checkName, appId }) {
      calls.checks.push({ sha, checkName, appId });
      if (checkName === "ci-status") {
        return ci.get(sha) ?? [];
      }
      return checks.get(sha) ?? [];
    },
    async dispatchWorkflow({ workflow, ref, inputs }) {
      calls.dispatch.push({ workflow, ref, inputs });
      return { workflowRunId: 7000 + Number(inputs["pr-number"]) };
    },
  };
}

const run = (api, extra = {}) => dispatchDependencyReviews({ api, runId: "55", log: () => {}, config: [], ...extra });

test("dispatches review-dependency for a review-tier Dependabot PR", async () => {
  const api = fakeApi({ nodes: [pr(4)] });
  const { dispatched, failed } = await run(api);
  assert.equal(failed, 0);
  assert.deepEqual(dispatched, [{ number: 4, workflowRunId: "7004" }]);
  assert.deepEqual(api.calls.dispatch[0], {
    workflow: "pr-unblock.yml",
    ref: "refs/heads/main",
    inputs: { "pr-number": "4", activity: "review-dependency", "dispatcher-run-id": "55" },
  });
});

test("leaves auto-tier bumps, other authors, drafts and forks alone", async () => {
  const api = fakeApi({
    nodes: [
      pr(1, { title: "bump x from 1.0.0 to 1.1.0" }),
      pr(2, { author: { login: "octocat" } }),
      pr(3, { isDraft: true }),
      pr(5, { isCrossRepository: true }),
      pr(6, { baseRefName: "release/plugins" }),
    ],
  });
  const { dispatched } = await run(api);
  assert.deepEqual(dispatched, []);
});

test("a red ci-status makes a patch bump review", async () => {
  const node = pr(8, { title: "bump x from 1.0.0 to 1.0.1" });
  const api = fakeApi({
    nodes: [node],
    ci: new Map([[node.headRefOid, [{ id: 1, app: { slug: "github-actions" }, status: "completed", conclusion: "failure" }]]]),
  });
  assert.equal((await run(api)).dispatched.length, 1);
});

test("skips a head that already has a review-dependency check run, except an untrusted-trigger skip", async () => {
  const a = pr(10);
  const b = pr(11);
  const api = fakeApi({
    nodes: [a, b],
    checks: new Map([
      [a.headRefOid, [{ status: "completed", conclusion: "success", output: { title: "Reviewed" } }]],
      [b.headRefOid, [{ status: "completed", conclusion: "neutral", output: { title: "Skipped: untrusted-trigger" } }]],
    ]),
  });
  const { dispatched } = await run(api);
  assert.deepEqual(dispatched.map((d) => d.number), [11]);
  assert.ok(api.calls.checks.some((call) => call.checkName === CHECK && call.appId === 15368));
});

test("Dependabot commit metadata that disagrees with the title is review, and so is another author's commit", async () => {
  const message = "bump\n---\nupdated-dependencies:\n- dependency-name: other\n  update-type: version-update:semver-patch\n...\n";
  const nodes = [pr(30, { title: "bump x from 1.0.0 to 1.0.1" }), pr(31, { title: "bump x from 1.0.0 to 1.0.1" }), pr(32, { title: "bump x from 1.0.0 to 1.0.1" })];
  const commits = new Map([
    [30, [{ sha: "a".repeat(40), commit: { message, author: DEPENDABOT_COMMIT_AUTHOR, ...SIGNED } }]],
    [31, [{ sha: "b".repeat(40), commit: { message, author: { name: "someone", email: "someone@example.test" }, ...SIGNED } }]],
    [32, [{ sha: "e".repeat(40), commit: { message: "bump", author: DEPENDABOT_COMMIT_AUTHOR } }]],
  ]);
  const { dispatched } = await run(fakeApi({ nodes, commits }), { maxDispatch: 3 });
  assert.deepEqual(dispatched.map((d) => d.number), [30, 31, 32], "an unverified Dependabot author is review too");
});

test("a patch bump whose files the content rule does not cover is review", async () => {
  const config = [["npm", "/"]];
  const nodes = [pr(40, { title: "bump x from 1.0.0 to 1.0.1", changedFiles: 1 }), pr(41, { title: "bump x from 1.0.0 to 1.0.1", changedFiles: 2 })];
  const files = new Map([
    [40, [{ filename: "package-lock.json" }]],
    [41, [{ filename: "package-lock.json" }, { filename: "dist/bundle.js" }]],
  ]);
  const { dispatched } = await run(fakeApi({ nodes, files }), { config });
  assert.deepEqual(dispatched.map((d) => d.number), [41]);
});

test("a patch bump whose commits listing is short of its total is review", async () => {
  const config = [["npm", "/"]];
  const bump = { title: "bump x from 1.0.0 to 1.0.1", changedFiles: 1 };
  const nodes = [pr(50, bump), pr(51, { ...bump, commits: { totalCount: 251 } })];
  const files = new Map([
    [50, [{ filename: "package-lock.json" }]],
    [51, [{ filename: "package-lock.json" }]],
  ]);
  const { dispatched } = await run(fakeApi({ nodes, files }), { config });
  assert.deepEqual(dispatched.map((d) => d.number), [51]);
});

test("dispatches at most the cap, lowest number first", async () => {
  const api = fakeApi({ nodes: [pr(23), pr(21), pr(22)] });
  const { dispatched } = await run(api, { maxDispatch: 2 });
  assert.deepEqual(dispatched.map((d) => d.number), [21, 22]);
});
