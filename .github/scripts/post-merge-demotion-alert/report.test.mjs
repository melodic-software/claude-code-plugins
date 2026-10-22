// report() against a fake GitHub: hand-built runs, merges and issues, with
// the expected decision taken from the red-main rule (README.md, "Red main").
import assert from "node:assert/strict";
import { test } from "node:test";

import { report } from "./report.mjs";

const REPO = "melodic-software/claude-code-plugins";
const LANES = "melodic-automation-lanes[bot]";
const NOW = "2026-10-20T12:00:00Z";
const sha = (c) => c.repeat(40);
const BASE = sha("0");
const HEAD = sha("f");
const ENV = {
  REPOSITORY: REPO,
  RUN_ID: "500",
  RUN_SHA: HEAD,
  RUN_URL: `https://github.com/${REPO}/actions/runs/500`,
  RUN_WORKFLOW_ID: "77",
  RUN_CREATED: "2026-10-20T11:00:00Z",
};

const failedJob = (id, name) => ({ id, name, conclusion: "failure", steps: [{ name: "Run tests", conclusion: "failure" }] });

// A fake world: `merges` oldest first ({ sha, number, by, run }), where `run`
// is that merge's own full run ({ id, conclusion, attempts: [[jobs]...] }).
function world({ merges, head = { attempts: [[failedJob(1, "test-node")], [failedJob(2, "test-node")]] }, issues = [], comments = [], autoReverts = [], startAttempt }) {
  const writes = [];
  const runs = {
    500: { id: 500, head_sha: HEAD, run_attempt: head.attempts.length, status: "completed", conclusion: "failure", attempts: head.attempts },
  };
  const listed = [
    { id: 400, head_sha: BASE, head_branch: "main", event: "schedule", conclusion: "success", created_at: "2026-10-20T06:00:00Z", html_url: "base-run" },
  ];
  merges.forEach((m, i) => {
    if (m.run) {
      runs[m.run.id] = { ...m.run, head_sha: m.sha, run_attempt: m.run.attempts.length, status: "completed" };
      listed.push({
        id: m.run.id,
        head_sha: m.sha,
        head_branch: "main",
        event: "workflow_dispatch",
        conclusion: m.run.conclusion,
        run_attempt: m.run.attempts.length,
        status: "completed",
        created_at: `2026-10-20T0${7 + i}:00:00Z`,
        html_url: `run-${m.run.id}`,
      });
    }
  });
  let polls = 0;
  const call = async (method, path, body) => {
    if (method !== "GET") {
      writes.push({ method, path, body });
      return { number: 900 };
    }
    let m;
    if ((m = /^\/repos\/[^/]+\/[^/]+\/actions\/runs\/(\d+)$/.exec(path))) {
      const run = runs[m[1]];
      polls += 1;
      if (startAttempt && polls === 1) return { ...run, run_attempt: startAttempt, status: "completed" };
      return run;
    }
    if ((m = /\/actions\/runs\/(\d+)\/attempts\/(\d+)\/jobs/.exec(path))) {
      return { jobs: runs[m[1]].attempts[m[2] - 1] };
    }
    if ((m = /\/actions\/runs\/(\d+)\/attempts\/(\d+)$/.exec(path))) {
      return { conclusion: runs[m[1]].attempts.length > 1 || runs[m[1]].conclusion === "failure" ? "failure" : runs[m[1]].conclusion };
    }
    if (/\/check-runs\/\d+\/annotations/.test(path)) return [];
    if (/\/actions\/workflows\/77\/runs/.test(path)) return { workflow_runs: listed };
    if (path.includes(`/compare/${BASE}...${HEAD}`)) {
      let parent = BASE;
      return {
        commits: merges.map((x) => {
          const commit = { sha: x.sha, parents: [{ sha: parent }], commit: { message: x.message ?? `fix: change (#${x.number})`, committer: { date: "2026-10-20T09:00:00Z" } } };
          parent = x.sha;
          return commit;
        }),
      };
    }
    if ((m = /\/issues\/(\d+)\/timeline/.exec(path))) {
      const merge = merges.find((x) => String(x.number) === m[1]);
      return [{ event: "added_to_merge_queue", actor: { login: merge.by } }];
    }
    if ((m = /\/pulls\/(\d+)$/.exec(path))) {
      return { number: Number(m[1]), labels: [], merged_at: "2026-10-20T09:00:00Z" };
    }
    if (path.includes("labels=auto-revert")) return autoReverts;
    // `comments` is one list for every issue, or lists keyed by issue number.
    if ((m = /\/issues\/(\d+)\/comments/.exec(path))) return Array.isArray(comments) ? comments : (comments[m[1]] ?? []);
    if (path.includes("/issues?state=all&creator=")) return issues;
    throw new Error(`unexpected GET ${path}`);
  };
  return { call, writes };
}

