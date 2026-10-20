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

// run.json as the model job's runner writes it: two kept threads.
const RUN = {
  version: 1,
  head_sha: GATED,
  threads: [
    { id: "PRRT_a", path: "src/a.js", comment_ids: [100] },
    { id: "PRRT_b", path: "docs/b.md", comment_ids: [200] },
  ],
};
const reply = (fields) => ({ thread: "PRRT_a", disposition: "INCORRECT", evidence: ["src/a.js:3"], fix_sha: "", note: "Guarded at src/a.js:2.", ...fields });
const lines = (...replies) => replies.map((r) => JSON.stringify(r)).join("\n");

function fakeApi(overrides = {}) {
  const calls = [];
  const comment = (id, user, path) => ({ id, user: { id: user }, pull_request_review_id: 10, path, line: 1, body: `finding ${id}` });
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
    listReviews: async () => [{ id: 10, user: { id: REVIEWER }, commit_id: GATED }],
    listReviewComments: async () =>
      overrides.reviewComments ?? [comment(100, REVIEWER, "src/a.js"), comment(200, REVIEWER, "docs/b.md")],
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
      const replied = calls.some((call) => call[0] === "reply" && call[2] === t.ids[0]);
      const ids = replied ? [...t.ids, 900, ...(overrides.arrivedDuringReply ?? [])] : t.ids;
      return { isResolved: t.resolved, pr: t.pr ?? 42, commentCount: ids.length, commentIds: ids };
    },
    // The PR branch reads NOW until `movesAfter` reads, then a later push.
    readBranch: async (ref) => {
      calls.push(["readBranch", ref]);
      return calls.filter((call) => call[0] === "readBranch").length > (overrides.movesAfter ?? Infinity) ? PUSHED : NOW;
    },
    getCommit: async (sha) => overrides.commits?.[sha] ?? { files: [{ filename: "src/a.js" }] },
    compare: async (base, head) => {
      calls.push(["compare", base, head]);
      return overrides.compare ?? { status: "ahead", commits: [{ sha: FIX }], files: [{ filename: "src/a.js" }] };
    },
    replyToComment: async (pr, commentId, body) => {
      calls.push(["reply", pr, commentId, body]);
      return { id: 900, in_reply_to_id: overrides.landOn ?? commentId };
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

const run = (api, repliesText, runText = runFor(repliesText)) =>
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
    fileExists: exists,
  });

// The review-thread tool counts the note in code points (jq length); 2000
// emoji are 4000 UTF-16 units and must still pass here.
test("a note of exactly 2000 emoji is accepted and posted", async () => {
  const api = fakeApi();
  const result = await run(api, lines(reply({ note: "😀".repeat(2000) })));
  // INCORRECT goes to a person; what matters is the note passed validation.
  assert.equal(result.escalationReason, "feedback-disputed");
  assert.equal(api.posted().length, 1);
});

test("a VALID reply is posted in the fixed template on its root comment and resolved", async () => {
  const api = fakeApi();
  const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX, note: "Guarded the null case." })));
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
  const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX, note: "Applied the decision." })), decidedRun);
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
    readArtifact: () => ({ runText: decidedRun, repliesText: lines(reply({ disposition: "VALID", fix_sha: FIX })) }),
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
  assert.equal(api.markers()[0][2], `${ROUND}\n${MODEL_RUN}\npr-unblock / address-feedback finished round 2 of 2 on ${NOW}.`);
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
  assert.match(api.markers()[0][2], /finished round 1 of 3 on/);
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
  const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX })));
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
    lines(reply({ disposition: "VALID", fix_sha: FIX }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
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
  ["a VALID reply with no fix", lines(reply({ disposition: "VALID" }))],
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
  ["a note carrying a control character", lines(reply({ note: "bell \u0007" }))],
  ["a note carrying a direction override", lines(reply({ note: "safe‮evil" }))],
  ["a note carrying a zero-width space", lines(reply({ note: "a​b" }))],
  ["replies over the size limit", `${lines(reply())}\n${" ".repeat(262144)}`],
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

test("an INCORRECT reply is posted, left open, and hands the PR to a person", async () => {
  const api = fakeApi();
  const result = await run(
    api,
    lines(reply({ disposition: "VALID", fix_sha: FIX }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
    JSON.stringify(RUN),
  );
  assert.equal(result.escalationReason, "feedback-disputed");
  assert.deepEqual(api.posted().map((call) => call[2]), [100, 200]);
  assert.deepEqual(api.resolved(), ["PRRT_a"]);
  assert.match(api.posted()[1][3], /INCORRECT, left open/);
});

test("a VALID-only reply set escalates nothing", async () => {
  const api = fakeApi();
  assert.equal((await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX })))).escalationReason, "");
});

