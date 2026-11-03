import assert from "node:assert/strict";
import { test } from "node:test";

import { FINDING_STANDS, MARKER_AUTHOR_ID, securitySignals, VERIFY_NOTE_MARKER } from "./address-feedback.mjs";
import { FINDING_ANSWERED } from "./adjudicate-feedback.mjs";
import { renderReply } from "./publish-feedback.mjs";
import { judgeThread, resolveThreads } from "./resolve-threads.mjs";

const APP = 900;
const CLAUDE = 41;
const CODEX = 199175422;
const OWNER = 100;
const STRANGER = 555;
const HEAD = "a".repeat(40);

const REVIEW = "This drops the error the caller needs.";
const CRITICAL_REVIEW = "severity: CRITICAL\n\nThis writes the token to the log.";
const laneFooter = (lane) => `\n\n\`claude-lane: ${lane}\``;
const reply = (disposition) => renderReply({ disposition, evidence: ["lib/a.mjs:3"], fixSha: disposition === "VALID" ? HEAD : "", note: "The lane's note." });
const VALID = reply("VALID");
const ANSWERED = `${FINDING_ANSWERED}\n**pr-unblock / adjudicate-feedback: the finding does not hold, resolved**`;

let nextId = 1;
// A listThreads node and its REST rows; each comment is [author, body, editor?].
function make(comments, { id = "PRRT_a", outdated = false, resolved = false } = {}) {
  const rows = comments.map(([user, body]) => ({ id: nextId++, user: { id: user }, body, pull_request_review_id: 7 }));
  const thread = {
    id,
    isResolved: resolved,
    isOutdated: outdated,
    comments: {
      totalCount: rows.length,
      nodes: rows.map((row, i) => ({
        databaseId: row.id,
        lastEditedAt: comments[i][2] ? "2026-11-01T00:00:00Z" : null,
        editor: comments[i][2] ? { databaseId: comments[i][2] } : null,
      })),
    },
  };
  return { thread, rows };
}

const NO_SECURITY = { reviewed: new Set(), holds: [] };
const judge = (made, { review = { commit_id: HEAD, submitted_at: "2026-11-01T00:00:00Z" }, security = NO_SECURITY } = {}) =>
  judgeThread({ ...made, review, security, reviewerId: CLAUDE, reviewerIds: [CODEX], appId: APP });

test("a bot finding the lane answered VALID or an adjudication answered resolves, outdated or not", () => {
  assert.equal(judge(make([[CLAUDE, REVIEW], [APP, VALID]])), "answered");
  assert.equal(judge(make([[CLAUDE, REVIEW], [APP, reply("INCORRECT")], [APP, ANSWERED]])), "answered");
  assert.equal(judge(make([[MARKER_AUTHOR_ID, `${REVIEW}${laneFooter("claude-review")}`], [APP, VALID]])), "answered");
});

test("an outdated bot finding resolves; a current one with no answer stays", () => {
  assert.equal(judge(make([[CLAUDE, REVIEW]], { outdated: true })), "outdated");
  assert.equal(judge(make([[CLAUDE, REVIEW]])), "current");
  // A reviewer re-raise after the answer: not answered, so only outdated resolves it.
  assert.equal(judge(make([[CLAUDE, REVIEW], [APP, VALID], [CLAUDE, "Still wrong."]])), "current");
  assert.equal(judge(make([[CLAUDE, REVIEW], [APP, VALID], [CLAUDE, "Still wrong."]], { outdated: true })), "outdated");
});

test("a CRITICAL bot finding stays open, answered or outdated", () => {
  assert.equal(judge(make([[CLAUDE, CRITICAL_REVIEW], [APP, VALID]])), "person-decides");
  assert.equal(judge(make([[CLAUDE, CRITICAL_REVIEW]], { outdated: true })), "person-decides");
  assert.equal(judge(make([[MARKER_AUTHOR_ID, `${CRITICAL_REVIEW}${laneFooter("claude-review")}`], [APP, VALID]])), "person-decides");
  // A reviewer comment after the root that rates it CRITICAL holds it too.
  assert.equal(judge(make([[CLAUDE, REVIEW], [CLAUDE, CRITICAL_REVIEW]], { outdated: true })), "person-decides");
});

