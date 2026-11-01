// Every GitHub client factory a lane script builds counts each request it
// sends in $RUNNER_TEMP/api-budget/<token>, one reading line per answer, for
// the job-end api-calls notice (api-budget.bash api_budget_emit_calls).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
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
// (undefined unsets one), then restores them; lines(name) reads a token's file
// without each line's route, routes(name) only the routes.
async function withBudget(vars, fn) {
  const dir = tempDir("count-requests-");
  const keys = ["RUNNER_TEMP", "API_BUDGET_TOKEN", "API_BUDGET_OVERRIDE_TOKEN", "GH_TOKEN", "GITHUB_TOKEN", ...Object.keys(vars)];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  for (const key of keys) delete process.env[key];
  Object.assign(process.env, { RUNNER_TEMP: dir }, Object.fromEntries(Object.entries(vars).filter(([, value]) => value !== undefined)));
  const raw = (name) => {
    const file = join(dir, "api-budget", name);
    return existsSync(file) ? readFileSync(file, "utf8") : "";
  };
  const lines = Object.assign((name) => raw(name).replace(/ \S+$/gm, ""), {
    routes: (name) => raw(name).split("\n").filter(Boolean).map((line) => line.split(" ")[6]),
  });
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

test("countRequests records each request's templated route last on its line", () =>
  withBudget({ API_BUDGET_TOKEN: "github-token" }, async (lines) => {
    const send = countRequests(fake().fetch);
    await send(`${API}/repos/melodic-software/claude-code-plugins/issues/12/comments?per_page=100`);
    await send(new Request(`${API}/graphql`, { method: "POST" }));
    await send(`${API}/repos/o/r/git/ref/heads/ghp_secret`);
    assert.deepEqual(lines.routes("github-token"), ["repos/{repo}/issues/{n}/comments", "graphql", "repos/{repo}/git/ref/{x}/{x}"]);
  }));

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

// The mains run from the base checkout build their address-feedback client
// with countedFetch, over the global fetch. Each answers 404 here, so a main
// stops at its first request; every request it sent is one reading.
const ROOT = new URL("../../../", import.meta.url).pathname;
const SHA = "a".repeat(40);
for (const [name, run] of [
  ["address-feedback select", async (env) => (await import("../../scripts/pr-unblock/address-feedback.mjs")).main(["select"], env, { log: () => {} })],
  ["fix-ci-context", async (env) => (await import("../../scripts/pr-unblock/fix-ci-context.mjs")).main({ ...env, FIX_CI_ROUNDS: "3" }, { log: () => {} })],
  ["review-dependency select", async (env) => (await import("../../scripts/pr-unblock/review-dependency.mjs")).main(["select"], env, { log: () => {} })],
]) {
  test(`${name}'s main counts each request its client sends`, () =>
    withBudget({ API_BUDGET_TOKEN: "github-token" }, async (lines) => {
      const dir = tempDir("count-requests-main-");
      const saved = globalThis.fetch;
      let sent = 0;
      globalThis.fetch = async () => {
        sent += 1;
        return new Response("{}", { status: 404, headers: READING });
      };
      try {
        const env = {
          GITHUB_TOKEN: "t",
          GITHUB_REPOSITORY: "o/r",
          GITHUB_API_URL: API,
          GITHUB_OUTPUT: join(dir, "out"),
          PR_NUMBER: "7",
          HEAD_SHA: SHA,
          APP_SENDER_ID: "1",
          CONTEXT_FILE: join(dir, "context.json"),
          THREAD_FILE: join(dir, "threads.json"),
          RUN_FILE: join(dir, "run.json"),
          TRUSTED_ACTORS: join(ROOT, ".github/standards/trusted-actors/trusted-actors.json"),
          TRACKER_CONFIG: join(ROOT, ".work-item-tracker.json"),
          DEPENDENCY_FILE: join(dir, "dependency.json"),
          CONTEXT_RUN_FILE: join(dir, "run.json"),
          DEPENDABOT_CONFIG: join(ROOT, ".github/dependabot.yml"),
          DEPENDABOT_POLICY: join(ROOT, ".github/standards/dependabot-policy/policy.json"),
          BASE_PATH: ROOT,
        };
        await assert.rejects(run(env), /returned 404/);
        assert.ok(sent > 0, "the main sent a request");
        assert.equal(lines("github-token"), "404 5000 4990 10 1792751600 core\n".repeat(sent));
      } finally {
        globalThis.fetch = saved;
        rmSync(dir, { recursive: true, force: true });
      }
    }));
}

// A step's own api-calls line (API_BUDGET_SCRIPT): one child process sends
// two core reads, a 304 and a GraphQL query on the step's token and one read
// on a second token, so its line reads github-token=3 lanes-app=1
// not-modified=1 graphql=1, and the job-end lines over the same files agree.
const STEP_CALLS = `
import { createGitHub } from ${JSON.stringify(new URL("../check-trusted-trigger/check-trusted-trigger.mjs", import.meta.url).href)};
const answer = (status, resource) => new Response(status === 304 ? null : "{}", { status, headers: { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4990", "x-ratelimit-used": "10", "x-ratelimit-reset": "1792751600", "x-ratelimit-resource": resource } });
const fetchImpl = async (url, init) => (init.headers["If-None-Match"] ? answer(304, "core") : url.endsWith("/graphql") ? answer(200, "graphql") : answer(200, "core"));
const own = createGitHub({ token: "own", fetchImpl, log: () => {} });
await own("GET", "/repos/o/r/pulls/1");
await own("GET", "/repos/o/r/pulls/2");
await own("GET", "/repos/o/r/pulls/3", undefined, { "If-None-Match": "etag" }).catch(() => {});
await own("POST", "/graphql", { query: "{ viewer { login } }" });
await createGitHub({ token: "other", fetchImpl, log: () => {} })("GET", "/repos/o/r");
`;
const runStep = (script) => {
  const dir = tempDir("count-requests-step-");
  const env = { PATH: process.env.PATH, RUNNER_TEMP: dir, GH_TOKEN: "own", API_BUDGET_TOKEN: "github-token", API_BUDGET_OVERRIDE_TOKEN: "lanes-app" };
  try {
    const step = spawnSync(process.execPath, ["--input-type=module", "-e", STEP_CALLS], { encoding: "utf8", env: script === undefined ? env : { ...env, API_BUDGET_SCRIPT: script } });
    assert.equal(step.status, 0, step.stderr);
    const job = spawnSync("bash", ["-c", `. ${JSON.stringify(fileURLToPath(new URL("./api-budget.bash", import.meta.url)))}; api_budget_emit_calls github-token lanes-app`], { encoding: "utf8", env });
    return { step: step.stdout, job: job.stdout };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};

test("API_BUDGET_SCRIPT ends the process with its own api-calls line, which the job-end lines agree with", () => {
  const { step, job } = runStep("who");
  assert.equal(step, "::notice title=api-calls::script=who github-token=3 lanes-app=1 not-modified=1 graphql=1\n");
  assert.equal(job, "::notice title=api-calls::github-token=3 not-modified=1 graphql=1\n::notice title=api-calls::lanes-app=1 not-modified=0 graphql=0\n");
});

test("without API_BUDGET_SCRIPT, or with one that is not lower-case kebab case, the same calls print nothing", () => {
  for (const script of [undefined, "Who", "who::x", ""]) {
    const { step, job } = runStep(script);
    assert.equal(step, "", String(script));
    assert.match(job, /^::notice title=api-calls::github-token=3 not-modified=1 graphql=1$/m);
  }
});

test("a 4xx or 5xx answer is a lane run report row, by path with no query; a 2xx or 304 is not", () =>
  withBudget({ API_BUDGET_TOKEN: "github-token" }, async () => {
    const answers = [404, 200, 304, 503];
    const send = countRequests(async () => new Response(null, { status: answers.shift(), headers: READING }));
    await send(`${API}/repos/o/r/pulls/1?per_page=100&token=x`);
    await send(`${API}/repos/o/r`);
    await send(`${API}/repos/o/r`);
    await send(`${API}/graphql`, { method: "post" });
    const file = join(process.env.RUNNER_TEMP, "lane-run-report", "api-failures.jsonl");
    assert.deepEqual(
      readFileSync(file, "utf8").trim().split("\n").map((line) => JSON.parse(line)),
      [
        { method: "GET", path: "/repos/o/r/pulls/1", status: 404 },
        { method: "POST", path: "/graphql", status: 503 },
      ],
    );
  }));

test("without RUNNER_TEMP a failed answer is returned and nothing is written", () =>
  withBudget({}, async () => {
    delete process.env.RUNNER_TEMP;
    const send = countRequests(async () => new Response("{}", { status: 500 }));
    assert.equal((await send(`${API}/x`)).status, 500);
  }));