for (const [label, compare] of [
  ["the fix is not on the PR branch", { status: "ahead", commits: [{ sha: "e".repeat(40) }], files: [{ filename: "src/a.js" }] }],
  ["the PR branch did not move", { status: "identical", commits: [], files: [] }],
  ["the branch diverged from the gated head", { status: "diverged", commits: [{ sha: FIX }], files: [{ filename: "src/a.js" }] }],
  ["the branch changed a path no kept thread names", { status: "ahead", commits: [{ sha: FIX }], files: [{ filename: "src/a.js" }, { filename: "src/other.js" }] }],
  ["the branch changed .github/", { status: "ahead", commits: [{ sha: FIX }], files: [{ filename: ".github/workflows/ci.yml" }] }],
  ["the branch renamed a file out of .github/", { status: "ahead", commits: [{ sha: FIX }], files: [{ filename: "src/a.js", previous_filename: ".github/x.yml" }] }],
  ["the branch changed too many files to check", { status: "ahead", commits: [{ sha: FIX }], files: Array(300).fill({ filename: "src/a.js" }) }],
]) {
  test(`feedback-not-landed, nothing posted: ${label}`, async () => {
    const api = fakeApi({ compare });
    const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })));
    assert.equal(result.escalationReason, "feedback-not-landed");
    assert.deepEqual(api.posted(), []);
    assert.deepEqual(api.resolved(), []);
    assert.equal(api.markers().length, 1);
  });
}

test("a VALID fix that also adds a file in its thread's plugin lands; another plugin's file does not", async () => {
  const caseRun = JSON.stringify({ ...RUN, threads: [{ ...RUN.threads[0], path: "plugins/p/evals/c/case.yaml" }] });
  for (const [sample, landed] of [
    ["plugins/p/evals/c/samples/new.json", true],
    ["plugins/p/evals/other/samples/new.json", true],
    ["plugins/q/evals/c/samples/new.json", false],
  ]) {
    const api = fakeApi({
      compare: { status: "ahead", commits: [{ sha: FIX }], files: [{ filename: "plugins/p/evals/c/case.yaml" }, { filename: sample }] },
      commits: { [FIX]: { files: [{ filename: "plugins/p/evals/c/case.yaml" }, { filename: sample }] } },
    });
    const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX })), caseRun);
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
      compare: { status: "ahead", commits: [{ sha: FIX }], files: [{ filename: thread.path }, { filename: `${T}/run-transcript.js` }] },
      commits: { [FIX]: { files: [{ filename: thread.path }, { filename: `${T}/run-transcript.js` }] } },
    });
    const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX })), JSON.stringify({ ...RUN, threads }));
    assert.equal(result.escalationReason, landed ? "" : "feedback-not-landed", JSON.stringify(threads[0].named_paths));
  }
  const malformed = await run(fakeApi(), lines(reply({ disposition: "VALID", fix_sha: FIX })), JSON.stringify({ ...RUN, threads: [{ ...thread, named_paths: [7] }] }));
  assert.equal(malformed.escalationReason, "feedback-invalid");
});

test("feedback-not-landed, nothing posted: a VALID fix commit that does not change its own thread's path", async () => {
  const api = fakeApi({
    compare: { status: "ahead", commits: [{ sha: FIX }], files: [{ filename: "docs/b.md" }] },
    commits: { [FIX]: { files: [{ filename: "docs/b.md" }] } },
  });
  const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX })));
  assert.equal(result.escalationReason, "feedback-not-landed");
  assert.deepEqual(api.posted(), []);
});

