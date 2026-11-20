// Expected values come from the owner's rule for the hosted review callers
// (docs/conventions/pr-pipeline/README.md): review waits for this head's Refine; a head that moved is
// skipped (its push starts its own review); every other outcome, a failed
// read included, reviews. Run and artifact shapes follow the REST docs for
// workflow runs (https://docs.github.com/en/rest/actions/workflow-runs) and
// artifacts; the record name is the one
// pr-unblock-dispatch.yml's refine job uploads. Times use the 300 s window,
// 1800 s cap and a 30 s poll (INPUT; the default poll is 60 s), computed by
// hand. Between polls the head is read from refs/pull/7/head, the ref GitHub
// keeps for every pull request (git fetch origin pull/ID/head in the docs on
// checking out pull requests locally).
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { createRateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { DEFAULTS as FIX_DOCS } from "../pr-unblock/fix-docs-dispatch.mjs";
import { budgetedFetch } from "../pr-unblock/request-budget.mjs";
import { createApi, decide, main, NO_REFINE_ACCOUNTS, noRefineDue, readEnv } from "./wait-refine.mjs";

const REPO = "o/r";
const HEAD = "a".repeat(40);
const MOVED = "b".repeat(40);
const COMMIT = "c".repeat(40);
const DISPATCHER_ID = 500;
const REFINE_ID = 900;
const LIST = `actions/workflows/pr-unblock-dispatch.yml/runs?event=pull_request_target&head_sha=${HEAD}&per_page=100`;
const INPUT = { number: 7, head: HEAD, repository: REPO, appearMs: 300_000, capMs: 1_800_000, pollMs: 30_000 };
const PROBE = "git/ref/pull/7/head";
// The Get a reference response shape (REST docs, git refs).
const ref = (sha = HEAD) => ({ ref: "refs/pull/7/head", object: { type: "commit", sha } });
const NOT_FOUND = new Error(`GET ${PROBE} returned 404`);

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
const refineRun = (extra = {}) => ({ id: REFINE_ID, path: ".github/workflows/pr-refine.yml", event: "workflow_dispatch", head_branch: "main", display_title: "pr-refine fix-docs #7", status: "completed", conclusion: "success", ...extra });
const record = (id = REFINE_ID) => ({ artifacts: [{ name: `pr-unblock-target-dispatched-${COMMIT}-${id}` }] });

// Each route answers a value, or a list it steps through one read at a time
// (holding its last), or throws when the value is an Error. A world that
// names no ref route answers the ref read 404, so each test that does not
// name one shows the pull request read deciding at every poll.
function world(routes) {
  routes = { [PROBE]: NOT_FOUND, ...routes };
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
          if (typeof value === "function") value = value(t);
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
  assert.equal(w.elapsed(), 60_000, "one 30 s poll for the dispatcher, then Refine is first read one 30 s poll after its record");
});

test("a push while Refine runs ends the wait at the next poll, not at the 1800 s cap", async () => {
  const w = world(refined(refineRun({ status: "in_progress", conclusion: null }), steps(pull(), pull(MOVED))));
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: false, reason: "head-moved" });
  assert.equal(w.elapsed(), 60_000, "one 30 s poll, then the 30 s confirming read");
});

test("a push while the dispatcher has not yet appeared ends the wait at the next poll, not at the 300 s window", async () => {
  const w = world({ "pulls/7": steps(pull(), pull(MOVED)), [LIST]: { workflow_runs: [] } });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: false, reason: "head-moved" });
  assert.equal(w.elapsed(), 60_000, "one 30 s poll, then the 30 s confirming read");
});

test("a moved head read once mid-wait and not confirmed resumes the wait: Refine is waited for and the review runs", async () => {
  const w = world(refined(steps(refineRun({ status: "in_progress", conclusion: null }), refineRun()), steps(pull(), pull(MOVED), pull())));
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(w.elapsed(), 120_000, "Refine's first 30 s poll and its 30 s confirming read, then two 30 s polls to Refine's next read, which shows it completed");
  assert.equal(w.reads.filter((line) => line === `actions/runs/${REFINE_ID}`).length, 2, "Refine is read again after the unconfirmed move");
});

