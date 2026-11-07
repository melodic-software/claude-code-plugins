// Expected values come from the behaviour issue #13717 sets for the hosted
// review callers: review waits for this head's Refine; a head that moved is
// skipped (its push starts its own review); every other outcome, a failed
// read included, reviews. Run and artifact shapes follow the REST docs for
// workflow runs and artifacts; the record name is the one
// pr-unblock-dispatch.yml's refine job uploads. Times are the defaults
// (300 s window, 2400 s cap, 30 s poll), computed by hand.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { createRateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { budgetedFetch } from "../pr-unblock/request-budget.mjs";
import { createApi, decide, main, readEnv } from "./wait-refine.mjs";

const REPO = "o/r";
const HEAD = "a".repeat(40);
const MOVED = "b".repeat(40);
const COMMIT = "c".repeat(40);
const DISPATCHER_ID = 500;
const REFINE_ID = 900;
const LIST = `actions/workflows/pr-unblock-dispatch.yml/runs?event=pull_request_target&head_sha=${HEAD}&per_page=100`;
const INPUT = { number: 7, head: HEAD, repository: REPO, appearMs: 300_000, capMs: 2_400_000, pollMs: 30_000 };

const pull = (sha = HEAD, extra = {}) => ({ state: "open", head: { sha, repo: { full_name: REPO } }, base: { ref: "main" }, ...extra });
const dispatcherRun = (extra = {}) => ({
  id: DISPATCHER_ID,
  path: ".github/workflows/pr-unblock-dispatch.yml",
  event: "pull_request_target",
  head_sha: HEAD,
  head_repository: { full_name: REPO },
  status: "completed",
  conclusion: "success",
  ...extra,
});
const refineRun = (extra = {}) => ({ id: REFINE_ID, path: ".github/workflows/pr-refine.yml", event: "workflow_dispatch", head_branch: "main", status: "completed", conclusion: "success", ...extra });
const record = (id = REFINE_ID) => ({ artifacts: [{ name: `pr-unblock-target-dispatched-${COMMIT}-${id}` }] });

// Each route answers a value, or a list it steps through one read at a time
// (holding its last), or throws when the value is an Error.
function world(routes) {
  const reads = [];
  const seen = new Map();
  let t = 0;
  return {
    reads,
    elapsed: () => t,
    deps: {
      now: () => t,
      sleep: async (ms) => {
        t += ms;
      },
      log: (line) => reads.push(`log ${line}`),
      api: {
        async get(path) {
          reads.push(path);
          assert.ok(Object.hasOwn(routes, path), `unexpected read ${path}`);
          let value = routes[path];
          if (Array.isArray(value) && value.sequence) {
            const n = seen.get(path) ?? 0;
            seen.set(path, n + 1);
            value = value[Math.min(n, value.length - 1)];
          }
          if (value instanceof Error) throw value;
          return structuredClone(value);
        },
      },
    },
  };
}
const steps = (...values) => Object.assign(values, { sequence: true });

const refined = (refine, pulls = pull()) => ({
  "pulls/7": pulls,
  [LIST]: { workflow_runs: [dispatcherRun()] },
  [`actions/runs/${DISPATCHER_ID}/artifacts?per_page=100`]: record(),
  [`actions/runs/${REFINE_ID}`]: refine,
});

test("no dispatcher run within the 300 s window: the review runs", async () => {
  const w = world({ "pulls/7": pull(), [LIST]: { workflow_runs: [] } });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "no-dispatcher" });
  assert.equal(w.elapsed(), 300_000, "it polls out the whole window, no longer");
});

test("a dispatcher run of another workflow, event or repository is no dispatcher run", async () => {
  for (const other of [{ path: ".github/workflows/pr-merge.yml" }, { event: "pull_request" }, { head_sha: MOVED }, { head_repository: { full_name: "fork/r" } }]) {
    const w = world({ "pulls/7": pull(), [LIST]: { workflow_runs: [dispatcherRun(other)] } });
    assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "no-dispatcher" }, JSON.stringify(other));
  }
});

test("a dispatcher run that appears after a poll is waited for", async () => {
  const w = world({ ...refined(refineRun()), [LIST]: steps({ workflow_runs: [] }, { workflow_runs: [dispatcherRun()] }) });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(w.elapsed(), 30_000);
});

test("a dispatcher run that recorded no dispatch: the review runs", async () => {
  const w = world({ ...refined(refineRun()), [`actions/runs/${DISPATCHER_ID}/artifacts?per_page=100`]: { artifacts: [{ name: "pr-unblock-dispatched-1-2" }] } });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "no-dispatch" });
  assert.ok(!w.reads.includes(`actions/runs/${REFINE_ID}`));
});