const run = (env, w, over = {}) =>
  report(env, {
    call: w.call,
    sleep: async () => {},
    clock: () => NOW,
    loadConfig: () => ({ redMain: {}, agentIdentity: LANES }),
    revertApplies: () => true,
    ...over,
  });

const decisionOf = (body) => /decision=([a-z-]+) -->/.exec(body)?.[1];
const culpritOf = (body) => /culprit=([0-9a-f]{40}|none)/.exec(body)?.[1];

test("a single-merge range of a lane merge: the bot would auto-revert it, and only the log is written", async () => {
  const w = world({ merges: [{ sha: HEAD, number: 101, by: LANES }] });
  const result = await run(ENV, w);
  assert.equal(culpritOf(result.body), HEAD);
  assert.equal(decisionOf(result.body), "auto-revert");
  assert.deepEqual(
    w.writes.map((x) => `${x.method} ${x.path}`),
    [`POST /repos/${REPO}/issues`, `POST /repos/${REPO}/issues/900/comments`],
  );
  assert.match(result.body, /git revert --no-edit f{40}/);
});

test("an owner merge pinned as the culprit goes to a person, with a draft revert", async () => {
  const w = world({ merges: [{ sha: HEAD, number: 102, by: "kyle-sexton" }] });
  const result = await run(ENV, w);
  assert.equal(decisionOf(result.body), "human");
  assert.match(result.body, /The revert it would open \(draft\)/);
});

test("under fail-forward a pinned lane merge goes to a person and the report plans no revert", async () => {
  const w = world({ merges: [{ sha: HEAD, number: 101, by: LANES }] });
  const result = await run(ENV, w, { loadConfig: () => ({ redMain: { remedy: "fail-forward" }, agentIdentity: LANES }) });
  assert.equal(culpritOf(result.body), HEAD);
  assert.equal(decisionOf(result.body), "human");
  assert.match(result.body, /Culprit: `f{40}`/);
  assert.match(result.body, /fail-forward/);
  assert.doesNotMatch(result.body, /The revert it would open|git revert/);
});

const confirmedRed = (id) => ({ id, conclusion: "failure", attempts: [[failedJob(id * 10, "test-node")], [failedJob(id * 10 + 1, "test-node")]] });

test("a mixed range: a lane merge pinned as the culprit may auto-revert past an owner merge", async () => {
  const w = world({
    merges: [
      { sha: sha("a"), number: 201, by: LANES, run: confirmedRed(41) },
      { sha: sha("b"), number: 202, by: "kyle-sexton" },
      { sha: HEAD, number: 203, by: LANES },
    ],
  });
  const result = await run(ENV, w);
  assert.equal(culpritOf(result.body), sha("a"));
  assert.equal(decisionOf(result.body), "auto-revert");
});

test("a mixed range whose pinned culprit is the owner's merge goes to a person", async () => {
  const w = world({
    merges: [
      { sha: sha("a"), number: 201, by: "kyle-sexton", run: confirmedRed(41) },
      { sha: HEAD, number: 203, by: LANES },
    ],
  });
  assert.equal(decisionOf((await run(ENV, w)).body), "human");
});

