// Expected values come from the owner's needs-human brief, Part A2, and the
// coordinator's direction that ci-status re-runs the App's predicate instead
// of trusting its marker: after the lanes App removed a stale review-lane hold,
// the base commit's clear-escalations.mjs recheckStaleHold, run by ci-status with its own token,
// judges the head the App's marker names (CLEARED_SHA), which must be the
// head when the App removed the label, so a later clean push stays green
// before its lanes run (thread PRRT_kwDOTCGFQM6xmIfF). A CRITICAL thread opened
// after the clear, or a lane with no run at the cleared head, makes it fail.
// Shapes are the review lanes' (#10743).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { recheckStaleHold as main } from "./clear-escalations.mjs";

const REPO = "melodic-software/claude-code-plugins";
const ACTIONS_BOT = { login: "github-actions[bot]", type: "Bot" };
const APP = { login: "melodic-automation-lanes[bot]", type: "Bot" };
const PERSON = { login: "kyle-sexton", id: 153232337, type: "User" };
const APP_ACTOR = { login: APP.login, id: 337595936, type: "Bot" };
const MAIN = "a".repeat(40);
const HEAD = "b".repeat(40);
const OLD = "c".repeat(40);
const LATER = "d".repeat(40);

const DIR = mkdtempSync(join(tmpdir(), "stale-review-hold-"));
after(() => rmSync(DIR, { recursive: true, force: true }));
const TRUSTED = join(DIR, "trusted-actors.json");
writeFileSync(
  TRUSTED,
  JSON.stringify({
    version: 1,
    actors: [
      { id: PERSON.id, login: PERSON.login, kind: "human" },
      { id: APP_ACTOR.id, login: APP.login, kind: "bot" },
    ],
  }),
);
const ENV = { GITHUB_REPOSITORY: REPO, PR_NUMBER: "7", HEAD_SHA: HEAD, CLEARED_SHA: HEAD, HUMAN_GATED: "needs-human", TRUSTED_ACTORS_PATH: TRUSTED };

const commented = (user, body, at) => ({ event: "commented", user, actor: user, body, created_at: at, updated_at: at });
// The timeline ci-status sees on the unlabeled event: the lane's label and
// hold at OLD, the security summary at HEAD, the App's marker and removal.
const timeline = [
  { event: "labeled", actor: ACTIONS_BOT, label: { name: "needs-human" }, created_at: "2026-10-18T10:00:00Z" },
  commented(ACTIONS_BOT, `<!-- claude-lane-hold lane=claude-security-review sha=${OLD} criteria=critical-security -->\nHeld.\n\nclaude-lane: claude-security-review`, "2026-10-18T10:00:02Z"),
  commented(ACTIONS_BOT, `<!-- claude-lane-reviewed-head lane=claude-security-review sha=${HEAD} -->\nReviewed.\n\ncritical-findings: 0\n\nclaude-lane: claude-security-review`, "2026-10-18T11:20:00Z"),
  commented(APP, `<!-- pr-pipeline needs-human-cleared reason=stale-review-hold head=${HEAD} -->\nCleared.`, "2026-10-18T12:00:00Z"),
  { event: "unlabeled", actor: APP, label: { name: "needs-human" }, created_at: "2026-10-18T12:00:01Z" },
];
const thread = (severity, lane = "claude-security-review", { isResolved = false, path = "plugins/x/z.py", commit = HEAD } = {}) => ({
  isResolved,
  path,
  comments: { nodes: [{ author: { __typename: "Bot", login: "github-actions" }, body: `${severity}\n\nA finding.\n\nclaude-lane: ${lane}`, originalCommit: { oid: commit }, originalLine: 12, originalStartLine: null }] },
});
// The held CRITICAL finding, inline at OLD on line 12 of the file the fix changed there, resolved.
const heldFinding = () => thread("severity: CRITICAL", "claude-security-review", { isResolved: true, path: "plugins/x/y.py", commit: OLD });
const notice = (lane) => ({ annotation_level: "notice", message: `claude-lane-review-complete lane=${lane} sha=${HEAD} findings=0 inline=0 scope=whole` });
const LANES = {
  "pr-review-hosted.yml": { check: "pr-review / claude-review-status", lane: "claude-review" },
  "pr-review-security-hosted.yml": { check: "pr-review-security / security-review", lane: "claude-security-review" },
};
const pushes = [
  { activity_type: "push", actor: PERSON, after: HEAD, timestamp: "2026-10-18T11:00:00Z" },
  { activity_type: "push", actor: PERSON, after: OLD, timestamp: "2026-10-18T09:50:00Z" },
];

