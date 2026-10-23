// The hourly triage sweep's rules, from the owner-approved design: an open
// issue qualifies when it has no intake-triage comment and no triage or
// status label (the needs-triage floor label is not one), is not a pull
// request, was not born triaged, and is over an hour old; its author must be
// one the intake lane admits on open. Each pass dispatches at most 5, and
// after 2 dispatches that left the issue untriaged the sweep files one
// needs-triage issue and stops dispatching that issue.
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  decide,
  FILING,
  hasIntakeComment,
  MAX_DISPATCHES,
  readState,
  renderFiledIssue,
  renderState,
  runSweep,
  selectCandidates,
} from "./triage-sweep.mjs";

const NOW = new Date("2026-10-18T12:00:00Z");
const BOT = { login: "github-actions[bot]", id: 41898282 };
const HUMAN = 153232337;
const OUTSIDER = 555;

const issue = (number, over = {}) => ({
  number,
  user: { id: HUMAN },
  labels: [],
  body: "a report",
  created_at: "2026-10-18T09:00:00Z",
  ...over,
});

const APP = 337595936;
const authors = new Set([String(HUMAN), String(APP)]);

// The needs-triage floor label lands on open whether or not intake runs, so
// it does not mark an issue triaged: the missing intake comment decides.
test("a candidate has no triage or status label, is no PR, not born triaged, over an hour old, by an admitted author", () => {
  const issues = [
    issue(1),
    issue(2, { labels: [{ name: "needs-triage" }] }),
    issue(3, { labels: [{ name: "status: needs-info" }] }),
    issue(4, { labels: [{ name: "agent-ready" }] }),
    issue(5, { labels: [{ name: "needs-human" }] }),
    issue(6, { labels: [{ name: "priority: low" }] }),
    issue(7, { labels: [{ name: "work-class: scoped" }] }),
    issue(8, { labels: [{ name: "needs-spec" }] }),
    issue(9, { pull_request: { url: "x" } }),
    issue(10, { body: "text\n<!-- work-items:born-triaged -->\n" }),
    issue(11, { created_at: "2026-10-18T11:30:00Z" }),
    issue(12, { user: { id: OUTSIDER } }),
    issue(13, { labels: [{ name: "question" }, { name: "dependencies" }] }),
    issue(14, { user: { id: APP }, created_at: "2026-10-01T00:00:00Z" }),
    issue(15, { user: { id: BOT.id } }),
  ];
  assert.deepEqual(
    selectCandidates({ issues, now: NOW, authorIds: authors }).map((i) => i.number),
    [14, 1, 2, 13],
  );
});

test("a quoted born-triaged marker mid-body does not exempt the issue", () => {
  const issues = [issue(1, { body: "<!-- work-items:born-triaged -->\nmore text" })];
  assert.deepEqual(
    selectCandidates({ issues, now: NOW, authorIds: authors }).map((i) => i.number),
    [1],
  );
});

test("only the bot's comment that starts with the intake marker counts as triaged", () => {
  const marker = "<!-- claude-lane intake-triage -->\nThanks for the report.";
  assert.equal(hasIntakeComment([{ user: BOT, body: marker }]), true);
  assert.equal(hasIntakeComment([{ user: { login: "someone", id: 9 }, body: marker }]), false);
  assert.equal(hasIntakeComment([{ user: BOT, body: `quoted: ${marker}` }]), false);
  assert.equal(hasIntakeComment([]), false);
});

test("the sweep state round-trips and is read only from the bot's comment", () => {
  const body = renderState({ runs: [11, 22], filed: null, runUrl: "https://github.com/o/r/actions/runs/22" });
  const comments = [
    { id: 1, user: { login: "someone", id: 9 }, body: renderState({ runs: [], filed: 5, runUrl: "u" }) },
    { id: 2, user: BOT, body },
  ];
  assert.deepEqual(readState(comments), { commentId: 2, runs: [11, 22], filed: null });
  assert.deepEqual(readState([{ id: 3, user: BOT, body: renderState({ runs: [11, 22], filed: 77, runUrl: "u" }) }]), {
    commentId: 3,
    runs: [11, 22],
    filed: 77,
  });
  assert.deepEqual(readState([]), { commentId: null, runs: [], filed: null });
  assert.equal(readState([{ id: 4, user: BOT, body: renderState({ runs: [11, 22], filed: FILING }) }]).filed, FILING);
});