test("a range with no evidence run at its oldest merge pins no culprit and opens no revert", async () => {
  const w = world({
    merges: [
      { sha: sha("a"), number: 201, by: LANES },
      { sha: HEAD, number: 203, by: LANES },
    ],
  });
  const result = await run(ENV, w);
  assert.equal(culpritOf(result.body), "none");
  assert.doesNotMatch(result.body, /The revert it would open/);
});

test("a re-run that passed is no confirmed red: nothing is written", async () => {
  const w = world({
    merges: [{ sha: HEAD, number: 101, by: LANES }],
    head: { attempts: [[failedJob(1, "test-node")], []] },
  });
  // The fake's run reads `failure`; the re-run attempt's conclusion is what decides.
  w.call = ((inner) => async (method, path, body) => {
    const value = await inner(method, path, body);
    return /\/actions\/runs\/500$/.test(path) ? { ...value, conclusion: "success" } : value;
  })(w.call);
  const result = await run(ENV, w);
  assert.equal(result.posted, false);
  assert.deepEqual(w.writes, []);
});

test("the job waits for the re-run a later pr-merge run starts", async () => {
  let slept = 0;
  const w = world({ merges: [{ sha: HEAD, number: 101, by: LANES }], startAttempt: 1 });
  const result = await run(ENV, w, { sleep: async () => { slept += 1; } });
  assert.equal(slept, 1);
  assert.equal(decisionOf(result.body), "auto-revert");
});

// github-actions[bot]'s numeric user id, which GitHub assigns and no account can take.
const BOT = { login: "github-actions[bot]", id: 41898282 };
const LOG = { number: 77, state: "open", user: BOT, body: "<!-- red-main-revert-log -->\n\nlog" };
const logged = (culprit, decision, at, runId = 1, user = BOT) => ({
  user,
  created_at: at,
  body: `<!-- red-main-report run=${runId} attempt=2 culprit=${culprit} decision=${decision} -->\n\nreport`,
});

test("a run and attempt already in the log is not reported twice", async () => {
  const w = world({
    merges: [{ sha: HEAD, number: 101, by: LANES }],
    issues: [LOG],
    comments: [logged(HEAD, "auto-revert", "2026-10-20T11:30:00Z", 500)],
  });
  const result = await run(ENV, w);
  assert.equal(result.posted, false);
  assert.deepEqual(w.writes, []);
});

test("three auto-revert decisions in the last day reach the cap, and the next culprit goes to a person", async () => {
  const w = world({
    merges: [{ sha: HEAD, number: 101, by: LANES }],
    issues: [LOG],
    comments: [
      logged(sha("1"), "auto-revert", "2026-10-20T01:00:00Z", 11),
      logged(sha("2"), "auto-revert", "2026-10-20T02:00:00Z", 12),
      logged(sha("3"), "auto-revert", "2026-10-20T03:00:00Z", 13),
    ],
  });
  const result = await run(ENV, w);
  assert.equal(decisionOf(result.body), "human");
  assert.deepEqual(w.writes.map((x) => x.path), [`/repos/${REPO}/issues/77/comments`]);
});

test("a decision older than a day does not count against the cap", async () => {
  const w = world({
    merges: [{ sha: HEAD, number: 101, by: LANES }],
    issues: [LOG],
    comments: [
      logged(sha("1"), "auto-revert", "2026-10-19T01:00:00Z", 11),
      logged(sha("2"), "auto-revert", "2026-10-19T02:00:00Z", 12),
      logged(sha("3"), "auto-revert", "2026-10-19T03:00:00Z", 13),
    ],
  });
  assert.equal(decisionOf((await run(ENV, w)).body), "auto-revert");
});

test("an open canary record on a merge in the range is a suspected platform fault", async () => {
  const w = world({
    merges: [{ sha: HEAD, number: 101, by: LANES }],
    issues: [{ number: 12, state: "open", user: BOT, body:`<!-- babysit-merge-demotion sha=${HEAD} signal=canary -->\n\ncanary` }],
  });
  const result = await run(ENV, w);
  assert.equal(decisionOf(result.body), "human");
  assert.match(result.body, /platform fault/);
});

