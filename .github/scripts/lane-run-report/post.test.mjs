// test-scope: .github/workflows/*.yml
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { test } from "node:test";
import { SIGNALS } from "../../actions/log-api-budget/rate-guard.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { prMessages } from "../lib/pr-messages/pr-messages.mjs";
import { memoryStore } from "../lib/pr-messages/stores.mjs";
import {
  escapeCell,
  failureRows,
  MAX_BODY,
  MAX_ROWS,
  MAX_WAIT_SECONDS,
  main,
  parseSection,
  renderSection,
  reportOf,
  secondaryWait,
  templatePath,
} from "./post.mjs";

const BOT = "github-actions[bot]";
const ENV = {
  LANE: "read",
  ACTIVITY: "fix-ci",
  RUN_ID: "123",
  GITHUB_RUN_ATTEMPT: "1",
  PULL: "42",
  REPOSITORY: "o/r",
  GITHUB_SERVER_URL: "https://github.com",
  RUN_RESULT: "failure",
  ACT_OUTCOME: "success",
  READ_LANE: "true",
  API_FAILURES: JSON.stringify({
    rows: [{ method: "GET", path: "/repos/o/r/pulls/42", status: 502 }],
    dropped: 0,
  }),
};
const MARKER = "<!-- lane-run-report run=123 -->";
const OLD_MARKER = "<!-- lane-run-report activity=read/fix-ci -->";
const heading = (attempt, rung, leg, activity = "read/fix-ci") => `<!-- lane-run-report-section activity=${activity} attempt=${attempt} rung=${rung} leg=${leg} -->`;
const headings = (body) => body.split("\n").filter((line) => line.startsWith("<!-- lane-run-report-section "));
const current = (store) => prMessages({ store, repo: "o/r", number: 42 }).read("lane-run-report", { run: "123" });

async function run(env, deps = {}) {
  const lines = [];
  const waits = [];
  const original = console.log;
  console.log = (line) => lines.push(line);
  try {
    const code = await main({ ...ENV, ...env }, { sleep: async (ms) => waits.push(ms), ...deps });
    return { code, lines, waits };
  } finally {
    console.log = original;
  }
}

const page = (nodes) => ({ data: { repository: { pullRequest: { comments: { pageInfo: { hasNextPage: false, endCursor: null }, nodes } } } } });

function fakeGitHub(nodes = [], { fail = false } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (fail) throw new Error("boom");
    if (path === "/graphql") return page(nodes);
    return method === "POST" ? { id: 77 } : {};
  };
  return { github, calls, writes: () => calls.filter((c) => c.path !== "/graphql") };
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
  const rows = Array.from({ length: MAX_ROWS + 7 }, (_, i) => ({
    method: "GET",
    path: "/repos/o/r/pulls",
    status: 400 + i,
  }));
  const out = failureRows(JSON.stringify({ rows, dropped: 0 }));
  assert.equal(out.rows.length, MAX_ROWS);
  assert.equal(out.dropped, 7);
});

test("an empty, unparsable or wrongly shaped carry is no rows", () => {
  for (const text of [
    undefined,
    "",
    "{",
    "[]",
    "null",
    JSON.stringify({ rows: "x", dropped: -1 }),
  ]) {
    assert.deepEqual(failureRows(text).rows, [], String(text));
  }
  assert.equal(
    failureRows(JSON.stringify({ rows: [], dropped: "9" })).dropped,
    0,
  );
});

test("a cell is escaped for markdown and HTML", () => {
  assert.equal(
    escapeCell("a|b<c>&`*_[x](y)"),
    "a&#124;b&lt;c&gt;&amp;&#96;&#42;&#95;&#91;x&#93;(y)",
  );
});

const report = (more = {}) =>
  reportOf({ activity: "read/fix-ci", attempt: "1", rung: "0", leg: "base", runResult: "success", actOutcome: "success", readLane: true, failures: { rows: [], dropped: 0 }, ...more });

