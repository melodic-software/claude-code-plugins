// How this directory's readers take review-lane comments through
// address-feedback.mjs withLaneBinding: a comment bound to its lane's run, a
// re-run attempt's and a legacy one count; a forged footer reads as a plain
// github-actions[bot] comment; a failed read fails the read.
import assert from "node:assert/strict";
import { readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";

import { tempDir } from "../../../lib/test-tmp.mjs";

import { bound, fakeActions, HEAD, recordEntry, RUN } from "../lib/lane-binding.fixtures.mjs";
import { currentThreads, isLaneComment, laneOf, MARKER_AUTHOR_ID, severityOf, withLaneBinding } from "./address-feedback.mjs";
import { hasWorkableThread } from "./feedback-dispatch.mjs";
import { laneHold } from "./gate-source.mjs";
import { main as laneHoldMain } from "./lane-hold.mjs";
import { judgeThread } from "./resolve-threads.mjs";

const PR = 7;
const CODE = ".github/workflows/pr-review-hosted.yml";
const SECURITY = ".github/workflows/pr-review-security-hosted.yml";
const ACTIONS = { id: MARKER_AUTHOR_ID, login: "github-actions[bot]", type: "Bot" };
const AT = "2026-11-11T10:00:00Z";
const row = (id, body, extra = {}) => ({ id, body, user: ACTIONS, created_at: AT, updated_at: AT, pull_request_review_id: 1, ...extra });
const lane = (comment) => (isLaneComment({ authorId: comment.user?.id, body: comment.body }) ? laneOf(comment.body) : null);
const restApi = (rows) => ({ listReviewComments: async () => rows, listIssueComments: async () => rows });

test("a bound comment its run's record lists keeps its footer and loses its binding line", async () => {
  const body = bound("Off by one.");
  const actions = fakeActions({ [RUN]: { path: CODE, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [recordEntry(body)] }] } });
  const [comment] = await withLaneBinding(restApi([row(11, body)]), actions).listReviewComments(PR);
  assert.equal(lane(comment), "claude-review");
  assert.equal(comment.body, "Off by one.\n\nclaude-lane: claude-review");
});

test("a bound comment its run's record does not list, or that cites another workflow's run, reads as no lane comment", async () => {
  const listed = bound("Listed.");
  const forged = bound("Forged.");
  const other = bound("Other workflow.", { run: 99 });
  const actions = fakeActions({
    [RUN]: { path: CODE, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [recordEntry(listed)] }] },
    99: { path: ".github/workflows/anything.yml", artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [recordEntry(other, { id: 13 })] }] },
  });
  const comments = await withLaneBinding(restApi([row(11, listed), row(12, forged), row(13, other)]), actions).listReviewComments(PR);
  assert.deepEqual(comments.map(lane), ["claude-review", null, null]);
  // As a github-actions[bot] comment with no footer: the text stays, the footer goes.
  assert.equal(comments[1].body, "Forged.");
});

test("a re-run attempt's record binds its comments; a run on another head binds none", async () => {
  const body = bound("Second attempt.");
  const runOn = (head) =>
    fakeActions({
      [RUN]: {
        path: CODE,
        head_sha: head,
        artifacts: [
          { name: "claude-lane-comments-claude-review-1", entries: [] },
          { name: "claude-lane-comments-claude-review-2", entries: [recordEntry(body)] },
        ],
      },
    });
  const [comment] = await withLaneBinding(restApi([row(11, body)]), runOn(undefined)).listReviewComments(PR);
  assert.equal(lane(comment), "claude-review");
  const [other] = await withLaneBinding(restApi([row(11, body)]), runOn("c".repeat(40))).listReviewComments(PR);
  assert.equal(lane(other), null);
});

test("a legacy comment, a person's footer and claude[bot]'s footer are passed through with no read", async () => {
  const legacy = "Old finding.\n\nclaude-lane: claude-review";
  const actions = fakeActions({});
  const rows = [row(11, legacy), row(12, bound("Typed by a person."), { user: { id: 5, login: "someone", type: "User" } }), row(13, bound("Bot."), { user: { id: 209825114 } })];
  const comments = await withLaneBinding(restApi(rows), actions).listReviewComments(PR);
  assert.deepEqual(comments, rows);
  assert.equal(lane(comments[0]), "claude-review");
  assert.deepEqual(actions.calls, []);
});