test("a moved head read once at the start and not confirmed waits for the dispatcher and Refine: the review runs", async () => {
  const w = world(refined(steps(refineRun({ status: "in_progress", conclusion: null }), refineRun()), steps(pull(MOVED), pull())));
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(w.elapsed(), 120_000, "the 30 s confirming read, Refine's first read one 30 s poll later, then two 30 s polls to its next read");
  assert.ok(w.reads.includes(LIST), "the dispatcher listing is read");
});

test("the record on an older dispatcher run of this head is found and its Refine waited for", async () => {
  const older = dispatcherRun({ id: 400 });
  const newer = dispatcherRun({ id: 600, status: "in_progress" });
  const w = world({
    ...refined(steps(refineRun({ status: "in_progress", conclusion: null }), refineRun())),
    [LIST]: { workflow_runs: [older, newer] },
    "actions/runs/600": steps(newer, dispatcherRun({ id: 600 })),
    "actions/runs/600/artifacts?per_page=100": { artifacts: [] },
    "actions/runs/400/artifacts?per_page=100": record(),
  });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.ok(w.reads.includes(`log ::notice::wait-refine #7 ${HEAD}: dispatcher run 400 started pr-refine run ${REFINE_ID}`));
});

test("only the newest five dispatcher runs are searched for the record", async () => {
  const runs = [1, 2, 3, 4, 5, 6].map((id) => dispatcherRun({ id }));
  const routes = { "pulls/7": pull(), [LIST]: { workflow_runs: runs }, "actions/runs/1/artifacts?per_page=100": record() };
  for (const id of [2, 3, 4, 5, 6]) routes[`actions/runs/${id}/artifacts?per_page=100`] = { artifacts: [] };
  const w = world(routes);
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "no-dispatch" });
  assert.ok(!w.reads.includes("actions/runs/1/artifacts?per_page=100"), "the sixth-newest run is not read");
});

test("a dispatcher run that recorded no dispatch: the review runs", async () => {
  const w = world({ ...refined(refineRun()), [`actions/runs/${DISPATCHER_ID}/artifacts?per_page=100`]: { artifacts: [{ name: "pr-unblock-dispatched-1-2" }] } });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "no-dispatch" });
  assert.ok(!w.reads.includes(`actions/runs/${REFINE_ID}`));
});

test("a running dispatcher is waited for before its artifacts are read", async () => {
  const w = world({ ...refined(refineRun()), [LIST]: { workflow_runs: [dispatcherRun({ status: "in_progress" })] }, [`actions/runs/${DISPATCHER_ID}`]: steps(dispatcherRun({ status: "in_progress" }), dispatcherRun({ conclusion: "cancelled" })) });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(w.elapsed(), 120_000, "the dispatcher is read at polls 1 and 3, then Refine one poll after the record");
  assert.equal(reads(w, `actions/runs/${DISPATCHER_ID}`), 2, "no dispatcher read at the even poll");
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

test("a head that already moved when the job starts is skipped after one confirming read, without waiting for any run", async () => {
  const w = world({ "pulls/7": pull(MOVED) });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: false, reason: "head-moved" });
  assert.equal(w.elapsed(), 30_000);
  assert.deepEqual(w.reads.filter((line) => !line.startsWith("log ")), ["pulls/7", "pulls/7"], "the first read and its one confirming read, no third");
});

test("one lagging head read is read again before a skip: a head that matches on the second read is reviewed", async () => {
  const w = world(refined(refineRun(), steps(pull(), pull(MOVED), pull())));
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
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

test("Refine still running at the 1800 s cap: the review runs", async () => {
  const w = world(refined(refineRun({ status: "in_progress", conclusion: null })));
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-timeout" });
  assert.equal(w.elapsed(), 1_800_000, "it stops at the cap, never past it");
});

test("a dispatcher still running at the cap: the review runs", async () => {
  const running = dispatcherRun({ status: "in_progress" });
  const w = world({ ...refined(refineRun()), [LIST]: { workflow_runs: [running] }, [`actions/runs/${DISPATCHER_ID}`]: running });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "dispatcher-timeout" });
});