test("decide: dispatch first, wait on an unfinished run, dispatch again after one, file after two, stop once filed", () => {
  const done = { status: "completed", conclusion: "failure" };
  assert.equal(decide({ state: { runs: [], filed: null }, latest: null }), "dispatch");
  assert.equal(decide({ state: { runs: [1], filed: null }, latest: { status: "in_progress" } }), "wait");
  assert.equal(decide({ state: { runs: [1], filed: null }, latest: { status: "queued" } }), "wait");
  assert.equal(decide({ state: { runs: [1], filed: null }, latest: done }), "dispatch");
  assert.equal(
    decide({ state: { runs: [1], filed: null }, latest: { status: "completed", conclusion: "success" } }),
    "dispatch",
  );
  assert.equal(decide({ state: { runs: [1, 2], filed: null }, latest: { status: "in_progress" } }), "wait");
  assert.equal(decide({ state: { runs: [1, 2], filed: null }, latest: done }), "file");
  assert.equal(decide({ state: { runs: [1, 2], filed: 9 }, latest: done }), "stop");
  assert.equal(decide({ state: { runs: [1, 2], filed: FILING }, latest: done }), "stop");
});

test("the filed issue names the issue and every failed run, and carries needs-triage", () => {
  const filed = renderFiledIssue({
    number: 42,
    runs: [
      { id: 11, conclusion: "failure" },
      { id: 22, conclusion: "success" },
    ],
    repoUrl: "https://github.com/o/r",
  });
  assert.equal(filed.title, "Intake triage left #42 untriaged after 2 dispatches");
  assert.deepEqual(filed.labels, ["needs-triage"]);
  assert.match(filed.body, /#42/);
  assert.ok(filed.body.includes("https://github.com/o/r/actions/runs/11"));
  assert.ok(filed.body.includes("https://github.com/o/r/actions/runs/22"));
});

// A fake GitHub holding issues, comments and runs, recording every write.
function fakeGitHub({ issues, comments = {}, runs = {}, failPatch = () => false, filedIssues = [] }) {
  const writes = [];
  let nextRun = 900;
  let nextIssue = 5000;
  let nextComment = 100;
  const call = async (method, path, body) => {
    let m;
    if (method === "GET" && (m = /^\/search\/issues\?q=([^&]+)&per_page=100&page=(\d+)$/.exec(path))) {
      assert.equal(decodeURIComponent(m[1]), 'repo:o/r is:issue author:app/github-actions in:title "Intake triage left"');
      return { incomplete_results: false, items: filedIssues.slice((Number(m[2]) - 1) * 100, Number(m[2]) * 100) };
    }
    if (method === "GET" && (m = /^\/repos\/o\/r\/issues\?state=open&per_page=100&page=(\d+)$/.exec(path))) {
      return issues.slice((Number(m[1]) - 1) * 100, Number(m[1]) * 100);
    }
    if (method === "GET" && (m = /^\/repos\/o\/r\/issues\/(\d+)\/comments\?per_page=100&page=(\d+)$/.exec(path))) {
      return (comments[m[1]] ?? []).slice((Number(m[2]) - 1) * 100, Number(m[2]) * 100);
    }
    if (method === "GET" && (m = /^\/repos\/o\/r\/actions\/runs\/(\d+)$/.exec(path))) {
      return runs[m[1]] ?? null;
    }
    writes.push({ method, path, body });
    // API version 2022-11-28 returns the run id only when return_run_details
    // is true, else 204, which `call` turns into null.
    if (method === "POST" && path === "/repos/o/r/actions/workflows/intake-triage.yml/dispatches") {
      if (body?.return_run_details !== true) return null;
      nextRun += 1;
      return { workflow_run_id: nextRun };
    }
    if (method === "POST" && path === "/repos/o/r/issues") return { number: (nextIssue += 1) };
    if (method === "POST" && (m = /^\/repos\/o\/r\/issues\/(\d+)\/labels$/.exec(path))) {
      const target = issues.find((i) => i.number === Number(m[1]));
      target.labels = [...(target.labels ?? []), ...body.labels.map((name) => ({ name }))];
      return [];
    }
    if (method === "PATCH" && failPatch(body)) throw new Error(`PATCH ${path}: HTTP 502`);
    if (method === "POST" || method === "PATCH") return { id: (nextComment += 1) };
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { call, writes };
}

const sweep = (gh) =>
  runSweep({ call: gh.call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors });

test("a pass dispatches at most 5 issues, oldest first, and records each run on the issue", async () => {
  // Listed newest first, as the issues API returns them.
  const issues = Array.from({ length: 7 }, (_, i) => issue(7 - i, { created_at: `2026-10-1${6 - i}T00:00:00Z` }));
  const gh = fakeGitHub({ issues });
  const result = await sweep(gh);
  assert.equal(MAX_DISPATCHES, 5);
  const dispatches = gh.writes.filter((w) => w.path.endsWith("/dispatches"));
  assert.deepEqual(
    dispatches.map((w) => w.body),
    [1, 2, 3, 4, 5].map((n) => ({ ref: "main", inputs: { "issue-number": String(n) }, return_run_details: true })),
  );
  const states = gh.writes.filter((w) => /\/issues\/\d+\/comments$/.test(w.path));
  assert.deepEqual(
    states.map((w) => [w.path, readState([{ id: 1, user: BOT, body: w.body.body }]).runs]),
    [1, 2, 3, 4, 5].map((n, i) => [`/repos/o/r/issues/${n}/comments`, [901 + i]]),
  );
  assert.deepEqual(result.dispatched, [1, 2, 3, 4, 5]);
});

test("an issue with an intake comment is left alone", async () => {
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: "<!-- claude-lane intake-triage -->\nok" }] },
  });
  await sweep(gh);
  assert.deepEqual(gh.writes, []);
});

