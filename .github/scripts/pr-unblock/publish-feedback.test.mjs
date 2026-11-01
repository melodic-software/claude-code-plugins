import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { cpSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

import { isEscalationReply } from "./address-feedback.mjs";
import { main, publish, renderReply, undisposedLines } from "./publish-feedback.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

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
// review-threads row's message and trailer (patch-rules.json), naming both
// kept threads as a round whose replies are both VALID does.
const fixCommit = (sha = FIX, fields = {}) => ({
  sha,
  author: { id: APP },
  committer: { id: 19864447 },
  commit: {
    message: "Address review feedback on feature\n\nLane-Activity: pr-unblock/address-feedback\nLane-Thread: PRRT_a\nLane-Thread: PRRT_b\n",
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
    listIssueComments: async () => [{ id: 1, user: { id: ACTIONS_BOT }, body: overrides.marker ?? marker }, ...(overrides.issueComments ?? [])],
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
    // The lanes App opened the PR unless the case names another opener.
    getPull: async () => ({ user: { id: overrides.opener ?? APP } }),
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

test("INCORRECT, UNCERTAIN and VALID-defer are posted, left open, and go to the adjudicator, not a person", async () => {
  const api = fakeApi();
  const result = await run(
    api,
    lines(
      reply({ evidence: ["src/a.js:3", "docs/b.md:1"] }),
      reply({ thread: "PRRT_b", disposition: "UNCERTAIN", evidence: [], note: "Needs the vendor docs." }),
    ),
    undefined,
    // The finding stands, so INCORRECT leaves the thread open; the UNCERTAIN
    // thread has no verdict, so the round ends unadjudicated: a failing
    // status, not a person.
    verdicts(judged("PRRT_a", "reviewer")),
  );
  assert.equal(result.escalationReason, "feedback-unadjudicated");
  assert.deepEqual(api.resolved(), []);
  assert.match(api.posted()[0][3], /^\*\*pr-unblock \/ address-feedback: INCORRECT, left open\*\*\n\nEvidence: `src\/a.js:3`, `docs\/b.md:1`\n/);
  assert.match(api.posted()[1][3], /UNCERTAIN, left open\*\*\n\nEvidence: none in the checkout\n/);
  assert.deepEqual(api.calls.find((call) => call[0] === "compare"), ["compare", GATED, NOW], "a moved branch is checked even with no VALID reply");

  // A lane verdict never resolves a deferred finding the lane agreed holds:
  // the thread stays open with only the lane's reply, and the round ends
  // unadjudicated. A stands verdict hands it to the next round. One that
  // finds an UNCERTAIN finding stands does the same.
  const defer = fakeApi();
  assert.equal((await run(defer, lines(reply({ disposition: "VALID-defer" })), undefined, verdicts(judged("PRRT_a", "lane")))).escalationReason, "feedback-unadjudicated");
  assert.match(defer.posted()[0][3], /VALID \(defer\), left open\*\*/);
  assert.equal(defer.posted().length, 1);
  assert.deepEqual(defer.resolved(), []);
  const deferStands = fakeApi();
  assert.equal((await run(deferStands, lines(reply({ disposition: "VALID-defer" })), undefined, verdicts(judged("PRRT_a", "reviewer")))).escalationReason, "");
  assert.match(deferStands.posted()[1][3], /finding-stands/);
  assert.deepEqual(deferStands.resolved(), []);
  const unsure = fakeApi();
  assert.equal((await run(unsure, lines(reply({ disposition: "UNCERTAIN" })), undefined, verdicts(judged("PRRT_a", "reviewer")))).escalationReason, "");
  assert.match(unsure.posted()[1][3], /finding-stands/);
  assert.deepEqual(unsure.resolved(), []);
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

// #8218's round 1 on 9c0a446 (2026-10-18): the select job kept one claude[bot]
// thread on lib/session-bridge/session_bridge.py, root comment 4306751638, and
// the model recorded no disposition for it. Its node id is not public, so
// PRRT_8218 stands in for it.
const RUN_8218 = { version: 1, head_sha: GATED, threads: [{ id: "PRRT_8218", path: "lib/session-bridge/session_bridge.py", comment_ids: [4306751638] }] };

test("feedback-incomplete names each kept thread with no disposition in the round marker and the log", async () => {
  const cases = [
    [RUN_8218, "", [{ id: "PRRT_8218", comment: 4306751638 }]],
    [RUN, lines(reply()), [{ id: "PRRT_b", comment: 200 }]],
  ];
  for (const [runJson, repliesText, undisposed] of cases) {
    const api = fakeApi();
    const logged = [];
    const result = await publish({
      api,
      pr: 42,
      headSha: NOW,
      headRef: "feature",
      appId: APP,
      modelRun: "5000-1",
      reviewerId: REVIEWER,
      readArtifact: () => ({ runText: JSON.stringify(runJson), repliesText }),
      fileExists: exists,
      log: (line) => logged.push(line),
    });
    assert.equal(result.escalationReason, "feedback-incomplete");
    assert.deepEqual(result.undisposed, undisposed);
    assert.deepEqual(api.posted(), []);
    assert.deepEqual(api.resolved(), []);
    assert.equal(
      api.markers()[0][2],
      [
        `${ROUND}\n${MODEL_RUN}\npr-unblock / address-feedback finished round 1 of max 3 on ${NOW}.`,
        "",
        "Kept review threads with no disposition:",
        ...undisposed.map(({ id, comment }) => `- \`${id}\` (root comment ${comment})`),
      ].join("\n"),
    );
    assert.ok(logged.some((line) => line.endsWith(`none for ${undisposed.map(({ id }) => id).join(", ")}`)), logged.join("\n"));
  }
});

test("the round marker names at most 20 threads with no disposition, then how many more", () => {
  const undisposed = Array.from({ length: 23 }, (_, n) => ({ id: `PRRT_${n}`, comment: n + 1 }));
  const shown = undisposedLines(undisposed);
  assert.equal(shown.at(-2), "- `PRRT_19` (root comment 20)");
  assert.equal(shown.at(-1), "- and 3 more");
  assert.deepEqual(undisposedLines([]), []);
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
      `A fresh-context adjudicator read the review comment, the locations both sides cited and the code at \`${GATED}\`, without the fixing lane's reasoning, and found that the code answers the finding.`,
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

// A claude[bot] finding names no lane (a footer in it is model text), so it
// is adjudicated as a code-review finding, with or without a footer, unless
// its text claims the security-review lane at a rating a person decides.
test("a claude[bot] finding, with no footer or a footer it wrote, is adjudicated as a code-review finding and escalates nothing", async () => {
  for (const body of ["finding 200", "finding 200\n\nclaude-lane: claude-review"]) {
    const own = { id: 200, user: { id: REVIEWER }, pull_request_review_id: 10, path: "docs/b.md", line: 1, body };
    const api = fakeApi({ reviewComments: [{ id: 100, user: { id: ACTIONS_BOT }, pull_request_review_id: 30, path: "src/a.js", line: 1, body: "finding 100\n\nclaude-lane: claude-review" }, own] });
    const result = await run(
      api,
      lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
      JSON.stringify(RUN),
      verdicts(judged("PRRT_b", "lane")),
    );
    assert.equal(result.escalationReason, "", body);
    assert.deepEqual(api.posted().map((call) => call[2]), [100, 200, 200], "the lane's replies, then the adjudication reply");
    assert.deepEqual(api.resolved(), ["PRRT_a", "PRRT_b"]);
  }
});

test("a claude[bot] finding whose text names the security-review lane with no rating keeps that hold, and is not adjudicated", async () => {
  const claimed = { id: 200, user: { id: REVIEWER }, pull_request_review_id: 10, path: "docs/b.md", line: 1, body: "finding 200\n\nclaude-lane: claude-security-review" };
  const api = fakeApi({ reviewComments: [{ id: 100, user: { id: ACTIONS_BOT }, pull_request_review_id: 30, path: "src/a.js", line: 1, body: "finding 100\n\nclaude-lane: claude-review" }, claimed] });
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
  assert.match(stands[3], /a round that leaves this thread open again ends the lane in a failing status/);
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

  // An UNCERTAIN reply in the same round with no verdict of its own ends the
  // round unadjudicated.
  const uncertain = fakeApi({ compare: unmoved });
  const both = await run(
    uncertain,
    lines(reply(), reply({ thread: "PRRT_b", disposition: "UNCERTAIN", evidence: [], note: "Needs the vendor docs." })),
    atNow(),
    verdictsAt(NOW, judged("PRRT_a", "reviewer")),
  );
  assert.deepEqual([both.escalationReason, both.skipReason], ["feedback-unadjudicated", ""]);
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

test("no second dispute: an INCORRECT reply on a thread whose finding stood ends feedback-stood-open and is not adjudicated", async () => {
  const api = stoodApi({ compare: { status: "identical", commits: [], files: [] } });
  const result = await run(api, lines(reply()), stoodRun, verdicts(judged("PRRT_a", "lane")));
  assert.equal(result.escalationReason, "feedback-stood-open");
  assert.equal(api.posted().length, 1, "the lane's reply, and no adjudication reply");
  assert.match(api.posted()[0][3], /INCORRECT, left open/);
  assert.deepEqual(api.resolved(), []);
});

test("the cap: a stood thread the next round leaves open ends feedback-stood-open; one it fixes resolves", async () => {
  for (const disposition of ["UNCERTAIN", "VALID-defer"]) {
    const api = stoodApi({ compare: { status: "identical", commits: [], files: [] } });
    const result = await run(api, lines(reply({ disposition, evidence: [] })), stoodRun);
    assert.equal(result.escalationReason, "feedback-stood-open", disposition);
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

// The fix commit's message as apply-patch writes it, naming `threads` in
// Lane-Thread trailer lines; built here so the default fixture cannot hide a
// commit that names the wrong thread.
const fixMessage = (...threads) => ["Address review feedback on feature", "", "Lane-Activity: pr-unblock/address-feedback", ...threads.map((id) => `Lane-Thread: ${id}`), ""].join("\n");

for (const [label, message] of [
  // A sibling fix on the same file, bound to the other thread.
  ["the fix commit names only a same-file sibling thread", fixMessage("PRRT_b")],
  ["the fix commit names no thread", fixMessage()],
  ["the thread id is in the subject, not a trailer line", fixMessage().replace("Address review feedback", "PRRT_a Address review feedback")],
]) {
  test(`feedback-not-landed, nothing posted: ${label}`, async () => {
    const api = fakeApi({ compare: { status: "ahead", commits: [fixCommit(FIX, { commit: { ...fixCommit().commit, message } })], files: [{ filename: "src/a.js" }] } });
    const result = await run(api, lines(reply({ disposition: "VALID" })));
    assert.equal(result.escalationReason, "feedback-not-landed");
    assert.deepEqual(api.posted(), []);
    assert.deepEqual(api.resolved(), []);
  });
}

test("a fix commit whose trailer names the VALID thread lands it, CRLF line ends included", async () => {
  for (const message of [fixMessage("PRRT_a"), fixMessage("PRRT_b", "PRRT_a").replaceAll("\n", "\r\n")]) {
    const api = fakeApi({ compare: { status: "ahead", commits: [fixCommit(FIX, { commit: { ...fixCommit().commit, message } })], files: [{ filename: "src/a.js" }] } });
    assert.equal((await run(api, lines(reply({ disposition: "VALID" })))).escalationReason, "");
    assert.deepEqual(api.resolved(), ["PRRT_a"]);
  }
});

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

// A same-file sibling fix: the newest lane commit changed src/a.js at the
// line PRRT_a's evidence cites, but its trailer binds it to PRRT_b alone.
test("feedback-not-landed: an earlier same-file fix whose trailer names another thread is not credited", async () => {
  const sibling = earlierFix({ commit: { message: fixMessage("PRRT_b") } });
  const api = retry([sibling]);
  const result = await run(api, lines(reply({ disposition: "VALID" })));
  assert.equal(result.escalationReason, "feedback-not-landed");
  assert.deepEqual(api.posted(), []);
  assert.deepEqual(api.resolved(), []);
  // The same commit named for PRRT_a is its fix.
  const own = retry([earlierFix({ commit: { message: fixMessage("PRRT_a") } })]);
  assert.equal((await run(own, lines(reply({ disposition: "VALID" })))).escalationReason, "");
  assert.deepEqual(own.resolved(), ["PRRT_a"]);
});

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

// publish() with the checkout holding `files` too, for evidence outside src/ and docs/.
const runWith = (api, repliesText, runText, files = []) =>
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
    fileExists: (path) => exists(path) || files.includes(path),
  });

// #9965: the thread sat on research/context/dispatch.md; the lane's fix
// changed the operator block in parent-contract.md (hunk +784,11), a file of
// the thread's plugin the PR had not touched, and the reply cited :787.
test("a VALID fix in a file of the thread's scope outside the PR's files lands only at a line the evidence cites", async () => {
  const D = "plugins/discovery";
  const contract = `${D}/reference/parent-contract.md`;
  const fixed = [contract, `${D}/skills/setup/SKILL.md`].map((filename) => ({ filename, status: "modified", patch: "@@ -784,9 +784,11 @@\n a\n+b\n+c\n d" }));
  const caseRun = JSON.stringify({
    ...RUN,
    pr_paths: [`${D}/skills/research/SKILL.md`, `${D}/skills/research/context/dispatch.md`],
    threads: [{ ...RUN.threads[0], path: `${D}/skills/research/context/dispatch.md` }],
  });
  for (const [evidence, landed] of [
    [[`${contract}:787`, `${contract}:791`], true],
    [["src/a.js:3"], false],
    [[`${contract}:9`], false],
  ]) {
    const api = fakeApi({ compare: { status: "ahead", commits: [fixCommit()], files: fixed }, commits: { [FIX]: { files: fixed } } });
    const result = await runWith(api, lines(reply({ disposition: "VALID", evidence })), caseRun, [contract]);
    assert.equal(result.escalationReason, landed ? "" : "feedback-not-landed", evidence.join());
    assert.equal(api.posted().length, landed ? 1 : 0, evidence.join());
    if (landed) {
      assert.match(api.posted()[0][3], new RegExp(`^Fix: ${FIX}$`, "m"));
      assert.deepEqual(api.resolved(), ["PRRT_a"]);
    }
  }
});

// Each fix passes the branch's scope check; a thread whose evidence cites no
// line the fix changed is not credited, and one that cites it is.
test("a fix in a thread's scope that its evidence does not cite is not credited to it", async () => {
  const hunk = "@@ -1,2 +1,3 @@\n x\n+y\n z";
  // [label, thread paths, fix files, each thread's evidence, landed]
  for (const [label, threads, filenames, evidence, landed] of [
    ["a sibling thread's file", ["plugins/p/reference/a.md", "plugins/p/scripts/run.sh"], ["plugins/p/reference/a.md"], [["src/a.js:3"], ["src/a.js:3"]], false],
    ["a sibling thread's file, cited", ["plugins/p/reference/a.md", "plugins/p/scripts/run.sh"], ["plugins/p/reference/a.md"], [["src/a.js:3"], ["plugins/p/reference/a.md:2"]], true],
    ["a plugin README", ["plugins/p/scripts/run.sh"], ["plugins/p/README.md"], [["src/a.js:3"]], false],
    ["a plugin README, cited", ["plugins/p/scripts/run.sh"], ["plugins/p/README.md"], [["plugins/p/README.md:2"]], true],
    ["a same-directory test file", ["src/a.js"], ["src/a.test.js"], [["src/a.js:3"]], false],
    ["a same-directory test file, cited", ["src/a.js"], ["src/a.test.js"], [["src/a.test.js:2"]], true],
  ]) {
    const caseRun = JSON.stringify({ ...RUN, threads: threads.map((path, i) => ({ ...RUN.threads[i], path })) });
    const fixed = filenames.map((filename) => ({ filename, status: "modified", patch: hunk }));
    const replies = evidence.map((ev, i) => reply({ thread: RUN.threads[i].id, disposition: "VALID", evidence: ev }));
    const api = fakeApi({ compare: { status: "ahead", commits: [fixCommit()], files: fixed }, commits: { [FIX]: { files: fixed } } });
    const result = await runWith(api, lines(...replies), caseRun, filenames);
    assert.equal(result.escalationReason, landed ? "" : "feedback-not-landed", label);
    assert.equal(api.posted().length, landed ? replies.length : 0, label);
  }
});

test("a retry credits an earlier fix in the thread's scope at a cited line, not one in another plugin", async () => {
  const D = "plugins/discovery";
  const contract = `${D}/reference/parent-contract.md`;
  const runText = JSON.stringify({ ...RUN, threads: [{ id: "PRRT_a", path: `${D}/skills/research/context/dispatch.md`, comment_ids: [100] }] });
  for (const [filename, landed] of [[contract, true], ["plugins/other/reference/parent-contract.md", false]]) {
    const api = retry([earlierFix()], [{ filename, patch: FIXED[0].patch }]);
    const result = await runWith(api, lines(reply({ disposition: "VALID", evidence: [`${filename}:3`] })), runText, [filename]);
    assert.equal(result.escalationReason, landed ? "" : "feedback-not-landed", filename);
    assert.equal(api.posted().length, landed ? 1 : 0, filename);
  }
});

// #10082 review: the earlier fix changed a file of the thread's scope and one
// outside it, the reply cited both, and a later commit changed the scoped one.
test("a retry does not credit an earlier fix whose scoped cited file a later commit changed", async () => {
  const contract = "plugins/p/reference/contract.md";
  const other = "plugins/q/reference/other.md";
  const runText = JSON.stringify({ ...RUN, threads: [{ id: "PRRT_a", path: "plugins/p/reference/x.md", comment_ids: [100] }] });
  const repliesText = lines(reply({ disposition: "VALID", evidence: [`${contract}:3`, `${other}:3`] }));
  const LATER = "9".repeat(40);
  for (const [laterFiles, landed] of [[[{ filename: "src/a.js" }], true], [[{ filename: contract }], false]]) {
    const api = retry(
      [earlierFix(), { sha: LATER, author: { id: HUMAN }, commit: { message: "tweak\n", committer: { date: "2026-10-22T12:00:00Z" } } }],
      [contract, other].map((filename) => ({ filename, patch: FIXED[0].patch })),
    );
    const getCommit = api.getCommit;
    api.getCommit = async (sha) => (sha === LATER ? { files: laterFiles } : getCommit(sha));
    const result = await runWith(api, repliesText, runText, [contract, other]);
    assert.equal(result.escalationReason, landed ? "" : "feedback-not-landed", laterFiles[0].filename);
    assert.equal(api.posted().length, landed ? 1 : 0, laterFiles[0].filename);
  }
});

test("a fix in one thread's plugin is not credited to a thread in another plugin", async () => {
  const caseRun = JSON.stringify({
    ...RUN,
    threads: [
      { ...RUN.threads[0], path: "plugins/p/reference/a.md" },
      { ...RUN.threads[1], path: "plugins/q/reference/b.md" },
    ],
  });
  const fixed = [{ filename: "plugins/q/reference/b.md" }, { filename: "plugins/q/reference/c.md" }];
  const api = fakeApi({ compare: { status: "ahead", commits: [fixCommit()], files: fixed }, commits: { [FIX]: { files: fixed } } });
  const result = await run(api, lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", disposition: "VALID" })), caseRun);
  assert.equal(result.escalationReason, "feedback-not-landed");
  assert.deepEqual(api.posted(), []);
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

// The review lane edits its one reviewed-head marker in place: after this
// round's fix push it names the fix head, not the head the threads' review
// sits on. run.json's reviewed_heads (the select job's) still vouch for them.
const repointed = `<!-- claude-lane-reviewed-head lane=claude-review sha=${FIX} -->\nreviewed.`;
const recordedRun = (repliesText, heads = [GATED]) => JSON.stringify({ ...JSON.parse(runFor(repliesText)), reviewed_heads: heads });

test("a VALID reply posts and resolves after the review lane re-marks the fix head, against the heads the select job recorded", async () => {
  const api = fakeApi({ marker: repointed });
  const repliesText = lines(reply({ disposition: "VALID" }));
  const result = await run(api, repliesText, recordedRun(repliesText));
  assert.equal(result.escalationReason, "");
  assert.deepEqual(api.posted().map((call) => call[2]), [100]);
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
});

test("with the marker re-pointed, a thread that changed, or one on no recorded head, is still skipped", async () => {
  const repliesText = lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] }));
  for (const [overrides, heads] of [
    [{ threads: { PRRT_a: { ids: [100, 101], resolved: false }, PRRT_b: { ids: [200], resolved: false } } }, [GATED]],
    [{ threads: { PRRT_a: { ids: [100], resolved: true }, PRRT_b: { ids: [200], resolved: false } } }, [GATED]],
    [{ reread: { PRRT_a: { ids: [100], resolved: true } } }, [GATED]],
    [{ reread: { PRRT_a: { ids: [100, 102], resolved: false } } }, [GATED]],
    [{}, [FIX]],
  ]) {
    const api = fakeApi({ marker: repointed, ...overrides });
    await run(api, repliesText, recordedRun(repliesText, heads));
    const posted = api.posted().map((call) => call[2]);
    assert.deepEqual(posted, heads.includes(GATED) ? [200] : [], JSON.stringify({ overrides, heads }));
    assert.deepEqual(api.resolved(), [], JSON.stringify({ overrides, heads }));
  }
});

test("feedback-invalid, nothing posted: a malformed reviewed_heads", async () => {
  const repliesText = lines(reply({ disposition: "VALID" }));
  for (const heads of ["x", ["x"], [1]]) {
    const api = fakeApi();
    const result = await run(api, repliesText, JSON.stringify({ ...JSON.parse(runFor(repliesText)), reviewed_heads: heads }));
    assert.equal(result.escalationReason, "feedback-invalid", JSON.stringify(heads));
    assert.deepEqual(api.posted(), []);
  }
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
  const dir = tempDir("publish-feedback-");
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
  assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-unadjudicated\n");

  // replies.jsonl must be the bytes the scan job uploaded, whose SHA-256 it
  // passed out.
  for (const sha of ["0".repeat(64), ""]) {
    const forged = fakeApi();
    await main({ ...env, REPLIES_SHA256: sha }, { api: forged, log: () => {} });
    assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-invalid\n", `replies SHA-256 ${JSON.stringify(sha)}`);
    assert.deepEqual(forged.posted(), []);
    assert.equal(forged.markers().length, 1);
  }
  assert.equal(readFileSync(env.SKIP_REASON_FILE, "utf8"), "lane-stopped\n");
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
// signature are what only the App's API commit carries.
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
  const dir = tempDir("publish-feedback-");
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

// collect-base-activity runs a script activity from a copy of its own
// directory under $RUNNER_TEMP, so every import must resolve inside it.
test("the script loads from a copy of its own directory alone", async () => {
  const copy = tempDir("base-script-");
  try {
    cpSync(dirname(fileURLToPath(import.meta.url)), copy, { recursive: true });
    const module = await import(pathToFileURL(join(copy, "publish-feedback.mjs")).href);
    assert.equal(typeof module.main, "function");
  } finally {
    rmSync(copy, { recursive: true, force: true });
  }
});

// A pass-only round (address-feedback.mjs select with VERIFY_PASS_HEAD):
// run.json lists the stale fail-note threads, and no model ran.
const NOTE = "<!-- pr-verify:fail-note -->\nThe pr-verify verifier failed head.";
const noteThread = (id, { resolved = false, commit = GATED, author = ACTIONS_BOT, body = NOTE } = {}) => ({
  id,
  isResolved: resolved,
  comments: { totalCount: 1, nodes: [{ databaseId: 1 }] },
  root: { nodes: [{ author: { databaseId: author }, body, originalCommit: { oid: commit } }] },
});
const staleRun = (ids, head = NOW) => JSON.stringify({ version: 1, head_sha: head, pr_paths: [], threads: [], stale_notes: ids });
const staleApi = (threads, { failOn = [], moved = false } = {}) => {
  const calls = [];
  return {
    calls,
    resolved: () => calls.filter((call) => call[0] === "resolve").map((call) => call[1]),
    listThreads: async () => threads,
    readBranch: async () => (moved ? PUSHED : NOW),
    resolveThread: async (id) => {
      calls.push(["resolve", id]);
      if (failOn.includes(id)) throw new Error("POST https://api.github.com/graphql returned 502");
      return true;
    },
    listIssueComments: async () => assert.fail("a pass-only round posts no round marker"),
    createIssueComment: async () => assert.fail("a pass-only round posts no round marker"),
    replyToComment: async () => assert.fail("a pass-only round posts no reply"),
  };
};

test("a pass-only round resolves each listed fail-note thread still open from an earlier head, and posts nothing", async () => {
  const api = staleApi([
    noteThread("PRRT_old"),
    noteThread("PRRT_also_old"),
    noteThread("PRRT_now", { commit: NOW }),
    noteThread("PRRT_done", { resolved: true }),
    noteThread("PRRT_reviewer", { author: REVIEWER }),
    noteThread("PRRT_plain", { body: "finding" }),
  ]);
  const result = await run(api, null, staleRun(["PRRT_old", "PRRT_also_old", "PRRT_now", "PRRT_done", "PRRT_reviewer", "PRRT_plain"]));
  assert.deepEqual(api.resolved(), ["PRRT_old", "PRRT_also_old"]);
  assert.equal(result.escalationReason, "");
});

// The select job names the head in superseded_head only when the gate's
// reader found the FAIL there superseded; without it a note on the passing
// head stays open.
test("a pass-only round resolves a fail-note thread at the passing head only when run.json names that head superseded", async () => {
  const threads = () => [noteThread("PRRT_old"), noteThread("PRRT_now", { commit: NOW })];
  const superseded = staleApi(threads());
  await run(superseded, null, JSON.stringify({ version: 1, head_sha: NOW, pr_paths: [], threads: [], stale_notes: ["PRRT_old", "PRRT_now"], superseded_head: NOW }));
  assert.deepEqual(superseded.resolved(), ["PRRT_old", "PRRT_now"]);
  const not = staleApi(threads());
  await run(not, null, staleRun(["PRRT_old", "PRRT_now"]));
  assert.deepEqual(not.resolved(), ["PRRT_old"]);
  const elsewhere = staleApi(threads());
  await run(elsewhere, null, JSON.stringify({ version: 1, head_sha: NOW, pr_paths: [], threads: [], stale_notes: ["PRRT_old", "PRRT_now"], superseded_head: GATED }));
  assert.deepEqual(elsewhere.resolved(), ["PRRT_old"]);
  const malformed = fakeApi();
  const result = await run(malformed, null, JSON.stringify({ version: 1, head_sha: NOW, pr_paths: [], threads: [], stale_notes: ["PRRT_now"], superseded_head: "yes" }));
  assert.equal(result.escalationReason, "feedback-invalid");
  assert.deepEqual(malformed.resolved(), []);
});

test("a pass-only round re-run with nothing left open resolves none and succeeds", async () => {
  const api = staleApi([noteThread("PRRT_old", { resolved: true })]);
  const result = await run(api, null, staleRun(["PRRT_old"]));
  assert.deepEqual(api.resolved(), []);
  assert.equal(result.escalationReason, "");
});

test("a failed resolve does not stop the others from being tried, and fails the job after them", async () => {
  const api = staleApi([noteThread("PRRT_a"), noteThread("PRRT_b"), noteThread("PRRT_c")], { failOn: ["PRRT_a"] });
  await assert.rejects(run(api, null, staleRun(["PRRT_a", "PRRT_b", "PRRT_c"])), /PRRT_a/);
  assert.deepEqual(api.resolved(), ["PRRT_a", "PRRT_b", "PRRT_c"]);
});

test("a pass-only round resolves nothing once the head moved past the passing one", async () => {
  for (const [api, runText] of [
    [staleApi([noteThread("PRRT_old")], { moved: true }), staleRun(["PRRT_old"])],
    [staleApi([noteThread("PRRT_old")]), staleRun(["PRRT_old"], GATED.replace(/a/g, "e"))],
  ]) {
    const result = await run(api, null, runText);
    assert.deepEqual(api.resolved(), []);
    assert.equal(result.escalationReason, "");
  }
});

test("a malformed stale_notes list reads as a malformed run.json", async () => {
  const api = fakeApi();
  const result = await run(api, null, JSON.stringify({ version: 1, head_sha: NOW, threads: [], stale_notes: ["not a thread"] }));
  assert.equal(result.escalationReason, "feedback-invalid");
  assert.deepEqual(api.resolved(), []);
});

test("a pass-only round skips pass-only, so the dispatcher can tell its reply check from a round's", async () => {
  const result = await run(staleApi([noteThread("PRRT_old")]), null, staleRun(["PRRT_old"]));
  assert.equal(result.skipReason, "pass-only");
});

// On a PR a person opened GitHub lets the lanes App reply but not resolve
// (#10763): each answer posts as the lanes App and the thread stays open for
// the person or their babysit worker tier, with no escalation.
test("on an owner PR a VALID reply and a lane verdict post as the lanes App and leave their threads open", async () => {
  const api = fakeApi({ opener: HUMAN });
  const logged = [];
  const result = await publish({
    api,
    pr: 42,
    headSha: NOW,
    headRef: "feature",
    appId: APP,
    modelRun: "5000-1",
    reviewerId: REVIEWER,
    trustedHumans: new Set([HUMAN]),
    readArtifact: () => ({ runText: JSON.stringify(RUN), repliesText: lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })) }),
    readAdjudication: () => verdicts(judged("PRRT_b", "lane")),
    fileExists: exists,
    log: (line) => logged.push(line),
  });
  assert.equal(result.escalationReason, "");
  assert.deepEqual(api.posted().map((call) => call[2]), [100, 200, 200], "both lane replies and the adjudication reply");
  assert.deepEqual(api.resolved(), []);
  assert.ok(logged.some((line) => line === "PRRT_a: left open; the lanes App cannot resolve a thread on a PR it did not open"), logged.join("\n"));
  assert.ok(logged.includes("replied on PRRT_a (VALID)"), logged.join("\n"));
  assert.ok(logged.includes("PRRT_b: the finding does not hold; left open for the person"), logged.join("\n"));
  assert.ok(!logged.some((line) => line.endsWith("; resolved")), logged.join("\n"));
});

test("on a lanes App PR the same round still resolves both threads", async () => {
  const api = fakeApi();
  await run(api, lines(reply({ disposition: "VALID" }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })), JSON.stringify(RUN), verdicts(judged("PRRT_b", "lane")));
  assert.deepEqual(api.resolved(), ["PRRT_a", "PRRT_b"]);
});

// A tests-only finding (#10075): run.json carries the select job's CI
// snapshot of the gated head, and the reply job settles from it alone.
const CI_RUNS = [{ name: "test-node", url: "https://github.com/o/r/actions/runs/1/job/3" }];
const ciRun = (ci, threads = [RUN.threads[0]]) => JSON.stringify({ ...RUN, threads, ci });
// A round that pushed nothing: the select job read the head the reply job sees.
const ciRunAtNow = (ci, threads = [RUN.threads[0]]) => JSON.stringify({ ...RUN, head_sha: NOW, threads, ci });
const testsVerdict = () => verdictsAt(NOW, judged("PRRT_a", "tests-only"));

test("an UNCERTAIN tests-only finding on a green head is resolved citing the runs, with no feedback-uncertain", async () => {
  const api = fakeApi();
  const result = await run(api, lines(reply({ disposition: "UNCERTAIN" })), ciRunAtNow({ state: "green", runs: CI_RUNS }), testsVerdict());
  assert.equal(result.escalationReason, "");
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
  assert.match(api.posted()[1][3], /\[test-node\]\(https:\/\/github\.com\/o\/r\/actions\/runs\/1\/job\/3\)/);
  // Red leaves it open with no person; no snapshot leaves it as today.
  const red = fakeApi();
  assert.equal((await run(red, lines(reply({ disposition: "UNCERTAIN" })), ciRunAtNow({ state: "red", runs: CI_RUNS }), testsVerdict())).escalationReason, "");
  assert.deepEqual(red.resolved(), []);
  assert.equal(red.posted().length, 1);
  const none = fakeApi();
  assert.equal((await run(none, lines(reply({ disposition: "UNCERTAIN" })), ciRunAtNow(undefined), testsVerdict())).escalationReason, "feedback-unadjudicated");
});

test("a tests-only finding stays open when the round pushed a fix past the head whose checks were read", async () => {
  const api = fakeApi();
  const result = await run(api, lines(reply({ disposition: "UNCERTAIN" })), ciRun({ state: "green", runs: CI_RUNS }), verdicts(judged("PRRT_a", "tests-only")));
  assert.equal(result.escalationReason, "feedback-unadjudicated");
  assert.deepEqual(api.resolved(), []);
});

test("a run.json whose ci snapshot is malformed posts nothing", async () => {
  for (const ci of [
    { state: "passed", runs: [] },
    { state: "green" },
    { state: "green", runs: [{ name: "test-node", url: "https://evil.example/x" }] },
    { state: "green", runs: [{ name: "test-node\n- [x](y)", url: "https://github.com/o/r/actions/runs/1/job/3" }] },
    { state: "green", runs: Array.from({ length: 101 }, () => CI_RUNS[0]) },
    { state: "green", runs: CI_RUNS, extra: 1 },
  ]) {
    const api = fakeApi();
    const result = await run(api, lines(reply({ disposition: "UNCERTAIN" })), ciRun(ci), verdicts(judged("PRRT_a", "tests-only")));
    assert.equal(result.escalationReason, "feedback-invalid", JSON.stringify(ci));
    assert.equal(api.posted().length, 0);
  }
});

// A mode-only fix (#10080): GitHub lists the file with no patch and no
// changed lines, and the lane's commit still credits the thread.
test("a VALID reply whose fix commit only changes the file's mode is posted and resolved", async () => {
  const modeOnly = [{ filename: "src/a.js", status: "changed", changes: 0 }];
  const api = fakeApi({ compare: { status: "ahead", commits: [fixCommit()], files: modeOnly }, commits: { [FIX]: { files: modeOnly } } });
  const result = await run(api, lines(reply({ disposition: "VALID", evidence: ["src/a.js:1"], note: "Dropped the executable bit." })));
  assert.equal(result.escalationReason, "");
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
});