test("a section opens with its marker and lists the rung, leg, outcome, commits and failures", () => {
  const text = renderSection(
    report({
      rung: "1",
      leg: "handoff",
      actOutcome: "failure",
      commit: "a".repeat(40),
      readLane: false,
      failures: failureRows(JSON.stringify({ rows: [{ method: "PATCH", path: "/repos/o/r/git/refs/heads/my_branch", status: 422 }], dropped: 2 })),
    }),
  );
  assert.ok(text.startsWith(`${heading(1, 1, "handoff")}\n`));
  assert.match(text, /\| Model rung \| 1 \|/);
  assert.match(text, /\| Leg \| handoff \|/);
  assert.match(text, /\| Run job \| success \|/);
  assert.match(text, /\| Activity step \| failure \|/);
  assert.match(text, new RegExp(`\\| Commits pushed \\| ${"a".repeat(40)} \\|`));
  assert.match(text, /^### read\/fix-ci, attempt 1$/m);
  assert.match(text, /\| PATCH \| \/repos\/\{repo\}\/git\/refs\/heads\/&#42; \| 422 \|/);
  assert.match(text, /more rows not shown/i);
  assert.doesNotMatch(text, /\b2 more/);
});

test("a read lane pushes no commits, and a run with no failures says so", () => {
  const text = renderSection(report());
  assert.match(text, /\| Commits pushed \| none \(read lane\) \|/);
  assert.match(text, /No failed call recorded by the run job's scripts\./);
});

const TAG_MISS = { method: "GET", path: "/repos/o/r/git/ref/tags/main", status: 404 };
const reportWith = (rows) => renderSection(report({ failures: failureRows(JSON.stringify({ rows, dropped: 0 })) }));

test("a run whose only failed call is a tag-ref 404 reports no failed call", () => {
  const body = reportWith([TAG_MISS, { ...TAG_MISS, path: "/repos/o/r/git/ref/tags/release/v1" }]);
  assert.match(body, /No failed call recorded by the run job's scripts\./);
  assert.doesNotMatch(body, /More rows not shown/);
  assert.deepEqual(failureRows(JSON.stringify({ rows: [TAG_MISS], dropped: 0 })), { rows: [], dropped: 0 });
});

test("a 404 on another path, a non-404 status or a non-GET method on a tag ref is still listed", () => {
  const listed = [
    { method: "GET", path: "/repos/o/r/git/ref/heads/main", status: 404 },
    { ...TAG_MISS, status: 500 },
    { ...TAG_MISS, method: "PATCH" },
  ];
  assert.deepEqual(failureRows(JSON.stringify({ rows: listed, dropped: 0 })), {
    rows: [
      { method: "GET", path: "/repos/{repo}/git/ref/heads/*", status: 404 },
      { method: "GET", path: "/repos/{repo}/git/ref/tags/*", status: 500 },
      { method: "PATCH", path: "/repos/{repo}/git/ref/tags/*", status: 404 },
    ],
    dropped: 0,
  });
});

test("a tag-ref 404 beside a real failure leaves only the real failure in the table", () => {
  const body = reportWith([TAG_MISS, { method: "GET", path: "/repos/o/r/pulls/42", status: 502 }]);
  assert.match(body, /\| GET \| \/repos\/\{repo\}\/pulls\/&#42; \| 502 \|/);
  assert.doesNotMatch(body, /tags/);
  assert.doesNotMatch(body, /More rows not shown/);
});

test("a forged outcome or commit renders as unknown or none, never as given", () => {
  const body = renderSection(report({ runResult: "neutral", actOutcome: "pwned", commit: "zz", readLane: false }));
  assert.match(body, /\| Run job \| unknown \|/);
  assert.match(body, /\| Activity step \| unknown \|/);
  assert.match(body, /\| Commits pushed \| none recorded \|/);
});

test("a section parsed back from its text renders the same", () => {
  const original = report({
    readLane: false,
    commit: "b".repeat(40),
    actOutcome: "failure",
    failures: failureRows(
      JSON.stringify({
        rows: [
          { method: "GET", path: "/repos/o/r/pulls/42", status: 502 },
          { method: "POST", path: "/graphql", status: 0 },
          { method: "PATCH", path: "/repos/o/r/git/refs/heads/my_branch", status: 422 },
        ],
        dropped: 1,
      }),
    ),
  });
  const text = renderSection(original);
  const [head, ...rest] = text.split("\n");
  assert.equal(head, heading(1, 0, "base"));
  const parsed = parseSection({ fields: original.fields, text: rest.join("\n") });
  assert.equal(renderSection(parsed), text);
});

test("main posts the report on the pull request after one GraphQL list", async () => {
  const api = fakeGitHub([{ fullDatabaseId: "1", author: { __typename: "User", login: "someone" }, editor: null, body: `${MARKER}\nquoted`, createdAt: "2026-11-21T00:00:00Z", lastEditedAt: null, isMinimized: false }]);
  const out = await run({}, { github: api.github });
  assert.equal(out.code, 0);
  assert.deepEqual(
    api.calls.map((c) => [c.method, c.path]),
    [
      ["POST", "/graphql"],
      ["POST", "/repos/o/r/issues/42/comments"],
    ],
  );
  const body = api.writes()[0].body.body;
  assert.ok(body.startsWith(`${MARKER}\n`));
  assert.deepEqual(headings(body), [heading(1, 0, "base")]);
  assert.match(body, /\| Run \| \[123\]\(https:\/\/github\.com\/o\/r\/actions\/runs\/123\) \|/);
  assert.match(body, /\| GET \| \/repos\/\{repo\}\/pulls\/&#42; \| 502 \|/);
  assert.ok(out.lines.includes("::notice::posted the lane run report on #42"));
});

const CLEAN = { RUN_RESULT: "success", ACT_OUTCOME: "success", API_FAILURES: JSON.stringify({ rows: [], dropped: 0 }) };

test("a clean run writes its report to the job summary and makes no call", async () => {
  const summary = join(tempDir("lane-run-report-summary-"), "summary.md");
  writeFileSync(summary, "");
  const api = fakeGitHub();
  const out = await run({ ...CLEAN, GITHUB_STEP_SUMMARY: summary }, { github: api.github });
  assert.equal(out.code, 0);
  assert.deepEqual(api.calls, []);
  assert.deepEqual(headings(readFileSync(summary, "utf8")), [heading(1, 0, "base")]);
  assert.ok(out.lines.includes("::notice::read/fix-ci succeeded with no failed GitHub API call, so no lane run report comment is posted; the report is in this job's summary"));
});

test("a run whose step failed, or that recorded only a failed or dropped API call, posts its report", async () => {
  for (const env of [
    { ACT_OUTCOME: "failure" },
    { RUN_RESULT: "cancelled" },
    { API_FAILURES: ENV.API_FAILURES },
    { API_FAILURES: JSON.stringify({ rows: [], dropped: 3 }) },
  ]) {
    const store = memoryStore();
    await run({ ...CLEAN, ...env }, { store });
    assert.equal(store.comments.length, 1, JSON.stringify(env));
  }
});

test("a designed skip of the run job or its activity step posts no comment", async () => {
  for (const env of [{ ACT_OUTCOME: "skipped" }, { RUN_RESULT: "skipped", ACT_OUTCOME: "skipped" }]) {
    const store = memoryStore();
    await run({ ...CLEAN, ...env }, { store });
    assert.equal(store.comments.length, 0, JSON.stringify(env));
  }
});

test("every activity of one run shares one comment, and another run gets its own", async () => {
  const store = memoryStore();
  await run({}, { store });
  await run({ LANE: "pr-unblock", ACTIVITY: "apply-patch" }, { store });
  await run({ RUN_ID: "124" }, { store });
  assert.equal(store.comments.length, 2);
  assert.deepEqual(headings(store.comments[0].body), [heading(1, 0, "base"), heading(1, 0, "base", "pr-unblock/apply-patch")]);
  assert.ok(store.comments[1].body.startsWith("<!-- lane-run-report run=124 -->\n"));
});

test("every leg and every same-activity call of one run keeps its own section", async () => {
  const store = memoryStore();
  await run({}, { store });
  await run({ LEG: "handoff" }, { store });
  await run({ MODEL_RUNG: "1" }, { store });
  await run({}, { store });
  assert.equal(store.comments.length, 1);
  assert.deepEqual(headings(store.comments[0].body), [heading(1, 0, "base"), heading(1, 0, "handoff"), heading(1, 1, "base"), heading(1, 0, "base")]);
});

test("a re-run attempt replaces the newest earlier-attempt section of its rung and leg", async () => {
  const store = memoryStore();
  await run({}, { store });
  await run({ LEG: "handoff" }, { store });
  await run({}, { store });
  await run({ GITHUB_RUN_ATTEMPT: "2" }, { store });
  assert.deepEqual(headings(store.comments[0].body), [heading(1, 0, "base"), heading(1, 0, "handoff"), heading(2, 0, "base")]);
  await run({ GITHUB_RUN_ATTEMPT: "2" }, { store });
  assert.deepEqual(headings(store.comments[0].body), [heading(2, 0, "base"), heading(1, 0, "handoff"), heading(2, 0, "base")]);
});

test("a person-edited comment, then two more report jobs, leaves exactly one current bot comment", async () => {
  const edited = `${MARKER}\n${heading(1, 0, "base")}\nmy note`;
  const store = memoryStore({
    comments: [{ id: 1, author: BOT, body: edited, createdAt: "2026-11-21T00:00:00Z", lastEditedAt: "2026-11-21T00:01:00Z", editor: "octocat", isMinimized: false }],
  });
  await run({}, { store });
  await run({ LEG: "handoff" }, { store });
  assert.equal(store.comments.length, 2);
  assert.equal(store.comments[0].body, edited);
  const own = await current(store);
  assert.equal(own.id, 2);
  assert.deepEqual(
    own.sections.map((s) => s.fields.leg),
    ["base", "handoff"],
  );
});

test("an old per-activity comment is ignored and left as it is", async () => {
  const old = { id: 1, author: BOT, body: `${OLD_MARKER}\nold`, createdAt: "2026-11-21T00:00:00Z", lastEditedAt: null, editor: null, isMinimized: false };
  const store = memoryStore({ comments: [{ ...old }] });
  await run({}, { store });
  assert.deepEqual(store.comments[0], old);
  assert.equal(store.comments.length, 2);
  assert.ok(store.comments[1].body.startsWith(`${MARKER}\n`));
});

test("planted text in a kept section is not carried forward", async () => {
  const planted = [
    MARKER,
    heading(1, 0, "base"),
    "| Run job | pwned |",
    "| Activity step | success |",
    "| Commits pushed | [click](https://example.com) |",
    "[click me](https://example.com/sk-ant-AAAA)",
    "| GET | /repos/{repo}/sk-ant-AAAA | 500 |",
    "| GET | /repos/{repo}/pulls/&#42; | 007 |",
    "| GET | /repos/{repo}/pulls/&#42; | 404 |",
    "",
  ].join("\n");
  const store = memoryStore({ comments: [{ id: 1, author: BOT, body: planted, createdAt: "2026-11-21T00:00:00Z", lastEditedAt: null, editor: null, isMinimized: false }] });
  await run({ LEG: "handoff" }, { store });
  const body = store.comments[0].body;
  assert.equal(store.comments.length, 1);
  assert.deepEqual(headings(body), [heading(1, 0, "base"), heading(1, 0, "handoff")]);
  assert.doesNotMatch(body, /sk-ant|example\.com|pwned|007/);
  const [kept] = body.split(heading(1, 0, "handoff"));
  assert.match(kept, /\| Run job \| unknown \|/);
  assert.match(kept, /\| Commits pushed \| none recorded \|/);
  assert.match(kept, /\| GET \| \/repos\/\{repo\}\/pulls\/&#42; \| 404 \|/);
  assert.match(kept, /More rows not shown/);
});

test("a body past 60,000 characters drops the oldest sections' rows, then the oldest sections, and says how many", async () => {
  const rows = Array.from({ length: MAX_ROWS }, (_, i) => ({ method: "GET", path: "/repos/o/r/pulls/1", status: 400 + i }));
  const store = memoryStore();
  const reports = 130;
  for (let i = 0; i < reports; i++) await run({ API_FAILURES: JSON.stringify({ rows, dropped: 0 }) }, { store });
  const body = store.comments[0].body;
  assert.equal(store.comments.length, 1);
  const size = body.length - MARKER.length - 1;
  assert.ok(size <= MAX_BODY && size > MAX_BODY - 3000, String(size));
  const note = /^Not shown, to keep this comment under 60,000 characters: ([0-9]+) failure rows and ([0-9]+) sections\.$/m.exec(body);
  assert.ok(note, "the trim note");
  const [rowsCut, sectionsCut] = [Number(note[1]), Number(note[2])];
  assert.ok(sectionsCut > 0, "sections were dropped");
  assert.equal(headings(body).length + sectionsCut, reports);
  assert.equal(rowsCut, (reports - 1) * MAX_ROWS);
  const sections = body.split(/^(?=<!-- lane-run-report-section )/m).slice(1);
  assert.match(sections.at(-1), /\| GET \| \/repos\/\{repo\}\/pulls\/&#42; \| 449 \|/);
  for (const kept of sections.slice(0, -1)) {
    assert.doesNotMatch(kept, /\| GET \|/);
    assert.match(kept, /More rows not shown/);
  }
});

test("a newer run's comment carries no trim note from an older run", async () => {
  const rows = Array.from({ length: MAX_ROWS }, (_, i) => ({ method: "GET", path: "/repos/o/r/pulls/1", status: 400 + i }));
  const store = memoryStore();
  for (let i = 0; i < 30; i++) await run({ API_FAILURES: JSON.stringify({ rows, dropped: 0 }) }, { store });
  assert.match(store.comments[0].body, /^Not shown/m);
  await run({ RUN_ID: "124" }, { store });
  assert.doesNotMatch(store.comments[1].body, /Not shown/);
});

test("a list past its time limit falls back to the job summary without a write", async () => {
  const summary = join(tempDir("lane-run-report-summary-"), "summary.md");
  writeFileSync(summary, "");
  const calls = [];
  const github = (method, path, body, headers, options) => {
    calls.push(path);
    return new Promise((_, reject) => options.signal.addEventListener("abort", () => reject(options.signal.reason)));
  };
  const out = await run({ GITHUB_STEP_SUMMARY: summary }, { github, listTimeoutMs: 20 });
  assert.equal(out.code, 0);
  assert.deepEqual(calls, ["/graphql"]);
  assert.deepEqual(out.waits, []);
  assert.ok(out.lines.some((line) => line.startsWith("::warning::could not post")));
  assert.deepEqual(headings(readFileSync(summary, "utf8")), [heading(1, 0, "base")]);
});

test("no pull request, or a bad lane, activity, run id, attempt, rung, leg or repository, makes no call", async () => {
  for (const env of [
    { PULL: "" },
    { PULL: "0" },
    { LANE: "Read" },
    { ACTIVITY: "a b" },
    { RUN_ID: "x" },
    { GITHUB_RUN_ATTEMPT: "" },
    { GITHUB_RUN_ATTEMPT: "0" },
    { MODEL_RUNG: "2" },
    { LEG: "base" },
    { LEG: "Fallback" },
    { LEG: "x -->" },
    { REPOSITORY: "o" },
  ]) {
    const api = fakeGitHub();
    assert.equal((await run(env, { github: api.github })).code, 0, JSON.stringify(env));
    assert.deepEqual(api.calls, [], JSON.stringify(env));
  }
});

test("each runner leg and model rung renders as its own section", async () => {
  const store = memoryStore();
  for (const LEG of ["", "handoff", "credit-stop", "no-key", "fallback"]) await run({ LEG }, { store });
  await run({ MODEL_RUNG: "" }, { store });
  await run({ MODEL_RUNG: "1" }, { store });
  assert.deepEqual(
    headings(store.comments[0].body),
    [...["base", "handoff", "credit-stop", "no-key", "fallback", "base"].map((leg) => heading(1, 0, leg)), heading(1, 1, "base")],
  );
});

test("a posting failure warns and does not fail the step", async () => {
  const api = fakeGitHub([], { fail: true });
  const out = await run({}, { github: api.github });
  assert.equal(out.code, 0);
  assert.ok(out.lines.some((line) => line.startsWith("::warning::could not post")));
});

const refusal = (status, detail) =>
  Object.assign(new Error(`POST /repos/o/r/issues/42/comments failed with status ${status}`), { status, detail });

test("a refused post names GitHub's answer and writes the report to the job summary", async () => {
  const summary = join(tempDir("lane-run-report-summary-"), "summary.md");
  writeFileSync(summary, "");
  const detail = 'status=403 x-ratelimit-remaining=2575 x-ratelimit-reset=1 x-ratelimit-resource=core body="{\\"message\\":\\"Resource not accessible by integration\\"}"';
  const github = async (method, path) => {
    if (path === "/graphql") return page([]);
    throw refusal(403, detail);
  };
  const out = await run({ GITHUB_STEP_SUMMARY: summary }, { github });
  assert.equal(out.code, 0);
  assert.deepEqual(out.waits, []);
  const warning = out.lines.find((line) => line.startsWith("::warning::could not post"));
  assert.ok(warning.endsWith(`status 403 [${detail}]; the report is in this job's summary`), warning);
  assert.deepEqual(headings(readFileSync(summary, "utf8")), [heading(1, 0, "base")]);
});

test("a secondary rate limit on the list is retried once, list and write together, after its retry-after", async () => {
  const calls = [];
  const github = async (method, path) => {
    calls.push(path);
    if (calls.length === 1) throw refusal(403, 'status=403 x-ratelimit-remaining=4000 x-ratelimit-reset=1 x-ratelimit-resource=core retry-after=7 body="{}"');
    return path === "/graphql" ? page([]) : { id: 5 };
  };
  const out = await run({}, { github });
  assert.equal(out.code, 0);
  assert.deepEqual(out.waits, [7000]);
  assert.deepEqual(calls, ["/graphql", "/graphql", "/repos/o/r/issues/42/comments"]);
  assert.ok(out.lines.includes("::notice::posted the lane run report on #42"));
});

test("a secondary limit named only in the body waits the default, and a second refusal goes to the summary", async () => {
  const summary = join(tempDir("lane-run-report-summary-"), "summary.md");
  writeFileSync(summary, "");
  let calls = 0;
  const github = async (method, path) => {
    if (path === "/graphql") return page([]);
    calls += 1;
    throw refusal(429, 'status=429 x-ratelimit-remaining=4000 x-ratelimit-reset=1 x-ratelimit-resource=core body="You have exceeded a secondary rate limit"');
  };
  const out = await run({ GITHUB_STEP_SUMMARY: summary }, { github });
  assert.equal(out.code, 0);
  assert.equal(calls, 2);
  assert.deepEqual(out.waits, [SIGNALS.fallbackSeconds * 1000]);
  assert.deepEqual(headings(readFileSync(summary, "utf8")), [heading(1, 0, "base")]);
});

test("secondaryWait leaves a primary limit, other statuses, an unexplained 403 and a retry-after past the cap alone", () => {
  assert.equal(secondaryWait(refusal(403, "status=403 x-ratelimit-remaining=0 x-ratelimit-reset=1 x-ratelimit-resource=core retry-after=5 body=\"\"")), undefined);
  assert.equal(secondaryWait(refusal(404, "status=404 retry-after=5")), undefined);
  assert.equal(secondaryWait(refusal(403, 'status=403 x-ratelimit-remaining=9 body="Resource not accessible by integration"')), undefined);
  assert.equal(secondaryWait(new Error("boom")), undefined);
  assert.equal(secondaryWait(refusal(429, "status=429 x-ratelimit-remaining=9 retry-after=9999")), undefined);
  assert.equal(secondaryWait(refusal(429, `status=429 x-ratelimit-remaining=9 retry-after=${MAX_WAIT_SECONDS}`)), MAX_WAIT_SECONDS);
  assert.equal(secondaryWait(refusal(403, 'status=403 x-ratelimit-remaining=9 body="abuse detection mechanism"')), SIGNALS.fallbackSeconds);
});

test("a path renders as a template: known words stay, the repository is {repo}, anything else is *", () => {
  assert.equal(
    templatePath("/repos/a/b/issues/123/comments"),
    "/repos/{repo}/issues/*/comments",
  );
  assert.equal(
    templatePath("/repos/o/r/git/refs/heads/my_branch"),
    "/repos/{repo}/git/refs/heads/*",
  );
  assert.equal(
    templatePath("/repos/o/r/commits/abc123/check-runs"),
    "/repos/{repo}/commits/*/check-runs",
  );
  assert.equal(templatePath("/graphql"), "/graphql");
  assert.equal(templatePath("/repos/o"), "/repos/*");
  assert.equal(
    templatePath("/api/v3/repos/o/r/pulls/7"),
    "/api/v3/repos/{repo}/pulls/*",
  );
});

test("planted text never reaches the comment", () => {
  const key = "sk-ant-" + "api03-AAAABBBBCCCCDDDD";
  assert.equal(
    templatePath(`/repos/o/r/issues/${key}`),
    "/repos/{repo}/issues/*",
  );
  assert.equal(templatePath(`/${key}/pulls`), "/*/pulls");
  const rows = Array.from({ length: 4 }, (_, i) => ({
    method: "GET",
    path: `/repos/o/r/${key}${i}`,
    status: 404,
  }));
  const body = reportWith(rows);
  assert.doesNotMatch(body, /sk-ant|AAAA/);
});

test("rows that template alike fold into one before the cap", () => {
  const rows = Array.from({ length: MAX_ROWS + 20 }, (_, i) => ({
    method: "GET",
    path: `/repos/o/r/pulls/${i}`,
    status: 500,
  }));
  rows.push({ method: "GET", path: "/repos/o/r/issues/1", status: 500 });
  const out = failureRows(JSON.stringify({ rows, dropped: 0 }));
  assert.deepEqual(out.rows, [
    { method: "GET", path: "/repos/{repo}/pulls/*", status: 500 },
    { method: "GET", path: "/repos/{repo}/issues/*", status: 500 },
  ]);
  assert.equal(out.dropped, MAX_ROWS + 19);
});

const CARRY = "Carry the failed API calls to the report job";
function carryScript(name) {
  const text = readFileSync(
    new URL(`../../workflows/${name}`, import.meta.url),
    "utf8",
  );
  const step = text.slice(text.indexOf(`- name: ${CARRY}\n`));
  const block = /\n {8}run: \|\n((?: {10}.*\n|\n)+)/.exec(step);
  assert.ok(block, `${name}: the carry step's run block`);
  return block[1].replace(/^ {10}/gm, "");
}

test("both run jobs carry the failed API calls with one script", () => {
  assert.equal(
    carryScript("pr-run-activity-read.yml"),
    carryScript("pr-run-activity-write.yml"),
  );
});

function jobsOf(name) {
  const text = readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8");
  const body = text.slice(text.search(/^jobs:\n/m));
  return body.split(/^(?= {2}[A-Za-z0-9_-]+:\s*$)/m).slice(1).map((block) => {
    const perms = /\n {4}permissions:\s*\n((?: {6}.*\n)+)/.exec(block);
    const permissions = Object.fromEntries(
      [...(perms?.[1] ?? "").matchAll(/^ {6}([a-z-]+):\s*([a-z]+)/gm)].map((m) => [m[1], m[2]]),
    );
    return { name: /^ {2}([A-Za-z0-9_-]+):/.exec(block)[1], block, permissions };
  });
}

for (const runner of ["pr-run-activity-read.yml", "pr-run-activity-write.yml"]) {
  test(`${runner}: only the job posting the lane run report holds pull-requests: write`, () => {
    const jobs = jobsOf(runner);
    const posting = jobs.filter((job) => job.block.includes("lane-run-report/post.mjs")).map((job) => job.name);
    assert.deepEqual(posting, ["report"]);
    const writers = jobs.filter((job) => job.permissions["pull-requests"] === "write").map((job) => job.name);
    assert.deepEqual(writers, ["report"]);
  });
}

test("every job calling a runner grants pull-requests: write", () => {
  const callers = [];
  for (const file of readdirSync(new URL("../../workflows/", import.meta.url)).filter((f) => /\.ya?ml$/.test(f))) {
    for (const job of jobsOf(file)) {
      if (!/^ {4}uses: \.\/\.github\/workflows\/pr-run-activity-(read|write)\.yml/m.test(job.block)) continue;
      callers.push(job.name);
      assert.equal(job.permissions["pull-requests"], "write", `${file} job ${job.name}`);
    }
  }
  assert.ok(callers.length > 0, "no job calls either runner");
});

test("a different failure after 60 distinct-id 404s reaches the report", () => {
  const dir = tempDir("lane-run-report-carry-");
  const failures = join(dir, "api-failures.jsonl");
  const output = join(dir, "output");
  const lines = Array.from({ length: 60 }, (_, i) =>
    JSON.stringify({
      method: "GET",
      path: `/repos/o/r/pulls/${i + 1}`,
      status: 404,
    }),
  );
  lines.push(
    JSON.stringify({ method: "GET", path: "/repos/o/r/git/refs", status: 403 }),
  );
  writeFileSync(failures, `${lines.join("\n")}\n`);
  writeFileSync(output, "");
  const run = spawnSync(
    "bash",
    ["-e", "-c", carryScript("pr-run-activity-read.yml")],
    {
      env: { ...process.env, FAILURES: failures, GITHUB_OUTPUT: output },
      encoding: "utf8",
    },
  );
  assert.equal(run.status, 0, run.stderr);
  const carried = /^api-failures=(.*)$/m.exec(readFileSync(output, "utf8"))[1];
  assert.deepEqual(failureRows(carried), {
    rows: [
      { method: "GET", path: "/repos/{repo}/pulls/*", status: 404 },
      { method: "GET", path: "/repos/{repo}/git/refs", status: 403 },
    ],
    dropped: 59,
  });
});