// One token answers every read, as ci-status's job token does.
function world({ threads = [thread("severity: SUGGESTION"), heldFinding()], notRun = null, head = HEAD, activity = pushes, extra = [], threadComments = [] } = {}) {
  const calls = [];
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    const route = path.replace(/[?&]per_page=100(?:&page=\d+)?$/, "");
    if (method === "GET" && route === `/repos/${REPO}/pulls/7`) {
      return { number: 7, state: "open", base: { ref: "main", sha: MAIN }, head: { sha: head, ref: "feat/x", repo: { full_name: REPO } } };
    }
    if (method === "GET" && route === `/repos/${REPO}/issues/7/timeline`) {
      return path.endsWith("page=1") ? [...timeline, ...extra] : [];
    }
    if (method === "GET" && route === `/repos/${REPO}/compare/${MAIN}...${HEAD}`) {
      return { files: [{ filename: "plugins/x/y.py" }] };
    }
    if (method === "GET" && route === `/repos/${REPO}/activity?ref=${encodeURIComponent("refs/heads/feat/x")}&direction=desc`) {
      return activity;
    }
    if (method === "GET" && route === `/repos/${REPO}/compare/${OLD}...${HEAD}`) {
      return { total_commits: 1, commits: [{ sha: HEAD, parents: [{ sha: OLD }] }], files: [{ filename: "plugins/x/y.py", patch: "@@ -12,1 +12,1 @@\n-    run(user_input)\n+    run(quote(user_input))" }] };
    }
    if (method === "GET" && route === `/repos/${REPO}/compare/main...${HEAD}`) {
      return { total_commits: 2, commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }] }] };
    }
    if (method === "GET" && route === `/repos/${REPO}/commits/${HEAD}`) {
      return { sha: HEAD, files: [{ filename: "plugins/x/y.py" }] };
    }
    if (method === "GET" && /^\/repos\/[^/]+\/[^/]+\/pulls\/7\/comments\?since=[^&]+$/.test(route)) {
      return path.endsWith("page=1") ? threadComments : [];
    }
    if (method === "GET" && route === `/repos/${REPO}/pulls/7/reviews`) {
      return [];
    }
    if (method === "POST" && path === "/graphql") {
      return { data: { repository: { pullRequest: { reviewThreads: { nodes: threads, pageInfo: { hasNextPage: false } } } } } };
    }
    for (const [file, { check, lane }] of Object.entries(LANES)) {
      const id = file.length;
      if (route === `/repos/${REPO}/actions/workflows/${file}/runs?event=pull_request&head_sha=${HEAD}`) {
        return { workflow_runs: file === notRun ? [] : [{ id, head_sha: HEAD, head_repository: { full_name: REPO } }] };
      }
      if (route === `/repos/${REPO}/actions/runs/${id}/jobs?filter=latest`) {
        return { jobs: [{ id: id * 10, name: check, status: "completed", conclusion: "success" }] };
      }
      if (route === `/repos/${REPO}/check-runs/${id * 10}/annotations`) {
        return [notice(lane)];
      }
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, calls };
}

const run = async (w, env = ENV) => {
  const logs = [];
  const original = console.log;
  console.log = (line) => logs.push(line);
  try {
    return { code: await main({ env, github: w.github }), log: logs.join("\n") };
  } finally {
    console.log = original;
  }
};

test("ci-status's recheck accepts the App's removal while the hold still no longer stands at the head", async () => {
  const w = world();
  const { code, log } = await run(w);
  assert.equal(code, 0, log);
  assert.match(log, new RegExp(`the hold at ${OLD} no longer stands at ${HEAD}: kyle-sexton moved the head`));
  assert.ok(w.calls.every((call) => call.startsWith("GET ") || call === "POST /graphql"), "the recheck writes nothing");
});

test("ci-status's recheck fails a valid marker once a CRITICAL thread opened after the clear", async () => {
  const { code, log } = await run(world({ threads: [thread("severity: SUGGESTION"), thread("severity: CRITICAL")] }));
  assert.equal(code, 1);
  assert.match(log, /the hold stands at .*: 1 unresolved claude-security-review finding\(s\) at CRITICAL or with no one readable severity/);
});

test("ci-status's recheck fails a valid marker when a lane has no run at the head", async () => {
  const { code, log } = await run(world({ notRun: "pr-review-security-hosted.yml" }));
  assert.equal(code, 1);
  assert.match(log, new RegExp(`claude-security-review has not run on ${HEAD}`));
});