test("a record naming a run that is not a pr-refine dispatch on main: the review runs, with a warning", async () => {
  for (const other of [{ path: ".github/workflows/pr-merge.yml" }, { event: "pull_request" }, { head_branch: "feature" }, { display_title: "pr-refine fix-docs #77" }]) {
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

const reads = (w, path) => w.reads.filter((line) => line === path).length;
const running = () => refineRun({ status: "in_progress", conclusion: null });
const runningUntilWorld = (doneAt) => (t) => (t >= doneAt ? refineRun() : running());

test("an unchanged head is read from its ref at each poll: the pull request is read only at the start and the finish", async () => {
  const w = world({ ...refined(steps(running(), running(), running(), refineRun())), [PROBE]: ref() });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(reads(w, PROBE), 7, "one ref read per poll: Refine is read at polls 1, 3, 5 and 7");
  assert.equal(reads(w, `actions/runs/${REFINE_ID}`), 4, "four Refine reads for its four answers");
  assert.equal(reads(w, "pulls/7"), 2, "the start read and the finish read, none between");
});

test("an unchanged head is read from its ref while the dispatcher has not yet appeared", async () => {
  const w = world({ ...refined(refineRun()), [LIST]: steps({ workflow_runs: [] }, { workflow_runs: [] }, { workflow_runs: [dispatcherRun()] }), [PROBE]: ref() });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(reads(w, PROBE), 3, "two polls for the dispatcher, one before Refine's first read");
  assert.equal(reads(w, "pulls/7"), 2, "the start read and the finish read, none between");
});

const apiReads = (w) => w.reads.filter((line) => !line.startsWith("log "));

test("a ref showing another head falls back to the pull request reads: a move they confirm ends the wait", async () => {
  const w = world({ ...refined(running(), steps(pull(), pull(MOVED))), [PROBE]: ref(MOVED) });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: false, reason: "head-moved" });
  assert.equal(w.elapsed(), 60_000, "one 30 s poll, then the 30 s confirming read");
  assert.deepEqual(apiReads(w).slice(-3), [PROBE, "pulls/7", "pulls/7"]);
});

test("a ref showing another head while the pull request still shows this one resumes the wait: the review runs", async () => {
  const w = world({ ...refined(steps(running(), refineRun())), [PROBE]: ref(MOVED) });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(reads(w, PROBE), 3, "Refine is read at polls 1 and 3");
  assert.equal(reads(w, "pulls/7"), 5, "the start read, one fallback read per poll, the finish read");
});

test("a ref read that fails, or answers 404, or names no commit falls back to the pull request reads, never to read-error", async () => {
  const failures = { "a 502": new Error(`GET ${PROBE} returned 502`), "a 404": NOT_FOUND, "no object": { ref: "refs/pull/7/head" } };
  for (const [name, answer] of Object.entries(failures)) {
    const moving = world({ ...refined(running(), steps(pull(), pull(MOVED))), [PROBE]: answer });
    assert.deepEqual(await decide(INPUT, moving.deps), { proceed: false, reason: "head-moved" }, `${name}: a move the pull request reads confirm is skipped`);
    assert.deepEqual(apiReads(moving).slice(-3), [PROBE, "pulls/7", "pulls/7"], name);
    const closed = world({ ...refined(running(), steps(pull(), pull(HEAD, { state: "closed" }))), [PROBE]: answer });
    assert.deepEqual(await decide(INPUT, closed.deps), { proceed: false, reason: "head-moved" }, `${name}: a closed pull request is not reviewed`);
    const still = world({ ...refined(steps(running(), refineRun())), [PROBE]: answer });
    assert.deepEqual(await decide(INPUT, still.deps), { proceed: true, reason: "refine-success" }, `${name}: an unchanged head waits for Refine`);
  }
});

test("a pull request closed while Refine runs is caught at the final read once Refine completes: it is not reviewed", async () => {
  const w = world({ ...refined(steps(running(), running(), refineRun()), steps(pull(), pull(HEAD, { state: "closed" }))), [PROBE]: ref() });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: false, reason: "head-moved" });
  assert.equal(reads(w, `actions/runs/${REFINE_ID}`), 3, "Refine is read until it completes");
  assert.equal(reads(w, "pulls/7"), 2, "the start read and the final read that finds it closed");
});