test("a second dispatch edits the same state comment", async () => {
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11], filed: null, runUrl: "u" }) }] },
    runs: { 11: { status: "completed", conclusion: "failure" } },
  });
  await sweep(gh);
  assert.deepEqual(
    gh.writes.map((w) => [w.method, w.path]),
    [
      ["POST", "/repos/o/r/actions/workflows/intake-triage.yml/dispatches"],
      ["PATCH", "/repos/o/r/issues/comments/5"],
    ],
  );
  assert.deepEqual(readState([{ id: 5, user: BOT, body: gh.writes[1].body.body }]).runs, [11, 901]);
});

test("after 2 untriaged dispatches the sweep files once, then never dispatches or files again", async () => {
  const runs = {
    11: { status: "completed", conclusion: "failure" },
    22: { status: "completed", conclusion: "success" },
  };
  const first = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }] },
    runs,
  });
  const result = await sweep(first);
  assert.deepEqual(
    first.writes.map((w) => [w.method, w.path]),
    [
      ["POST", "/repos/o/r/issues/1/labels"],
      ["PATCH", "/repos/o/r/issues/comments/5"],
      ["POST", "/repos/o/r/issues"],
      ["PATCH", "/repos/o/r/issues/comments/5"],
    ],
  );
  assert.deepEqual(first.writes[0].body, { labels: ["needs-triage"] });
  // The filing is recorded before the issue is filed, so a later pass stops.
  assert.equal(readState([{ id: 5, user: BOT, body: first.writes[1].body.body }]).filed, FILING);
  assert.deepEqual(first.writes[2].body.labels, ["needs-triage"]);
  assert.deepEqual(result.filed, [5001]);
  const marked = first.writes[3].body.body;
  assert.equal(readState([{ id: 5, user: BOT, body: marked }]).filed, 5001);

  const second = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: marked }] },
    runs,
  });
  await sweep(second);
  assert.deepEqual(second.writes, []);
});

test("a run still in progress holds the issue for a later pass", async () => {
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11], filed: null, runUrl: "u" }) }] },
    runs: { 11: { status: "in_progress", conclusion: null } },
  });
  const result = await sweep(gh);
  assert.deepEqual(gh.writes, []);
  assert.deepEqual(result.waiting, [1]);
});

// A comment flood past the pages read would hide the state comment and force
// a dispatch every pass.
test("an issue with more comments than the sweep reads goes to a maintainer, undispatched", async () => {
  const flood = Array.from({ length: 300 }, (_, i) => ({ id: i, user: { login: "someone", id: 9 }, body: "spam" }));
  const gh = fakeGitHub({ issues: [issue(1)], comments: { 1: flood } });
  const result = await sweep(gh);
  assert.deepEqual(
    gh.writes.map((w) => [w.method, w.path, w.body]),
    [["POST", "/repos/o/r/issues/1/labels", { labels: ["needs-triage"] }]],
  );
  assert.deepEqual(result.dispatched, []);
});

test("a pass stops dispatching when the budget left cannot record the run", async () => {
  const gh = fakeGitHub({ issues: [issue(1), issue(2, { created_at: "2026-10-18T09:30:00Z" })] });
  let left = 7;
  const call = async (...args) => {
    if (left === 0) throw new Error("call budget of 7 reached");
    left -= 1;
    return gh.call(...args);
  };
  // issues page 1, the hand-off search, comments of #1, dispatch, state
  // write: 5 calls; #2's comments leave 1, too few for a dispatch and its
  // state write.
  const result = await runSweep({
    call,
    remaining: () => left,
    repo: "o/r",
    serverUrl: "https://github.com",
    now: NOW,
    authorIds: authors,
  });
  assert.deepEqual(result.dispatched, [1]);
  assert.equal(gh.writes.filter((w) => w.path.endsWith("/dispatches")).length, 1);
  assert.match(result.truncated, /budget/);
});