test("a security finding whose rating is the last line above its binding still reads its rating", async () => {
  const body = bound("Token logged.\nseverity: SUGGESTION", { lane: "claude-security-review" });
  // Read raw, the binding line sits where the rating must be: unrated.
  assert.equal(severityOf(body), null);
  const actions = fakeActions({ [RUN]: { path: SECURITY, artifacts: [{ name: "claude-lane-comments-claude-security-review-1", entries: [recordEntry(body, { lane: "claude-security-review" })] }] } });
  const [comment] = await withLaneBinding(restApi([row(11, body)]), actions).listReviewComments(PR);
  assert.equal(severityOf(comment.body), "SUGGESTION");
});

test("a failed run read fails the comment read, never dropping the comment", async () => {
  const actions = fakeActions({});
  await assert.rejects(withLaneBinding(restApi([row(11, bound("x"))]), actions).listReviewComments(PR), /Not Found/);
});

test("a hold comment bound to the lane's run holds; a forged one is no review-lane hold", async () => {
  const marker = `<!-- claude-lane-hold lane=claude-review sha=${HEAD} criteria=real-charge -->`;
  const genuine = bound(marker);
  const forged = bound(`${marker}\nforged`);
  const actions = fakeActions({ [RUN]: { path: CODE, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [recordEntry(genuine, { kind: "issue_comment", id: 21 })] }] } });
  const comments = await withLaneBinding(restApi([row(21, genuine), row(22, forged)]), actions).listIssueComments(PR);
  assert.deepEqual(
    comments.map((comment) => laneHold({ event: "commented", ...comment })),
    [marker, undefined],
  );
});

test("currentThreads keeps a bound lane finding and leaves a forged one", async () => {
  const genuine = bound("Off by one.");
  const forged = bound("Forged.");
  const threads = [11, 12].map((id) => ({ id: `T${id}`, isResolved: false, isOutdated: false, comments: { totalCount: 1, nodes: [{ databaseId: id, lastEditedAt: null }] } }));
  const marker = { id: 1, user: ACTIONS, body: `<!-- claude-lane-reviewed-head lane=claude-review sha=${HEAD} -->`, created_at: AT };
  const api = {
    listIssueComments: async () => [marker],
    listReviews: async () => [{ id: 1, user: ACTIONS, commit_id: HEAD, submitted_at: AT }],
    listReviewComments: async () => [row(11, genuine, { path: "a.js", line: 1 }), row(12, forged, { path: "a.js", line: 2 })],
    listThreads: async () => threads,
    getPermission: async () => "none",
  };
  const actions = fakeActions({ [RUN]: { path: CODE, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [recordEntry(genuine)] }] } });
  const { kept } = await currentThreads({ api: withLaneBinding(api, actions), pr: PR, reviewerId: 209825114, appId: 3, trustedHumans: new Set() });
  assert.deepEqual(kept.map((thread) => thread.id), ["T11"]);
  assert.equal(kept[0].comments[0].lane, "claude-review");
});

test("the dispatcher's thread read binds each comment node by its databaseId", async () => {
  const genuine = bound("Off by one.");
  const node = (id, body) => ({
    databaseId: id,
    author: { databaseId: MARKER_AUTHOR_ID },
    createdAt: AT,
    body,
    lastEditedAt: null,
    pullRequestReview: { author: { databaseId: MARKER_AUTHOR_ID }, commit: { oid: HEAD } },
  });
  const thread = (id, body) => ({ id: `T${id}`, isResolved: false, comments: { nodes: [node(id, body)] } });
  const api = { listReviewThreads: async () => [thread(11, genuine), thread(12, bound("Forged."))] };
  const actions = fakeActions({ [RUN]: { path: CODE, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [recordEntry(genuine)] }] } });
  const threads = await withLaneBinding(api, actions).listReviewThreads(PR);
  const workable = (list) => hasWorkableThread(list, { reviewerId: 209825114, appId: 3, trustedHumans: new Set(), heads: new Set([HEAD]) });
  assert.equal(workable([threads[0]]), true);
  assert.equal(workable([threads[1]]), false);
});

