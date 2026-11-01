// Expected values come from the owner's needs-human brief, Part A2
// (2026-10-29): a review-lane hold recorded against an older head clears once
// a new head's review lanes pass with no CRITICAL finding, stays when the new
// head still carries the finding or the lanes have not passed there, and a
// lanes App push alone never clears it (only a trusted move does). Only a
// CRITICAL finding holds; an IMPORTANT one is reported (owner decision
// 2026-10-30, #11020). Notice and comment shapes are the ones the review lanes
// post (#10743's security lane comments).
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
// is a SUGGESTION, so a clear shows the bar is CRITICAL, not any finding.
// A thread carries its file and the commit its root comment was made on.
// A thread carries its file, the commit its root comment was made on and the line it names there.
const thread = (isResolved, author, body, path = "plugins/x/z.py", commit = HEAD, line = 12) => ({
  isResolved,
  path,
  comments: { nodes: [{ author, body, originalCommit: { oid: commit }, originalLine: line, originalStartLine: null }] },
});
const securityThread = (severity, isResolved = false, path = undefined, commit = undefined, line = undefined) =>
  thread(isResolved, { __typename: "Bot", login: "github-actions" }, `${severity}\n\nA finding.\n\nclaude-lane: claude-security-review`, path, commit, line);
const codeThread = thread(false, { __typename: "Bot", login: "github-actions" }, "A code finding.\n\nclaude-lane: claude-review");
// The held CRITICAL finding: inline at OLD on the file the person's fix changed, now resolved.
const heldFinding = () => securityThread("severity: CRITICAL", true, "plugins/x/y.py", OLD);
const baseThreads = () => [securityThread("severity: SUGGESTION"), heldFinding(), codeThread];
// The person's fix rewrites line 12 of plugins/x/y.py, the held finding's line.
const FIX_PATCH = "@@ -10,5 +10,5 @@ def f():\n     a = 1\n     b = 2\n-    run(user_input)\n+    run(quote(user_input))\n     c = 3\n     d = 4";
// The compare from the held head to the head: the person's one fix commit;
// from main to the head: the pull request's own commits, the held head and the fix.
const baseHeldCompare = () => ({ total_commits: 1, commits: [{ sha: HEAD, parents: [{ sha: OLD }] }], files: [{ filename: "plugins/x/y.py", patch: FIX_PATCH }] });
const baseOwnCompare = () => ({ total_commits: 2, commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, { sha: HEAD, parents: [{ sha: OLD }] }] });

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