test("feedback-not-landed with no VALID reply when the branch moved onto .github/ or another path", async () => {
  for (const filename of [".github/actions/x/action.yml", "src/other.js"]) {
    const api = fakeApi({ compare: { status: "ahead", commits: [{ sha: FIX }], files: [{ filename }] } });
    const result = await run(api, lines(reply()));
    assert.equal(result.escalationReason, "feedback-not-landed", filename);
    assert.deepEqual(api.posted(), []);
  }
});

test("a VALID thread that gained a comment while the reply was posted is left open and escalates feedback-partial", async () => {
  const api = fakeApi({ arrivedDuringReply: [101] });
  const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX })));
  assert.equal(api.posted().length, 1);
  assert.deepEqual(api.resolved(), []);
  assert.equal(result.escalationReason, "feedback-partial");
});

test("a resolve that fails once after the reply is retried and resolves", async () => {
  const api = fakeApi({ resolveFailures: 1 });
  const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX })));
  assert.deepEqual(api.resolved(), ["PRRT_a", "PRRT_a"]);
  assert.equal(result.escalationReason, "");
});

test("a resolve that keeps failing after the reply escalates feedback-partial and posts no later reply", async () => {
  const api = fakeApi({ resolveFailures: 2 });
  const result = await run(
    api,
    lines(reply({ disposition: "VALID", fix_sha: FIX }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })),
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
    await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX }), reply({ thread: "PRRT_b", evidence: ["docs/b.md:1"] })));
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
  const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX })));
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
  const result = await run(api, lines(reply({ disposition: "VALID", fix_sha: FIX })));
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
  };
  const api = fakeApi();
  assert.equal(await main(env, { api, log: () => {} }), 0);
  assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-uncertain\n");
  assert.equal(readFileSync(env.SKIP_REASON_FILE, "utf8"), "awaiting-human\n");
  assert.equal(api.posted().length, 1);
  assert.equal(api.markers()[0][2].split("\n")[1], MODEL_RUN);
  // No model attempt names no run, so even a marker already on the PR from
  // an earlier attempt without replies does not stop this one.
  const noAttempt = fakeApi({ issueComments: [{ id: 2, user: { id: APP }, body: `${ROUND}\nround 1` }] });
  await main({ ...env, MODEL_RUN_ATTEMPT: "" }, { api: noAttempt, log: () => {} });
  assert.equal(noAttempt.markers().length, 1);
  assert.match(noAttempt.markers()[0][2], /^<!-- pr-unblock:address-feedback-round -->\npr-unblock \/ address-feedback finished round 2 of 2/);

  // A run.json other than the bytes the model job's runner hashed is refused.
  for (const sha of ["0".repeat(64), ""]) {
    const forged = fakeApi();
    await main({ ...env, RUN_SHA256: sha }, { api: forged, log: () => {} });
    assert.equal(readFileSync(env.ESCALATION_REASON_FILE, "utf8"), "feedback-invalid\n");
    assert.deepEqual(forged.posted(), []);
    assert.equal(forged.markers().length, 1);
  }

  // An oversized replies file is refused before it is read.
  writeFileSync(join(replies, "replies.jsonl"), "x".repeat(262146));
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

  await assert.rejects(main({ ...env, HEAD_SHA: "x" }, { api }), /HEAD_SHA/);
  await assert.rejects(main({ ...env, PR_NUMBER: "0" }, { api }), /PR_NUMBER/);
  await assert.rejects(main({ ...env, HEAD_REF: "" }, { api }), /HEAD_REF/);
  await assert.rejects(main({ ...env, GITHUB_RUN_ID: "x" }, { api }), /GITHUB_RUN_ID/);
  await assert.rejects(main({ ...env, MODEL_RUN_ATTEMPT: "1 -->" }, { api }), /MODEL_RUN_ATTEMPT/);
  await assert.rejects(main({ ...env, ESCALATION_REASON_FILE: "" }, { api }), /ESCALATION_REASON_FILE/);
});
