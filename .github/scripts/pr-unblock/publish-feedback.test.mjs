import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { isEscalationReply } from "./address-feedback.mjs";
import { main, publish, renderReply } from "./publish-feedback.mjs";

// Ids from .github/standards/trusted-actors/trusted-actors.json and the
// GitHub users API (github-actions[bot] is 41898282).
const APP = 337595936;
const REVIEWER = 209825114;
const ACTIONS_BOT = 41898282;
const HUMAN = 153232337;
const GATED = "a".repeat(40);
const NOW = "c".repeat(40);
const FIX = "f".repeat(40);
const PUSHED = "d".repeat(40);
const ROUND = "<!-- pr-unblock:address-feedback-round -->";
const MODEL_RUN = "<!-- pr-unblock:address-feedback-model-run 5000-1 -->";
const marker = `<!-- claude-lane-reviewed-head lane=claude-review sha=${GATED} -->\nreviewed.`;

// run.json as the select job writes it: two kept threads.
const RUN = {
  version: 1,
  head_sha: GATED,
  threads: [
    { id: "PRRT_a", path: "src/a.js", comment_ids: [100] },
    { id: "PRRT_b", path: "docs/b.md", comment_ids: [200] },
  ],
};
// The commit apply-feedback-patch pushes: the lanes App's, with the
// review-threads row's message and trailer (patch-rules.json).
const fixCommit = (sha = FIX, fields = {}) => ({
  sha,
  author: { id: APP },
  committer: { id: 19864447 },
  commit: {
    message: "Address review feedback on feature\n\nLane-Activity: pr-unblock/address-feedback\n",
    verification: { verified: true, reason: "valid" },
  },
  ...fields,
});
const reply = (fields) => ({ thread: "PRRT_a", disposition: "INCORRECT", evidence: ["src/a.js:3"], fix_sha: "", note: "Guarded at src/a.js:2.", ...fields });
const lines = (...replies) => replies.map((r) => JSON.stringify(r)).join("\n");

function fakeApi(overrides = {}) {
  const calls = [];
  // A code-review lane finding as the lane posts it (github-actions[bot],
  // review 30, the lane footer), which the adjudicator may judge.
  const comment = (id, path) => ({ id, user: { id: ACTIONS_BOT }, pull_request_review_id: 30, path, line: 1, body: `finding ${id}\n\nclaude-lane: claude-review` });
  const threads = overrides.threads ?? {
    PRRT_a: { ids: [100], resolved: false },
    PRRT_b: { ids: [200], resolved: false },
  };
  return {
    calls,
    posted: () => calls.filter((call) => call[0] === "reply"),
    resolved: () => calls.filter((call) => call[0] === "resolve").map((call) => call[1]),
    markers: () => calls.filter((call) => call[0] === "comment"),
    listIssueComments: async () => [{ id: 1, user: { id: ACTIONS_BOT }, body: marker }, ...(overrides.issueComments ?? [])],
    listReviews: async () => [{ id: 10, user: { id: REVIEWER }, commit_id: GATED }, { id: 30, user: { id: ACTIONS_BOT }, commit_id: GATED }, ...(overrides.reviews ?? [])],
    listReviewComments: async () =>
      overrides.reviewComments ?? [comment(100, "src/a.js"), comment(200, "docs/b.md")],
    listThreads: async () =>
      Object.entries(threads).map(([id, t]) => ({
        id,
        isResolved: t.resolved,
        comments: { totalCount: t.ids.length, nodes: t.ids.map((databaseId) => ({ databaseId })) },
      })),
    readThread: async (id) => {
      if (overrides.readFails?.includes(id)) {
        throw new Error("POST https://api.github.com/graphql returned 502");
      }
      const t = overrides.reread?.[id] ?? threads[id];
      // After the reply lands the thread holds it too, plus any comment the
      // case says arrived meanwhile.
      const replied = calls.filter((call) => call[0] === "reply" && call[2] === t.ids[0]).length;
      const ids = replied > 0 ? [...t.ids, ...Array.from({ length: replied }, (_, k) => 900 + k), ...(overrides.arrivedDuringReply ?? [])] : t.ids;
      return { isResolved: t.resolved, pr: t.pr ?? 42, commentCount: ids.length, commentIds: ids };
    },
    // The PR branch reads NOW until `movesAfter` reads, then a later push.
    readBranch: async (ref) => {
      calls.push(["readBranch", ref]);
      return calls.filter((call) => call[0] === "readBranch").length > (overrides.movesAfter ?? Infinity) ? PUSHED : NOW;
    },
    getCommit: async (sha) => overrides.commits?.[sha] ?? { files: [{ filename: "src/a.js" }] },
    // The PR's commits, oldest first; none earlier than the range by default.
    listPullCommits: async () => overrides.pullCommits ?? [],
    compare: async (base, head) => {
      calls.push(["compare", base, head]);
      return overrides.compare ?? { status: "ahead", commits: [fixCommit()], files: [{ filename: "src/a.js" }] };
    },
    replyToComment: async (pr, commentId, body) => {
      const earlier = calls.filter((call) => call[0] === "reply" && call[2] === commentId).length;
      calls.push(["reply", pr, commentId, body]);
      return { id: 900 + earlier, in_reply_to_id: overrides.landOn ?? commentId };
    },
    resolveThread: async (id) => {
      calls.push(["resolve", id]);
      if (overrides.resolveLandsThenFails && calls.filter((call) => call[0] === "resolve").length === 1) {
        threads[id].resolved = true;
        throw new Error("POST https://api.github.com/graphql returned 502");
      }
      if (calls.filter((call) => call[0] === "resolve").length <= (overrides.resolveFailures ?? 0)) {
        throw new Error("POST https://api.github.com/graphql returned 502");
      }
      return true;
    },
    createIssueComment: async (pr, body) => {
      if (overrides.markerFails) {
        throw new Error("POST https://api.github.com/repos/o/r/issues/42/comments returned 502");
      }
      calls.push(["comment", pr, body]);
    },
  };
}

const exists = (path) => ["src/a.js", "docs/b.md"].includes(path);

// run.json keeping just the threads the replies name, so a case about one
// reply has a complete reply set; cases about completeness pass RUN itself.
function runFor(repliesText) {
  let named;
  try {
    named = new Set(repliesText.split("\n").filter(Boolean).map((line) => JSON.parse(line).thread));
  } catch {
    return JSON.stringify(RUN);
  }
  const threads = RUN.threads.filter((thread) => named.has(thread.id));
  return JSON.stringify(threads.length > 0 ? { ...RUN, threads } : RUN);
}

// The adjudicate-feedback job's verdicts.json, stamped with the head the
// select job read (run.json's GATED), the code the adjudicator saw; the gated
// head NOW is past this round's fix push.
const verdicts = (...entries) => JSON.stringify({ version: 1, head_sha: GATED, threads: entries });
const judged = (thread, verdict, question = "none") => ({ thread, verdict, question });

const run = (api, repliesText, runText = runFor(repliesText), adjudication = null) =>
  publish({
    api,
    pr: 42,
    headSha: NOW,
    headRef: "feature",
    appId: APP,
    modelRun: "5000-1",
    reviewerId: REVIEWER,
    trustedHumans: new Set([HUMAN]),
    readArtifact: () => ({ runText, repliesText }),
    readAdjudication: () => adjudication,
    fileExists: exists,
  });

// The review-thread tool counts the note in code points (jq length); 2000
// emoji are 4000 UTF-16 units and must still pass here.
test("a note of exactly 2000 emoji is accepted and posted", async () => {
  const api = fakeApi();
  const result = await run(api, lines(reply({ note: "😀".repeat(2000) })));
  // INCORRECT with no verdict goes to a person; what matters is the note passed validation.
  assert.equal(result.escalationReason, "feedback-unadjudicated");
  assert.equal(api.posted().length, 1);
});

test("a note naming a token placeholder and a commit sha is accepted and posted", async () => {
  const api = fakeApi();
  const result = await run(api, lines(reply({ note: `The fixture uses ghs_job; see ${FIX}.` })));
  assert.equal(result.escalationReason, "feedback-unadjudicated");
  assert.equal(api.posted().length, 1);
});

test("a VALID reply is posted in the fixed template on its root comment and resolved", async () => {
  const api = fakeApi();
  const result = await run(api, lines(reply({ disposition: "VALID", note: "Guarded the null case." })));
  assert.equal(result.escalationReason, "");
  assert.deepEqual(api.posted(), [
    [
      "reply",
      42,
      100,
      [
        "**pr-unblock / address-feedback: VALID, fixed**",
        "",
        "Evidence: `src/a.js:3`",
        `Fix: ${FIX}`,
        "",
        "```text",
        "Guarded the null case.",
        "```",
      ].join("\n"),
    ],
  ]);
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
  assert.deepEqual(api.calls.find((call) => call[0] === "compare"), ["compare", GATED, NOW]);
});