test("a security finding a person decides stays open: unrated security-review, a listed bot's on a held or unreviewed head", () => {
  assert.equal(judge(make([[MARKER_AUTHOR_ID, `Unsafe eval.${laneFooter("claude-security-review")}`], [APP, VALID]])), "person-decides");
  assert.equal(judge(make([[MARKER_AUTHOR_ID, `severity: IMPORTANT\n\nUnsafe eval.${laneFooter("claude-security-review")}`], [APP, VALID]])), "answered");
  const codex = () => make([[CODEX, REVIEW]], { outdated: true });
  assert.equal(judge(codex()), "person-decides", "the security-review lane has not reviewed the bot's head");
  const reviewed = securitySignals([{ user: { id: MARKER_AUTHOR_ID }, body: `<!-- claude-lane-reviewed-head lane=claude-security-review sha=${HEAD} -->` }]);
  assert.equal(judge(codex(), { security: reviewed }), "outdated");
  assert.equal(judge(codex(), { security: { ...reviewed, holds: [{ sha: HEAD, at: 0 }] } }), "person-decides");
});

test("a human-authored or human-joined thread stays open", () => {
  assert.equal(judge(make([[OWNER, REVIEW]], { outdated: true })), "not-bot-only");
  assert.equal(judge(make([[CLAUDE, REVIEW], [APP, VALID], [OWNER, "Thanks"]], { outdated: true })), "not-bot-only");
  assert.equal(judge(make([[CLAUDE, REVIEW], [STRANGER, "+1"], [APP, VALID]])), "not-bot-only");
  // A bot comment someone else edited is no longer the bot's alone.
  assert.equal(judge(make([[CLAUDE, REVIEW, OWNER], [APP, VALID]])), "not-bot-only");
  assert.equal(judge(make([[CLAUDE, REVIEW, CLAUDE], [APP, VALID]])), "answered");
  // A thread the lanes App opened is no review finding.
  assert.equal(judge(make([[APP, "note"]], { outdated: true })), "not-bot-only");
});

test("a thread the lane left open or a pr-verify note stays open even when outdated", () => {
  for (const body of [reply("INCORRECT"), reply("UNCERTAIN"), reply("VALID-defer"), `${FINDING_STANDS}\n**the finding stands**`]) {
    assert.equal(judge(make([[CLAUDE, REVIEW], [APP, body]], { outdated: true })), "left-open", body.split("\n")[0]);
  }
  assert.equal(judge(make([[MARKER_AUTHOR_ID, `${VERIFY_NOTE_MARKER}\nA note.`]], { outdated: true })), "verifier-note");
  assert.equal(judge(make([[CLAUDE, REVIEW]], { outdated: true, resolved: true })), "resolved");
});

// A fake API holding one PR's threads; resolveThread marks a thread resolved.
// `edits` maps a thread id to the [body, editor] its comments hold at the re-read.
function fakeApi({ author = { id: OWNER, type: "User" }, made = [], changed = new Set(), edits = {}, failing = new Set() } = {}) {
  const calls = [];
  const threads = made.map(({ thread }) => thread);
  const rows = made.flatMap((m) => m.rows);
  return {
    calls,
    getPull: async () => ({ user: author }),
    listThreads: async () => threads,
    listReviewComments: async () => rows,
    listReviews: async () => [{ id: 7, commit_id: HEAD, submitted_at: "2026-11-01T00:00:00Z", user: { id: CLAUDE } }],
    listIssueComments: async () => [],
    readThread: async (id) => {
      const thread = threads.find((t) => t.id === id);
      const nodes = thread.comments.nodes.map((node, i) => {
        const [body, editor] = edits[id]?.[i] ?? [rows.find((row) => row.id === node.databaseId).body];
        return editor ? { ...node, body, lastEditedAt: "2026-11-02T00:00:00Z", editor: { databaseId: editor } } : { ...node, body };
      });
      const ids = nodes.map((node) => node.databaseId);
      const commentIds = changed.has(id) ? [...ids, 99999] : ids;
      return { isResolved: thread.isResolved, isOutdated: thread.isOutdated, pr: 12, commentCount: commentIds.length, commentIds, nodes };
    },
    resolveThread: async (id) => {
      calls.push(id);
      if (failing.has(id)) {
        throw new Error("HTTP 403");
      }
      threads.find((t) => t.id === id).isResolved = true;
      return true;
    },
  };
}

