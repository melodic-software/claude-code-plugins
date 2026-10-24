// The hourly triage sweep's rules, from the owner-approved design: an open
// issue qualifies when it is not a pull request, is over an hour old, its
// author is one the intake lane admits on open, and it has no `status:` label
// and no agent-ready, needs-human or needs-spec (the needs-triage floor label
// is not one), whatever comments intake left (owner 2026-10-24, rows S2 and
// S3); or it was born triaged in `status: ready` with nothing admitting it
// and nothing holding it (row S1). Each pass dispatches at most 5, and
// after 2 dispatches that left the issue untriaged the sweep labels it
// needs-triage, says so in its comment on the issue, and stops dispatching it.
// Owner rule 2026-10-24: no new issues; comment on the original instead.
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  decide,
  FILING,
  HANDED,
  MAX_DISPATCHES,
  readState,
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
// it does not mark an issue triaged. Priority and work-class labels are no
// verdict either: only a status label, agent-ready or a person's hold is.
test("a candidate has no status label, agent-ready or hold, is no PR, over an hour old, by an admitted author", () => {
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
    issue(16, { labels: [{ name: "status: ready" }] }),
  ];
  assert.deepEqual(
    selectCandidates({ issues, now: NOW, authorIds: authors }).map((i) => i.number),
    [14, 1, 2, 6, 7, 10, 13],
  );
});

// /work-items:decompose publishes an issue already triaged, so intake never
// ran admission on it: one in status: ready with nothing admitting or holding
// it, and no open blocker (work-unblock labels those when the blocker closes),
// is dispatched so intake's admission takes it.
test("a born-triaged issue in status: ready with no agent-ready, deferral, hold or open blocker is a candidate", () => {
  const born = (number, labels = [], over = {}) =>
    issue(number, { body: "Fix it.\n\n<!-- work-items:born-triaged -->", labels: [{ name: "status: ready" }, ...labels.map((name) => ({ name }))], ...over });
  const issues = [
    born(1),
    born(2, ["agent-ready"]),
    born(3, ["admission-deferred"]),
    born(4, ["needs-human"]),
    born(5, ["work-class: untrusted-provenance"]),
    born(6, [], { issue_dependencies_summary: { blocked_by: 1, total_blocked_by: 1, blocking: 0, total_blocking: 0 } }),
    born(7, [], { issue_dependencies_summary: { blocked_by: 0, total_blocked_by: 1, blocking: 0, total_blocking: 0 } }),
    born(8, ["priority: high"]),
    issue(9, { labels: [{ name: "status: ready" }] }),
    born(10, [], { user: { id: OUTSIDER } }),
    // A quoted marker mid-body is not the publisher's last line.
    born(11, [], { body: "<!-- work-items:born-triaged -->\nmore text" }),
  ];
  assert.deepEqual(
    selectCandidates({ issues, now: NOW, authorIds: authors }).map((i) => i.number),
    [1, 7, 8],
  );
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
  assert.equal(readState([{ id: 6, user: BOT, body: renderState({ runs: [11, 22], filed: HANDED, repoUrl: "u" }) }]).filed, HANDED);
});

test("decide: dispatch first, wait on an unfinished run, dispatch again after one, hand off after two, stop once handed off", () => {
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
  assert.equal(decide({ state: { runs: [1, 2], filed: null }, latest: done }), "hand");
  assert.equal(decide({ state: { runs: [1, 2], filed: HANDED }, latest: done }), "stop");
  assert.equal(decide({ state: { runs: [1, 2], filed: 9 }, latest: done }), "stop");
  assert.equal(decide({ state: { runs: [1, 2], filed: FILING }, latest: done }), "stop");
});

test("the hand-off comment names every dispatched run and asks a maintainer to triage the issue", () => {
  const body = renderState({
    runs: [11, 22],
    filed: HANDED,
    repoUrl: "https://github.com/o/r",
    details: [
      { id: 11, conclusion: "failure" },
      { id: 22, conclusion: "success" },
    ],
  });
  assert.ok(body.startsWith("<!-- claude-lane triage-sweep runs=11,22 filed=handed -->\n"));
  assert.ok(body.includes("after 2 dispatches"));
  assert.ok(body.includes("- https://github.com/o/r/actions/runs/11 (failure)"));
  assert.ok(body.includes("- https://github.com/o/r/actions/runs/22 (success)"));
  assert.ok(body.includes("Triage it by hand"));
});

