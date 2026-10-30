// post.mjs: the lane run report comment, its rows checked again here because
// the run job that carried them shared RUNNER_TEMP with the model.
import assert from "node:assert/strict";
import { test } from "node:test";

import { escapeCell, failureRows, main, MAX_ROWS, render, templatePath } from "./post.mjs";

const BOT = { login: "github-actions[bot]" };
const ENV = {
  LANE: "read",
  ACTIVITY: "fix-ci",
  RUN_ID: "123",
  PULL: "42",
  REPOSITORY: "o/r",
  GITHUB_SERVER_URL: "https://github.com",
  RUN_RESULT: "failure",
  ACT_OUTCOME: "success",
  READ_LANE: "true",
  API_FAILURES: JSON.stringify({ rows: [{ method: "GET", path: "/repos/o/r/pulls/42", status: 502 }], dropped: 0 }),
};
const MARKER = "<!-- lane-run-report activity=read/fix-ci run=123 -->";

function fakeGitHub(comments = [], { fail = false } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (fail) throw new Error("boom");
    return method === "GET" ? comments : {};
  };
  return { github, calls, writes: () => calls.filter((c) => c.method !== "GET") };
}

async function run(env, github) {
  const lines = [];
  const original = console.log;
  console.log = (line) => lines.push(line);
  try {
    return { code: await main({ ...ENV, ...env }, { github }), lines };
  } finally {
    console.log = original;
  }
}

test("only rows of the recorded shape pass, duplicates fold, and the rest count as dropped", () => {
  const rows = [
    { method: "GET", path: "/repos/o/r/pulls/1", status: 404 },
    { method: "GET", path: "/repos/o/r/pulls/1", status: 404 },
    { method: "POST", path: "/graphql", status: 0 },
    { method: "TRACE", path: "/x", status: 500 },
    { method: "GET", path: "/repos/o/r?token=x", status: 500 },
    { method: "GET", path: "repos/o/r", status: 500 },
    { method: "GET", path: `/${"a".repeat(201)}`, status: 500 },
    { method: "GET", path: "/x", status: 600 },
    { method: "GET", path: "/x", status: 4.5 },
    { method: "GET", path: "/x", status: "500" },
    { method: "GET", path: "/x<b>", status: 500 },
    "not a row",
  ];
  assert.deepEqual(failureRows(JSON.stringify({ rows, dropped: 3 })), {
    rows: [
      { method: "GET", path: "/repos/{repo}/pulls/*", status: 404 },
      { method: "POST", path: "/graphql", status: 0 },
    ],
    dropped: 13,
  });
});

test("rows past the cap are dropped and counted", () => {
  const rows = Array.from({ length: MAX_ROWS + 7 }, (_, i) => ({ method: "GET", path: "/repos/o/r/pulls", status: 400 + i }));
  const out = failureRows(JSON.stringify({ rows, dropped: 0 }));
  assert.equal(out.rows.length, MAX_ROWS);
  assert.equal(out.dropped, 7);
});

test("an empty, unparsable or wrongly shaped carry is no rows", () => {
  for (const text of [undefined, "", "{", "[]", "null", JSON.stringify({ rows: "x", dropped: -1 })]) {
    assert.deepEqual(failureRows(text).rows, [], String(text));
  }
  assert.equal(failureRows(JSON.stringify({ rows: [], dropped: "9" })).dropped, 0);
});

test("a cell is escaped for markdown and HTML", () => {
  assert.equal(escapeCell("a|b<c>&`*_[x](y)"), "a&#124;b&lt;c&gt;&amp;&#96;&#42;&#95;&#91;x&#93;(y)");
});

