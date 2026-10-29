// Expected values come from the owner's needs-human brief, Part A2, and the
// coordinator's direction that ci-status re-runs the App's predicate instead
// of trusting its marker: after the lanes App removed a stale review-lane hold,
// the base commit's clear-escalations.mjs recheckStaleHold, run by ci-status with its own token
// at the event's head, passes only while the hold still no longer stands
// there. A CRITICAL thread opened after the clear, or a lane with no run at
// the head, makes it fail. Shapes are the review lanes' (#10743).
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
const ENV = { GITHUB_REPOSITORY: REPO, PR_NUMBER: "7", HEAD_SHA: HEAD, HUMAN_GATED: "needs-human", TRUSTED_ACTORS_PATH: TRUSTED };

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
const thread = (severity, lane = "claude-security-review") => ({
  isResolved: false,
  comments: { nodes: [{ author: { __typename: "Bot", login: "github-actions" }, body: `${severity}\n\nA finding.\n\nclaude-lane: ${lane}` }] },
});
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
function world({ threads = [thread("severity: SUGGESTION")], notRun = null, head = HEAD } = {}) {
  const calls = [];
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    const route = path.replace(/[?&]per_page=100(?:&page=\d+)?$/, "");
    if (method === "GET" && route === `/repos/${REPO}/pulls/7`) {
      return { number: 7, state: "open", base: { ref: "main", sha: MAIN }, head: { sha: head, ref: "feat/x", repo: { full_name: REPO } } };
    }
    if (method === "GET" && route === `/repos/${REPO}/issues/7/timeline`) {
      return path.endsWith("page=1") ? timeline : [];
    }
    if (method === "GET" && route === `/repos/${REPO}/compare/${MAIN}...${HEAD}`) {
      return { files: [{ filename: "plugins/x/y.py" }] };
    }
    if (method === "GET" && route === `/repos/${REPO}/activity?ref=${encodeURIComponent("refs/heads/feat/x")}`) {
      return pushes;
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
  assert.match(log, /the hold stands at .*: 1 unresolved claude-security-review finding\(s\) at CRITICAL or IMPORTANT/);
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
  for (const key of ["HEAD_SHA", "PR_NUMBER", "HUMAN_GATED"]) {
    const { code } = await run(world(), { ...ENV, [key]: "" });
    assert.equal(code, 1, key);
  }
});