// A thread the lane left UNCERTAIN, then a trusted person's decision.
function decided() {
  const at = (minute) => `2026-10-17T20:0${minute}:00Z`;
  const row = (id, user, body, minute) => ({ id, user: { id: user }, pull_request_review_id: 10, path: "src/a.js", line: 1, body, created_at: at(minute) });
  const escalation = renderReply({ disposition: "UNCERTAIN", evidence: [], fixSha: "", note: "Needs the owner." });
  return {
    reviewComments: [row(100, REVIEWER, "finding 100", 0), row(101, APP, escalation, 1), row(102, HUMAN, "Drop the reference.", 2)],
    threads: { PRRT_a: { ids: [100, 101, 102], resolved: false } },
  };
}
const decidedRun = JSON.stringify({ ...RUN, threads: [{ id: "PRRT_a", path: "src/a.js", comment_ids: [100, 101, 102] }] });

test("a VALID reply on a thread a trusted person decided after the escalation is posted and resolved", async () => {
  const api = fakeApi(decided());
  const result = await run(api, lines(reply({ disposition: "VALID", note: "Applied the decision." })), decidedRun);
  assert.equal(result.escalationReason, "");
  assert.deepEqual(api.posted().map((call) => call[2]), [100]);
  assert.match(api.posted()[0][3], /^\*\*pr-unblock \/ address-feedback: VALID, fixed\*\*/);
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
});

test("a decided thread whose reply no trusted person wrote is not posted on", async () => {
  const api = fakeApi(decided());
  await publish({
    api,
    pr: 42,
    headSha: NOW,
    headRef: "feature",
    appId: APP,
    modelRun: "5000-1",
    reviewerId: REVIEWER,
    trustedHumans: new Set(),
    readArtifact: () => ({ runText: decidedRun, repliesText: lines(reply({ disposition: "VALID" })) }),
    fileExists: exists,
  });
  assert.deepEqual(api.posted(), []);
  assert.deepEqual(api.resolved(), []);
});

test("every reply the reply job leaves open reads as an escalation; a VALID one does not", () => {
  const body = (disposition) => renderReply({ disposition, evidence: [], fixSha: disposition === "VALID" ? FIX : "", note: "n" });
  for (const disposition of ["INCORRECT", "UNCERTAIN", "VALID-defer"]) {
    assert.equal(isEscalationReply({ user: { id: APP }, body: body(disposition) }, APP), true, disposition);
  }
  assert.equal(isEscalationReply({ user: { id: APP }, body: body("VALID") }, APP), false);
});

test("INCORRECT is posted and left open; UNCERTAIN and VALID-defer are posted, left open, and escalate", async () => {
  const api = fakeApi();
  const result = await run(
    api,
    lines(
      reply({ evidence: ["src/a.js:3", "docs/b.md:1"] }),
      reply({ thread: "PRRT_b", disposition: "UNCERTAIN", evidence: [], note: "Needs the vendor docs." }),
    ),
    undefined,
    // The finding stands, so INCORRECT leaves the thread open; UNCERTAIN
    // still escalates.
    verdicts(judged("PRRT_a", "reviewer")),
  );
  assert.equal(result.escalationReason, "feedback-uncertain");
  assert.deepEqual(api.resolved(), []);
  assert.match(api.posted()[0][3], /^\*\*pr-unblock \/ address-feedback: INCORRECT, left open\*\*\n\nEvidence: `src\/a.js:3`, `docs\/b.md:1`\n/);
  assert.match(api.posted()[1][3], /UNCERTAIN, left open for a person\*\*\n\nEvidence: none in the checkout\n/);
  assert.deepEqual(api.calls.find((call) => call[0] === "compare"), ["compare", GATED, NOW], "a moved branch is checked even with no VALID reply");

  const defer = fakeApi();
  assert.equal((await run(defer, lines(reply({ disposition: "VALID-defer" })))).escalationReason, "feedback-uncertain");
  assert.match(defer.posted()[0][3], /VALID \(defer\), left open for a person/);
  assert.deepEqual(defer.resolved(), []);
});

test("the round marker is posted once, as the first line, numbered after the App's earlier rounds", async () => {
  const api = fakeApi({
    issueComments: [
      { id: 2, user: { id: APP }, body: `${ROUND}\nround 1` },
      { id: 3, user: { id: HUMAN }, body: ROUND },
    ],
  });
  await run(api, lines(reply()));
  assert.equal(api.markers().length, 1);
  assert.equal(api.markers()[0][1], 42);
  assert.equal(api.markers()[0][2], `${ROUND}\n${MODEL_RUN}\npr-unblock / address-feedback finished round 2 of max 3 on ${NOW}.`);
});

test("the round marker names the configured cap", async () => {
  const api = fakeApi();
  await publish({
    api,
    pr: 42,
    headSha: NOW,
    headRef: "feature",
    appId: APP,
    modelRun: "5000-1",
    maxRounds: 3,
    reviewerId: REVIEWER,
    readArtifact: () => ({ runText: runFor(lines(reply())), repliesText: lines(reply()) }),
    fileExists: exists,
  });
  assert.match(api.markers()[0][2], /finished round 1 of max 4 on/);
});

test("the fresh fixer's round, past the cap, is the last of the max", async () => {
  const api = fakeApi({
    issueComments: [1, 2].map((n) => ({ id: n + 1, user: { id: APP }, body: `${ROUND}\nround ${n}` })),
  });
  await run(api, lines(reply()));
  assert.match(api.markers()[0][2], /finished round 3 of max 3 on /);
});

// #7545: a re-run of the reply job alone reuses the model run's artifact, so
// it must not count that model turn as a second round.
test("a re-run for a model run whose round the App already recorded posts no second marker", async () => {
  const api = fakeApi({
    issueComments: [{ id: 2, user: { id: APP }, body: `${ROUND}\n${MODEL_RUN}\nround 1` }],
  });
  await run(api, lines(reply()));
  assert.equal(api.markers().length, 0);
});

test("a marker naming the run from another author or for another run does not stop the round marker", async () => {
  for (const issueComments of [
    [{ id: 2, user: { id: HUMAN }, body: `${ROUND}\n${MODEL_RUN}` }],
    [{ id: 2, user: { id: APP }, body: `${ROUND}\n<!-- pr-unblock:address-feedback-model-run 5000-2 -->` }],
    [{ id: 2, user: { id: APP }, body: `note\n${MODEL_RUN}` }],
  ]) {
    const api = fakeApi({ issueComments });
    await run(api, lines(reply()));
    assert.equal(api.markers().length, 1, JSON.stringify(issueComments));
  }
});

// #7545: fixesLanded judged the branch up to the head this job gated; a push
// after that is unjudged, so nothing is posted or resolved against it.
test("a push after the gated head, before the first post, posts nothing and escalates feedback-not-landed", async () => {
  const api = fakeApi({ movesAfter: 0 });
  const result = await run(api, lines(reply({ disposition: "VALID" })));
  assert.equal(result.escalationReason, "feedback-not-landed");
  assert.deepEqual(api.posted(), []);
  assert.deepEqual(api.resolved(), []);
  assert.equal(api.markers().length, 1);
  assert.ok(api.calls.some((call) => call[0] === "readBranch" && call[1] === "feature"));
});

test("a push after a reply posted leaves its VALID thread open, posts no later reply, and escalates feedback-partial", async () => {
  const api = fakeApi({ movesAfter: 1 });
  const result = await run(
    api,
    lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
    JSON.stringify(RUN),
  );
  assert.equal(result.escalationReason, "feedback-partial");
  assert.deepEqual(api.posted().map((call) => call[2]), [100]);
  assert.deepEqual(api.resolved(), []);
});