test("ci-status's recheck fails when the pull request's head is not the event's", async () => {
  const { code, log } = await run(world({ head: "f".repeat(40) }));
  assert.equal(code, 1);
  assert.match(log, new RegExp(`head is no longer ${HEAD}`));
});

test("ci-status's recheck fails closed on missing input", async () => {
  for (const key of ["HEAD_SHA", "CLEARED_SHA", "PR_NUMBER", "HUMAN_GATED"]) {
    const { code } = await run(world(), { ...ENV, [key]: "" });
    assert.equal(code, 1, key);
  }
});

test("ci-status's recheck at a later head judges the head the App cleared, before the lanes run there and after a lanes App push", async () => {
  const later = [{ activity_type: "push", actor: APP_ACTOR, after: LATER, timestamp: "2026-10-18T12:30:00Z" }, ...pushes];
  const { code, log } = await run(world({ head: LATER, activity: later }), { ...ENV, HEAD_SHA: LATER });
  assert.equal(code, 0, log);
  assert.match(log, new RegExp(`the hold at ${OLD} no longer stands at ${HEAD}`));
});

test("ci-status's recheck fails when a lanes App push landed the cleared head", async () => {
  const appLanded = [{ activity_type: "push", actor: APP_ACTOR, after: HEAD, timestamp: "2026-10-18T11:00:00Z" }, pushes[1]];
  const { code, log } = await run(world({ activity: appLanded }));
  assert.equal(code, 1);
  assert.match(log, /no trusted push alone moved the head off the held head/);
});

test("ci-status's recheck fails when the cleared head was not the head as the App removed the label", async () => {
  const moved = [{ activity_type: "push", actor: PERSON, after: LATER, timestamp: "2026-10-18T11:59:00Z" }, ...pushes];
  const { code, log } = await run(world({ head: LATER, activity: moved }), { ...ENV, HEAD_SHA: LATER });
  assert.equal(code, 1);
  assert.match(log, /no trusted push alone moved the head off the held head/);
});

// The rest of the App's predicate, at the removal (thread PRRT_kwDOTCGFQM6xqn0Y):
// a marker comment the App wrote outside clear-escalations proves nothing.
test("ci-status's recheck fails on a signed-commits hold, another App marker or a person speaking before the removal", async () => {
  for (const [extra, why] of [
    [[commented(ACTIONS_BOT, "<!-- check-signed-commits hold -->\nA lane commit is not verified.", "2026-10-18T11:30:00Z")], "check-signed-commits holds it"],
    [[commented(ACTIONS_BOT, "<!-- stop-reason lane=pr-verify reason=security -->\nReason: `security`", "2026-10-18T11:30:00Z")], "pr-verify holds it for a credential"],
    [[commented(APP, "<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-risk -->\nHeld.", "2026-10-18T11:30:00Z")], "a lanes App comment since needs-human went on carries a marker"],
    [[commented(PERSON, "Do not merge this yet.", "2026-10-18T11:30:00Z")], "kyle-sexton commented or reviewed after needs-human went on"],
  ]) {
    const { code, log } = await run(world({ extra }));
    assert.equal(code, 1, why);
    assert.match(log, new RegExp(why));
  }
  const reply = { user: PERSON, created_at: "2026-10-18T11:30:00Z", updated_at: "2026-10-18T11:30:00Z", body: "Keep this held." };
  const { code, log } = await run(world({ threadComments: [reply] }));
  assert.equal(code, 1);
  assert.match(log, /kyle-sexton commented or reviewed after needs-human went on/);
});

// A reply written before the removal and edited after it still counts
// (thread PRRT_kwDOTCGFQM6xqzoY).
test("ci-status's recheck fails on a person's thread reply written before the removal and edited after it", async () => {
  const reply = { user: PERSON, created_at: "2026-10-18T11:30:00Z", updated_at: "2026-10-18T12:30:00Z", body: "Keep this held." };
  const { code, log } = await run(world({ threadComments: [reply] }));
  assert.equal(code, 1, log);
  assert.match(log, /kyle-sexton commented or reviewed after needs-human went on/);
});

test("ci-status's recheck ignores a person who spoke only after the removal", async () => {
  const { code, log } = await run(world({ extra: [commented(PERSON, "Thanks.", "2026-10-18T12:30:00Z")] }));
  assert.equal(code, 0, log);
});