const run = (api) => resolveThreads({ api, pr: 12, appId: APP, reviewerId: CLAUDE, reviewerIds: [CODEX], trustedHumans: new Set([OWNER]) });

test("on an owner PR it resolves only the answered or outdated non-CRITICAL bot threads", async () => {
  const api = fakeApi({
    made: [
      make([[CLAUDE, REVIEW], [APP, VALID]], { id: "PRRT_answered" }),
      make([[CLAUDE, REVIEW]], { id: "PRRT_outdated", outdated: true }),
      make([[CLAUDE, CRITICAL_REVIEW], [APP, VALID]], { id: "PRRT_critical" }),
      make([[OWNER, REVIEW]], { id: "PRRT_human", outdated: true }),
      make([[CLAUDE, REVIEW]], { id: "PRRT_current" }),
    ],
  });
  assert.deepEqual(await run(api), { skipReason: "", resolved: ["PRRT_answered", "PRRT_outdated"] });
  assert.deepEqual(api.calls, ["PRRT_answered", "PRRT_outdated"]);
});

test("a PR the owner did not open is skipped with nothing resolved", async () => {
  for (const author of [{ id: STRANGER, type: "User" }, { id: APP, type: "Bot" }, { id: OWNER, type: "Bot" }]) {
    const api = fakeApi({ author, made: [make([[CLAUDE, REVIEW], [APP, VALID]])] });
    assert.deepEqual(await run(api), { skipReason: "not-applicable", resolved: [] }, JSON.stringify(author));
    assert.deepEqual(api.calls, []);
  }
});

test("a thread that changed since it was read is left open; a failed resolve fails the job after the rest", async () => {
  const changed = fakeApi({ made: [make([[CLAUDE, REVIEW], [APP, VALID]], { id: "PRRT_x" })], changed: new Set(["PRRT_x"]) });
  assert.deepEqual(await run(changed), { skipReason: "", resolved: [] });
  assert.deepEqual(changed.calls, []);
  const failing = fakeApi({
    made: [make([[CLAUDE, REVIEW], [APP, VALID]], { id: "PRRT_f" }), make([[CLAUDE, REVIEW], [APP, VALID]], { id: "PRRT_g" })],
    failing: new Set(["PRRT_f"]),
  });
  await assert.rejects(run(failing), /could not resolve PRRT_f/);
  assert.deepEqual(failing.calls, ["PRRT_f", "PRRT_g"]);
});

test("a comment edited between the reads is judged again: rated CRITICAL or edited by a person, the thread stays open", async () => {
  const made = () => [make([[CLAUDE, REVIEW], [APP, VALID]], { id: "PRRT_e" }), make([[CLAUDE, REVIEW], [APP, VALID]], { id: "PRRT_kept" })];
  for (const edit of [[CRITICAL_REVIEW, CLAUDE], [REVIEW, OWNER]]) {
    const api = fakeApi({ made: made(), edits: { PRRT_e: [edit] } });
    assert.deepEqual(await run(api), { skipReason: "", resolved: ["PRRT_kept"] }, JSON.stringify(edit));
    assert.deepEqual(api.calls, ["PRRT_kept"]);
  }
  // The bot's own edit that keeps the finding below CRITICAL still resolves.
  const own = fakeApi({ made: made(), edits: { PRRT_e: [["This drops the error, as noted.", CLAUDE]] } });
  assert.deepEqual((await run(own)).resolved, ["PRRT_e", "PRRT_kept"]);
});