// Every case here must post no reply, resolve nothing, still post the round
// marker, and escalate feedback-invalid.
const INVALID = [
  ["a line that does not parse", "not json"],
  ["an array line", "[1]"],
  ["an extra field", lines(reply({ resolve: true }))],
  ["a missing field", JSON.stringify({ thread: "PRRT_a", disposition: "INCORRECT", evidence: ["src/a.js:3"], note: "x" })],
  ["a thread the runner did not keep", lines(reply({ thread: "PRRT_zzz" }))],
  ["a thread a human opened, never kept", lines(reply({ thread: "PRRT_human" }))],
  ["two replies on one thread", lines(reply(), reply())],
  ["a disposition outside the four", lines(reply({ disposition: "APPROVE" }))],
  ["a VALID reply naming a fix commit", lines(reply({ disposition: "VALID", fix_sha: FIX }))],
  ["a fix on an INCORRECT reply", lines(reply({ fix_sha: FIX }))],
  ["a short fix sha", lines(reply({ disposition: "VALID", fix_sha: "abc" }))],
  ["INCORRECT with no evidence", lines(reply({ evidence: [] }))],
  ["evidence with no line", lines(reply({ evidence: ["src/a.js"] }))],
  ["evidence escaping the checkout", lines(reply({ evidence: ["../../etc/passwd:1"] }))],
  ["evidence naming a missing file", lines(reply({ evidence: ["src/missing.js:1"] }))],
  ["eleven evidence entries", lines(reply({ evidence: Array(11).fill("src/a.js:3") }))],
  ["an empty note", lines(reply({ note: "" }))],
  ["a note over 2000 characters", lines(reply({ note: "x".repeat(2001) }))],
  ["a note of 2001 emoji", lines(reply({ note: "😀".repeat(2001) }))],
  ["a note carrying a marker", lines(reply({ note: `done ${ROUND}` }))],
  ["a note closing an HTML comment", lines(reply({ note: "a --> b" }))],
  ["a note carrying a token", lines(reply({ note: `token ghs_${"A".repeat(36)}` }))],
  ["a note carrying a stateless installation token", lines(reply({ note: `token ${"ghs"}_123456_${Array(3).fill("FAKE-not_a_token".repeat(10)).join(".")}` }))],
  ["a note carrying a JWT-shaped installation token", lines(reply({ note: `token ${"ghs"}_${Array(3).fill("eyJGAKEnotAtoken".repeat(10)).join(".")}` }))],
  ["a note carrying a control character", lines(reply({ note: "bell \u0007" }))],
  ["a note carrying a direction override", lines(reply({ note: "safe‮evil" }))],
  ["a note carrying a zero-width space", lines(reply({ note: "a​b" }))],
  ["replies over the 49152-byte limit", `${lines(reply())}\n${" ".repeat(49152)}`],
];

for (const [label, text] of INVALID) {
  test(`feedback-invalid, nothing posted: ${label}`, async () => {
    const api = fakeApi({ threads: { PRRT_a: { ids: [100], resolved: false }, PRRT_human: { ids: [300], resolved: false } } });
    const result = await run(api, text);
    assert.equal(result.escalationReason, "feedback-invalid");
    assert.deepEqual(api.posted(), []);
    assert.deepEqual(api.resolved(), []);
    assert.equal(api.markers().length, 1);
  });
}

test("feedback-invalid, nothing posted: a malformed run.json or a missing artifact", async () => {
  for (const runText of ["{", JSON.stringify({ ...RUN, head_sha: "x" }), JSON.stringify({ ...RUN, threads: [{ id: "PRRT_a", path: "src/a.js", comment_ids: [] }] })]) {
    const api = fakeApi();
    assert.equal((await run(api, lines(reply()), runText)).escalationReason, "feedback-invalid");
    assert.deepEqual(api.posted(), []);
    assert.equal(api.markers().length, 1);
  }
  const api = fakeApi();
  const missing = Object.assign(new Error("no file"), { code: "ENOENT" });
  const result = await publish({
    api,
    pr: 42,
    headSha: NOW,
    appId: APP,
    reviewerId: REVIEWER,
    readArtifact: () => {
      throw missing;
    },
    fileExists: exists,
  });
  assert.equal(result.escalationReason, "feedback-invalid");
  assert.equal(api.markers().length, 1);
});

test("an empty or partial reply set posts nothing and escalates feedback-incomplete", async () => {
  for (const text of ["", lines(reply())]) {
    const api = fakeApi();
    assert.equal((await run(api, text, JSON.stringify(RUN))).escalationReason, "feedback-incomplete");
    assert.deepEqual(api.posted(), []);
    assert.deepEqual(api.resolved(), []);
    assert.equal(api.markers().length, 1);
  }
});

// Owner decision 2026-10-24: a disputed finding goes to an adjudicator, not
// to a person. Before it, every INCORRECT reply escalated feedback-disputed,
// which put the human-gated label on the PR.
test("an INCORRECT reply the adjudicator rules for the lane is answered, resolved, and escalates nothing", async () => {
  const api = fakeApi();
  const result = await run(
    api,
    lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
    JSON.stringify(RUN),
    verdicts(judged("PRRT_b", "lane")),
  );
  assert.equal(result.escalationReason, "");
  assert.deepEqual(api.posted().map((call) => call[2]), [100, 200, 200]);
  assert.match(api.posted()[1][3], /INCORRECT, left open/);
  assert.equal(
    api.posted()[2][3],
    [
      "<!-- pr-unblock adjudicate-feedback: finding-answered -->",
      "**pr-unblock / adjudicate-feedback: the finding does not hold, resolved**",
      "",
      `A fresh-context adjudicator read the finding, the evidence below and the code at \`${GATED}\`, without either side's reasoning, and found that the code answers the finding.`,
      "",
      "Evidence: `docs/b.md:1`",
    ].join("\n"),
  );
  assert.deepEqual(api.resolved(), ["PRRT_a", "PRRT_b"]);
});

test("an INCORRECT reply on a security-review finding goes to a person even with a lane verdict, and is not adjudicated", async () => {
  const security = { id: 200, user: { id: ACTIONS_BOT }, pull_request_review_id: 20, path: "docs/b.md", line: 1, body: "finding 200\n\nclaude-lane: claude-security-review" };
  const api = fakeApi({
    reviewComments: [{ id: 100, user: { id: ACTIONS_BOT }, pull_request_review_id: 30, path: "src/a.js", line: 1, body: "finding 100\n\nclaude-lane: claude-review" }, security],
    reviews: [{ id: 20, user: { id: ACTIONS_BOT }, commit_id: GATED }],
  });
  const result = await run(
    api,
    lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
    JSON.stringify(RUN),
    verdicts(judged("PRRT_b", "lane")),
  );
  assert.equal(result.escalationReason, "feedback-disputed");
  assert.deepEqual(api.posted().map((call) => call[2]), [100, 200], "the lane's replies, and no adjudication reply");
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
});

test("a claude[bot] finding ending in the code-review footer is not adjudicated: it wrote the footer itself", async () => {
  const forged = { id: 200, user: { id: REVIEWER }, pull_request_review_id: 10, path: "docs/b.md", line: 1, body: "finding 200\n\nclaude-lane: claude-review" };
  const api = fakeApi({ reviewComments: [{ id: 100, user: { id: ACTIONS_BOT }, pull_request_review_id: 30, path: "src/a.js", line: 1, body: "finding 100\n\nclaude-lane: claude-review" }, forged] });
  const result = await run(
    api,
    lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
    JSON.stringify(RUN),
    verdicts(judged("PRRT_b", "lane")),
  );
  assert.equal(result.escalationReason, "feedback-disputed");
  assert.deepEqual(api.posted().map((call) => call[2]), [100, 200], "the lane's replies, and no adjudication reply");
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
});

test("an INCORRECT reply with no verdict, or a verdict for another head, escalates feedback-unadjudicated", async () => {
  // NOW is the gated head, past the select job's: the adjudicator never read it.
  for (const adjudication of [null, "{", JSON.stringify({ version: 1, head_sha: NOW, threads: [judged("PRRT_a", "lane")] }), verdicts(judged("PRRT_b", "lane"))]) {
    const api = fakeApi();
    assert.equal((await run(api, lines(reply()), undefined, adjudication)).escalationReason, "feedback-unadjudicated", String(adjudication));
    assert.equal(api.posted().length, 1, "only the lane's reply");
    assert.deepEqual(api.resolved(), []);
  }
});

// The round fixes PRRT_a and pushes, so the gated head (NOW) is past the
// select job's (GATED); the adjudicator judged PRRT_b at GATED, and its
// verdict still applies.
test("a verdict lands in the same round as a fix push: the verdict for the select job's head is applied", async () => {
  const api = fakeApi();
  const result = await run(
    api,
    lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
    JSON.stringify(RUN),
    JSON.stringify({ version: 1, head_sha: GATED, threads: [judged("PRRT_b", "lane")] }),
  );
  assert.deepEqual(api.calls.find((call) => call[0] === "compare"), ["compare", GATED, NOW], "the fix push moved the head");
  assert.equal(result.escalationReason, "");
  assert.deepEqual(api.resolved(), ["PRRT_a", "PRRT_b"]);
  assert.match(api.posted()[2][3], new RegExp(`the code at \`${GATED}\``));
});

test("a reviewer verdict posts the finding-stands reply and leaves the thread open for the next round", async () => {
  // A fix commit landed this round, so the review lanes run again on the new
  // head and the next round picks the thread up.
  const api = fakeApi();
  const result = await run(
    api,
    lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
    JSON.stringify(RUN),
    verdicts(judged("PRRT_b", "reviewer")),
  );
  assert.equal(result.escalationReason, "");
  assert.equal(result.skipReason, "", "the moved head gets a review run, which starts the next round");
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
  const stands = api.posted()[2][3].split("\n");
  assert.equal(stands[0], "<!-- pr-unblock adjudicate-feedback: finding-stands -->");
  assert.equal(stands[1], "**pr-unblock / adjudicate-feedback: the finding stands**");
  assert.match(stands[3], /another INCORRECT reply on this thread is not accepted/);
  assert.equal(stands[5], "Evidence: `docs/b.md:1`");
});

