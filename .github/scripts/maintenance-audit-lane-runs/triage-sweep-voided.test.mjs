// An intake run whose verdict a lanes kill switch voided (the broker refused
// apply-verdict's token with reason kill-switch, as in runs 43076956280 and
// 43077440327) wrote nothing. apply-verdict stays green, as every lane's
// lane-token-stopped does, and runs one named step; the sweep reads that step
// from the job listing, counts the run as no attempt, and dispatches intake
// again rather than handing the issue off on it.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { workflowText } from "../lib/workflow-text.mjs";
import { classifyRun, MAX_DISPATCHES, renderState, runSweep, VOIDED_STEP } from "./triage-sweep.mjs";

const NOW = new Date("2026-11-12T12:00:00Z");
const BOT = { login: "github-actions[bot]", id: 41898282 };
const HUMAN = 153232337;
const authors = new Set([String(HUMAN)]);

const issue = (number, over = {}) => ({ number, user: { id: HUMAN }, labels: [], body: "a report", created_at: "2026-11-09T12:00:00Z", ...over });
const step = (name, conclusion) => ({ name, status: "completed", conclusion });
const job = (name, conclusion, steps, id) => ({ name, status: "completed", conclusion, steps, check_run_url: `https://api.github.com/repos/o/r/check-runs/${id}` });
const reached = (apply) => [job("Kill Switch", "success", [], 1), job("Born Triaged", "success", [], 2), job("Intake Triage / claude-intake-triage", "success", [], 3), apply];
// apply-verdict's steps as those two runs listed them, with the voided step run.
const VOIDED = reached(
  job("Apply Verdict", "success", [step("Check who started the run", "success"), step("Request the lane token", "success"), step(VOIDED_STEP, "success"), step("Write the verdict", "skipped")], 301),
);
// The same stop with the step skipped: what those runs list without it.
const UNMARKED = reached(
  job("Apply Verdict", "success", [step("Check who started the run", "success"), step("Request the lane token", "success"), step(VOIDED_STEP, "skipped"), step("Write the verdict", "skipped")], 302),
);
// A verdict written that left the issue untriaged.
const WROTE = reached(job("Apply Verdict", "success", [step("Request the lane token", "success"), step(VOIDED_STEP, "skipped"), step("Write the verdict", "success")], 303));
const STOPPED_NOTE = { annotation_level: "notice", message: "lane-token-stopped: the broker refused the token because a lanes kill switch is on, a designed stop; this run takes no token and skips the rest" };
const done = { status: "completed", conclusion: "success" };

function fakeGitHub({ issues, comments = {}, runs = {}, jobs = {} }) {
  const reads = [];
  const writes = [];
  let nextRun = 900;
  const call = async (method, path, body) => {
    let m;
    if (method === "GET") reads.push(path);
    if (method === "GET" && path.startsWith("/search/issues?")) return { incomplete_results: false, items: [] };
    if (method === "POST" && path === "/graphql") return { data: { search: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: [] } } };
    if (method === "GET" && path === "/repos/o/r/issues?state=open&per_page=100&page=1") return issues;
    if (method === "GET" && (m = /^\/repos\/o\/r\/issues\/(\d+)\/comments\?per_page=100&page=1$/.exec(path))) return comments[m[1]] ?? [];
    if (method === "GET" && (m = /^\/repos\/o\/r\/actions\/runs\/(\d+)$/.exec(path))) return runs[m[1]] ?? null;
    if (method === "GET" && (m = /^\/repos\/o\/r\/actions\/runs\/(\d+)\/jobs\?per_page=100$/.exec(path))) {
      if (!(m[1] in jobs)) throw new Error(`GET ${path}: HTTP 502`);
      return { total_count: jobs[m[1]].length, jobs: jobs[m[1]] };
    }
    // Only a written verdict's annotations are listed (none); any other read fails.
    if (method === "GET" && path === "/repos/o/r/check-runs/303/annotations?per_page=100") return [];
    if (method === "GET") throw new Error(`GET ${path}: HTTP 502`);
    writes.push({ method, path, body });
    if (method === "POST" && path === "/repos/o/r/actions/workflows/intake-triage.yml/dispatches") return { workflow_run_id: (nextRun += 1) };
    return { id: 100 };
  };
  const setStatus = async (number, state) => {
    writes.push({ method: "STATUS", path: `/repos/o/r/issues/${number}`, body: { state } });
  };
  return { call, reads, writes, setStatus };
}

const sweep = (gh) => runSweep({ call: gh.call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, setStatus: gh.setStatus });
const stateComment = (runs, marks = []) => ({ id: 5, user: BOT, body: renderState({ runs, filed: null, runUrl: "u", reached: new Map(marks) }) });
const stateLine = (write) => write.body.body.split("\n")[0];