test("a running dispatcher is waited for before its artifacts are read", async () => {
  const w = world({ ...refined(refineRun()), [LIST]: { workflow_runs: [dispatcherRun({ status: "in_progress" })] }, [`actions/runs/${DISPATCHER_ID}`]: steps(dispatcherRun({ status: "in_progress" }), dispatcherRun({ conclusion: "cancelled" })) });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(w.elapsed(), 60_000);
});

test("Refine succeeded and the head is unchanged: the review runs", async () => {
  const w = world(refined(steps(refineRun({ status: "in_progress", conclusion: null }), refineRun())));
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.ok(w.reads.some((line) => line === `log ::notice::wait-refine #7 ${HEAD}: review: refine-success`));
});

test("Refine pushed a commit: this head's review is skipped for the new head's", async () => {
  const w = world(refined(refineRun(), steps(pull(), pull(MOVED))));
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: false, reason: "head-moved" });
});

test("a closed pull request is not reviewed", async () => {
  const w = world(refined(refineRun(), steps(pull(), pull(HEAD, { state: "closed" }))));
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: false, reason: "head-moved" });
});

test("a head that already moved when the job starts is skipped without waiting", async () => {
  const w = world({ "pulls/7": pull(MOVED) });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: false, reason: "head-moved" });
  assert.equal(w.elapsed(), 0);
});

test("a PR into another base, or from a fork, is reviewed at once: no refine runs for it", async () => {
  for (const other of [pull(HEAD, { base: { ref: "release" } }), pull(HEAD, { head: { sha: HEAD, repo: { full_name: "fork/r" } } })]) {
    const w = world({ "pulls/7": other });
    assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "no-refine" });
    assert.deepEqual(w.reads.filter((line) => !line.startsWith("log ")), ["pulls/7", "pulls/7"]);
  }
});

test("Refine failed, was cancelled or timed out: the review runs", async () => {
  for (const conclusion of ["failure", "cancelled", "timed_out"]) {
    const w = world(refined(refineRun({ conclusion })));
    assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: `refine-${conclusion}` });
  }
});

test("Refine still running at the 2400 s cap: the review runs", async () => {
  const w = world(refined(refineRun({ status: "in_progress", conclusion: null })));
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-timeout" });
  assert.equal(w.elapsed(), 2_400_000, "it stops at the cap, never past it");
});

test("a dispatcher still running at the cap: the review runs", async () => {
  const running = dispatcherRun({ status: "in_progress" });
  const w = world({ ...refined(refineRun()), [LIST]: { workflow_runs: [running] }, [`actions/runs/${DISPATCHER_ID}`]: running });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "dispatcher-timeout" });
});

test("a record naming a run that is not a pr-refine dispatch on main: the review runs, with a warning", async () => {
  for (const other of [{ path: ".github/workflows/pr-merge.yml" }, { event: "pull_request" }, { head_branch: "feature" }]) {
    const w = world(refined(refineRun(other)));
    assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "not-refine" }, JSON.stringify(other));
    assert.ok(w.reads.some((line) => line.startsWith(`log ::warning::wait-refine #7 ${HEAD}: run ${REFINE_ID} `)));
  }
});

test("any failed read: the review runs, with a warning", async () => {
  const failure = new Error("GET x returned 502");
  for (const path of ["pulls/7", LIST, `actions/runs/${DISPATCHER_ID}/artifacts?per_page=100`, `actions/runs/${REFINE_ID}`]) {
    const w = world({ ...refined(refineRun()), [path]: failure });
    assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "read-error" }, path);
    assert.ok(w.reads.some((line) => line.startsWith("log ::warning::") && line.includes("returned 502")));
  }
});

const ENV = { PR_NUMBER: "7", HEAD_SHA: HEAD, GITHUB_REPOSITORY: REPO, GITHUB_TOKEN: "t", GITHUB_OUTPUT: "/dev/null" };

test("malformed env throws before any read", () => {
  for (const bad of [{ PR_NUMBER: "7x" }, { PR_NUMBER: "0" }, { HEAD_SHA: "abc" }, { HEAD_SHA: HEAD.toUpperCase() }, { GITHUB_TOKEN: "" }, { GITHUB_OUTPUT: undefined }, { GITHUB_REPOSITORY: "o" }, { WAIT_CAP_SECONDS: "-1" }]) {
    assert.throws(() => readEnv({ ...ENV, ...bad }), Error, JSON.stringify(bad));
  }
  assert.deepEqual(readEnv({ ...ENV, WAIT_POLL_SECONDS: "5" }), { ...INPUT, pollMs: 5_000 });
});