// A round that leaves the PR head where the select job read it (NOW): no
// review run follows, so the reply job skips finding-stands for the sweep
// (feedback-dispatch.mjs) to dispatch the head again; no person is asked.
const unmoved = { status: "identical", commits: [], files: [] };
const atNow = (threads = RUN.threads) => JSON.stringify({ ...RUN, head_sha: NOW, threads });
const verdictsAt = (head, ...entries) => JSON.stringify({ version: 1, head_sha: head, threads: entries });

test("a finding that stands with the head unmoved skips finding-stands and escalates nothing", async () => {
  const api = fakeApi({ compare: unmoved });
  const result = await run(api, lines(reply()), atNow([RUN.threads[0]]), verdictsAt(NOW, judged("PRRT_a", "reviewer")));
  assert.equal(result.escalationReason, "");
  assert.equal(result.skipReason, "finding-stands");
  assert.equal(api.posted().length, 2, "the lane's reply and the finding-stands reply");
  assert.deepEqual(api.resolved(), []);

  // An UNCERTAIN reply in the same round still goes to a person.
  const uncertain = fakeApi({ compare: unmoved });
  const both = await run(
    uncertain,
    lines(reply(), reply({ thread: "PRRT_b", disposition: "UNCERTAIN", evidence: [], note: "Needs the vendor docs." })),
    atNow(),
    verdictsAt(NOW, judged("PRRT_a", "reviewer")),
  );
  assert.deepEqual([both.escalationReason, both.skipReason], ["feedback-uncertain", ""]);
});

// #9560's fallback lands a VALID reply on an earlier lane commit: nothing is
// pushed, so the standing finding beside it still needs the sweep.
test("a VALID reply landed on an earlier fix pushes nothing: a finding standing beside it skips finding-stands", async () => {
  const at = (time) => `2026-10-22T${time}:00Z`;
  const api = fakeApi({
    compare: unmoved,
    pullCommits: [fixCommit("e".repeat(40), { commit: { ...fixCommit().commit, committer: { date: at("11:00") } } })],
    commits: { ["e".repeat(40)]: { files: [{ filename: "src/a.js", patch: "@@ -1,2 +1,4 @@\n a\n+b\n+c\n d" }] } },
    reviewComments: [
      { id: 100, user: { id: ACTIONS_BOT }, pull_request_review_id: 30, path: "src/a.js", line: 1, body: "finding 100\n\nclaude-lane: claude-review", created_at: at("10:00") },
      { id: 200, user: { id: ACTIONS_BOT }, pull_request_review_id: 30, path: "docs/b.md", line: 1, body: "finding 200\n\nclaude-lane: claude-review", created_at: at("10:00") },
    ],
  });
  const result = await run(
    api,
    lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
    atNow(),
    verdictsAt(NOW, judged("PRRT_b", "reviewer")),
  );
  assert.match(api.posted()[0][3], new RegExp(`^Fix: ${"e".repeat(40)}$`, "m"), "the earlier fix landed");
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
  assert.deepEqual([result.escalationReason, result.skipReason], ["", "finding-stands"]);
});

test("a human verdict posts no adjudication reply and escalates with the question it names", async () => {
  for (const question of ["intent", "design", "security"]) {
    const api = fakeApi();
    const result = await run(api, lines(reply()), undefined, verdicts(judged("PRRT_a", "human", question)));
    assert.equal(result.escalationReason, `feedback-question-${question}`);
    assert.equal(api.posted().length, 1);
    assert.deepEqual(api.resolved(), []);
  }
  // A question only the owner answers stays theirs: it outranks a stands
  // verdict in the same round, head unmoved, and no sweep skip is taken.
  const both = fakeApi({ compare: { status: "identical", commits: [], files: [] } });
  const result = await run(
    both,
    lines(reply(), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
    JSON.stringify({ ...RUN, head_sha: NOW }),
    JSON.stringify({ version: 1, head_sha: NOW, threads: [judged("PRRT_a", "reviewer"), judged("PRRT_b", "human", "security")] }),
  );
  assert.deepEqual([result.escalationReason, result.skipReason], ["feedback-question-security", ""]);
});

test("an adjudication reply is not posted on a thread that changed after the lane's reply", async () => {
  const api = fakeApi({ arrivedDuringReply: [950] });
  assert.equal((await run(api, lines(reply()), undefined, verdicts(judged("PRRT_a", "lane")))).escalationReason, "feedback-partial");
  assert.equal(api.posted().length, 1);
  assert.deepEqual(api.resolved(), []);
});

// A thread whose finding stood at an earlier adjudication: the review
// comment, the lane's INCORRECT reply, then the lanes App's stands reply.
const STOOD = "<!-- pr-unblock adjudicate-feedback: finding-stands -->\n**pr-unblock / adjudicate-feedback: the finding stands**";
const stoodApi = (overrides = {}) =>
  fakeApi({
    threads: { PRRT_a: { ids: [100, 101, 102], resolved: false } },
    reviewComments: [
      { id: 100, user: { id: ACTIONS_BOT }, pull_request_review_id: 30, path: "src/a.js", line: 1, body: "finding 100\n\nclaude-lane: claude-review" },
      { id: 101, user: { id: APP }, pull_request_review_id: 11, path: "src/a.js", line: 1, body: "**pr-unblock / address-feedback: INCORRECT, left open**" },
      { id: 102, user: { id: APP }, pull_request_review_id: 12, path: "src/a.js", line: 1, body: STOOD },
    ],
    ...overrides,
  });
const stoodRun = JSON.stringify({ ...RUN, threads: [{ id: "PRRT_a", path: "src/a.js", comment_ids: [100, 101, 102] }] });

test("no second dispute: an INCORRECT reply on a thread whose finding stood escalates feedback-disputed and is not adjudicated", async () => {
  const api = stoodApi({ compare: { status: "identical", commits: [], files: [] } });
  const result = await run(api, lines(reply()), stoodRun, verdicts(judged("PRRT_a", "lane")));
  assert.equal(result.escalationReason, "feedback-disputed");
  assert.equal(api.posted().length, 1, "the lane's reply, and no adjudication reply");
  assert.match(api.posted()[0][3], /INCORRECT, left open/);
  assert.deepEqual(api.resolved(), []);
});

test("the cap: a stood thread the next round leaves open escalates feedback-disputed; one it fixes resolves", async () => {
  for (const disposition of ["UNCERTAIN", "VALID-defer"]) {
    const api = stoodApi({ compare: { status: "identical", commits: [], files: [] } });
    const result = await run(api, lines(reply({ disposition, evidence: [] })), stoodRun);
    assert.equal(result.escalationReason, "feedback-disputed", disposition);
    assert.deepEqual(api.resolved(), []);
  }
  const fixed = stoodApi();
  assert.equal((await run(fixed, lines(reply({ disposition: "VALID" })), stoodRun)).escalationReason, "");
  assert.deepEqual(fixed.resolved(), ["PRRT_a"]);
});

test("a VALID-only reply set escalates nothing", async () => {
  const api = fakeApi();
  assert.equal((await run(api, lines(reply({ disposition: "VALID" })))).escalationReason, "");
});

for (const [label, compare] of [
  // apply-feedback-patch pushed nothing: superseded, refused, escalated or held.
  ["the PR branch did not move", { status: "identical", commits: [], files: [] }],
  ["the only new commit is a person's", { status: "ahead", commits: [fixCommit("e".repeat(40), { author: { id: HUMAN } })], files: [{ filename: "src/a.js" }] }],
  ["the App's new commit carries no fix trailer", { status: "ahead", commits: [fixCommit(FIX, { commit: { ...fixCommit().commit, message: "Address review feedback on feature\n" } })], files: [{ filename: "src/a.js" }] }],
  ["the App's new commit is another activity's", { status: "ahead", commits: [fixCommit(FIX, { commit: { ...fixCommit().commit, message: "Fix\n\nLane-Activity: pr-unblock/fix-ci\n" } })], files: [{ filename: "src/a.js" }] }],
  ["two fix commits", { status: "ahead", commits: [fixCommit(), fixCommit("e".repeat(40))], files: [{ filename: "src/a.js" }] }],
  ["the branch diverged from the gated head", { status: "diverged", commits: [fixCommit()], files: [{ filename: "src/a.js" }] }],
  ["the branch changed a path no kept thread names", { status: "ahead", commits: [fixCommit()], files: [{ filename: "src/a.js" }, { filename: "src/other.js" }] }],
  ["the branch changed .github/", { status: "ahead", commits: [fixCommit()], files: [{ filename: ".github/workflows/ci.yml" }] }],
  ["the branch renamed a file out of .github/", { status: "ahead", commits: [fixCommit()], files: [{ filename: "src/a.js", previous_filename: ".github/x.yml" }] }],
  ["the branch changed too many files to check", { status: "ahead", commits: [fixCommit()], files: Array(300).fill({ filename: "src/a.js" }) }],
]) {
  test(`feedback-not-landed, nothing posted: ${label}`, async () => {
    const api = fakeApi({ compare });
    const result = await run(api, lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })));
    assert.equal(result.escalationReason, "feedback-not-landed");
    assert.deepEqual(api.posted(), []);
    assert.deepEqual(api.resolved(), []);
    assert.equal(api.markers().length, 1);
  });
}

