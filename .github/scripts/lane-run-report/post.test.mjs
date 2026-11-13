// post.mjs: the lane run report comment, its rows checked again here because
// the run job that carried them shared RUNNER_TEMP with the model.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { test } from "node:test";
import { SIGNALS } from "../../actions/log-api-budget/rate-guard.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";
import {
  escapeCell,
  failureRows,
  MAX_ROWS,
  MAX_WAIT_SECONDS,
  main,
  marker,
  render,
  secondaryWait,
  templatePath,
} from "./post.mjs";

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
  API_FAILURES: JSON.stringify({
    rows: [{ method: "GET", path: "/repos/o/r/pulls/42", status: 502 }],
    dropped: 0,
  }),
};
const MARKER =
  "<!-- lane-run-report activity=read/fix-ci run=123 rung=0 leg=base -->";

function fakeGitHub(comments = [], { fail = false } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (fail) throw new Error("boom");
    return method === "GET" ? comments : {};
  };
  return {
    github,
    calls,
    writes: () => calls.filter((c) => c.method !== "GET"),
  };
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
    failures: failureRows(
      JSON.stringify({
        rows: [
          {
            method: "PATCH",
            path: "/repos/o/r/git/refs/heads/my_branch",
            status: 422,
          },
        ],
        dropped: 2,
      }),
    ),
  });
  assert.ok(
    body.startsWith(
      "<!-- lane-run-report activity=write/fix-docs run=9 rung=0 leg=base -->\n",
    ),
  );
  assert.match(body, /\| Activity \| write\/fix-docs \|/);
  assert.match(body, /\| Run job \| success \|/);
  assert.match(body, /\| Activity step \| failure \|/);
  assert.match(
    body,
    new RegExp(`\\| Commits pushed \\| ${"a".repeat(40)} \\|`),
  );
  assert.match(
    body,
    /\| PATCH \| \/repos\/\{repo\}\/git\/refs\/heads\/&#42; \| 422 \|/,
  );
  assert.match(body, /more rows not shown/i);
  assert.doesNotMatch(body, /\b2 more/);
});

test("a read lane pushes no commits, and a run with no failures says so", () => {
  const body = render({
    lane: "read",
    activity: "fix-ci",
    runId: "1",
    runResult: "success",
    actOutcome: "success",
    readLane: true,
    failures: { rows: [], dropped: 0 },
  });
  assert.match(body, /\| Commits pushed \| none \(read lane\) \|/);
  assert.match(body, /No failed call recorded by the run job's scripts\./);
});

test("a forged outcome or commit renders as unknown or none, never as given", () => {
  const body = render({
    lane: "write",
    activity: "x",
    runId: "1",
    runResult: "neutral",
    actOutcome: "pwned",
    commit: "zz",
    readLane: false,
    failures: { rows: [], dropped: 0 },
  });
  assert.match(body, /\| Run job \| unknown \|/);
  assert.match(body, /\| Activity step \| unknown \|/);
  assert.match(body, /\| Commits pushed \| none recorded \|/);
});

test("main posts the report on the pull request", async () => {
  const api = fakeGitHub([
    { id: 1, user: { login: "someone" }, body: `${MARKER}\nquoted` },
  ]);
  const out = await run({}, api.github);
  assert.equal(out.code, 0);
  const [write] = api.writes();
  assert.equal(write.method, "POST");
  assert.equal(write.path, "/repos/o/r/issues/42/comments");
  assert.ok(write.body.body.startsWith(`${MARKER}\n`));
  assert.match(
    write.body.body,
    /\| GET \| \/repos\/\{repo\}\/pulls\/&#42; \| 502 \|/,
  );
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
  for (const env of [
    { PULL: "" },
    { PULL: "0" },
    { LANE: "Read" },
    { ACTIVITY: "a b" },
    { RUN_ID: "x" },
    { REPOSITORY: "o" },
  ]) {
    const api = fakeGitHub();
    assert.equal((await run(env, api.github)).code, 0, JSON.stringify(env));
    assert.deepEqual(api.calls, [], JSON.stringify(env));
  }
});

test("a posting failure warns and does not fail the step", async () => {
  const api = fakeGitHub([], { fail: true });
  const out = await run({}, api.github);
  assert.equal(out.code, 0);
  assert.ok(
    out.lines.some((line) => line.startsWith("::warning::could not post")),
  );
});

// A thrown GitHubError's shape: its status and responseDetail's line.
const refusal = (status, detail) =>
  Object.assign(new Error(`POST /repos/o/r/issues/42/comments failed with status ${status}`), { status, detail });

async function runWith(env, github) {
  const lines = [];
  const waits = [];
  const original = console.log;
  console.log = (line) => lines.push(line);
  try {
    const code = await main({ ...ENV, GITHUB_RUN_ATTEMPT: "1", ...env }, { github, sleep: async (ms) => waits.push(ms) });
    return { code, lines, waits };
  } finally {
    console.log = original;
  }
}

test("a refused post names GitHub's answer and writes the report to the job summary", async () => {
  const summary = join(tempDir("lane-run-report-summary-"), "summary.md");
  writeFileSync(summary, "");
  const detail = 'status=403 x-ratelimit-remaining=2575 x-ratelimit-reset=1 x-ratelimit-resource=core body="{\\"message\\":\\"Resource not accessible by integration\\"}"';
  const github = async () => {
    throw refusal(403, detail);
  };
  const out = await runWith({ GITHUB_STEP_SUMMARY: summary }, github);
  assert.equal(out.code, 0);
  assert.deepEqual(out.waits, []);
  const warning = out.lines.find((line) => line.startsWith("::warning::could not post"));
  assert.ok(warning.endsWith(`status 403 [${detail}]; the report is in this job's summary`), warning);
  assert.ok(readFileSync(summary, "utf8").startsWith(`${MARKER}\n`));
});

test("a secondary rate limit is retried once after its retry-after", async () => {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (calls.length === 1) throw refusal(403, 'status=403 x-ratelimit-remaining=4000 x-ratelimit-reset=1 x-ratelimit-resource=core retry-after=7 body="{}"');
    return {};
  };
  const out = await runWith({}, github);
  assert.equal(out.code, 0);
  assert.deepEqual(out.waits, [7000]);
  assert.equal(calls.length, 2);
  assert.ok(out.lines.some((line) => line === "::notice::posted the lane run report on #42"));
});