// The needs-triage label no longer takes the original out of later passes, so
// the in-progress record is what stops a second filing.
test("a filing whose state write fails is not filed again on the next pass", async () => {
  const comments = { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }] };
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments,
    runs: {
      11: { status: "completed", conclusion: "failure" },
      22: { status: "completed", conclusion: "failure" },
    },
    failPatch: (body) => /filed=[0-9]/.test(body.body),
  });
  const first = await sweep(gh);
  assert.equal(first.failed.length, 1);
  // The pass persisted the in-progress record before it failed.
  const recorded = gh.writes.find((w) => w.method === "PATCH").body.body;
  comments[1] = [{ id: 5, user: BOT, body: recorded }];
  await sweep(gh);
  assert.equal(gh.writes.filter((w) => w.method === "POST" && w.path === "/repos/o/r/issues").length, 1);
});

test("issues the sweep already filed do not use up the per-pass check limit", async () => {
  const filed = Array.from({ length: 20 }, (_, i) =>
    issue(i + 1, { labels: [{ name: "needs-triage" }], created_at: "2026-10-01T00:00:00Z" }),
  );
  const gh = fakeGitHub({
    issues: [...filed, issue(21, { labels: [{ name: "needs-triage" }] })],
    comments: Object.fromEntries(
      filed.map((i) => [i.number, [{ id: i.number, user: BOT, body: renderState({ runs: [1, 2], filed: 7000 + i.number }) }]]),
    ),
  });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [21]);
});

// Codex P2 on #9303: with needs-triage no longer excluding them, the issues
// the sweep already handed off would spend the call budget on their comments
// every pass. One search for the sweep's own hand-off issues skips them unread.
test("issues the sweep filed a hand-off for are skipped without reading their comments", async () => {
  const handed = Array.from({ length: 118 }, (_, i) =>
    issue(i + 1, { labels: [{ name: "needs-triage" }], created_at: "2026-10-01T00:00:00Z" }),
  );
  const filedIssues = [
    ...handed.map((i) => ({
      number: 6000 + i.number,
      title: renderFiledIssue({ number: i.number, runs: [{}, {}], repoUrl: "u" }).title,
      user: BOT,
    })),
    // The same title from anyone else excludes nothing.
    { number: 7000, title: renderFiledIssue({ number: 119, runs: [{}, {}], repoUrl: "u" }).title, user: { login: "someone" } },
  ];
  const gh = fakeGitHub({
    issues: [...handed, issue(119, { labels: [{ name: "needs-triage" }] })],
    comments: Object.fromEntries(
      handed.map((i) => [i.number, [{ id: i.number, user: BOT, body: renderState({ runs: [1, 2], filed: 6000 + i.number }) }]]),
    ),
    filedIssues,
  });
  const reads = [];
  let left = 120;
  const call = async (method, path, body) => {
    if (left === 0) throw new Error("call budget of 120 reached");
    left -= 1;
    if (method === "GET") reads.push(path);
    return gh.call(method, path, body);
  };
  const result = await runSweep({ call, remaining: () => left, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors });
  assert.deepEqual(result.dispatched, [119]);
  assert.equal(reads.filter((p) => p.includes("/comments")).length, 1);
});

test("an issue past the comment pages that already carries needs-triage is not handed off again", async () => {
  const flood = Array.from({ length: 300 }, (_, i) => ({ id: i, user: { login: "someone", id: 9 }, body: "spam" }));
  const gh = fakeGitHub({ issues: [issue(1, { labels: [{ name: "needs-triage" }] })], comments: { 1: flood } });
  const result = await sweep(gh);
  assert.deepEqual(gh.writes, []);
  assert.deepEqual(result.handedOff, []);
});

test("issues intake already commented on do not use up the per-pass check limit", async () => {
  const commented = Array.from({ length: 20 }, (_, i) => issue(i + 1, { created_at: "2026-10-01T00:00:00Z" }));
  const gh = fakeGitHub({
    issues: [...commented, issue(21)],
    comments: Object.fromEntries(
      commented.map((i) => [i.number, [{ id: i.number, user: BOT, body: "<!-- claude-lane intake-triage -->\nok" }]]),
    ),
  });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [21]);
});