// A retry after a round whose fix commit landed but whose replies did not
// post: the branch did not move since, and the fix is an earlier commit on
// the PR. The thread's first comment is from 10:00.
const EARLIER = "e".repeat(40);
const earlierFix = ({ date = "2026-10-22T11:00:00Z", ...fields } = {}) =>
  fixCommit(EARLIER, { ...fields, commit: { ...fixCommit().commit, committer: { date }, ...fields.commit } });
const threadRow = (id, user, body, time) => ({ id, user: { id: user }, pull_request_review_id: 10, path: "src/a.js", line: 1, body, created_at: `2026-10-22T${time}:00Z` });
// The fix's hunk holds new-side lines 1 to 4 of src/a.js, so the default
// evidence, src/a.js:3, cites a line it changed.
const FIXED = [{ filename: "src/a.js", patch: "@@ -1,2 +1,4 @@\n a\n+b\n+c\n d" }];
// `others`: review comments on other threads, such as the lane's replies there.
const retry = (pullCommits, files = FIXED, reviewComments = [threadRow(100, REVIEWER, "finding 100", "10:00")], others = []) =>
  fakeApi({
    compare: { status: "identical", commits: [], files: [] },
    pullCommits: [{ sha: "0".repeat(40), author: { id: HUMAN }, commit: { message: "feat: start\n", committer: { date: "2026-10-22T09:00:00Z" } } }, ...pullCommits],
    commits: { [EARLIER]: { files } },
    reviewComments: [...reviewComments, ...others],
    threads: { PRRT_a: { ids: reviewComments.map((row) => row.id), resolved: false } },
  });
const retryRun = (ids) => JSON.stringify({ ...RUN, threads: [{ id: "PRRT_a", path: "src/a.js", comment_ids: ids }] });

test("a VALID reply whose fix is an earlier lane commit after the thread's comment on its path lands, naming that commit", async () => {
  const api = retry([earlierFix()]);
  const result = await run(api, lines(reply({ disposition: "VALID", note: "Guarded the null case." })));
  assert.equal(result.escalationReason, "");
  assert.equal(api.posted().length, 1);
  assert.match(api.posted()[0][3], new RegExp(`^Fix: ${EARLIER}$`, "m"));
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
});

for (const [label, pullCommits, files] of [
  ["it is a person's commit", [earlierFix({ author: { id: HUMAN } })]],
  ["it carries no fix trailer", [earlierFix({ commit: { message: "Address review feedback on feature\n" } })]],
  ["it is not signed by web-flow", [earlierFix({ committer: { id: HUMAN } })]],
  ["its signature is not valid", [earlierFix({ commit: { verification: { verified: false, reason: "unsigned" } } })]],
  ["it was committed before the thread's comment", [earlierFix({ date: "2026-10-22T09:30:00Z" })]],
  ["it changed another path", [earlierFix()], [{ filename: "docs/b.md", patch: FIXED[0].patch }]],
  // Another finding on the same file, fixed further down it.
  ["it changed no line the evidence cites", [earlierFix()], [{ filename: "src/a.js", patch: "@@ -10,2 +10,3 @@\n a\n+b\n c" }]],
  // A person's later commit on the file shifts its lines off the fix's.
  ["a later commit changed the cited file", [earlierFix(), { sha: "9".repeat(40), author: { id: HUMAN }, commit: { message: "tweak\n", committer: { date: "2026-10-22T12:00:00Z" } } }]],
]) {
  test(`feedback-not-landed, nothing posted: an earlier commit is no fix when ${label}`, async () => {
    const api = retry(pullCommits, files);
    const result = await run(api, lines(reply({ disposition: "VALID" })));
    assert.equal(result.escalationReason, "feedback-not-landed");
    assert.deepEqual(api.posted(), []);
    assert.deepEqual(api.resolved(), []);
  });
}

test("feedback-not-landed: an earlier commit a lane reply already named as another thread's fix is not credited again", async () => {
  const sibling = renderReply({ disposition: "VALID", evidence: ["src/a.js:3"], fixSha: EARLIER, note: "Guarded it." });
  const api = retry([earlierFix()], FIXED, undefined, [{ ...threadRow(301, APP, sibling, "11:05"), path: "src/a.js" }]);
  const result = await run(api, lines(reply({ disposition: "VALID" })));
  assert.equal(result.escalationReason, "feedback-not-landed");
  assert.deepEqual(api.posted(), []);
  // A person's comment naming that commit does not claim it.
  const quoted = retry([earlierFix()], FIXED, undefined, [threadRow(302, HUMAN, `Fix: ${EARLIER}`, "11:05")]);
  assert.equal((await run(quoted, lines(reply({ disposition: "VALID" })))).escalationReason, "");
});

// The lane answered the thread (UNCERTAIN) at 11:30 and a trusted person
// decided at 12:00: a commit before the lane's answer was already judged no
// fix for this thread; one after it can be.
test("an earlier commit counts only when it came after the lane's last answer on the thread", async () => {
  const escalation = renderReply({ disposition: "UNCERTAIN", evidence: [], fixSha: "", note: "Needs the owner." });
  const rows = [threadRow(100, REVIEWER, "finding 100", "10:00"), threadRow(101, APP, escalation, "11:30"), threadRow(102, HUMAN, "Drop the reference.", "12:00")];
  for (const [date, reason] of [["2026-10-22T11:00:00Z", "feedback-not-landed"], ["2026-10-22T11:45:00Z", ""]]) {
    const api = retry([earlierFix({ date })], undefined, rows);
    const result = await run(api, lines(reply({ disposition: "VALID" })), retryRun([100, 101, 102]));
    assert.equal(result.escalationReason, reason, date);
    assert.equal(api.posted().length, reason === "" ? 1 : 0, date);
  }
});

test("an earlier commit is no fix when the reviewer raised the finding again after it", async () => {
  const rows = [threadRow(100, REVIEWER, "finding 100", "10:00"), threadRow(101, REVIEWER, "Still unguarded.", "11:30")];
  const api = retry([earlierFix()], undefined, rows);
  const result = await run(api, lines(reply({ disposition: "VALID" })), retryRun([100, 101]));
  assert.equal(result.escalationReason, "feedback-not-landed");
  assert.deepEqual(api.posted(), []);
});

test("no earlier commit stands in when this round wrote a patch that did not land", async () => {
  const runText = retryRun([100]);
  const repliesText = lines(reply({ disposition: "VALID" }));
  const api = retry([earlierFix()]);
  const result = await publish({
    api,
    pr: 42,
    headSha: NOW,
    headRef: "feature",
    appId: APP,
    modelRun: "5000-1",
    patchState: "written",
    reviewerId: REVIEWER,
    trustedHumans: new Set([HUMAN]),
    readArtifact: () => ({ runText, repliesText }),
    fileExists: exists,
  });
  assert.equal(result.escalationReason, "feedback-not-landed");
  assert.deepEqual(api.posted(), []);
});

test("a VALID fix that also adds a file in its thread's plugin lands; another plugin's file does not", async () => {
  const caseRun = JSON.stringify({ ...RUN, threads: [{ ...RUN.threads[0], path: "plugins/p/evals/c/case.yaml" }] });
  for (const [sample, landed] of [
    ["plugins/p/evals/c/samples/new.json", true],
    ["plugins/p/evals/other/samples/new.json", true],
    ["plugins/q/evals/c/samples/new.json", false],
  ]) {
    const api = fakeApi({
      compare: { status: "ahead", commits: [fixCommit()], files: [{ filename: "plugins/p/evals/c/case.yaml" }, { filename: sample }] },
      commits: { [FIX]: { files: [{ filename: "plugins/p/evals/c/case.yaml" }, { filename: sample }] } },
    });
    const result = await run(api, lines(reply({ disposition: "VALID" })), caseRun);
    assert.equal(result.escalationReason, landed ? "" : "feedback-not-landed", sample);
    assert.equal(api.posted().length, landed ? 1 : 0, sample);
  }
});