test("a secondary limit named only in the body waits the default, and a second refusal goes to the summary", async () => {
  const summary = join(tempDir("lane-run-report-summary-"), "summary.md");
  writeFileSync(summary, "");
  let calls = 0;
  const github = async () => {
    calls += 1;
    throw refusal(429, 'status=429 x-ratelimit-remaining=4000 x-ratelimit-reset=1 x-ratelimit-resource=core body="You have exceeded a secondary rate limit"');
  };
  const out = await runWith({ GITHUB_STEP_SUMMARY: summary }, github);
  assert.equal(out.code, 0);
  assert.equal(calls, 2);
  assert.deepEqual(out.waits, [SIGNALS.fallbackSeconds * 1000]);
  assert.ok(readFileSync(summary, "utf8").startsWith(`${MARKER}\n`));
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
  const key = "sk-ant-api03-AAAABBBBCCCCDDDD";
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
  const body = render({
    lane: "read",
    activity: "fix-ci",
    runId: "1",
    runResult: "success",
    actOutcome: "success",
    readLane: true,
    failures: failureRows(JSON.stringify({ rows, dropped: 0 })),
  });
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

test("each model rung of one run has its own marker; an unknown rung posts nothing", async () => {
  assert.equal(
    marker({ lane: "read", activity: "fix-ci", runId: "5", rung: "1" }),
    "<!-- lane-run-report activity=read/fix-ci run=5 rung=1 leg=base -->",
  );
  const rung0 = `${MARKER}\nold`;
  const api = fakeGitHub([{ id: 5, user: BOT, body: rung0 }]);
  assert.equal((await run({ MODEL_RUNG: "1" }, api.github)).code, 0);
  const [write] = api.writes();
  assert.equal(write.method, "POST");
  assert.ok(
    write.body.body.startsWith(
      "<!-- lane-run-report activity=read/fix-ci run=123 rung=1 leg=base -->\n",
    ),
  );
  const empty = fakeGitHub([{ id: 5, user: BOT, body: rung0 }]);
  await run({ MODEL_RUNG: "" }, empty.github);
  assert.deepEqual(
    empty.writes().map((c) => c.method),
    ["PATCH"],
  );
  const bad = fakeGitHub();
  assert.equal((await run({ MODEL_RUNG: "2" }, bad.github)).code, 0);
  assert.deepEqual(bad.calls, []);
});

test("a first attempt posts without listing comments; a re-run attempt lists them", async () => {
  const first = fakeGitHub();
  await run({ GITHUB_RUN_ATTEMPT: "1" }, first.github);
  assert.deepEqual(
    first.calls.map((c) => c.method),
    ["POST"],
  );
  const rerun = fakeGitHub([{ id: 5, user: BOT, body: `${MARKER}\nold` }]);
  await run({ GITHUB_RUN_ATTEMPT: "2" }, rerun.github);
  assert.deepEqual(
    rerun.calls.map((c) => c.method),
    ["GET", "PATCH"],
  );
});

test("each leg of one call has its own marker; an unknown leg posts nothing", async () => {
  assert.notEqual(
    marker({ lane: "read", activity: "fix-ci", runId: "5", leg: "base" }),
    marker({ lane: "read", activity: "fix-ci", runId: "5", leg: "handoff" }),
  );
  const legs = [];
  for (const LEG of ["", "handoff", "credit-stop", "no-key", "fallback"]) {
    const api = fakeGitHub();
    await run({ LEG, GITHUB_RUN_ATTEMPT: "1" }, api.github);
    legs.push(api.writes()[0].body.body.split("\n")[0]);
  }
  assert.deepEqual(
    legs,
    ["base", "handoff", "credit-stop", "no-key", "fallback"].map(
      (leg) =>
        `<!-- lane-run-report activity=read/fix-ci run=123 rung=0 leg=${leg} -->`,
    ),
  );
  const rerun = fakeGitHub([{ id: 5, user: BOT, body: `${MARKER}\nbase leg` }]);
  await run({ LEG: "fallback", GITHUB_RUN_ATTEMPT: "2" }, rerun.github);
  assert.deepEqual(
    rerun.writes().map((c) => c.method),
    ["POST"],
  );
  const own = fakeGitHub([
    {
      id: 6,
      user: BOT,
      body: `${marker({ lane: "read", activity: "fix-ci", runId: "123", leg: "fallback" })}\nold`,
    },
  ]);
  await run({ LEG: "fallback", GITHUB_RUN_ATTEMPT: "2" }, own.github);
  assert.deepEqual(
    own.calls.map((c) => c.method),
    ["GET", "PATCH"],
  );
  for (const LEG of ["base", "Fallback", "x -->"]) {
    const bad = fakeGitHub();
    const out = await run({ LEG }, bad.github);
    assert.equal(out.code, 0);
    assert.deepEqual(bad.calls, [], LEG);
    assert.ok(
      out.lines.some((line) => line.startsWith("::warning::")),
      LEG,
    );
  }
});

test("the model rung renders as its own row", async () => {
  for (const [MODEL_RUNG, shown] of [
    ["", "0"],
    ["0", "0"],
    ["1", "1"],
  ]) {
    const api = fakeGitHub();
    await run({ MODEL_RUNG, GITHUB_RUN_ATTEMPT: "1" }, api.github);
    assert.match(
      api.writes()[0].body.body,
      new RegExp(`\\| Model rung \\| ${shown} \\|`),
    );
  }
});

// The run job's carry step, as each run-activity workflow writes it.
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

// Each top-level job of a workflow: its name, text, and permissions map.
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

// GitHub refused the comment POST with issues: write alone (403 "Resource
// not accessible by integration"), so the posting job holds pull-requests:
// write, and no other runner job does: the run jobs hold the model.
for (const runner of ["pr-run-activity-read.yml", "pr-run-activity-write.yml"]) {
  test(`${runner}: only the job posting the lane run report holds pull-requests: write`, () => {
    const jobs = jobsOf(runner);
    const posting = jobs.filter((job) => job.block.includes("lane-run-report/post.mjs")).map((job) => job.name);
    assert.deepEqual(posting, ["report"]);
    const writers = jobs.filter((job) => job.permissions["pull-requests"] === "write").map((job) => job.name);
    assert.deepEqual(writers, ["report"]);
  });
}

// A called job holds no more than its caller grants, and a caller granting
// less fails the workflow at load.
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

// Many failures on distinct ids fold into one template in post.mjs, so the
// carry must not spend its rows on them before a later, different failure.
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