test("a revert of a revert is never auto-reverted", async () => {
  const w = world({ merges: [{ sha: HEAD, number: 104, by: LANES, message: "revert: fix(x): y (#104)" }] });
  assert.equal(decisionOf((await run(ENV, w)).body), "human");
});

test("the culprit's age is read after the wait for the re-run, not before it", async () => {
  // Merged 23 h 40 min before the job starts; the re-run finishes 30 minutes later.
  let minutes = 0;
  const start = Date.parse("2026-10-20T12:00:00Z");
  const w = world({ merges: [{ sha: HEAD, number: 101, by: LANES }], startAttempt: 1 });
  w.call = ((inner) => async (method, path, body) => {
    const value = await inner(method, path, body);
    return /\/pulls\/101$/.test(path) ? { ...value, merged_at: "2026-10-19T12:20:00Z" } : value;
  })(w.call);
  const result = await run(ENV, w, {
    sleep: async () => {
      minutes += 30;
    },
    clock: () => new Date(start + minutes * 60_000).toISOString(),
  });
  assert.equal(decisionOf(result.body), "human");
  assert.match(result.body, /past max-culprit-age-hours/);
});

// #8699 item 2: the cap counts only the log issue's own decisions.
test("a newer issue carrying the log marker is not the log, so its decisions neither fill the cap nor take the report", async () => {
  const decoy = { number: 99, state: "open", user: BOT, body: "<!-- red-main-revert-log -->\n\ndecoy" };
  const w = world({
    merges: [{ sha: HEAD, number: 101, by: LANES }],
    // Newest first, as the issues list returns them.
    issues: [decoy, LOG],
    comments: {
      99: [
        logged(sha("1"), "auto-revert", "2026-10-20T01:00:00Z", 11),
        logged(sha("2"), "auto-revert", "2026-10-20T02:00:00Z", 12),
        logged(sha("3"), "auto-revert", "2026-10-20T03:00:00Z", 13),
      ],
    },
  });
  const result = await run(ENV, w);
  assert.equal(decisionOf(result.body), "auto-revert");
  assert.deepEqual(w.writes.map((x) => x.path), [`/repos/${REPO}/issues/77/comments`]);
});

test("a marker comment from an account other than github-actions[bot]'s id does not count against the cap", async () => {
  const other = { login: "github-actions[bot]", id: 1 };
  const w = world({
    merges: [{ sha: HEAD, number: 101, by: LANES }],
    issues: [LOG],
    comments: [
      logged(sha("1"), "auto-revert", "2026-10-20T01:00:00Z", 11, other),
      logged(sha("2"), "auto-revert", "2026-10-20T02:00:00Z", 12, other),
      logged(sha("3"), "auto-revert", "2026-10-20T03:00:00Z", 13, other),
    ],
  });
  assert.equal(decisionOf((await run(ENV, w)).body), "auto-revert");
});

// #8699 item 1: a red whose report was dropped is named by the next report.
const midRangeRed = () => [
  { sha: sha("a"), number: 201, by: LANES, run: confirmedRed(41) },
  { sha: HEAD, number: 203, by: LANES },
];

test("a red full run since the last green one with no report on the log is named in the next report", async () => {
  const w = world({ merges: midRangeRed(), issues: [LOG], comments: [] });
  const result = await run(ENV, w);
  assert.match(result.body, /no report on this log/);
  assert.match(result.body, /run-41 at `a{12}`/);
});

test("a red full run the log already reports is not named again", async () => {
  const w = world({
    merges: midRangeRed(),
    issues: [LOG],
    comments: [logged(sha("a"), "auto-revert", "2026-10-20T07:30:00Z", 41)],
  });
  assert.doesNotMatch((await run(ENV, w)).body, /no report on this log/);
});