// A fake GitHub holding issues, comments and runs, recording every write.
function fakeGitHub({ issues, comments = {}, runs = {}, failPatch = () => false, filedIssues = [], handedIssues = [] }) {
  const writes = [];
  let nextRun = 900;
  let nextIssue = 5000;
  let nextComment = 100;
  const call = async (method, path, body) => {
    let m;
    if (method === "GET" && (m = /^\/search\/issues\?q=([^&]+)&per_page=100&page=(\d+)$/.exec(path))) {
      const found = {
        'repo:o/r is:issue author:app/github-actions in:title "Intake triage left"': filedIssues,
        'repo:o/r is:issue is:open commenter:app/github-actions in:comments "so the sweep no longer dispatches it"': handedIssues,
      }[decodeURIComponent(m[1])];
      assert.ok(found, decodeURIComponent(m[1]));
      return { incomplete_results: false, items: found.slice((Number(m[2]) - 1) * 100, Number(m[2]) * 100) };
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
  runSweep({ call: gh.call, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP) });

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

// Row S3: an intake comment with no verdict label left the issue untriaged.
// Row S2: the lanes App opened the issue, so apply-verdict's --check refused
// the App as actor; a dispatch by this job's token passes it.
test("an issue with an intake comment but no status label is dispatched again, and so is one the lanes App opened", async () => {
  const gh = fakeGitHub({
    issues: [issue(1), issue(2, { user: { id: APP } })],
    comments: { 1: [{ id: 5, user: BOT, body: "<!-- claude-lane intake-triage -->\nok" }] },
  });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [1, 2]);
});

test("an issue with a status label is left alone, whatever its comments", async () => {
  const gh = fakeGitHub({
    issues: [issue(1, { labels: [{ name: "status: needs-decision" }] })],
    comments: { 1: [{ id: 5, user: BOT, body: "<!-- claude-lane intake-triage -->\nok" }] },
  });
  const result = await sweep(gh);
  assert.deepEqual(gh.writes, []);
  assert.equal(result.candidates, 0);
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

test("after 2 untriaged dispatches the sweep labels the issue and hands it off in its own comment, files no issue, and stops", async () => {
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
    ],
  );
  assert.deepEqual(first.writes[0].body, { labels: ["needs-triage"] });
  const marked = first.writes[1].body.body;
  assert.equal(readState([{ id: 5, user: BOT, body: marked }]).filed, HANDED);
  assert.ok(marked.includes("- https://github.com/o/r/actions/runs/11 (failure)"));
  assert.deepEqual(result.handed, [1]);

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
  let left = 8;
  const call = async (...args) => {
    if (left === 0) throw new Error("call budget of 8 reached");
    left -= 1;
    return gh.call(...args);
  };
  // issues page 1, the two hand-off searches, comments of #1, dispatch, state
  // write: 6 calls; #2's comments leave 1, too few for a dispatch and its
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

test("a hand-off whose record write fails is retried on the next pass, and no pass files an issue", async () => {
  const comments = { 1: [{ id: 5, user: BOT, body: renderState({ runs: [11, 22], filed: null, runUrl: "u" }) }] };
  const runs = {
    11: { status: "completed", conclusion: "failure" },
    22: { status: "completed", conclusion: "failure" },
  };
  const failing = fakeGitHub({ issues: [issue(1)], comments, runs, failPatch: (body) => /filed=handed/.test(body.body) });
  const first = await sweep(failing);
  assert.equal(first.failed.length, 1);
  const retry = fakeGitHub({ issues: [issue(1)], comments, runs });
  const second = await sweep(retry);
  assert.deepEqual(second.handed, [1]);
  for (const gh of [failing, retry]) {
    assert.ok(!gh.writes.some((w) => w.method === "POST" && w.path === "/repos/o/r/issues"));
  }
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
// an older sweep filed a hand-off issue for would spend the call budget on
// their comments every pass. One search for those hand-off issues skips them unread.
test("issues an older sweep filed a hand-off for are skipped without reading their comments", async () => {
  const handed = Array.from({ length: 118 }, (_, i) =>
    issue(i + 1, { labels: [{ name: "needs-triage" }], created_at: "2026-10-01T00:00:00Z" }),
  );
  const filedIssues = [
    ...handed.map((i) => ({
      number: 6000 + i.number,
      title: `Intake triage left #${i.number} untriaged after 2 dispatches`,
      user: BOT,
    })),
    // The same title from anyone else excludes nothing.
    { number: 7000, title: "Intake triage left #119 untriaged after 2 dispatches", user: { login: "someone" } },
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

// Review threads on #9814 (claude-review and Codex P2): work-unblock hands an
// issue back to intake after a Refs: merge or a closed lane PR, so a lifetime
// count of 2 dispatches would cut that flow off. The lanes App's hand-back
// comment, newer than the state comment's last edit, starts a new cycle.
const stateAt = (runs, filed, at) => ({
  id: 5,
  user: BOT,
  body: renderState({ runs, filed, runUrl: "u", repoUrl: "https://github.com/o/r" }),
  created_at: "2026-10-17T00:00:00Z",
  updated_at: at,
});
const handBack = (user, at) => ({ id: 6, user, body: "<!-- work-unblock handed triage #40 -->\nThe lanes App's pull request #40 merged with `Refs:`.", created_at: at });
const triaged = { 11: { status: "completed", conclusion: "success" }, 22: { status: "completed", conclusion: "success" } };
const LANES = { login: "melodic-automation-lanes[bot]", id: APP };

test("a lanes App hand-back newer than the state comment starts a new cycle of dispatches in the same comment", async () => {
  for (const filed of [null, HANDED]) {
    const gh = fakeGitHub({
      issues: [issue(1)],
      comments: { 1: [stateAt([11, 22], filed, "2026-10-17T06:00:00Z"), handBack(LANES, "2026-10-18T08:00:00Z")] },
      runs: triaged,
    });
    const result = await sweep(gh);
    assert.deepEqual(result.dispatched, [1], String(filed));
    assert.deepEqual(
      gh.writes.map((w) => [w.method, w.path]),
      [
        ["POST", "/repos/o/r/actions/workflows/intake-triage.yml/dispatches"],
        ["PATCH", "/repos/o/r/issues/comments/5"],
      ],
      String(filed),
    );
    assert.deepEqual(readState([{ id: 5, user: BOT, body: gh.writes[1].body.body }]), { commentId: 5, runs: [901], filed: null });
  }
});

test("a hand-back older than the state comment's last edit, or posted by anyone but the lanes App, keeps the count", async () => {
  for (const [name, back] of [
    ["older", handBack(LANES, "2026-10-17T05:00:00Z")],
    ["not the App", handBack({ login: "someone", id: OUTSIDER }, "2026-10-18T08:00:00Z")],
    ["a listed human", handBack({ login: "owner", id: HUMAN }, "2026-10-18T08:00:00Z")],
  ]) {
    const gh = fakeGitHub({ issues: [issue(1)], comments: { 1: [stateAt([11, 22], null, "2026-10-17T06:00:00Z"), back] }, runs: triaged });
    const result = await sweep(gh);
    assert.deepEqual(result.dispatched, [], name);
    assert.deepEqual(result.handed, [1], name);
  }
});

// Codex P2 on #9814: hand-offs now live only in a comment, so each handed
// issue would cost a comment read every pass and could use up the 120-call
// budget before a fresh issue behind them. One search for the hand-off text
// skips those still carrying needs-triage unread.
test("issues this sweep handed off in a comment are skipped without reading their comments", async () => {
  const handed = Array.from({ length: 118 }, (_, i) =>
    issue(i + 1, { labels: [{ name: "needs-triage" }], created_at: "2026-10-01T00:00:00Z" }),
  );
  const marked = renderState({ runs: [1, 2], filed: HANDED, repoUrl: "https://github.com/o/r" });
  const gh = fakeGitHub({
    issues: [...handed, issue(119, { labels: [{ name: "needs-triage" }] })],
    comments: Object.fromEntries(handed.map((i) => [i.number, [{ id: i.number, user: BOT, body: marked }]])),
    handedIssues: handed.map((i) => ({ number: i.number })),
  });
  const reads = [];
  let left = 120;
  const call = async (method, path, body) => {
    if (left === 0) throw new Error("call budget of 120 reached");
    left -= 1;
    if (method === "GET") reads.push(path);
    return gh.call(method, path, body);
  };
  const result = await runSweep({ call, remaining: () => left, repo: "o/r", serverUrl: "https://github.com", now: NOW, authorIds: authors, appId: String(APP) });
  assert.deepEqual(result.dispatched, [119]);
  assert.equal(reads.filter((p) => p.includes("/comments")).length, 1);
});

test("a search hit without needs-triage is read, so a hand-back after its label came off starts a new cycle", async () => {
  const gh = fakeGitHub({
    issues: [issue(1)],
    comments: { 1: [stateAt([11, 22], HANDED, "2026-10-17T06:00:00Z"), handBack(LANES, "2026-10-18T08:00:00Z")] },
    runs: triaged,
    handedIssues: [{ number: 1 }],
  });
  const result = await sweep(gh);
  assert.deepEqual(result.dispatched, [1]);
});

test("an issue past the comment pages that already carries needs-triage is not handed off again", async () => {
  const flood = Array.from({ length: 300 }, (_, i) => ({ id: i, user: { login: "someone", id: 9 }, body: "spam" }));
  const gh = fakeGitHub({ issues: [issue(1, { labels: [{ name: "needs-triage" }] })], comments: { 1: flood } });
  const result = await sweep(gh);
  assert.deepEqual(gh.writes, []);
  assert.deepEqual(result.handedOff, []);
});