test("classifyRun marks a voided verdict transient from the job listing alone; the same stop without the step counts", async () => {
  const unread = () => {
    throw new Error("annotations read");
  };
  assert.equal(await classifyRun(VOIDED, unread), "~");
  assert.equal(await classifyRun(UNMARKED, async () => [STOPPED_NOTE]), "+");
  assert.equal(await classifyRun(WROTE, async () => []), "+");
});

test("a voided second dispatch is no attempt: the sweep dispatches again and records it transient", async () => {
  const gh = fakeGitHub({ issues: [issue(1)], comments: { 1: [stateComment([11, 22])] }, runs: { 11: done, 22: done }, jobs: { 11: WROTE, 22: VOIDED } });
  const result = await sweep(gh);
  assert.deepEqual([result.dispatched, result.handed], [[1], []]);
  assert.equal(stateLine(gh.writes[1]), "<!-- claude-lane triage-sweep runs=11+,22~,901 filed= -->");
  assert.equal(gh.reads.filter((p) => p.includes("/check-runs/301/")).length, 0);

  const before = fakeGitHub({ issues: [issue(1)], comments: { 1: [stateComment([11, 22])] }, runs: { 11: done, 22: done }, jobs: { 11: WROTE, 22: UNMARKED } });
  assert.deepEqual((await sweep(before)).handed, [1]);
});

test("a voided latest run is dispatched again after two attempts; a written one hands the issue off", async () => {
  const comments = { 1: [stateComment([11, 22, 33], [[11, "+"], [22, "+"]])] };
  const voided = fakeGitHub({ issues: [issue(1)], comments, runs: { 33: done }, jobs: { 33: VOIDED } });
  const again = await sweep(voided);
  assert.deepEqual([again.dispatched, again.handed], [[1], []]);
  assert.equal(stateLine(voided.writes[1]), "<!-- claude-lane triage-sweep runs=11+,22+,33~,901 filed= -->");

  const wrote = fakeGitHub({ issues: [issue(1)], comments, runs: { 33: done }, jobs: { 33: WROTE } });
  const handedOff = await sweep(wrote);
  assert.deepEqual([handedOff.dispatched, handedOff.handed], [[], [1]]);
});

test("a voided latest run with no dispatch left this pass is not recorded, so the next pass dispatches it", async () => {
  const fresh = Array.from({ length: MAX_DISPATCHES }, (_, i) => issue(i + 2, { created_at: "2026-11-01T00:00:00Z" }));
  const comments = { 1: [stateComment([11, 22, 33], [[11, "+"], [22, "+"]])] };
  const full = fakeGitHub({ issues: [...fresh, issue(1)], comments, runs: { 33: done }, jobs: { 33: VOIDED } });
  const first = await sweep(full);
  assert.deepEqual([first.dispatched, first.handed], [fresh.map((i) => i.number), []]);
  assert.deepEqual(full.writes.filter((w) => w.path.endsWith("/comments/5")), []);

  const next = fakeGitHub({ issues: [issue(1)], comments, runs: { 33: done }, jobs: { 33: VOIDED } });
  assert.deepEqual((await sweep(next)).dispatched, [1]);
});

// The step's `if:` is reached only through the token step, which runs only
// after the config and the who-check passed: a run is marked voided only when
// it passed the trust checks a dispatch must pass.
test("apply-verdict runs the voided step only on the broker's kill-switch refusal, after the who-check, and stays green", () => {
  const wf = workflowText(readFileSync(new URL("../../workflows/intake-triage.yml", import.meta.url), "utf8"));
  const voided = wf.step("apply-verdict", "voided");
  assert.match(voided.text, new RegExp(`^ {6}- name: ${VOIDED_STEP}$`, "m"));
  assert.equal(voided.if, "steps.lane-token.outputs.skip-reason == 'kill-switch'");
  assert.match(voided.text, /^ {10}ISSUE_NUMBER: \$\{\{ github\.event\.issue\.number \|\| inputs\.issue-number \}\}$/m);
  assert.match(voided.text, /run: \|\n {10}echo "::notice title=apply-verdict::#\$\{ISSUE_NUMBER\}'s verdict was not written: /);
  assert.doesNotMatch(voided.text, /continue-on-error|exit [1-9]/);
  const token = wf.step("apply-verdict", "lane-token");
  assert.equal(token.if, "steps.config.outcome == 'success' && steps.config.outputs.applies == 'true'");
  assert.equal(token.inputs["kill-switch-ok"], "true");
  assert.equal(wf.step("apply-verdict", "config").if, "steps.who.outputs.proceed == 'true'");
  assert.equal(wf.step("apply-verdict", "who").if, "steps.kill.outputs.proceed == 'true'");
});
