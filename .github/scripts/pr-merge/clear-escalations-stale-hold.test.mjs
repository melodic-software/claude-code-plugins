// Expected values come from the owner's needs-human brief, Part A2
// (2026-10-29): a review-lane hold recorded against an older head clears once
// a new head's review lanes pass with no HIGH or CRITICAL finding, stays when
// the new head still carries the finding or the lanes have not passed there,
// and a lanes App push alone never clears it (only a trusted move does).
// Security-review IMPORTANT counts as HIGH (R47). Notice and comment shapes are
// the ones the review lanes post (#10743's security lane comments).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { main } from "./clear-escalations.mjs";

const REPO = "melodic-software/claude-code-plugins";
const ACTIONS_BOT = { login: "github-actions[bot]", type: "Bot" };
const APP = { login: "melodic-automation-lanes[bot]", type: "Bot" };
const OWNER = { login: "kyle-sexton", type: "User" };
const PERSON = { login: "kyle-sexton", id: 153232337, type: "User" };
const APP_ACTOR = { login: APP.login, id: 337595936, type: "Bot" };
const MAIN = "a".repeat(40);
const HEAD = "b".repeat(40);
const OLD = "c".repeat(40);
const LABELED_AT = "2026-10-18T10:00:00Z";

const TRUSTED_DIR = mkdtempSync(join(tmpdir(), "clear-escalations-stale-"));
after(() => rmSync(TRUSTED_DIR, { recursive: true, force: true }));
const TRUSTED = join(TRUSTED_DIR, "trusted-actors.json");
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
const ENV = {
  GITHUB_REPOSITORY: REPO,
  KILL_SWITCH: "proceed",
  TRACKER_CONFIG: "/nonexistent/.work-item-tracker.json",
  TRUSTED_ACTORS_PATH: TRUSTED,
  BABYSIT_VERIFY_GH_TOKEN: "job-token",
};

const commented = (user, body, at) => ({ event: "commented", user, actor: user, body, created_at: at, updated_at: at });
const hold = (sha, at = "2026-10-18T10:00:02Z") =>
  commented(
    ACTIONS_BOT,
    `<!-- claude-lane-hold lane=claude-security-review sha=${sha} criteria=critical-security -->\n**claude-security-review** holds this pull request for a person.\n\nclaude-lane: claude-security-review`,
    at,
  );
const summary = (critical = "critical-findings: 0") =>
  commented(
    ACTIONS_BOT,
    `<!-- claude-lane-reviewed-head lane=claude-security-review sha=${HEAD} -->\n**claude-security-review** reviewed \`${HEAD}\`: 1 finding(s), 1 as inline comments.\n\n${critical}\n\nclaude-lane: claude-security-review`,
    "2026-10-18T11:20:00Z",
  );
const baseTimeline = () => [{ event: "labeled", actor: ACTIONS_BOT, label: { name: "needs-human" }, created_at: LABELED_AT }, hold(OLD), summary()];

// Review threads, root comment first. The fixture's one open security finding
// is a SUGGESTION, so a clear shows the bar is HIGH or CRITICAL, not any finding.
const thread = (isResolved, author, body) => ({ isResolved, comments: { nodes: [{ author, body }] } });
const securityThread = (severity, isResolved = false) =>
  thread(isResolved, { __typename: "Bot", login: "github-actions" }, `${severity}\n\nA finding.\n\nclaude-lane: claude-security-review`);
const codeThread = thread(false, { __typename: "Bot", login: "github-actions" }, "A code finding.\n\nclaude-lane: claude-review");
const baseThreads = () => [securityThread("severity: SUGGESTION"), securityThread("severity: CRITICAL", true), codeThread];

const completeNotice = (lane, scope = "scope=whole") => ({
  annotation_level: "notice",
  title: "claude-lane-review-complete",
  message: `claude-lane-review-complete lane=${lane} sha=${HEAD} findings=1 inline=1 ${scope} account=fallback`,
});
// Each review caller's newest run on HEAD and its status job.
const baseLanes = () => ({
  "pr-review-hosted.yml": { check: "pr-review / claude-review-status", conclusion: "success", notes: [completeNotice("claude-review")] },
  "pr-review-security-hosted.yml": { check: "pr-review-security / security-review", conclusion: "success", notes: [completeNotice("claude-security-review")] },
});