function world({ later = {}, timeline = baseTimeline(), threads = baseThreads(), lanes = baseLanes(), pushes = basePushes(), headFiles = [{ filename: "plugins/x/y.py" }], heldCompare = baseHeldCompare(), ownCompare = baseOwnCompare(), fixFiles = [{ filename: "plugins/x/y.py" }] } = {}) {
  const calls = [];
  // `later` answers the reads after the first judgment: { head, timeline }.
  const seen = { pull: 0, timeline: 0 };
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
    if (method === "GET" && route === `/repos/${REPO}/issues?state=open&labels=needs-session`) {
      return [];
    }
    if (method === "GET" && route === `/repos/${REPO}/issues/7/timeline`) {
      if (first) {
        seen.timeline += 1;
      }
      return first ? (seen.timeline > 1 ? (later.timeline ?? timeline) : timeline) : [];
    }
    if (method === "GET" && route === `/repos/${REPO}/pulls/7`) {
      seen.pull += 1;
      return { number: 7, state: "open", user: OWNER, base: { ref: "main", sha: MAIN }, head: { sha: seen.pull > 1 ? (later.head ?? HEAD) : HEAD, ref: "feat/x", repo: { full_name: REPO } }, labels: [{ name: "needs-human" }] };
    }
    if (method === "GET" && route === `/repos/${REPO}/compare/${MAIN}...${HEAD}`) {
      return { files: headFiles };
    }
    if (method === "GET" && route === `/repos/${REPO}/compare/${OLD}...${HEAD}`) {
      return heldCompare;
    }
    if (method === "GET" && route === `/repos/${REPO}/compare/main...${HEAD}`) {
      return ownCompare;
    }
    if (method === "GET" && route === `/repos/${REPO}/commits/${HEAD}`) {
      return { sha: HEAD, files: fixFiles };
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
    // Pages of 100 by the Link cursor, as GitHub serves the activity API.
    const page = /^(.*?)(?:&after=c(\d+))?$/.exec(path);
    if (method === "GET" && page[1] === `/repos/${REPO}/activity?ref=${encodeURIComponent("refs/heads/feat/x")}&direction=desc&per_page=100`) {
      const n = Number(page[2] ?? 0);
      const next = pushes.length > (n + 1) * 100 ? `<https://api.github.com/repositories/1/activity?after=c${n + 1}>; rel="next"` : null;
      return Object.defineProperty(pushes.slice(n * 100, n * 100 + 100), Symbol.for("github.link"), { value: next });
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

test("a hold at an older head comes off once a person's push passes both review lanes with no CRITICAL finding", async () => {
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
  for (const severity of ["severity: CRITICAL", "severity: SUGGESTION\nseverity: IMPORTANT", "no severity line"]) {
    await assertKept(world({ threads: [...baseThreads(), securityThread(severity)] }), "1 unresolved claude-security-review finding\\(s\\) at CRITICAL or with no one readable severity");
  }
  await assertKept(world({ timeline: [...baseTimeline().slice(0, 2), summary("critical-findings: 1")] }), `the security lane's summary of ${HEAD} does not read critical-findings: 0`);
});

test("an unresolved IMPORTANT security thread no longer keeps the hold", async () => {
  const w = world({ threads: [...baseThreads(), securityThread("severity: IMPORTANT")] });
  await run(w);
  assert.deepEqual(
    w.writes().map(({ method }) => method),
    ["POST", "DELETE"],
  );
});

test("the hold stays while the review lanes have not passed on the new head", async () => {
  const lanes = baseLanes();
  await assertKept(world({ lanes: { ...lanes, "pr-review-security-hosted.yml": { ...lanes["pr-review-security-hosted.yml"], conclusion: "failure" } } }), `claude-security-review has not passed on ${HEAD}`);
  await assertKept(world({ lanes: { ...lanes, "pr-review-hosted.yml": null } }), `claude-review has not run on ${HEAD}`);
  await assertKept(world({ lanes: { ...lanes, "pr-review-hosted.yml": { ...lanes["pr-review-hosted.yml"], notes: [] } } }), `claude-review recorded no one review of ${HEAD}`);
  const incremental = [completeNotice("claude-security-review", `scope=incremental since=${OLD}`)];
  await assertKept(world({ lanes: { ...lanes, "pr-review-security-hosted.yml": { ...lanes["pr-review-security-hosted.yml"], notes: incremental } } }), `claude-security-review reviewed only part of ${HEAD}`);
});

test("a hold comes off when the push that landed the held head is past the first activity page", async () => {
  const between = Array.from({ length: 99 }, (_, i) => push(PERSON, "d".repeat(40), new Date(Date.parse("2026-10-18T10:59:00Z") - i * 1000).toISOString()));
  const [head, ...rest] = basePushes();
  const w = world({ pushes: [head, ...between, ...rest] });
  await run(w);
  assert.deepEqual(w.writes().at(-1), { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined });
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

test("pr-verify's credential stop keeps a stale review hold's label", async () => {
  const stop = (at) => commented(ACTIONS_BOT, "<!-- stop-reason lane=pr-verify reason=security -->\nReason: `security`", at);
  await assertKept(world({ timeline: [...baseTimeline(), stop("2026-10-18T11:40:00Z")] }), "pr-verify holds it for a credential, which a person lifts");
});

// Fixes from the security review of 990c1941.
test("an incremental review by either lane keeps the hold: a finding at the held head may not have been looked at again", async () => {
  const lanes = baseLanes();
  const incremental = [completeNotice("claude-review", `scope=incremental since=${OLD}`)];
  await assertKept(world({ lanes: { ...lanes, "pr-review-hosted.yml": { ...lanes["pr-review-hosted.yml"], notes: incremental } } }), `claude-review reviewed only part of ${HEAD}`);
});

test("an open code-lane thread at CRITICAL keeps the hold, and so does an unrated one when the hold names the code lane", async () => {
  const codeAt = (severity) => thread(false, { __typename: "Bot", login: "github-actions" }, `${severity}\n\nA code finding.\n\nclaude-lane: claude-review`);
  await assertKept(world({ threads: [...baseThreads(), codeAt("severity: CRITICAL")] }), "1 unresolved claude-review finding\\(s\\) at CRITICAL or with no one readable severity");
  const important = world({ threads: [...baseThreads(), codeAt("severity: IMPORTANT")] });
  await run(important);
  assert.deepEqual(
    important.writes().map(({ method }) => method),
    ["POST", "DELETE"],
  );
  const codeHold = commented(ACTIONS_BOT, `<!-- claude-lane-hold lane=claude-review sha=${OLD} criteria=critical-security -->\nHeld.\n\nclaude-lane: claude-review`, "2026-10-18T10:00:02Z");
  await assertKept(world({ timeline: [baseTimeline()[0], codeHold, summary()] }), "1 unresolved claude-review finding\\(s\\) at CRITICAL or with no one readable severity");
});

test("an open IMPORTANT security-lane thread no longer keeps the hold", async () => {
  const w = world({ threads: [...baseThreads(), securityThread("severity: IMPORTANT")] });
  const { code } = await run(w);
  assert.equal(code, 0);
  assert.deepEqual(w.writes().at(-1), { method: "DELETE", path: `/repos/${REPO}/issues/7/labels/needs-human`, body: undefined });
});

// A kept label gets no comment saying it came off (threads PRRT_kwDOTCGFQM6xqa-M, PRRT_kwDOTCGFQM6xqmzn).
test("a hold written, or a head pushed, after the judgment keeps the label with no clear comment", async () => {
  const after = (later) => world({ later });
  for (const [w, why] of [
    [after({ timeline: [...baseTimeline(), hold(HEAD, "2026-10-18T11:50:00Z")] }), "a review lane wrote a hold since it was judged"],
    [after({ head: "f".repeat(40) }), `its head moved to ${"f".repeat(40)} since it was judged`],
    [after({ timeline: [...baseTimeline(), commented(ACTIONS_BOT, "<!-- stop-reason lane=pr-verify reason=security -->\nReason: `security`", "2026-10-18T11:50:00Z")] }), "pr-verify holds it for a credential"],
  ]) {
    const { code, log } = await run(w);
    assert.equal(code, 0);
    assert.deepEqual(w.writes(), []);
    assert.match(log, new RegExp(`#7 kept: ${why}`));
  }
});

// Fixes from the security review of e18df308 (thread PRRT_kwDOTCGFQM6xmJXW): a
// lane's later verdict alone never lifts a critical-security hold, and a push
// that only merges the base is no fix.
test("a critical-security hold stays for a person when its lane left no CRITICAL inline finding at the held head", async () => {
  await assertKept(world({ threads: [securityThread("severity: SUGGESTION"), codeThread] }), `the critical-security hold at ${OLD} has no CRITICAL inline claude-security-review finding there`);
  await assertKept(
    world({ threads: [securityThread("severity: SUGGESTION"), securityThread("severity: CRITICAL", true, "plugins/x/y.py", "f".repeat(40)), codeThread] }),
    `the critical-security hold at ${OLD} has no CRITICAL inline claude-security-review finding there`,
  );
});

test("a critical-security hold stays when no push since the held head changed the held finding's file", async () => {
  await assertKept(world({ fixFiles: [{ filename: "plugins/x/other.py" }] }), `plugins/x/y.py, which holds a CRITICAL finding at ${OLD}, is unchanged since then`);
});

// Thread PRRT_kwDOTCGFQM6xwRR5: an edit elsewhere in the held file (a comment,
// whitespace) is no fix of the flagged code.
test("a critical-security hold stays when no push since the held head changed the held finding's lines", async () => {
  const elsewhere = "@@ -40,3 +40,3 @@\n x = 1\n-# old note\n+# new note\n y = 2";
  const files = [{ filename: "plugins/x/y.py", patch: elsewhere }];
  const why = `the lines of plugins/x/y.py that hold a CRITICAL finding at ${OLD} are unchanged since then`;
  await assertKept(world({ heldCompare: { ...baseHeldCompare(), files } }), why);
  await assertKept(world({ heldCompare: { ...baseHeldCompare(), files: [{ filename: "plugins/x/y.py" }] } }), why);
  const fileLevel = [securityThread("severity: SUGGESTION"), securityThread("severity: CRITICAL", true, "plugins/x/y.py", OLD, null), codeThread];
  await assertKept(world({ threads: fileLevel }), why);
});

test("the hold stays when only merges moved the head off the held head, or the compare does not read whole", async () => {
  const merge = { sha: HEAD, parents: [{ sha: OLD }, { sha: MAIN }] };
  await assertKept(world({ heldCompare: { ...baseHeldCompare(), commits: [merge] } }), `no commit of the pull request's own but merges moved the head off ${OLD}`);
  await assertKept(world({ heldCompare: { ...baseHeldCompare(), total_commits: 2 } }), `the commits from ${OLD} or main to ${HEAD} did not read whole`);
});

// An Update branch once main has moved: the compare from the held head lists
// main's own single-parent commits beside the merge (threads
// PRRT_kwDOTCGFQM6xqaIb, PRRT_kwDOTCGFQM6xqa-F, PRRT_kwDOTCGFQM6xqn0R).
test("an Update branch that brings in main's commits, even ones changing the held file, lifts no hold", async () => {
  const mainCommit = { sha: "9".repeat(40), parents: [{ sha: MAIN }] };
  const merge = { sha: HEAD, parents: [{ sha: OLD }, { sha: mainCommit.sha }] };
  const heldCompare = { total_commits: 2, commits: [mainCommit, merge] };
  const ownCompare = { total_commits: 2, commits: [{ sha: OLD, parents: [{ sha: MAIN }] }, merge] };
  await assertKept(world({ heldCompare, ownCompare }), `no commit of the pull request's own but merges moved the head off ${OLD}`);
  const gate = commented(ACTIONS_BOT, `<!-- claude-lane-hold lane=claude-security-review sha=${OLD} criteria=trust-gate -->\nHeld.\n\nclaude-lane: claude-security-review`, "2026-10-18T10:00:02Z");
  await assertKept(world({ heldCompare, ownCompare, timeline: [baseTimeline()[0], gate, summary()] }), `no commit of the pull request's own but merges moved the head off ${OLD}`);
});

test("a hold other than critical-security needs no inline finding at the held head", async () => {
  const gate = commented(ACTIONS_BOT, `<!-- claude-lane-hold lane=claude-security-review sha=${OLD} criteria=trust-gate -->\nHeld.\n\nclaude-lane: claude-security-review`, "2026-10-18T10:00:02Z");
  const w = world({ timeline: [baseTimeline()[0], gate, summary()], threads: [securityThread("severity: SUGGESTION"), codeThread] });
  await run(w);
  assert.deepEqual(
    w.writes().map(({ method }) => method),
    ["POST", "DELETE"],
  );
});