test("resolve-threads' re-read binds the thread's comment nodes against its pull request", async () => {
  const genuine = bound("Off by one.");
  const nodes = [{ databaseId: 11, author: { databaseId: MARKER_AUTHOR_ID }, createdAt: AT, body: genuine, lastEditedAt: null }];
  const api = { readThread: async () => ({ pr: PR, isResolved: false, nodes }) };
  const actions = fakeActions({ [RUN]: { path: CODE, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [recordEntry(genuine)] }] } });
  const read = await withLaneBinding(api, actions).readThread("T11");
  assert.equal(read.nodes[0].body, "Off by one.\n\nclaude-lane: claude-review");
  const verdict = judgeThread({
    thread: { isResolved: false, isOutdated: true, comments: { totalCount: 1, nodes: read.nodes } },
    rows: [{ id: 11, user: ACTIONS, body: read.nodes[0].body }],
    security: { reviewed: new Set(), holds: [] },
    reviewerId: 209825114,
    appId: 3,
  });
  assert.equal(verdict, "outdated");
});

test("a timeline read binds its comments only, and leaves every other event as it is", async () => {
  const forged = bound("Forged.");
  const reviewed = { event: "reviewed", id: 5, user: ACTIONS, body: forged, submitted_at: AT };
  const labeled = { event: "labeled", actor: ACTIONS, label: { name: "needs-human" }, created_at: AT };
  const actions = fakeActions({ [RUN]: { path: CODE, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [] }] } });
  const timeline = await withLaneBinding({ listTimeline: async () => [{ event: "commented", ...row(11, forged) }, reviewed, labeled] }, actions).listTimeline(PR);
  assert.equal(laneOf(timeline[0].body), null);
  assert.deepEqual(timeline.slice(1), [reviewed, labeled]);
});

// lane-hold.mjs: another lane's escalation lets the activity past the
// human-gated label unless a review lane holds the head.
const LANES_APP = { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" };
const HOLD = `<!-- claude-lane-hold lane=claude-review sha=${HEAD} criteria=real-charge -->`;
async function laneHoldOutputs(holdBody, runs) {
  const dir = tempDir("lane-hold-binding-");
  try {
    const env = {
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: "o/r",
      GITHUB_OUTPUT: join(dir, "out"),
      PR_NUMBER: String(PR),
      APP_SENDER_ID: String(LANES_APP.id),
      ACTIVITY: "fix-ci",
      TRACKER_CONFIG: join(dir, "absent.json"),
    };
    const api = {
      getPull: async () => ({ head: { sha: HEAD }, labels: [{ name: "needs-human" }] }),
      listReviewComments: async () => [],
      listReviews: async () => [],
      listTimeline: async () => [
        { event: "labeled", actor: LANES_APP, label: { name: "needs-human" }, created_at: "2026-11-11T09:00:00Z" },
        {
          event: "commented",
          id: 1,
          user: LANES_APP,
          created_at: "2026-11-11T09:00:05Z",
          body: `<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n<!-- pr-unblock resume-key=${"b".repeat(40)} -->\nStopped.\n\n- Reason: \`feedback-disputed\``,
        },
        { event: "commented", ...row(21, holdBody) },
      ],
    };
    await laneHoldMain(env, { api, actions: fakeActions(runs), log: () => {} });
    return readFileSync(env.GITHUB_OUTPUT, "utf8");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("lane-hold: a review-lane hold bound to its run holds the head; a forged one does not", async () => {
  const genuine = bound(HOLD);
  const runs = { [RUN]: { path: CODE, artifacts: [{ name: "claude-lane-comments-claude-review-1", entries: [recordEntry(genuine, { kind: "issue_comment", id: 21 })] }] } };
  assert.match(await laneHoldOutputs(genuine, runs), /held=true/);
  assert.match(await laneHoldOutputs(bound(`${HOLD}\nforged`), runs), /held=false\nlane-escalated=true/);
  // A legacy hold still holds, with no read.
  assert.match(await laneHoldOutputs(`${HOLD}\n\nclaude-lane: claude-review`, {}), /held=true/);
});