// The branch's pushes, newest first: the person's fix after the held head.
const push = (actor, sha, at) => ({ activity_type: "push", actor, after: sha, timestamp: at });
const basePushes = () => [push(PERSON, HEAD, "2026-10-18T11:00:00Z"), push(PERSON, OLD, "2026-10-18T09:50:00Z"), { activity_type: "branch_creation", actor: PERSON, after: "e".repeat(40), timestamp: "2026-10-18T08:00:00Z" }];

function world({ timeline = baseTimeline(), threads = baseThreads(), lanes = baseLanes(), pushes = basePushes(), headFiles = [{ filename: "plugins/x/y.py" }] } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    const route = path.replace(/[?&]per_page=100&page=\d+$/, "");
    const first = path.endsWith("page=1");
    if (method === "GET" && route === `/repos/${REPO}/git/ref/heads/main`) {
      return { ref: "refs/heads/main", object: { sha: MAIN } };
    }
    if (method === "GET" && route === `/repos/${REPO}/issues?state=open&labels=needs-human`) {
      return first ? [{ number: 7, pull_request: {} }] : [];
    }
    if (method === "GET" && route === `/repos/${REPO}/issues/7/timeline`) {
      return first ? timeline : [];
    }
    if (method === "GET" && route === `/repos/${REPO}/pulls/7`) {
      return { number: 7, state: "open", user: OWNER, base: { ref: "main", sha: MAIN }, head: { sha: HEAD, ref: "feat/x", repo: { full_name: REPO } }, labels: [{ name: "needs-human" }] };
    }
    if (method === "GET" && route === `/repos/${REPO}/compare/${MAIN}...${HEAD}`) {
      return { files: headFiles };
    }
    if (method === "POST" && path === "/graphql") {
      return { data: { repository: { pullRequest: { reviewThreads: { nodes: threads, pageInfo: { hasNextPage: false } } } } } };
    }
    if (method === "GET" && /^\/repos\/[^/]+\/[^/]+\/pulls\/7\/(comments\?since=[^&]+|reviews)$/.test(route)) {
      return [];
    }
    if (method === "POST" || method === "DELETE") {
      return null;
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  const checks = async (method, path) => {
    calls.push({ method, path, token: "checks" });
    for (const [file, lane] of Object.entries(lanes)) {
      const id = file.length;
      if (path === `/repos/${REPO}/actions/workflows/${file}/runs?event=pull_request&head_sha=${HEAD}&per_page=100`) {
        return { workflow_runs: lane === null ? [] : [{ id, head_sha: HEAD, head_repository: { full_name: REPO } }] };
      }
      if (path === `/repos/${REPO}/actions/runs/${id}/jobs?filter=latest&per_page=100`) {
        return { jobs: [{ id: id * 10, name: lane.check, status: "completed", conclusion: lane.conclusion }] };
      }
      if (path === `/repos/${REPO}/check-runs/${id * 10}/annotations?per_page=100`) {
        return lane.notes;
      }
    }
    throw new Error(`unexpected checks ${method} ${path}`);
  };
  const reader = async (method, path) => {
    if (method === "GET" && path === `/repos/${REPO}/activity?ref=${encodeURIComponent("refs/heads/feat/x")}&per_page=100`) {
      return pushes;
    }
    throw new Error(`unexpected reader ${method} ${path}`);
  };
  return { github, checks, reader, writes: () => calls.filter((call) => call.method !== "GET" && call.path !== "/graphql") };
}

const run = async (w) => {
  const logs = [];
  const original = console.log;
  console.log = (line) => logs.push(line);
  try {
    const code = await main({ env: ENV, github: w.github, checks: w.checks, reader: w.reader, verify: async () => null });
    return { code, log: logs.join("\n") };
  } finally {
    console.log = original;
  }
};

const assertKept = async (w, why) => {
  const { code, log } = await run(w);
  assert.equal(code, 0);
  assert.deepEqual(w.writes(), []);
  assert.match(log, new RegExp(`#7 kept: ${why}`));
};

test("a hold at an older head comes off once a person's push passes both review lanes with no HIGH or CRITICAL finding", async () => {
  const w = world();
  const { code } = await run(w);
  assert.equal(code, 0);
  const [comment, removal] = w.writes();
  assert.equal(w.writes().length, 2);
  assert.equal(comment.path, `/repos/${REPO}/issues/7/comments`);
  assert.equal(comment.body.body.split("\n")[0], `<!-- pr-pipeline needs-human-cleared reason=stale-review-hold head=${HEAD} -->`);
  assert.match(comment.body.body, new RegExp(`it held \`${OLD}\``));
  assert.match(comment.body.body, /kyle-sexton moved the head/);
  assert.deepEqual(removal, { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined });
});

test("the hold stays when the new head still carries the finding", async () => {
  await assertKept(world({ timeline: [...baseTimeline(), hold(HEAD, "2026-10-18T11:30:00Z")] }), `a review lane holds the current head ${HEAD}`);
  const notes = [completeNotice("claude-security-review"), { annotation_level: "notice", message: `claude-lane-hold lane=claude-security-review sha=${HEAD} criteria=critical-security label=needs-human` }];
  await assertKept(world({ lanes: { ...baseLanes(), "pr-review-security-hosted.yml": { ...baseLanes()["pr-review-security-hosted.yml"], notes } } }), `claude-security-review holds ${HEAD}`);
  for (const severity of ["severity: IMPORTANT", "severity: CRITICAL", "no severity line"]) {
    await assertKept(world({ threads: [...baseThreads(), securityThread(severity)] }), "1 unresolved security finding\\(s\\) at CRITICAL or IMPORTANT");
  }
  await assertKept(world({ timeline: [...baseTimeline().slice(0, 2), summary("critical-findings: 1")] }), `the security lane's summary of ${HEAD} does not read critical-findings: 0`);
});

test("the hold stays while the review lanes have not passed on the new head", async () => {
  const lanes = baseLanes();
  await assertKept(world({ lanes: { ...lanes, "pr-review-security-hosted.yml": { ...lanes["pr-review-security-hosted.yml"], conclusion: "failure" } } }), `claude-security-review has not passed on ${HEAD}`);
  await assertKept(world({ lanes: { ...lanes, "pr-review-hosted.yml": null } }), `claude-review has not run on ${HEAD}`);
  await assertKept(world({ lanes: { ...lanes, "pr-review-hosted.yml": { ...lanes["pr-review-hosted.yml"], notes: [] } } }), `claude-review recorded no one review of ${HEAD}`);
  const incremental = [completeNotice("claude-security-review", `scope=incremental since=${OLD}`)];
  await assertKept(world({ lanes: { ...lanes, "pr-review-security-hosted.yml": { ...lanes["pr-review-security-hosted.yml"], notes: incremental } } }), `the security lane reviewed only part of ${HEAD}`);
});

test("a lanes App push alone never clears the hold, even with both lanes passing", async () => {
  for (const pushes of [
    [push(APP_ACTOR, HEAD, "2026-10-18T11:00:00Z"), ...basePushes().slice(1)],
    [push(APP_ACTOR, HEAD, "2026-10-18T11:10:00Z"), ...basePushes()],
  ]) {
    await assertKept(world({ pushes }), "no trusted push alone moved the head off the held head");
  }
});

test("the hold stays when the head changes a review caller, a person spoke, or the App marked the PR since the label", async () => {
  await assertKept(world({ headFiles: [{ filename: ".github/workflows/pr-review-security-hosted.yml" }] }), "the head's lane runs prove nothing: it changes a review-lane workflow");
  await assertKept(world({ timeline: [...baseTimeline(), commented(OWNER, "Wait on this.", "2026-10-18T11:40:00Z")] }), "kyle-sexton commented or reviewed after needs-human went on");
  const escalation = commented(APP, "<!-- work-items:escalation lane=pr-merge kind=escalated -->\n<!-- babysit-merge-risk -->\nHeld.", "2026-10-18T11:40:00Z");
  await assertKept(world({ timeline: [...baseTimeline(), escalation] }), "a lanes App comment since needs-human went on carries a marker");
});