test("a ref read that keeps failing warns once per job, naming the status", async () => {
  const w = world({ ...refined(steps(running(), running(), running(), refineRun())), [PROBE]: new Error(`GET ${PROBE} returned 403`) });
  assert.deepEqual(await decide(INPUT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(reads(w, PROBE), 7, "Refine is read at polls 1, 3, 5 and 7");
  const warnings = w.reads.filter((line) => line.startsWith(`log ::warning::wait-refine #7 ${HEAD}: the head ref read failed`));
  assert.equal(warnings.length, 1, "one warning for three failed ref reads");
  assert.ok(warnings[0].includes("returned 403"), warnings[0]);
});

test("a ref with no commit warns once, and a ref naming another head does not warn", async () => {
  const empty = world({ ...refined(steps(running(), running(), refineRun())), [PROBE]: { ref: "refs/pull/7/head" } });
  await decide(INPUT, empty.deps);
  assert.equal(empty.reads.filter((line) => line.includes("the head ref read failed (it named no commit)")).length, 1);
  const other = world({ ...refined(steps(running(), refineRun())), [PROBE]: ref(MOVED) });
  await decide(INPUT, other.deps);
  assert.ok(!other.reads.some((line) => line.includes("the head ref read failed")));
});

// The workflows pass the base ref and head repository from the
// pull_request event, so the start needs no pull request read; the finish
// read still decides whether the head moved or the pull request closed.
const EVENT = { ...INPUT, baseRef: "main", headRepository: REPO };

test("with the event's base ref and head repository, no pull request read comes before the dispatcher listing; the finish read still comes", async () => {
  const w = world({ ...refined(refineRun()), [PROBE]: ref() });
  assert.deepEqual(await decide(EVENT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(apiReads(w)[0], LIST, "the dispatcher listing is the first read");
  assert.equal(reads(w, "pulls/7"), 1, "the finish read only");
  assert.equal(apiReads(w).at(-1), "pulls/7", "the finish read is the last read");
});

test("with the event's values, a head moved or a pull request closed by the finish is still not reviewed", async () => {
  for (const finish of [pull(MOVED), pull(HEAD, { state: "closed" }), pull(HEAD, { state: "closed", merged: true })]) {
    const w = world(refined(refineRun(), finish));
    assert.deepEqual(await decide(EVENT, w.deps), { proceed: false, reason: "head-moved" }, JSON.stringify(finish));
  }
});

test("with the event's values, a PR into another base, or from a fork, is reviewed after the one finish read", async () => {
  for (const other of [{ baseRef: "release" }, { headRepository: "fork/r" }]) {
    const w = world({ "pulls/7": pull() });
    assert.deepEqual(await decide({ ...EVENT, ...other }, w.deps), { proceed: true, reason: "no-refine" }, JSON.stringify(other));
    assert.deepEqual(apiReads(w), ["pulls/7"], JSON.stringify(other));
  }
});

test("with the event's values, a head already moved at the start is caught at the first poll: the listing comes first, then the poll and its confirming read", async () => {
  const w = world({ "pulls/7": pull(MOVED), [PROBE]: ref(MOVED), [LIST]: { workflow_runs: [dispatcherRun({ status: "in_progress" })] } });
  assert.deepEqual(await decide(EVENT, w.deps), { proceed: false, reason: "head-moved" });
  assert.equal(apiReads(w)[0], LIST, "the dispatcher listing is the first read");
  assert.equal(w.elapsed(), 60_000, "one 30 s poll, then the 30 s confirming read");
});

test("with the event's values, a pull request closed at the start is caught only at the finish read", async () => {
  const w = world({ "pulls/7": pull(HEAD, { state: "closed" }), [PROBE]: ref(), [LIST]: { workflow_runs: [] } });
  assert.deepEqual(await decide(EVENT, w.deps), { proceed: false, reason: "head-moved" });
  assert.equal(w.elapsed(), 300_000, "the ref outlives the close, so the 300 s window runs out first");
  assert.equal(reads(w, "pulls/7"), 1, "the finish read only");
});

test("with either event value empty or missing, the start reads the pull request as before", async () => {
  for (const missing of [{ baseRef: "" }, { headRepository: "" }, { baseRef: null }, { headRepository: undefined }]) {
    const w = world({ ...refined(refineRun()), [PROBE]: ref() });
    assert.deepEqual(await decide({ ...EVENT, ...missing }, w.deps), { proceed: true, reason: "refine-success" }, JSON.stringify(missing));
    assert.deepEqual(apiReads(w).slice(0, 2), ["pulls/7", LIST], JSON.stringify(missing));
    assert.equal(reads(w, "pulls/7"), 2, "the start read and the finish read");
  }
});

const ENV = { PR_NUMBER: "7", HEAD_SHA: HEAD, GITHUB_REPOSITORY: REPO, GITHUB_TOKEN: "t", GITHUB_OUTPUT: "/dev/null" };

test("readEnv takes PR_BASE_REF and PR_HEAD_REPO, empty or missing as none", () => {
  assert.deepEqual(readEnv({ ...ENV, PR_BASE_REF: "main", PR_HEAD_REPO: REPO }), { ...EVENT, pollMs: 60_000 });
  assert.deepEqual(readEnv({ ...ENV, PR_BASE_REF: "", PR_HEAD_REPO: "" }), { ...INPUT, pollMs: 60_000, baseRef: null, headRepository: null });
});

test("main with PR_BASE_REF and PR_HEAD_REPO set reads no pull request before the dispatcher listing", async () => {
  const w = world({ ...refined(steps(running(), refineRun())), [PROBE]: ref() });
  assert.deepEqual(await main({ ...ENV, PR_BASE_REF: "main", PR_HEAD_REPO: REPO }, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(apiReads(w)[0], LIST);
  assert.equal(reads(w, "pulls/7"), 1);
});

test("with no poll set, a poll comes 60 s after the last read", async () => {
  const w = world({ ...refined(steps(running(), refineRun())), [PROBE]: ref() });
  assert.deepEqual(await main(ENV, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(w.elapsed(), 180_000, "Refine is read at the 60 s poll and, still running, again two 60 s polls later");
});

test("malformed env throws before any read", () => {
  for (const bad of [{ PR_NUMBER: "7x" }, { PR_NUMBER: "0" }, { HEAD_SHA: "abc" }, { HEAD_SHA: HEAD.toUpperCase() }, { GITHUB_TOKEN: "" }, { GITHUB_OUTPUT: undefined }, { GITHUB_REPOSITORY: "o" }, { WAIT_CAP_SECONDS: "-1" }]) {
    assert.throws(() => readEnv({ ...ENV, ...bad }), Error, JSON.stringify(bad));
  }
  assert.deepEqual(readEnv({ ...ENV, WAIT_POLL_SECONDS: "5" }), { ...INPUT, pollMs: 5_000, baseRef: null, headRepository: null });
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
    let answer = answers[Math.min(n, answers.length - 1)];
    if (typeof answer === "function") answer = answer(t, init.headers?.["If-None-Match"] ?? null);
    if (answer === 304) return new Response(null, { status: 304 });
    const [status, body, headers = {}] = answer;
    return new Response(JSON.stringify(body), { status, headers: { etag: `"${path}-${n}"`, ...headers } });
  };
  const sleep = async (ms) => {
    t += ms;
  };
  const log = (line) => lines.push(line);
  const latch = createRateLimitLatch({ now: () => t, log, fail: () => (failed += 1), limits: () => ({}), stopFile: null, sleep, hold });
  const budget = budgetedFetch({ fetch, log, sleep, now: () => t, random: () => 0, latch });
  const api = createApi({ token: "t", repository: REPO, budget });
  return { sent, lines, failed: () => failed, budget, deps: { api, now: () => t, sleep, log } };
}

const ok = (body) => [200, body];

// GitHub answers each pull request read 200 with a new ETag (the body embeds
// the repository, whose pushed_at moves on every push), so only the ref read
// can come back 304.
const runningUntil = (doneAt) => [(t) => (t >= doneAt ? ok(refineRun()) : ok(running()))];

test("over budgetedFetch, repeat polls read the ref conditional and a 304 reads as the last answer, with no pull request read", async () => {
  const p = production({
    "pulls/7": [ok(pull())],
    [PROBE]: [ok(ref()), 304],
    [LIST]: [ok({ workflow_runs: [dispatcherRun()] })],
    [`actions/runs/${DISPATCHER_ID}/artifacts?per_page=100`]: [ok(record())],
    [`actions/runs/${REFINE_ID}`]: runningUntil(150_000),
  });
  assert.deepEqual(await decide(INPUT, p.deps), { proceed: true, reason: "refine-success" });
  assert.deepEqual(
    p.sent.filter((s) => s.path === PROBE).map((s) => s.etag),
    [null, `"${PROBE}-0"`, `"${PROBE}-0"`, `"${PROBE}-0"`, `"${PROBE}-0"`],
    "the first ref read is plain, each repeat carries its ETag",
  );
  assert.deepEqual(
    p.sent.filter((s) => s.path === `actions/runs/${REFINE_ID}`).map((s) => s.etag),
    [null, `"actions/runs/${REFINE_ID}-0"`, `"actions/runs/${REFINE_ID}-1"`],
    "Refine is read at polls 1, 3 and 5, each carrying the last read's ETag; a running run answers 200 to each, as the lanes' job records show",
  );
  assert.equal(p.sent.filter((s) => s.path === "pulls/7").length, 2, "the start read and the finish read, none between");
  assert.match(p.budget.summary(), /^api-calls rest=8 not-modified=4 /, "four ref 304s; Refine done at 150 s costs 8 counted calls, 11 when it was read at once and at every poll");
  assert.ok(p.sent.every((s) => s.auth === "Bearer t"));
});

test("a Refine that runs seven polls costs 8 counted calls, and the decision is the same review", async () => {
  const p = production({
    "pulls/7": [ok(pull())],
    [PROBE]: [ok(ref()), 304],
    [LIST]: [ok({ workflow_runs: [dispatcherRun()] })],
    [`actions/runs/${DISPATCHER_ID}/artifacts?per_page=100`]: [ok(record())],
    [`actions/runs/${REFINE_ID}`]: runningUntil(210_000),
  });
  assert.deepEqual(await decide(EVENT, p.deps), { proceed: true, reason: "refine-success" });
  assert.equal(p.deps.now(), 210_000, "Refine's completion is read at the poll it completes by, no later");
  assert.match(
    p.budget.summary(),
    /^api-calls rest=8 not-modified=6 /,
    "the listing, the artifacts, the first ref read, Refine at 30, 90, 150 and 210 s, and the finish read: 8, against 12 when Refine was read at once and at every poll",
  );
});

test("a push at a poll that skips the run read is still caught at that poll", async () => {
  const p = production({
    "pulls/7": [(t) => ok(pull(t >= 60_000 ? MOVED : HEAD))],
    [PROBE]: [(t, etag) => (t >= 60_000 ? ok(ref(MOVED)) : etag ? 304 : ok(ref()))],
    [LIST]: [ok({ workflow_runs: [dispatcherRun()] })],
    [`actions/runs/${DISPATCHER_ID}/artifacts?per_page=100`]: [ok(record())],
    [`actions/runs/${REFINE_ID}`]: runningUntil(Infinity),
  });
  assert.deepEqual(await decide(EVENT, p.deps), { proceed: false, reason: "head-moved" });
  assert.equal(p.deps.now(), 90_000, "the push lands by poll 2 (60 s) and its confirming read comes 30 s later");
  assert.equal(p.sent.filter((s) => s.path === `actions/runs/${REFINE_ID}`).length, 1, "Refine was read at poll 1 only");
});

test("a Refine completing at a poll the schedule would skip is read there when it is the last poll before the cap", async () => {
  const w = world({ ...refined(runningUntilWorld(120_000)), [PROBE]: ref() });
  assert.deepEqual(await decide({ ...EVENT, capMs: 120_000 }, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(w.elapsed(), 120_000, "polls at 30, 60, 90 and 120 s; the 120 s poll is even but the last that fits");
  const late = world({ ...refined(runningUntilWorld(121_000)), [PROBE]: ref() });
  assert.deepEqual(await decide({ ...EVENT, capMs: 120_000 }, late.deps), { proceed: true, reason: "refine-timeout" });
});

test("a Refine read once, already completed, waits one poll and reviews", async () => {
  const w = world({ ...refined(refineRun()), [PROBE]: ref() });
  assert.deepEqual(await decide(EVENT, w.deps), { proceed: true, reason: "refine-success" });
  assert.equal(reads(w, `actions/runs/${REFINE_ID}`), 1);
  assert.equal(w.elapsed(), 30_000);
});

test("over a holding rate guard, a rate-limited ref read reviews, fails nothing and sends no pull request read after it", async () => {
  const limited = [403, { message: "API rate limit exceeded for installation ID 1." }, { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1792751600", "x-ratelimit-resource": "core" }];
  const p = production({ "pulls/7": [ok(pull())], [LIST]: [ok({ workflow_runs: [] })], [PROBE]: [limited] });
  assert.deepEqual(await decide(INPUT, p.deps), { proceed: true, reason: "read-error" });
  assert.equal(p.failed(), 0);
  assert.deepEqual(p.sent.map((s) => s.path), ["pulls/7", LIST, PROBE], "the stopped pool sends nothing after the refusal");
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

// refine-event-dispatch.mjs starts fix-docs and every refine-dispatch activity
// only on an event whose sender is the lanes App or a listed human, and
// fix-docs-dispatch.mjs never starts fix-docs for a PR an excluded account
// opened, from any event. So an event an excluded account sent, on a PR one
// opened, has no refine run due on its head. Ids from trusted-actors.json
// (https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/pr-unblock/refine-event-dispatch.mjs).
const RELEASE_BOT = 337859524;
const HUMAN = 153232337;
const LANES_APP = 337595936;
const prEvent = ({ sender = RELEASE_BOT, author = RELEASE_BOT, number = 7, sha = HEAD } = {}) => ({
  action: "synchronize",
  number,
  sender: { id: sender, type: "Bot" },
  pull_request: { number, user: { id: author }, head: { sha } },
});
const eventFile = (event) => {
  const path = join(tempDir("wait-refine-event-"), "event.json");
  writeFileSync(path, typeof event === "string" ? event : JSON.stringify(event));
  return path;
};
const EVENT_ENV = { ...ENV, PR_BASE_REF: "main", PR_HEAD_REPO: REPO };

test("an event an excluded account sent on a PR one opened makes no poll read: the review runs after the one finish read", async () => {
  for (const id of NO_REFINE_ACCOUNTS) {
    const w = world({ "pulls/7": pull() });
    const result = await main({ ...EVENT_ENV, GITHUB_EVENT_PATH: eventFile(prEvent({ sender: id, author: id })) }, w.deps);
    assert.deepEqual(result, { proceed: true, reason: "no-refine-account" }, String(id));
    assert.deepEqual(apiReads(w), ["pulls/7"], "no listing, ref, run or artifact read");
    assert.equal(w.elapsed(), 0, "no poll");
  }
});

test("with no refine due, a head moved or a pull request closed by the finish read is still not reviewed", async () => {
  for (const finish of [steps(pull(MOVED)), pull(HEAD, { state: "closed" })]) {
    const w = world({ "pulls/7": finish });
    assert.deepEqual(await decide({ ...EVENT, noRefine: true }, w.deps), { proceed: false, reason: "head-moved" }, JSON.stringify(finish));
    assert.ok(!apiReads(w).includes(LIST));
  }
});

test("a refine-due event still polls: a listed human's, the lanes App's, or an excluded sender's on another author's PR reads the dispatcher listing first", async () => {
  for (const shape of [{ sender: HUMAN }, { sender: LANES_APP }, { author: HUMAN }, { sender: HUMAN, author: HUMAN }, { sender: LANES_APP, author: LANES_APP }]) {
    const w = world({ ...refined(refineRun()), [PROBE]: ref() });
    const result = await main({ ...EVENT_ENV, GITHUB_EVENT_PATH: eventFile(prEvent(shape)) }, w.deps);
    assert.deepEqual(result, { proceed: true, reason: "refine-success" }, JSON.stringify(shape));
    assert.equal(apiReads(w)[0], LIST, JSON.stringify(shape));
  }
});

test("an event file that is missing, unreadable, malformed, or names another PR or head still polls", async () => {
  const dir = tempDir("wait-refine-event-");
  for (const path of [undefined, "", join(dir, "absent.json"), eventFile("{not json"), eventFile("null"), eventFile(prEvent({ number: 8 })), eventFile(prEvent({ sha: MOVED }))]) {
    const w = world({ ...refined(refineRun()), [PROBE]: ref() });
    const result = await main({ ...EVENT_ENV, GITHUB_EVENT_PATH: path }, w.deps);
    assert.deepEqual(result, { proceed: true, reason: "refine-success" }, String(path));
    assert.equal(apiReads(w)[0], LIST, String(path));
  }
});

test("noRefineDue takes only numeric ids matching this PR and head", () => {
  const input = { number: 7, head: HEAD };
  assert.equal(noRefineDue(prEvent(), input), true);
  for (const event of [
    null,
    {},
    prEvent({ sender: String(RELEASE_BOT) }),
    prEvent({ author: String(RELEASE_BOT) }),
    { ...prEvent(), sender: undefined },
    { ...prEvent(), pull_request: { ...prEvent().pull_request, user: undefined } },
    { ...prEvent(), pull_request: { ...prEvent().pull_request, number: "7" } },
    { ...prEvent(), pull_request: { ...prEvent().pull_request, head: undefined } },
  ]) {
    assert.equal(noRefineDue(event, input), false, JSON.stringify(event));
  }
});

test("the no-refine accounts are fix-docs's excluded authors, none a listed human or the lanes App, and the live config lists no refine-dispatch activity", async () => {
  assert.deepEqual([...NO_REFINE_ACCOUNTS].sort(), [...FIX_DOCS.excludedAuthorIds].sort());
  const { humans, logins } = loadTrustedList(fileURLToPath(new URL("../../standards/trusted-actors/trusted-actors.json", import.meta.url)));
  const lanesApp = logins.get("melodic-automation-lanes[bot]");
  assert.ok(Number.isInteger(lanesApp));
  for (const id of NO_REFINE_ACCOUNTS) {
    assert.ok(!humans.has(id), `${id} is a listed human`);
    assert.notEqual(id, lanesApp, `${id} is the lanes App`);
  }
  // An activity starts on a listed human's later event on the same head,
  // which an excluded author does not rule out: the skip holds only while
  // the list is empty, which absent means
  // (https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-pipeline.schema.json).
  const config = readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8");
  assert.doesNotMatch(config, /^["']?refine-dispatch["']?\s*:/m);
});