// #8116's thread PRRT_kwDOTCGFQM6tojDu: the owner's fix request on
// write-transcript.js named run-transcript.js.
test("a VALID fix that changes a file its thread's named_paths holds lands; one not named, or a malformed list, does not", async () => {
  const T = "plugins/knowledge/skills/video-digest/extraction/transcript";
  const thread = { ...RUN.threads[0], path: `${T}/write-transcript.js` };
  for (const [threads, landed] of [
    [[{ ...thread, named_paths: [`${T}/run-transcript.js`] }], true],
    [[thread], false],
    [[{ ...thread, named_paths: ["plugins/other/run-transcript.js"] }], false],
  ]) {
    const api = fakeApi({
      compare: { status: "ahead", commits: [fixCommit()], files: [{ filename: thread.path }, { filename: `${T}/run-transcript.js` }] },
      commits: { [FIX]: { files: [{ filename: thread.path }, { filename: `${T}/run-transcript.js` }] } },
    });
    const result = await run(api, lines(reply({ disposition: "VALID" })), JSON.stringify({ ...RUN, threads }));
    assert.equal(result.escalationReason, landed ? "" : "feedback-not-landed", JSON.stringify(threads[0].named_paths));
  }
  const malformed = await run(fakeApi(), lines(reply({ disposition: "VALID" })), JSON.stringify({ ...RUN, threads: [{ ...thread, named_paths: [7] }] }));
  assert.equal(malformed.escalationReason, "feedback-invalid");
});

// A finding on one file of the PR fixed in another: run.json's pr_paths
// carry the PR's files into the thread's scope.
test("a VALID fix in another file the PR changes, citing a line it changed, lands; uncited, not in the PR, new or protected, it does not", async () => {
  // The doc and the script, as files the checkout holds.
  const thread = { ...RUN.threads[0], path: "docs/b.md" };
  const script = "src/a.js";
  for (const [label, prPaths, file, landed, evidence = [`${script}:1`]] of [
    ["in the PR", [thread.path, script], { filename: script, status: "modified" }, true],
    ["in the PR, not cited", [thread.path, script], { filename: script, status: "modified" }, false, [`${thread.path}:1`]],
    ["in the PR, cited outside the fix's hunks", [thread.path, script], { filename: script, status: "modified" }, false, [`${script}:9`]],
    ["not in the PR", [thread.path], { filename: script, status: "modified" }, false],
    ["added by the fix", [thread.path, script], { filename: script, status: "added" }, false],
    ["under .github/workflows/", [thread.path, ".github/workflows/x.yml"], { filename: ".github/workflows/x.yml", status: "modified" }, false],
    ["CODEOWNERS", [thread.path, "CODEOWNERS"], { filename: "CODEOWNERS", status: "modified" }, false],
  ]) {
    const api = fakeApi({
      compare: { status: "ahead", commits: [fixCommit()], files: [file] },
      commits: { [FIX]: { files: [{ ...file, patch: "@@ -1,2 +1,3 @@\n x\n+y\n z" }] } },
    });
    const result = await run(api, lines(reply({ disposition: "VALID", evidence })), JSON.stringify({ ...RUN, pr_paths: prPaths, threads: [thread] }));
    assert.equal(result.escalationReason, landed ? "" : "feedback-not-landed", label);
    assert.equal(api.posted().length, landed ? 1 : 0, label);
  }
  const malformed = await run(fakeApi(), lines(reply({ disposition: "VALID" })), JSON.stringify({ ...RUN, pr_paths: [7] }));
  assert.equal(malformed.escalationReason, "feedback-invalid");
});

test("feedback-not-landed, nothing posted: a VALID fix commit that does not change its own thread's path or a PR file its evidence cites", async () => {
  const api = fakeApi({
    compare: { status: "ahead", commits: [fixCommit()], files: [{ filename: "docs/b.md" }] },
    commits: { [FIX]: { files: [{ filename: "docs/b.md" }] } },
  });
  const result = await run(api, lines(reply({ disposition: "VALID" })), JSON.stringify({ ...RUN, pr_paths: ["docs/b.md", "src/a.js"], threads: [RUN.threads[0]] }));
  assert.equal(result.escalationReason, "feedback-not-landed");
  assert.deepEqual(api.posted(), []);
});

// #8832: the thread sat on the skill's SKILL.md and the fix changed only that
// skill's evals.
test("a VALID fix on a SKILL.md thread lands when it changes any file in that skill's directory, not a sibling skill's", async () => {
  const S = "plugins/discipline/skills/script-the-deterministic-work";
  const skillRun = JSON.stringify({ ...RUN, threads: [{ ...RUN.threads[0], path: `${S}/SKILL.md` }] });
  for (const [filename, landed] of [
    [`${S}/evals/evals.json`, true],
    [`${S}/reference/notes.md`, true],
    [`${S}-x/evals/evals.json`, false],
    ["plugins/discipline/skills/sweep-all/evals/evals.json", false],
  ]) {
    const api = fakeApi({
      compare: { status: "ahead", commits: [fixCommit()], files: [{ filename }] },
      commits: { [FIX]: { files: [{ filename }] } },
    });
    const result = await run(api, lines(reply({ disposition: "VALID" })), skillRun);
    assert.equal(result.escalationReason, landed ? "" : "feedback-not-landed", filename);
  }
});

test("a VALID fix on a thread that is not a SKILL.md still needs its exact path, even in the same directory", async () => {
  const S = "plugins/discipline/skills/script-the-deterministic-work";
  const refRun = JSON.stringify({ ...RUN, threads: [{ ...RUN.threads[0], path: `${S}/reference/a.md` }] });
  const api = fakeApi({
    compare: { status: "ahead", commits: [fixCommit()], files: [{ filename: `${S}/reference/b.md` }] },
    commits: { [FIX]: { files: [{ filename: `${S}/reference/b.md` }] } },
  });
  const result = await run(api, lines(reply({ disposition: "VALID" })), refRun);
  assert.equal(result.escalationReason, "feedback-not-landed");
});

test("feedback-not-landed with no VALID reply when the branch moved onto .github/ or another path", async () => {
  for (const filename of [".github/actions/x/action.yml", "src/other.js"]) {
    const api = fakeApi({ compare: { status: "ahead", commits: [fixCommit()], files: [{ filename }] } });
    const result = await run(api, lines(reply()));
    assert.equal(result.escalationReason, "feedback-not-landed", filename);
    assert.deepEqual(api.posted(), []);
  }
});

test("a VALID thread that gained a comment while the reply was posted is left open and escalates feedback-partial", async () => {
  const api = fakeApi({ arrivedDuringReply: [101] });
  const result = await run(api, lines(reply({ disposition: "VALID" })));
  assert.equal(api.posted().length, 1);
  assert.deepEqual(api.resolved(), []);
  assert.equal(result.escalationReason, "feedback-partial");
});

test("a resolve that fails once after the reply is retried and resolves", async () => {
  const api = fakeApi({ resolveFailures: 1 });
  const result = await run(api, lines(reply({ disposition: "VALID" })));
  assert.deepEqual(api.resolved(), ["PRRT_a", "PRRT_a"]);
  assert.equal(result.escalationReason, "");
});

test("a resolve that keeps failing after the reply escalates feedback-partial and posts no later reply", async () => {
  const api = fakeApi({ resolveFailures: 2 });
  const result = await run(
    api,
    lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
  );
  assert.equal(result.escalationReason, "feedback-partial");
  assert.deepEqual(api.posted().map((call) => call[2]), [100]);
  assert.equal(api.markers().length, 1);
});

test("a thread that changed since the model job read it is skipped; the rest are posted", async () => {
  for (const overrides of [
    { threads: { PRRT_a: { ids: [100, 101], resolved: false }, PRRT_b: { ids: [200], resolved: false } } },
    { threads: { PRRT_a: { ids: [100], resolved: true }, PRRT_b: { ids: [200], resolved: false } } },
    { reread: { PRRT_a: { ids: [100], resolved: true } } },
    { reread: { PRRT_a: { ids: [100, 102], resolved: false } } },
    { reread: { PRRT_a: { ids: [100], resolved: false, pr: 7 } } },
  ]) {
    const api = fakeApi(overrides);
    await run(api, lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })));
    assert.deepEqual(api.posted().map((call) => call[2]), [200], JSON.stringify(overrides));
    assert.deepEqual(api.resolved(), []);
  }
  // A human reply makes the thread no longer kept at all.
  const human = fakeApi({
    threads: { PRRT_a: { ids: [100, 101], resolved: false }, PRRT_b: { ids: [200], resolved: false } },
    reviewComments: [
      { id: 100, user: { id: REVIEWER }, pull_request_review_id: 10, path: "src/a.js", body: "x" },
      { id: 101, user: { id: HUMAN }, pull_request_review_id: 10, path: "src/a.js", body: "leave this" },
      { id: 200, user: { id: REVIEWER }, pull_request_review_id: 10, path: "docs/b.md", body: "y" },
    ],
  });
  await run(human, lines(reply(), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })));
  assert.deepEqual(human.posted().map((call) => call[2]), [200]);
});