// The production reader: createApi over budgetedFetch and a holding rate
// guard, against a fake GitHub that answers each route in turn (holding its
// last answer), `304` meaning "not modified" for a conditional repeat.
function production(routes, { hold = true } = {}) {
  const sent = [];
  const lines = [];
  let failed = 0;
  let t = 0;
  const seen = new Map();
  const fetch = async (url, init = {}) => {
    const prefix = `https://api.github.com/repos/${REPO}/`;
    assert.ok(url.startsWith(prefix), url);
    const path = url.slice(prefix.length);
    sent.push({ path, etag: init.headers?.["If-None-Match"] ?? null, auth: init.headers?.Authorization });
    const answers = routes[path];
    assert.ok(answers, `unexpected read ${path}`);
    const n = seen.get(path) ?? 0;
    seen.set(path, n + 1);
    const answer = answers[Math.min(n, answers.length - 1)];
    if (answer === 304) return new Response(null, { status: 304 });
    const [status, body, headers = {}] = answer;
    return new Response(JSON.stringify(body), { status, headers: { etag: `"${path}-${n}"`, ...headers } });
  };
  const sleep = async (ms) => {
    t += ms;
  };
  const log = (line) => lines.push(line);
  const latch = createRateLimitLatch({ now: () => t, log, fail: () => (failed += 1), limits: () => ({}), stopFile: null, sleep, hold });
  const api = createApi({ token: "t", repository: REPO, budget: budgetedFetch({ fetch, log, sleep, now: () => t, random: () => 0, latch }) });
  return { sent, lines, failed: () => failed, deps: { api, now: () => t, sleep, log } };
}

const ok = (body) => [200, body];

test("over budgetedFetch, repeat polls go out conditional and a 304 reads as the last answer", async () => {
  const p = production({
    "pulls/7": [ok(pull()), 304],
    [LIST]: [ok({ workflow_runs: [dispatcherRun()] })],
    [`actions/runs/${DISPATCHER_ID}/artifacts?per_page=100`]: [ok(record())],
    [`actions/runs/${REFINE_ID}`]: [ok(refineRun({ status: "in_progress", conclusion: null })), 304, ok(refineRun())],
  });
  assert.deepEqual(await decide(INPUT, p.deps), { proceed: true, reason: "refine-success" });
  assert.deepEqual(
    p.sent.filter((s) => s.path === `actions/runs/${REFINE_ID}`).map((s) => s.etag),
    [null, `"actions/runs/${REFINE_ID}-0"`, `"actions/runs/${REFINE_ID}-0"`],
  );
  assert.ok(p.sent.every((s) => s.auth === "Bearer t"));
});

test("over budgetedFetch, a head read fresh after a 200 moves the decision", async () => {
  const p = production({
    "pulls/7": [ok(pull()), ok(pull(MOVED))],
    [LIST]: [ok({ workflow_runs: [dispatcherRun()] })],
    [`actions/runs/${DISPATCHER_ID}/artifacts?per_page=100`]: [ok(record())],
    [`actions/runs/${REFINE_ID}`]: [ok(refineRun())],
  });
  assert.deepEqual(await decide(INPUT, p.deps), { proceed: false, reason: "head-moved" });
});

test("over a holding rate guard, a rate-limited read reviews and fails nothing", async () => {
  const limited = [403, { message: "API rate limit exceeded for installation ID 1." }, { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1792751600", "x-ratelimit-resource": "core" }];
  const p = production({ "pulls/7": [limited] });
  assert.deepEqual(await decide(INPUT, p.deps), { proceed: true, reason: "read-error" });
  assert.equal(p.failed(), 0, "the guard does not fail the step under API_BUDGET_HOLD");
  assert.deepEqual(p.lines.filter((line) => line.startsWith("::error::")), []);
  assert.ok(p.lines.some((line) => line.startsWith(`::warning::wait-refine #7 ${HEAD}: a read failed`)));
});

test("main writes proceed and reason to GITHUB_OUTPUT", async () => {
  const output = join(tempDir("wait-refine-"), "output");
  const w = world(refined(refineRun(), steps(pull(), pull(MOVED))));
  await main({ ...ENV, GITHUB_OUTPUT: output }, w.deps);
  assert.equal(readFileSync(output, "utf8"), "proceed=false\nreason=head-moved\n");
});
