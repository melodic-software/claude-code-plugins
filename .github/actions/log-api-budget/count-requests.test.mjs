// Every GitHub client factory a lane script builds counts each request it
// sends in $RUNNER_TEMP/api-budget/<token>, one reading line per answer, for
// the job-end api-calls notice (api-budget.bash api_budget_emit_calls).
import assert from "node:assert/strict";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { createGitHub } from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { countRequests, createRateLimitLatch } from "./rate-guard.mjs";
import { countedFetch, createGitHubApi as addressFeedbackApi } from "../../scripts/pr-unblock/address-feedback.mjs";
import { createGitHubApi as dispatchApi } from "../../scripts/pr-unblock/dispatch.mjs";
import { createGitHubApi as feedbackDispatchApi } from "../../scripts/pr-unblock/feedback-dispatch.mjs";
import { budgetedFetch } from "../../scripts/pr-unblock/request-budget.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const API = "https://api.github.com";
const READING = { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4990", "x-ratelimit-used": "10", "x-ratelimit-reset": "1792751600", "x-ratelimit-resource": "core" };
const LINE = "200 5000 4990 10 1792751600 core\n";

// A fetch that answers each request 200 with body and the core reading above.
const fake = (body = {}) => {
  const sent = [];
  const fetch = async (url, init = {}) => {
    sent.push(`${init.method ?? "GET"} ${url}`);
    return new Response(JSON.stringify(body), { status: 200, headers: READING });
  };
  return { sent, fetch };
};

// Runs fn with RUNNER_TEMP at a fresh directory and the given variables set
// (undefined unsets one), then restores them; lines(name) reads a token's file.
async function withBudget(vars, fn) {
  const dir = tempDir("count-requests-");
  const keys = ["RUNNER_TEMP", "API_BUDGET_TOKEN", "API_BUDGET_OVERRIDE_TOKEN", "GH_TOKEN", "GITHUB_TOKEN", ...Object.keys(vars)];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  for (const key of keys) delete process.env[key];
  Object.assign(process.env, { RUNNER_TEMP: dir }, Object.fromEntries(Object.entries(vars).filter(([, value]) => value !== undefined)));
  const lines = (name) => {
    const file = join(dir, "api-budget", name);
    return existsSync(file) ? readFileSync(file, "utf8") : "";
  };
  try {
    return await fn(lines);
  } finally {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    rmSync(dir, { recursive: true, force: true });
  }
}

const quietLatch = () => createRateLimitLatch({ log: () => {}, fail: () => {}, limits: () => ({}), stopFile: null });

test("createGitHub counts each request under API_BUDGET_TOKEN", () =>
  withBudget({ API_BUDGET_TOKEN: "github-token" }, async (lines) => {
    const github = createGitHub({ token: "t", fetchImpl: fake().fetch, latch: quietLatch(), log: () => {} });
    await github("GET", "/repos/o/r/pulls/1");
    await github("GET", "/repos/o/r/pulls/2");
    assert.equal(lines("github-token"), LINE + LINE);
  }));

test("a client on another token than the step's GH_TOKEN counts under API_BUDGET_OVERRIDE_TOKEN", () =>
  withBudget({ API_BUDGET_TOKEN: "lanes-app", API_BUDGET_OVERRIDE_TOKEN: "github-token", GH_TOKEN: "lane" }, async (lines) => {
    const latch = quietLatch();
    const own = createGitHub({ token: "lane", fetchImpl: fake().fetch, latch, log: () => {} });
    const job = createGitHub({ token: "job", fetchImpl: fake().fetch, latch, log: () => {} });
    await own("GET", "/repos/o/r/pulls/1");
    await job("GET", "/repos/o/r/actions/runs");
    await job("GET", "/repos/o/r/actions/runs");
    assert.equal(lines("lanes-app"), LINE);
    assert.equal(lines("github-token"), LINE + LINE);
  }));

test("without API_BUDGET_OVERRIDE_TOKEN, or with no GH_TOKEN or GITHUB_TOKEN to compare, every client counts under API_BUDGET_TOKEN", async () => {
  for (const vars of [{ GH_TOKEN: "lane" }, { API_BUDGET_OVERRIDE_TOKEN: "github-token" }]) {
    await withBudget({ API_BUDGET_TOKEN: "lanes-app", ...vars }, async (lines) => {
      await createGitHub({ token: "job", fetchImpl: fake().fetch, latch: quietLatch(), log: () => {} })("GET", "/repos/o/r/actions/runs");
      assert.equal(lines("lanes-app"), LINE, JSON.stringify(vars));
      assert.equal(lines("github-token"), "", JSON.stringify(vars));
    });
  }
});

test("GITHUB_TOKEN is the step's own token when GH_TOKEN is unset", () =>
  withBudget({ API_BUDGET_TOKEN: "github-token", API_BUDGET_OVERRIDE_TOKEN: "lanes-app", GITHUB_TOKEN: "job" }, async (lines) => {
    const latch = quietLatch();
    await createGitHub({ token: "job", fetchImpl: fake().fetch, latch, log: () => {} })("GET", "/repos/o/r/pulls/1");
    await createGitHub({ token: "app", fetchImpl: fake().fetch, latch, log: () => {} })("GET", "/repos/o/r/pulls/1");
    assert.equal(lines("github-token"), LINE);
    assert.equal(lines("lanes-app"), LINE);
  }));

test("a fetch that already counts is counted once, however often it is wrapped", () =>
  withBudget({ API_BUDGET_TOKEN: "github-token" }, async (lines) => {
    const latch = quietLatch();
    const twice = countRequests(latch.guard(countRequests(fake().fetch)));
    await twice(`${API}/repos/o/r/pulls/1`);
    assert.equal(lines("github-token"), LINE);
  }));

test("address-feedback's client counts each attempt, a resent read included, through countedFetch", () =>
  withBudget({ API_BUDGET_TOKEN: "github-token" }, async (lines) => {
    const answers = [500, 200];
    const fetch = async () => new Response(JSON.stringify({ number: 1 }), { status: answers.shift(), headers: READING });
    const api = addressFeedbackApi({ token: "t", repository: "o/r", apiUrl: API, graphqlUrl: `${API}/graphql`, fetch: await countedFetch(fetch), sleep: async () => {} });
    assert.deepEqual(await api.getPull(1), { number: 1 });
    assert.equal(lines("github-token"), `500 5000 4990 10 1792751600 core\n${LINE}`);
  }));

test("dispatch's client counts each request, and once when handed budgetedFetch", () =>
  withBudget({ API_BUDGET_TOKEN: "github-token" }, async (lines) => {
    const pulls = { data: { repository: { pullRequests: { nodes: [] } } } };
    const raw = dispatchApi({ token: "t", repository: "o/r", apiUrl: API, graphqlUrl: `${API}/graphql`, fetch: fake(pulls).fetch });
    assert.deepEqual(await raw.listOpenPulls({ base: "main" }), { nodes: [] });
    assert.equal(lines("github-token"), LINE);
    const budgeted = dispatchApi({ token: "t", repository: "o/r", apiUrl: API, graphqlUrl: `${API}/graphql`, fetch: budgetedFetch({ fetch: fake(pulls).fetch, latch: quietLatch(), log: () => {} }).fetch });
    await budgeted.listOpenPulls({ base: "main" });
    assert.equal(lines("github-token"), LINE + LINE);
  }));

test("feedback-dispatch's client counts each request, and once when handed budgetedFetch", () =>
  withBudget({ API_BUDGET_TOKEN: "github-token" }, async (lines) => {
    const raw = feedbackDispatchApi({ token: "t", repository: "o/r", apiUrl: API, graphqlUrl: `${API}/graphql`, fetch: fake({ permission: "write" }).fetch });
    assert.equal(await raw.getPermission("someone"), "write");
    assert.equal(lines("github-token"), LINE);
    const budgeted = feedbackDispatchApi({
      token: "t",
      repository: "o/r",
      apiUrl: API,
      graphqlUrl: `${API}/graphql`,
      fetch: budgetedFetch({ fetch: fake({ permission: "read" }).fetch, latch: quietLatch(), log: () => {} }).fetch,
    });
    assert.equal(await budgeted.getPermission("someone"), "read");
    assert.equal(lines("github-token"), LINE + LINE);
  }));