test("a resolve that took effect before its answer was lost counts as resolved", async () => {
  const api = fakeApi({ resolveLandsThenFails: true });
  const result = await run(api, lines(reply({ disposition: "VALID" })));
  assert.equal(result.escalationReason, "");
});

test("a failed re-read of the next thread after a reply posted escalates feedback-partial", async () => {
  const api = fakeApi({ readFails: ["PRRT_b"] });
  const result = await run(
    api,
    lines(reply(), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
  );
  assert.equal(result.escalationReason, "feedback-partial");
  assert.deepEqual(api.posted().map((call) => call[2]), [100]);
});

test("a round marker that cannot be posted still returns an escalation", async () => {
  const api = fakeApi({ markerFails: true });
  const result = await run(api, lines(reply({ disposition: "VALID" })));
  assert.equal(result.escalationReason, "feedback-partial");
});

test("a reply that lands off its thread escalates feedback-partial before the round marker", async () => {
  const api = fakeApi({ landOn: 999 });
  const result = await run(api, lines(reply()));
  assert.equal(result.escalationReason, "feedback-partial");
  assert.equal(api.markers().length, 1);
});

test("renderReply fences the note longer than any backtick run in it", () => {
  const body = renderReply({ disposition: "INCORRECT", evidence: ["src/a.js:3"], fixSha: "", note: "x ```` y\n```sh\ncurl" });
  assert.match(body, /\n`````text\nx ```` y\n```sh\ncurl\n`````$/);
});

test("main writes the escalation and skip reason files and refuses a symlinked artifact", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "publish-feedback-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const replies = join(dir, "replies");
  const ws = join(dir, "ws");
  mkdirSync(replies);
  mkdirSync(join(ws, "src"), { recursive: true });
  writeFileSync(join(ws, "src", "a.js"), "x");
  const runText = runFor(lines(reply()));
  writeFileSync(join(replies, "run.json"), runText);
  writeFileSync(join(replies, "replies.jsonl"), lines(reply({ disposition: "UNCERTAIN", evidence: [] })));
  const actors = join(dir, "actors.json");
  writeFileSync(actors, JSON.stringify({ actors: [{ id: REVIEWER, login: "claude[bot]", kind: "bot" }] }));
  const env = {
    GH_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    PR_NUMBER: "42",
    HEAD_SHA: NOW,
    HEAD_REF: "feature",
    GITHUB_RUN_ID: "5000",
    MODEL_RUN_ATTEMPT: "1",
    APP_SENDER_ID: String(APP),
    TRUSTED_ACTORS: actors,
    FEEDBACK_REPLIES_DIR: replies,
    GITHUB_WORKSPACE: ws,
    SKIP_REASON_FILE: join(dir, "skip"),
    ESCALATION_REASON_FILE: join(dir, "escalation"),
    RUN_SHA256: createHash("sha256").update(runText).digest("hex"),
    REPLIES_SHA256: createHash("sha256").update(lines(reply({ disposition: "UNCERTAIN", evidence: [] }))).digest("hex"),
    REVIEW_PATCH_STATE: "",
  };
  const api = fakeApi();
  assert.equal(await main(env, { api, log: () => {} }), 0);
  assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-uncertain\n");

  // replies.jsonl must be the bytes the scan job uploaded, whose SHA-256 it
  // passed out.
  for (const sha of ["0".repeat(64), ""]) {
    const forged = fakeApi();
    await main({ ...env, REPLIES_SHA256: sha }, { api: forged, log: () => {} });
    assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-invalid\n", `replies SHA-256 ${JSON.stringify(sha)}`);
    assert.deepEqual(forged.posted(), []);
    assert.equal(forged.markers().length, 1);
  }
  assert.equal(readFileSync(env.SKIP_REASON_FILE, "utf8"), "awaiting-human\n");
  assert.equal(api.posted().length, 1);
  assert.equal(api.markers()[0][2].split("\n")[1], MODEL_RUN);
  // No model attempt names no run, so even a marker already on the PR from
  // an earlier attempt without replies does not stop this one.
  const noAttempt = fakeApi({ issueComments: [{ id: 2, user: { id: APP }, body: `${ROUND}\nround 1` }] });
  await main({ ...env, MODEL_RUN_ATTEMPT: "" }, { api: noAttempt, log: () => {} });
  assert.equal(noAttempt.markers().length, 1);
  assert.match(noAttempt.markers()[0][2], /^<!-- pr-unblock:address-feedback-round -->\npr-unblock \/ address-feedback finished round 2 of max 3/);

  // A run.json other than the bytes the select job hashed is refused.
  for (const sha of ["0".repeat(64), ""]) {
    const forged = fakeApi();
    await main({ ...env, RUN_SHA256: sha }, { api: forged, log: () => {} });
    assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-invalid\n");
    assert.deepEqual(forged.posted(), []);
    assert.equal(forged.markers().length, 1);
  }

  // An oversized replies file is refused before it is read.
  writeFileSync(join(replies, "replies.jsonl"), "x".repeat(49154));
  const big = fakeApi();
  await main(env, { api: big, log: () => {} });
  assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-invalid\n");
  assert.deepEqual(big.posted(), []);

  rmSync(join(replies, "replies.jsonl"));
  symlinkSync(join(dir, "actors.json"), join(replies, "replies.jsonl"));
  const linked = fakeApi();
  await main(env, { api: linked, log: () => {} });
  assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-invalid\n");
  assert.deepEqual(linked.posted(), []);

  // verdicts.json counts only as the bytes the adjudicate job hashed.
  rmSync(join(replies, "replies.jsonl"));
  writeFileSync(join(replies, "replies.jsonl"), lines(reply()));
  const verdictsDir = join(dir, "adjudication");
  mkdirSync(verdictsDir);
  const verdictsText = verdicts(judged("PRRT_a", "lane"));
  writeFileSync(join(verdictsDir, "verdicts.json"), verdictsText);
  const incorrect = { ...env, ADJUDICATION_DIR: verdictsDir, REPLIES_SHA256: createHash("sha256").update(lines(reply())).digest("hex") };
  const answered = fakeApi();
  await main({ ...incorrect, ADJUDICATION_SHA256: createHash("sha256").update(verdictsText).digest("hex") }, { api: answered, log: () => {} });
  assert.deepEqual(answered.resolved(), ["PRRT_a"]);
  for (const sha of ["0".repeat(64), ""]) {
    rmSync(env.ESCALATION_REASON_FILE, { force: true });
    await main({ ...incorrect, ADJUDICATION_SHA256: sha }, { api: fakeApi(), log: () => {} });
    assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-unadjudicated\n");
  }

  await assert.rejects(main({ ...env, HEAD_SHA: "x" }, { api }), /HEAD_SHA/);
  await assert.rejects(main({ ...env, PR_NUMBER: "0" }, { api }), /PR_NUMBER/);
  await assert.rejects(main({ ...env, HEAD_REF: "" }, { api }), /HEAD_REF/);
  await assert.rejects(main({ ...env, GITHUB_RUN_ID: "x" }, { api }), /GITHUB_RUN_ID/);
  await assert.rejects(main({ ...env, MODEL_RUN_ATTEMPT: "1 -->" }, { api }), /MODEL_RUN_ATTEMPT/);
  await assert.rejects(main({ ...env, ESCALATION_REASON_FILE: "" }, { api }), /ESCALATION_REASON_FILE/);
});

test("a VALID reply's Fix line names the commit this job found, beside a later commit a person pushed in scope", async () => {
  const later = "e".repeat(40);
  const api = fakeApi({
    compare: { status: "ahead", commits: [fixCommit(), { sha: later, author: { id: HUMAN }, commit: { message: "tweak\n" } }], files: [{ filename: "src/a.js" }] },
  });
  const result = await run(api, lines(reply({ disposition: "VALID" })));
  assert.equal(result.escalationReason, "");
  assert.match(api.posted()[0][3], new RegExp(`\nFix: ${FIX}\n`));
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
});

test("with no VALID reply no fix commit is needed: INCORRECT replies post on an unmoved branch", async () => {
  const api = fakeApi({ compare: { status: "identical", commits: [], files: [] } });
  const result = await run(api, lines(reply(), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })), JSON.stringify(RUN));
  assert.equal(result.escalationReason, "feedback-unadjudicated");
  assert.deepEqual(api.posted().map((call) => call[2]), [100, 200]);
  assert.deepEqual(api.resolved(), []);
});

// A model call that never ran (credit stop on both legs, broker refusal, kill
// switch, a head that moved before the call) uploads no replies.jsonl: the
// round still counts, and the check posts a skip, not an escalation.
const noReplies = (api, { headSha = GATED, patchState = "", scanRefused = "", repliesExpected = false } = {}) =>
  publish({
    api,
    pr: 42,
    headSha,
    headRef: "feature",
    appId: APP,
    modelRun: null,
    patchState,
    scanRefused,
    repliesExpected,
    reviewerId: REVIEWER,
    trustedHumans: new Set([HUMAN]),
    readArtifact: () => ({ runText: JSON.stringify(RUN), repliesText: null }),
    fileExists: exists,
  });
test("no replies.jsonl is no escalation: the round counts and the check skips no-model-turn", async () => {
  const api = fakeApi();
  const result = await noReplies(api);
  assert.equal(result.escalationReason, "");
  assert.equal(result.skipReason, "no-model-turn");
  assert.deepEqual(api.posted(), []);
  assert.equal(api.markers().length, 1);
});
// Whether replies exist is the run job's to forge, so no-model-turn holds
// only when the scan handed on no patch and the head is the selected one.
test("no replies.jsonl beside a scanned patch or a moved head is an escalation", async () => {
  for (const patchState of ["written", "empty"]) {
    const api = fakeApi();
    const result = await noReplies(api, { patchState });
    assert.equal(result.escalationReason, "feedback-invalid", patchState);
    assert.equal(result.skipReason ?? "", "", patchState);
    assert.equal(api.markers().length, 1, patchState);
  }
  for (const patchState of ["", "written"]) {
    const api = fakeApi();
    const result = await noReplies(api, { headSha: NOW, patchState });
    assert.equal(result.escalationReason, "feedback-not-landed", `a push happened, patch-state ${patchState}`);
    assert.equal(api.markers().length, 1);
  }
});

// A scan that refused the leg's output (an oversize patch, a leak-scan block,
// a refused decode) uploads nothing, so no replies is no proof the model took
// no turn: the round goes to a person (#9225, #9340).
test("no replies.jsonl after the scan refused the leg's output escalates feedback-invalid, never no-model-turn", async () => {
  for (const scanRefused of ["patch", "output"]) {
    const api = fakeApi();
    const result = await noReplies(api, { scanRefused });
    assert.equal(result.escalationReason, "feedback-invalid", scanRefused);
    assert.equal(result.skipReason ?? "", "", scanRefused);
    assert.deepEqual(api.posted(), [], scanRefused);
    assert.equal(api.markers().length, 1, scanRefused);
  }
});

// The scan named replies it uploaded (an attempt or a SHA-256), yet none
// arrived: a failed download, not a round with no model turn (#9225).
test("no replies.jsonl where the scan named an upload escalates feedback-invalid", async () => {
  const api = fakeApi();
  const result = await noReplies(api, { repliesExpected: true });
  assert.equal(result.escalationReason, "feedback-invalid");
  assert.equal(result.skipReason ?? "", "");
  assert.equal(api.markers().length, 1);
});

// The lanes App's address, the trailer and a range position are what a person
// can put on a local commit; GitHub's web-flow committer and a valid
// signature are what only the App's API commit carries (upstreamHeadHolds).
test("a fix commit must be committed by web-flow with a valid signature", async () => {
  for (const [label, fields] of [
    ["committed by a person", { committer: { id: HUMAN } }],
    ["no committer", { committer: null }],
    ["unsigned", { commit: { ...fixCommit().commit, verification: { verified: false, reason: "unsigned" } } }],
    ["signed but not valid", { commit: { ...fixCommit().commit, verification: { verified: true, reason: "bad_email" } } }],
  ]) {
    const api = fakeApi({ compare: { status: "ahead", commits: [fixCommit(FIX, fields)], files: [{ filename: "src/a.js" }] } });
    const result = await run(api, lines(reply({ disposition: "VALID", evidence: ["src/a.js:3"] })));
    assert.equal(result.escalationReason, "feedback-not-landed", label);
    assert.deepEqual(api.posted(), [], label);
  }
});

test("main: a missing replies.jsonl writes the no-model-turn skip and no escalation; a missing run.json still escalates", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "publish-feedback-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const replies = join(dir, "replies");
  mkdirSync(replies);
  mkdirSync(join(dir, "ws"));
  const actors = join(dir, "actors.json");
  writeFileSync(actors, JSON.stringify({ actors: [{ id: REVIEWER, login: "claude[bot]", kind: "bot" }] }));
  // run.json has its own limit, R's 1 MiB, not the replies cap.
  const runText = JSON.stringify(RUN) + " ".repeat(60000);
  writeFileSync(join(replies, "run.json"), runText);
  const env = {
    GH_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    PR_NUMBER: "42",
    HEAD_SHA: GATED,
    HEAD_REF: "feature",
    GITHUB_RUN_ID: "5000",
    MODEL_RUN_ATTEMPT: "",
    REPLIES_SHA256: "",
    REVIEW_PATCH_STATE: "",
    APP_SENDER_ID: String(APP),
    TRUSTED_ACTORS: actors,
    FEEDBACK_REPLIES_DIR: replies,
    GITHUB_WORKSPACE: join(dir, "ws"),
    SKIP_REASON_FILE: join(dir, "skip"),
    ESCALATION_REASON_FILE: join(dir, "escalation"),
    RUN_SHA256: createHash("sha256").update(runText).digest("hex"),
  };
  const api = fakeApi();
  assert.equal(await main(env, { api, log: () => {} }), 0);
  assert.equal(readFileSync(env.SKIP_REASON_FILE, "utf8"), "no-model-turn\n");
  assert.throws(() => readFileSync(env.ESCALATION_REASON_FILE), /ENOENT/);
  assert.equal(api.markers().length, 1);
  // A written patch with no replies is no skip.
  rmSync(env.SKIP_REASON_FILE);
  await main({ ...env, REVIEW_PATCH_STATE: "written" }, { api: fakeApi(), log: () => {} });
  assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-invalid\n");
  rmSync(env.ESCALATION_REASON_FILE);
  await assert.rejects(main({ ...env, REVIEW_PATCH_STATE: "maybe" }, { api: fakeApi() }), /REVIEW_PATCH_STATE/);
  // The scan-refusal job's marker alone, with every leg output empty, is no
  // skip (#9340); nor is a marker download that failed, or replies the scan
  // named that never arrived (#9225).
  const markers = join(dir, "scan-refused");
  mkdirSync(markers);
  writeFileSync(join(markers, "scan-refused-1.txt"), "output\n");
  rmSync(env.SKIP_REASON_FILE, { force: true });
  await main({ ...env, SCAN_REFUSED_DIR: join(dir, "no-markers"), SCAN_REFUSED_READ: "success" }, { api: fakeApi(), log: () => {} });
  assert.equal(readFileSync(env.SKIP_REASON_FILE, "utf8"), "no-model-turn\n", "no marker downloaded");
  for (const extra of [
    { SCAN_REFUSED_DIR: markers, SCAN_REFUSED_READ: "success" },
    { SCAN_REFUSED_DIR: join(dir, "no-markers"), SCAN_REFUSED_READ: "failure" },
    { MODEL_RUN_ATTEMPT: "1" },
    { REPLIES_SHA256: "a".repeat(64) },
  ]) {
    rmSync(env.SKIP_REASON_FILE, { force: true });
    rmSync(env.ESCALATION_REASON_FILE, { force: true });
    await main({ ...env, ...extra }, { api: fakeApi(), log: () => {} });
    assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-invalid\n", JSON.stringify(extra));
  }
  rmSync(env.ESCALATION_REASON_FILE);

  rmSync(env.SKIP_REASON_FILE, { force: true });
  const huge = JSON.stringify(RUN) + " ".repeat(1048577);
  writeFileSync(join(replies, "run.json"), huge);
  await main({ ...env, RUN_SHA256: createHash("sha256").update(huge).digest("hex") }, { api: fakeApi(), log: () => {} });
  assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-invalid\n");

  rmSync(join(replies, "run.json"));
  rmSync(env.ESCALATION_REASON_FILE);
  await main(env, { api: fakeApi(), log: () => {} });
  assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-invalid\n");
});

test("no-model-turn is a schema skip reason, so its check posts neutral, not red", () => {
  const schema = JSON.parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json", import.meta.url), "utf8"));
  assert.ok(schema.$defs["skip-reason"].enum.includes("no-model-turn"));
});

test("lineChanged reads a patch's new-side hunks", async () => {
  const { lineChanged } = await import("./publish-feedback.mjs");
  const patch = "@@ -1,2 +1,3 @@\n x\n+y\n z\n@@ -10 +11 @@\n-a\n+b\n@@ -20,2 +21,0 @@\n-c\n-d";
  for (const [line, want] of [[1, true], [3, true], [4, false], [11, true], [12, false], [21, false]]) {
    assert.equal(lineChanged(patch, line), want, String(line));
  }
  assert.equal(lineChanged(undefined, 1), false);
});