test("the body opens with the marker and lists the activity, outcome, commits and failures", () => {
  const body = render({
    lane: "write",
    activity: "fix-docs",
    runId: "9",
    runUrl: "https://github.com/o/r/actions/runs/9",
    runResult: "success",
    actOutcome: "failure",
    commit: "a".repeat(40),
    readLane: false,
    failures: failureRows(JSON.stringify({ rows: [{ method: "PATCH", path: "/repos/o/r/git/refs/heads/my_branch", status: 422 }], dropped: 2 })),
  });
  assert.ok(body.startsWith("<!-- lane-run-report activity=write/fix-docs run=9 -->\n"));
  assert.match(body, /\| Activity \| write\/fix-docs \|/);
  assert.match(body, /\| Run job \| success \|/);
  assert.match(body, /\| Activity step \| failure \|/);
  assert.match(body, new RegExp(`\\| Commits pushed \\| ${"a".repeat(40)} \\|`));
  assert.match(body, /\| PATCH \| \/repos\/\{repo\}\/git\/refs\/heads\/&#42; \| 422 \|/);
  assert.match(body, /2 more not shown/);
});

test("a read lane pushes no commits, and a run with no failures says so", () => {
  const body = render({ lane: "read", activity: "fix-ci", runId: "1", runResult: "success", actOutcome: "success", readLane: true, failures: { rows: [], dropped: 0 } });
  assert.match(body, /\| Commits pushed \| none \(read lane\) \|/);
  assert.match(body, /No GitHub API call failed\./);
});

test("a forged outcome or commit renders as unknown or none, never as given", () => {
  const body = render({ lane: "write", activity: "x", runId: "1", runResult: "<img>", actOutcome: "a|b", commit: "zz", readLane: false, failures: { rows: [], dropped: 0 } });
  assert.match(body, /\| Run job \| unknown \|/);
  assert.match(body, /\| Activity step \| unknown \|/);
  assert.match(body, /\| Commits pushed \| none recorded \|/);
});

test("main posts the report on the pull request", async () => {
  const api = fakeGitHub([{ id: 1, user: { login: "someone" }, body: `${MARKER}\nquoted` }]);
  const out = await run({}, api.github);
  assert.equal(out.code, 0);
  const [write] = api.writes();
  assert.equal(write.method, "POST");
  assert.equal(write.path, "/repos/o/r/issues/42/comments");
  assert.ok(write.body.body.startsWith(`${MARKER}\n`));
  assert.match(write.body.body, /\| GET \| \/repos\/\{repo\}\/pulls\/&#42; \| 502 \|/);
});

test("a rerun of the same run edits its comment", async () => {
  const api = fakeGitHub([{ id: 5, user: BOT, body: `${MARKER}\nold` }]);
  assert.equal((await run({}, api.github)).code, 0);
  assert.deepEqual(
    api.writes().map((c) => [c.method, c.path]),
    [["PATCH", "/repos/o/r/issues/comments/5"]],
  );
});

test("no pull request, or a bad lane, activity, run id or repository, makes no call", async () => {
  for (const env of [{ PULL: "" }, { PULL: "0" }, { LANE: "Read" }, { ACTIVITY: "a b" }, { RUN_ID: "x" }, { REPOSITORY: "o" }]) {
    const api = fakeGitHub();
    assert.equal((await run(env, api.github)).code, 0, JSON.stringify(env));
    assert.deepEqual(api.calls, [], JSON.stringify(env));
  }
});

test("a posting failure warns and does not fail the step", async () => {
  const api = fakeGitHub([], { fail: true });
  const out = await run({}, api.github);
  assert.equal(out.code, 0);
  assert.ok(out.lines.some((line) => line.startsWith("::warning::could not post")));
});

test("a path renders as a template: known words stay, the repository is {repo}, anything else is *", () => {
  assert.equal(templatePath("/repos/a/b/issues/123/comments"), "/repos/{repo}/issues/*/comments");
  assert.equal(templatePath("/repos/o/r/git/refs/heads/my_branch"), "/repos/{repo}/git/refs/heads/*");
  assert.equal(templatePath("/repos/o/r/commits/abc123/check-runs"), "/repos/{repo}/commits/*/check-runs");
  assert.equal(templatePath("/graphql"), "/graphql");
  assert.equal(templatePath("/repos/o"), "/repos/*");
  assert.equal(templatePath("/api/v3/repos/o/r/pulls/7"), "/api/v3/repos/{repo}/pulls/*");
});

test("planted text never reaches the comment", () => {
  const key = "sk-ant-api03-AAAABBBBCCCCDDDD";
  assert.equal(templatePath(`/repos/o/r/issues/${key}`), "/repos/{repo}/issues/*");
  assert.equal(templatePath(`/${key}/pulls`), "/*/pulls");
  const rows = Array.from({ length: 4 }, (_, i) => ({ method: "GET", path: `/repos/o/r/${key}${i}`, status: 404 }));
  const body = render({ lane: "read", activity: "fix-ci", runId: "1", runResult: "success", actOutcome: "success", readLane: true, failures: failureRows(JSON.stringify({ rows, dropped: 0 })) });
  assert.doesNotMatch(body, /sk-ant|AAAA/);
});

test("rows that template alike fold into one before the cap", () => {
  const rows = Array.from({ length: MAX_ROWS + 20 }, (_, i) => ({ method: "GET", path: `/repos/o/r/pulls/${i}`, status: 500 }));
  rows.push({ method: "GET", path: "/repos/o/r/issues/1", status: 500 });
  const out = failureRows(JSON.stringify({ rows, dropped: 0 }));
  assert.deepEqual(out.rows, [
    { method: "GET", path: "/repos/{repo}/pulls/*", status: 500 },
    { method: "GET", path: "/repos/{repo}/issues/*", status: 500 },
  ]);
  assert.equal(out.dropped, MAX_ROWS + 19);
});
