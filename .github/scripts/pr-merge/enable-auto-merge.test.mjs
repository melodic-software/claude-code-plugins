// Expected values come from the native-merge plan's arm-merge item and the
// owner answers on it: a lanes App pull request is armed for native auto-merge (squash, at the head
// read) with no session, and is never armed, or is disarmed, while it carries
// a `Hold:` line, do-not-merge or the human-gated label. Its issue link is
// the gate's own rule (docs/conventions/pr-pipeline/README.md, "Eligibility":
// one closing issue, or one plain `Refs: #<n>` issue), read through the gate's
// Python, as is the body hold, babysit_merge_policy.BODY_MERGE_HOLD_RE, so
// the parity tests read their verdicts from Python.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

import {
  ARM_MUTATION,
  BODY_HOLD,
  DETAIL_QUERY,
  DISARM_MUTATION,
  DISCUSSION_PAGE_QUERIES,
  rotated,
  HUMAN_VETO,
  PULLS_QUERY,
  THREAD_PAGE_QUERY,
  UNLABELED_QUERY,
  decide,
  liftedByPerson,
  READER_EVENTS,
  main,
  pythonRoom,
  pythonVerify,
  costLine,
  ghCalls,
  LANE_ROOM_TIMEOUT_MS,
  VERIFY_TIMEOUT_MS,
  readRoom,
  verifyHold,
} from "./enable-auto-merge.mjs";
import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { createRateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";
import { COMMENT_DELETED_QUERY, COMMENT_EDITED_QUERY, LANE_HOLD, PULL_OPENED_QUERY, VERIFY_PATH, personWrote, verdictHold } from "./merge-holds.mjs";
import { VERIFY_PATH as RESOLVER_VERIFY_PATH } from "../pr-verify/resolve-pr.mjs";
import { HOLD_LINE, decide as decideOutcome } from "../work-resolve-issue/report-outcome.mjs";

const REPO = "melodic-software/claude-code-plugins";
const LANES = { __typename: "Bot", login: "melodic-automation-lanes" };
const HEAD = "b".repeat(40);
const ENV = {
  EVENT_NAME: "schedule",
  GITHUB_REPOSITORY: REPO,
  KILL_SWITCH: "proceed",
  REPORT_ONLY: "false",
  LANES_BOT_LOGIN: "melodic-automation-lanes[bot]",
  TRACKER_CONFIG: "/nonexistent/.work-item-tracker.json",
  RESOLVED_CONFIG: fileURLToPath(new URL("./fixtures/enable-auto-merge-resolved.json", import.meta.url)),
};

const pull = (number, overrides = {}) => ({
  id: `PR_${number}`,
  number,
  isDraft: false,
  isCrossRepository: false,
  headRefOid: HEAD,
  baseRefOid: "d".repeat(40),
  body: `Closes #${number + 1000}\n\n## Summary\n\nDone.`,
  author: LANES,
  labels: { totalCount: 0, nodes: [] },
  autoMergeRequest: null,
  ...overrides,
});
// One pull request's comments, reviews, inline comments and newest
// auto-merge-disabled event, as DETAIL_QUERY returns them.
const page = (nodes = []) => ({ totalCount: nodes.length, nodes });
function detail({ comments = [], reviews = [], inline = [], disabledBy = null } = {}) {
  return {
    comments: page(comments),
    reviews: page(reviews),
    reviewThreads: page(inline.length ? [{ comments: page(inline) }] : []),
    timelineItems: { nodes: disabledBy ? [{ actor: disabledBy }] : [] },
  };
}
const said = (login, body, at, association = "OWNER", typename = "User") => ({
  author: { __typename: typename, login },
  body,
  createdAt: at,
  authorAssociation: association,
});
const PASSED = { refusal: null, head: HEAD, ineligible: null, reviews: null };
const COST_LINK = `https://github.com/${REPO}/issues/1040#issuecomment-7`;
const COST_COMMENT = {
  issue_url: `https://api.github.com/repos/${REPO}/issues/1040`,
  user: { login: "kyle-sexton", id: 5, type: "User" },
  performed_via_github_app: null,
  body: "**Decision recorded.** Cost: approve it for #40.",
  node_id: "IC_7",
  created_at: "2026-10-22T12:00:00Z",
};
// lane-room's answer for a lane with room: nothing in flight of five.
const ROOM = { refusal: null, unreadable: null, count: 0, cap: 5, queued: [], rung: "C2" };
const room = (answer = ROOM) => async () => answer;
const labels = (...names) => ({ totalCount: names.length, nodes: names.map((name) => ({ name })) });

// armErrors: per pull request id, the errors its arm sends throw, in order.
// filesError: what every changed-files GET throws.
function world(pulls, { failArm = false, armErrors = {}, filesError = null, noteErrors = [], disarmError = null, pinError = null } = {}) {
  const pins = [];
  const noteThrows = [...noteErrors];
  const armThrows = Object.fromEntries(Object.entries(armErrors).map(([id, errors]) => [id, [...errors]]));
  const calls = [];
  const notes = [];
  const github = async (method, path, body, headers) => {
    calls.push({ method, path, body, headers });
    const listing = /^\/repos\/melodic-software\/claude-code-plugins\/pulls\/([0-9]+)\/files\?per_page=100&page=([0-9]+)$/.exec(path);
    if (method === "GET" && listing && filesError) {
      throw filesError;
    }
    if (method === "GET" && listing) {
      const files = pulls.find((candidate) => candidate.number === Number(listing[1]))?.files ?? [{ filename: "plugins/work-items/README.md" }];
      return files.slice((Number(listing[2]) - 1) * 100, Number(listing[2]) * 100);
    }
    // The cost decision reads (merge-holds.costDecision): the owner's comment
    // 7 on pull request 40's closing issue, and each pull request closes its own
    // number plus 1000.
    if (method === "GET" && path === "/repos/melodic-software/claude-code-plugins/issues/comments/7") {
      return COST_COMMENT;
    }
    // Its decided head: a review lane's cost hold marker at the head, before it.
    if (method === "GET" && /^\/repos\/melodic-software\/claude-code-plugins\/issues\/[0-9]+\/comments\?per_page=100&page=1$/.test(path)) {
      return [{ user: { login: "github-actions[bot]", type: "Bot" }, created_at: "2026-10-22T11:00:00Z", body: `<!-- claude-lane-hold lane=claude-review sha=${HEAD} criteria=cost -->` }];
    }
    // A pull request's whole label list, when its listing cut it.
    const labelPage = /^\/repos\/melodic-software\/claude-code-plugins\/issues\/([0-9]+)\/labels\?per_page=100&page=([0-9]+)$/.exec(path);
    if (method === "GET" && labelPage) {
      // With no `allLabels`, the read fails, so the list stays cut.
      const all = pulls.find((candidate) => candidate.number === Number(labelPage[1]))?.allLabels;
      if (all === undefined) {
        throw new Error("GET labels failed with status 502");
      }
      return all.slice((Number(labelPage[2]) - 1) * 100, Number(labelPage[2]) * 100).map((name) => ({ name }));
    }
    // The read-back pin, posted before an arm.
    if (method === "POST" && String(body?.body ?? "").startsWith("<!-- babysit-merge-pin ")) {
      pins.push({ path, body: body.body });
      if (pinError) {
        throw pinError;
      }
      return {};
    }
    // The refusal note: a comment posted or edited, and the label.
    const note = /^\/repos\/melodic-software\/claude-code-plugins\/issues\/(?:([0-9]+)\/(comments|labels)|comments\/([0-9]+))$/.exec(path);
    if (note && (method === "POST" || method === "PATCH")) {
      notes.push({ method, path, body });
      if (noteThrows.length > 0) {
        throw noteThrows.shift();
      }
      return {};
    }
    assert.equal(`${method} ${path}`, "POST /graphql");
    if (body.query === PULL_OPENED_QUERY) {
      const nodes = [{ number: body.variables.number + 1000, repository: { nameWithOwner: REPO } }];
      return { data: { repository: { pullRequest: { createdAt: "2026-10-22T10:00:00Z", closingIssuesReferences: { totalCount: 1, nodes } } } } };
    }
    if (body.query === COMMENT_EDITED_QUERY) {
      return { data: { node: { lastEditedAt: null } } };
    }
    if (body.query === COMMENT_DELETED_QUERY) {
      return { data: { repository: { pullRequest: { timelineItems: { filteredCount: 0, nodes: [] } } } } };
    }
    if (body.query === PULLS_QUERY) {
      assert.deepEqual(body.variables, { owner: "melodic-software", name: "claude-code-plugins", after: null });
      return { data: { repository: { pullRequests: { pageInfo: { hasNextPage: false, endCursor: null }, nodes: pulls } } } };
    }
    if (body.query === UNLABELED_QUERY) {
      const nodes = pulls.find((candidate) => candidate.number === body.variables.number)?.unlabeled ?? [];
      return { data: { repository: { pullRequest: { timelineItems: { totalCount: nodes.length, nodes } } } } };
    }
    if (body.query === DETAIL_QUERY) {
      const found = pulls.find((candidate) => candidate.number === body.variables.number);
      return { data: { repository: { pullRequest: found?.cutDiscussion ?? detail(found?.discussion) } } };
    }
    // The rest of a cut comment list, two to a page.
    if (body.query === DISCUSSION_PAGE_QUERIES.comments) {
      const all = pulls.find((candidate) => candidate.number === body.variables.number)?.discussion?.comments ?? [];
      const start = body.variables.after === null ? 0 : Number(body.variables.after);
      const nodes = all.slice(start, start + 2);
      return { data: { repository: { pullRequest: { comments: { totalCount: all.length, pageInfo: { hasNextPage: start + 2 < all.length, endCursor: String(start + 2) }, nodes } } } } };
    }
    // The rest of a cut review thread's comments, by the thread's id, two to
    // a page.
    if (body.query === THREAD_PAGE_QUERY) {
      const all = pulls.flatMap((candidate) => Object.entries(candidate.threads ?? {})).find(([id]) => id === body.variables.id)?.[1] ?? [];
      const start = body.variables.after === null ? 0 : Number(body.variables.after);
      const nodes = all.slice(start, start + 2);
      return { data: { node: { comments: { totalCount: all.length, pageInfo: { hasNextPage: start + 2 < all.length, endCursor: String(start + 2) }, nodes } } } };
    }
    if (body.query === ARM_MUTATION && armThrows[body.variables.id]?.length > 0) {
      throw armThrows[body.variables.id].shift();
    }
    if (body.query === DISARM_MUTATION && disarmError) {
      throw disarmError;
    }
    if (body.query === ARM_MUTATION && failArm) {
      throw new Error("POST /graphql (GraphQL errors) failed with status 200");
    }
    return { data: {} };
  };
  // The gate's verifier evidence: a pull request's `verdict` (a report, or
  // an Error to throw), else a pass at its head.
  const verified = [];
  const verify = async ({ number, headRefOid: head }) => {
    verified.push(number);
    const found = pulls.find((candidate) => candidate.number === number);
    if (found?.verdict instanceof Error) {
      throw found.verdict;
    }
    return found?.verdict ?? { refusal: null, head, ineligible: null, reviews: null };
  };
  const writes = () =>
    calls
      .filter(({ method, path, body }) => method === "POST" && path === "/graphql" && ![PULLS_QUERY, DETAIL_QUERY, PULL_OPENED_QUERY, COMMENT_EDITED_QUERY, COMMENT_DELETED_QUERY, UNLABELED_QUERY, DISCUSSION_PAGE_QUERIES.comments, THREAD_PAGE_QUERY].includes(body.query))
      .map(({ body }) => ({ mutation: body.query === ARM_MUTATION ? "arm" : body.query === DISARM_MUTATION ? "disarm" : "?", ...body.variables }));
  return { github, writes, verify, verified, calls, notes, pins };
}

async function run(pulls, env = {}, options = {}, lane = ROOM) {
  const { github, writes, verify, verified, calls, notes, pins } = world(pulls, options);
  const lines = [];
  const slept = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    const code = await main({ env: { ...ENV, ...env }, github, verify, room: room(lane), sleep: async (ms) => slept.push(ms), random: options.random, now: options.now });
    return { code, writes: writes(), lines, verified, slept, calls, notes, pins };
  } finally {
    console.log = log;
  }
}

// The refusal note's two bodies, written out by hand: the gate's reasons
// marker on its own line, the head named on the next, the reason fenced.
const laneNote = (reason) =>
  [
    "<!-- babysit-merge-risk -->",
    `Unattended merge: native auto-merge leaves this pull request unarmed at head \`${HEAD}\`. The lanes clear this reason on their own; the next scheduled run judges it again.`,
    "",
    "```text",
    reason,
    "```",
  ].join("\n");
const personNote = (reason) =>
  [
    "<!-- work-items:escalation lane=pr-merge kind=escalated -->",
    "<!-- babysit-merge-risk -->",
    `Unattended merge: native auto-merge leaves this pull request unarmed at head \`${HEAD}\`. A person must clear this reason, so the pr-merge lane added the \`needs-human\` label: fix the reason, then remove the label, and the next scheduled run judges it again.`,
    "",
    "```text",
    reason,
    "```",
  ].join("\n");
const ISSUES = "/repos/melodic-software/claude-code-plugins/issues";
const lanesSaid = (body, updatedAt = "2026-10-23T10:00:00Z") => ({
  databaseId: 77,
  author: { __typename: "Bot", login: LANES.login },
  body,
  createdAt: "2026-10-23T10:00:00Z",
  updatedAt,
  authorAssociation: "NONE",
});
const HOLD_PATH_REASON = "it changes docs/held.md, a hold path";
// A real charge, a cause a person must clear (owner direction 2026-10-24).
const COST_REASON = "it changes infra/main.tf, a cost path";
const COST_FILES = [{ filename: "infra/main.tf" }];
const MISSING = { refusal: "verify:missing", needsHuman: false, head: HEAD, ineligible: null, reviews: null };
const MISSING_REASON = "pr-merge's gate refuses its verifier verdict (verify:missing)";

test("a refusal a person must clear is commented on and labeled human-gated; a hold path only commented on", async () => {
  const { code, writes, notes } = await run([pull(1, { files: COST_FILES }), pull(2, { files: [{ filename: "docs/held.md" }] })]);
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
  assert.deepEqual(notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(COST_REASON) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
    { method: "POST", path: `${ISSUES}/2/comments`, body: { body: laneNote(HOLD_PATH_REASON) } },
  ]);
});

test("an untrusted spec and the repeated-FAIL round cap are a person's verifier refusals; the rest are a lane's", async () => {
  const refused = (refusal, needsHuman) => ({ refusal, needsHuman, head: HEAD, ineligible: null, reviews: null });
  const { notes } = await run([
    pull(1, { verdict: refused("verify:untrusted-spec", true) }),
    pull(2, { verdict: refused("verify:spec-changed", true) }),
    pull(3, { verdict: refused("verify:repeated-fail", true) }),
    pull(4, { verdict: { ...MISSING, refusal: "verify:ineligible", ineligible: "it closes 2 issues" } }),
  ]);
  const refusing = (code) => `pr-merge's gate refuses its verifier verdict (${code})`;
  assert.deepEqual(notes, [
    { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(refusing("verify:untrusted-spec")) } },
    { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
    { method: "POST", path: `${ISSUES}/2/comments`, body: { body: laneNote(refusing("verify:spec-changed")) } },
    { method: "POST", path: `${ISSUES}/3/comments`, body: { body: personNote(refusing("verify:repeated-fail")) } },
    { method: "POST", path: `${ISSUES}/3/labels`, body: { labels: ["needs-human"] } },
    { method: "POST", path: `${ISSUES}/4/comments`, body: { body: laneNote("pr-merge's lane does not take its issue link (it closes 2 issues)") } },
  ]);
});

test("a refusal a lane clears is commented on, with no label", async () => {
  const { code, notes } = await run([pull(1, { verdict: MISSING })]);
  assert.equal(code, 0);
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(MISSING_REASON) } }]);
});

const unlabeled = (at, typename = "User", name = "needs-human") => ({ createdAt: at, actor: { __typename: typename, login: "someone" }, label: { name } });

test("an unchanged refusal writes nothing, and a label a person removed stays off", async () => {
  const lane = pull(1, { verdict: MISSING, discussion: { comments: [lanesSaid(laneNote(MISSING_REASON))] } });
  const person = pull(2, {
    files: COST_FILES,
    discussion: { comments: [lanesSaid(personNote(COST_REASON))] },
    unlabeled: [unlabeled("2026-10-23T10:30:00Z", "User", "Needs-Human")],
  });
  const { code, notes } = await run([lane, person]);
  assert.equal(code, 0);
  assert.deepEqual(notes, []);
});

test("a person's refusal comment standing without its label gets the label back", async () => {
  // An earlier run's label write failed: no removal at all, a bot's, a
  // person's before the comment last changed, or another label's.
  for (const removals of [[], [unlabeled("2026-10-23T10:30:00Z", "Bot")], [unlabeled("2026-10-23T09:59:00Z")], [unlabeled("2026-10-23T10:30:00Z", "User", "do-not-merge")]]) {
    const person = pull(2, { files: COST_FILES, discussion: { comments: [lanesSaid(personNote(COST_REASON))] }, unlabeled: removals });
    const { code, notes } = await run([person]);
    assert.equal(code, 0);
    assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/2/labels`, body: { labels: ["needs-human"] } }]);
  }
});

test("a timeline not read whole puts no label back", () => {
  assert.equal(liftedByPerson({ totalCount: 101, nodes: [] }, "needs-human", "2026-10-23T10:00:00Z"), true);
  assert.equal(liftedByPerson(null, "needs-human", "2026-10-23T10:00:00Z"), true);
  assert.equal(liftedByPerson({ totalCount: 0, nodes: [] }, "needs-human", "2026-10-23T10:00:00Z"), false);
});

test("a changed refusal edits the one comment instead of posting another", async () => {
  const moved = pull(1, { verdict: MISSING, discussion: { comments: [lanesSaid(laneNote("an earlier reason"))] } });
  const { notes } = await run([moved]);
  assert.deepEqual(notes, [{ method: "PATCH", path: `${ISSUES}/comments/77`, body: { body: laneNote(MISSING_REASON) } }]);
});

test("a risk hold is a person's only for a security finding, an aliasing path, a trusted-actor widening or a cost hold", async () => {
  const risk = (reviews) => ({ refusal: null, needsHuman: false, head: HEAD, ineligible: null, reviews });
  const holding = (reviews) => `pr-merge's gate holds it on its risk score (${reviews})`;
  const lane = ["evidence-unbound:claude-review: no-marker", "manifest-review-required: plugins/a/.claude-plugin/plugin.json: hooks", "high-path:docs/**: docs/a.md"];
  const person = [
    "security-finding: 1 CRITICAL",
    "high-path:**: 'a' mode '120000' (symlink)",
    "files-incomplete: x; trust-gate:trusted-actors: entries added",
    "cost-review-required: infra/main.tf",
  ];
  for (const reviews of lane) {
    // A lane's stays a lane's however long its comment has stood.
    const stood = pull(1, { verdict: risk(reviews), discussion: { comments: [lanesSaid(laneNote(holding(reviews)), "2026-01-01T00:00:00Z")] } });
    assert.deepEqual((await run([stood])).notes, [], reviews);
    assert.deepEqual((await run([pull(1, { verdict: risk(reviews) })])).notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(holding(reviews)) } }], reviews);
  }
  for (const reviews of person) {
    assert.deepEqual(
      (await run([pull(1, { verdict: risk(reviews) })])).notes,
      [
        { method: "POST", path: `${ISSUES}/1/comments`, body: { body: personNote(holding(reviews)) } },
        { method: "POST", path: `${ISSUES}/1/labels`, body: { labels: ["needs-human"] } },
      ],
      reviews,
    );
  }
});

test("an armed pull request, an event run and report-only write no refusal note", async () => {
  assert.deepEqual((await run([pull(1)])).notes, []);
  const armedHeld = pull(2, { autoMergeRequest: {}, files: [{ filename: "docs/held.md" }] });
  const event = await run([armedHeld], { EVENT_NAME: "pull_request" });
  assert.deepEqual(event.writes, [{ mutation: "disarm", id: "PR_2" }]);
  assert.deepEqual(event.notes, []);
  const reported = await run([pull(3, { verdict: MISSING })], { REPORT_ONLY: "true" });
  assert.deepEqual(reported.notes, []);
  assert.ok(reported.lines.includes("enable-auto-merge: #3 would note its refusal (report-only)"));
});

test("a disarmed pull request gets the note after the disarm", async () => {
  const armed = pull(1, { autoMergeRequest: {}, verdict: MISSING });
  const { writes, notes } = await run([armed]);
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_1" }]);
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(MISSING_REASON) } }]);
});

test("a failed disarm writes no note, since the pull request is still armed", async () => {
  const armed = pull(1, { autoMergeRequest: {}, files: [{ filename: "docs/held.md" }] });
  const { code, writes, notes, lines } = await run([armed], {}, { disarmError: new GitHubError(200, "POST /graphql (GraphQL errors)") });
  assert.equal(code, 1);
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_1" }]);
  assert.deepEqual(notes, []);
  assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#1 disarm")));
});

test("a refusal comment that fails on the network is not sent again", async () => {
  const { code, notes, slept } = await run([pull(1, { verdict: MISSING })], {}, { noteErrors: [closed()] });
  assert.equal(code, 1);
  assert.deepEqual(notes, [{ method: "POST", path: `${ISSUES}/1/comments`, body: { body: laneNote(MISSING_REASON) } }]);
  assert.deepEqual(slept, []);
});

test("a lanes App pull request with no hold is armed, squash, at the head it read", async () => {
  const { code, writes } = await run([pull(7)]);
  assert.equal(code, 0);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_7", head: HEAD }]);
  assert.match(ARM_MUTATION, /mergeMethod: SQUASH, expectedHeadOid: \$head/);
});

// babysit_postmerge.PIN_RE, written out: the read-back takes the head from the
// first line of the lanes App's newest unedited pin comment.
const PIN_LINE = `<!-- babysit-merge-pin sha=${HEAD} -->`;

test("the head is pinned in the read-back's format before the arm", async () => {
  const { code, writes, pins, calls } = await run([pull(7)]);
  assert.equal(code, 0);
  assert.deepEqual(pins.map((pin) => [pin.path, pin.body.split("\n")[0]]), [[`${ISSUES}/7/comments`, PIN_LINE]]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_7", head: HEAD }]);
  const order = calls.map((call) => (call.body?.query === ARM_MUTATION ? "arm" : String(call.body?.body ?? "").startsWith(PIN_LINE) ? "pin" : null)).filter(Boolean);
  assert.deepEqual(order, ["pin", "arm"]);
});

test("an unedited pin for the same head is not posted again", async () => {
  const pin = { ...lanesSaid(`${PIN_LINE}\nArmed.`), lastEditedAt: null };
  const { writes, pins } = await run([pull(7, { discussion: { comments: [pin] } })]);
  assert.deepEqual(pins, []);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_7", head: HEAD }]);
});

test("a pin for another head, an edited pin or another author's pin is posted again", async () => {
  const other = { ...lanesSaid(`<!-- babysit-merge-pin sha=${"c".repeat(40)} -->`), lastEditedAt: null };
  const edited = { ...lanesSaid(`${PIN_LINE}\nArmed.`), lastEditedAt: "2026-10-23T11:00:00Z" };
  const person = { ...said("kyle-sexton", PIN_LINE, "2026-10-23T10:00:00Z"), lastEditedAt: null };
  const stale = [{ ...lanesSaid(PIN_LINE), lastEditedAt: null }, { ...other, createdAt: "2026-10-23T12:00:00Z" }];
  for (const comments of [[other], [edited], [person], stale]) {
    const { pins } = await run([pull(7, { discussion: { comments } })]);
    assert.equal(pins.length, 1);
  }
});

test("a pin that fails to post leaves it unarmed and fails the run", async () => {
  const { code, writes, pins, lines } = await run([pull(7), pull(8)], {}, { pinError: new Error("POST comments failed with status 502") });
  assert.equal(code, 1);
  assert.equal(pins.length, 2);
  assert.deepEqual(writes, []);
  assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#7 pin, so not armed")));
});

test("report-only posts no pin", async () => {
  const { pins } = await run([pull(7)], { REPORT_ONLY: "true" });
  assert.deepEqual(pins, []);
});

test("a Hold: line, do-not-merge or the human-gated label leaves it unarmed", async () => {
  const { code, writes } = await run([
    pull(1, { body: "Closes #5\n\nHold: a human merges this\n" }),
    pull(2, { body: "Closes #5\r\n  hold: wait for the canary" }),
    pull(3, { labels: labels("do-not-merge") }),
    pull(4, { labels: labels("Needs-Human") }),
    pull(5, { body: "Closes #5\n\nPlease do not merge yet." }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
});

test("the human-gated label comes from the tracker config", async () => {
  const config = fileURLToPath(new URL("./fixtures/enable-auto-merge-tracker.json", import.meta.url));
  const { writes } = await run([pull(1, { labels: labels("human-gated") }), pull(2, { labels: labels("needs-human") })], { TRACKER_CONFIG: config });
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_2", head: HEAD }]);
});

test("an armed pull request that now holds is disarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { code, writes } = await run([
    pull(1, { autoMergeRequest: armed, body: "Closes #5\n\nHold: a human merges this" }),
    pull(2, { autoMergeRequest: armed, labels: labels("needs-human") }),
    pull(3, { autoMergeRequest: armed }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_1" },
    { mutation: "disarm", id: "PR_2" },
  ]);
});

test("only the lanes App's ready pull requests from this repository are armed", async () => {
  const { writes } = await run([
    pull(1, { author: { __typename: "User", login: "kyle-sexton" } }),
    pull(2, { author: { __typename: "Bot", login: "dependabot" } }),
    pull(3, { author: { __typename: "User", login: "melodic-automation-lanes" } }),
    pull(4, { isDraft: true }),
    pull(5, { isCrossRepository: true }),
    pull(8, { headRefOid: "abc" }),
    pull(9, { labels: { totalCount: 101, nodes: [] } }),
  ]);
  assert.deepEqual(writes, []);
});

test("report-only arms and disarms nothing", async () => {
  const { code, writes, lines } = await run([pull(1), pull(2, { autoMergeRequest: {}, labels: labels("do-not-merge") })], { REPORT_ONLY: "true" });
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
  assert.ok(lines.some((line) => /#1 would arm \(report-only\)/.test(line)));
  assert.ok(lines.some((line) => /#2 would disarm \(report-only\)/.test(line)));
});

test("the kill switch stops it before any read", async () => {
  const { code, writes } = await run([pull(1)], { KILL_SWITCH: "" });
  assert.equal(code, 0);
  assert.deepEqual(writes, []);
});

test("a failed arm fails the run and still reaches the next pull request", async () => {
  const { code, writes, lines } = await run([pull(1), pull(2, { autoMergeRequest: {}, labels: labels("do-not-merge") })], {}, { failArm: true });
  assert.equal(code, 1);
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "disarm", id: "PR_2" },
  ]);
  assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#1 arm")));
});

// undici's shape for a dropped socket: a "fetch failed" TypeError whose cause
// carries the code and the socket's message.
const reset = () => new TypeError("fetch failed", { cause: Object.assign(new Error("read ECONNRESET"), { code: "ECONNRESET" }) });

// The socket GitHub closed while the connection sat idle: undici's
// UND_ERR_SOCKET "other side closed".
const closed = () => new TypeError("fetch failed", { cause: Object.assign(new Error("other side closed"), { code: "UND_ERR_SOCKET" }) });

test("an arm that fails on the network is sent again after a capped wait and arms", async () => {
  const { code, writes, lines, slept } = await run([pull(1)], {}, { armErrors: { PR_1: [reset(), closed()] } });
  assert.equal(code, 0);
  assert.deepEqual(writes, Array(3).fill({ mutation: "arm", id: "PR_1", head: HEAD }));
  // Two resends, each waiting no longer than the 8 s cap.
  assert.equal(slept.length, 2);
  assert.ok(slept.every((ms) => ms >= 0 && ms <= 8000));
  assert.ok(lines.includes(`enable-auto-merge: #1 armed at ${HEAD}`));
});

test("the resend waits are full jitter under caps of 4 s, then 8 s", async () => {
  const errors = () => ({ PR_1: [reset(), reset()] });
  assert.deepEqual((await run([pull(1)], {}, { armErrors: errors(), random: () => 1 })).slept, [4000, 8000]);
  assert.deepEqual((await run([pull(1)], {}, { armErrors: errors(), random: () => 0 })).slept, [0, 0]);
});

test("a GET that fails on the network is left to the client's own retry, not sent again here", async () => {
  const { calls, slept, writes } = await run([pull(1)], {}, { filesError: reset() });
  assert.equal(calls.filter(({ method }) => method === "GET").length, 1);
  assert.deepEqual(slept, []);
  assert.deepEqual(writes, []);
});

test("a lone arm that fails three times on the network is warned with its cause, and with no arm landing the run fails", async () => {
  const { code, writes, lines } = await run([pull(1)], {}, { armErrors: { PR_1: [reset(), reset(), reset(), reset()] } });
  assert.equal(code, 1);
  assert.equal(writes.length, 3);
  assert.ok(lines.includes("::warning title=enable-auto-merge::#1 arm failed on the network after its resends, skipped this run: fetch failed (cause: ECONNRESET read ECONNRESET)"));
});

const bare = () => new TypeError("fetch failed");

test("one pull request whose arm fails on the network every attempt is skipped, the other is armed, and the run stays green", async () => {
  const { code, writes, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [bare(), bare(), bare()] } });
  assert.equal(code, 0);
  assert.deepEqual(writes.at(-1), { mutation: "arm", id: "PR_2", head: HEAD });
  assert.ok(lines.includes("::warning title=enable-auto-merge::#1 arm failed on the network after its resends, skipped this run: fetch failed"));
  assert.ok(lines.includes(`enable-auto-merge: #2 armed at ${HEAD}`));
  assert.ok(!lines.includes(`enable-auto-merge: #1 armed at ${HEAD}`));
  assert.ok(!lines.some((line) => line.startsWith("::error")));
});

test("every arm in the run failing on the network, after the listing read, is an outage and fails red", async () => {
  const { code, writes, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [bare(), bare(), bare()], PR_2: [bare(), bare(), bare()] } });
  assert.equal(code, 1);
  assert.equal(writes.length, 6);
  assert.ok(lines.includes("::error title=enable-auto-merge::every arm this run failed: #1, #2"));
});

test("an arm that failed on the network keeps its slot, since it may have landed", async () => {
  const { writes, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [bare(), bare(), bare()] } }, { ...ROOM, cap: 1 });
  assert.deepEqual(writes, Array(3).fill({ mutation: "arm", id: "PR_1", head: HEAD }));
  assert.ok(lines.includes("enable-auto-merge: #2 left: merge.max-in-flight is 1 and 1 merges are in flight"));
});

test("a refusal after a resend keeps the slot, since the first attempt may have landed", async () => {
  const { writes, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [bare(), new GitHubError(200, "POST /graphql (GraphQL errors)")] } }, { ...ROOM, cap: 1 });
  assert.deepEqual(writes, Array(2).fill({ mutation: "arm", id: "PR_1", head: HEAD }));
  assert.ok(lines.some((line) => line.startsWith("::warning title=enable-auto-merge::#1 arm refused")));
  assert.ok(lines.includes("enable-auto-merge: #2 left: merge.max-in-flight is 1 and 1 merges are in flight"));
});

test("each network trigger alone is sent again, and an error with another code is not", async () => {
  const coded = (code) => Object.assign(new Error("socket"), { cause: Object.assign(new Error("x"), { code }) });
  for (const error of [new TypeError("fetch failed"), coded("ETIMEDOUT"), coded("UND_ERR_CONNECT_TIMEOUT"), Object.assign(new Error("socket"), { cause: new Error("other side closed") })]) {
    const { code, writes } = await run([pull(1)], {}, { armErrors: { PR_1: [error] } });
    assert.equal(code, 0);
    assert.equal(writes.length, 2);
  }
  const { code, writes } = await run([pull(1)], {}, { armErrors: { PR_1: [coded("EPIPE_NOT_LISTED")] } });
  assert.equal(code, 1);
  assert.equal(writes.length, 1);
});

test("the resend warning names the arm and its pull request", async () => {
  const { lines } = await run([pull(1)], {}, { armErrors: { PR_1: [closed()] } });
  assert.ok(lines.some((line) => line.startsWith("::warning::enable-auto-merge: POST /graphql (arm) for PR_1 failed (TypeError UND_ERR_SOCKET)")));
});

test("every request asks GitHub to close its connection after answering", async () => {
  const { calls } = await run([pull(1)]);
  assert.ok(calls.length > 1);
  assert.ok(calls.every(({ headers }) => headers?.Connection === "close"));
});

test("an arm GitHub refuses with GraphQL errors or a 4xx is skipped with a warning, not sent again, and the run stays green", async () => {
  for (const error of [new GitHubError(200, "POST /graphql (GraphQL errors)"), new GitHubError(422, "POST /graphql"), new GitHubError(404, "POST /graphql")]) {
    const { code, writes, slept, lines } = await run([pull(1)], {}, { armErrors: { PR_1: [error] } });
    assert.equal(code, 0);
    assert.deepEqual(writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
    assert.deepEqual(slept, []);
    assert.ok(lines.includes(`::warning title=enable-auto-merge::#1 arm refused, skipped this run: ${error.message}`));
    assert.ok(!lines.some((line) => line.startsWith("::error")));
  }
});

test("a refused arm on one of two pull requests still arms the other, inside a cap of one", async () => {
  const refusal = new GitHubError(200, "POST /graphql (GraphQL errors)");
  const { code, writes, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [refusal] } }, { ...ROOM, cap: 1 });
  assert.equal(code, 0);
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "arm", id: "PR_2", head: HEAD },
  ]);
  assert.ok(lines.some((line) => line.startsWith("::warning title=enable-auto-merge::#1 arm refused")));
  assert.ok(lines.includes(`enable-auto-merge: #2 armed at ${HEAD}`));
});

test("two arms each refused for their own reason (422) are warned and the run stays green", async () => {
  const refusal = () => new GitHubError(422, "POST /graphql");
  const { code, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [refusal()], PR_2: [refusal()] } });
  assert.equal(code, 0);
  assert.ok(lines.some((line) => line.startsWith("::warning title=enable-auto-merge::#1 arm refused")));
  assert.ok(lines.some((line) => line.startsWith("::warning title=enable-auto-merge::#2 arm refused")));
  assert.ok(lines.includes("::warning title=enable-auto-merge::every arm this run failed: #1, #2"));
  assert.ok(!lines.some((line) => line.startsWith("::error")));
});

test("two or more arms all answered 404 fail the run and say so", async () => {
  const missing = () => new GitHubError(404, "POST /graphql");
  const { code, lines } = await run([pull(1), pull(2)], {}, { armErrors: { PR_1: [missing()], PR_2: [missing()] } });
  assert.equal(code, 1);
  assert.ok(lines.includes("::error title=enable-auto-merge::every arm this run failed: #1, #2"));
});

test("an arm answered 401, 403, 429 or 5xx is not a refusal of that pull request: not sent again, and the run fails", async () => {
  for (const status of [401, 403, 429, 502]) {
    const { code, writes, slept, lines } = await run([pull(1)], {}, { armErrors: { PR_1: [new GitHubError(status, "POST /graphql")] } });
    assert.equal(code, 1);
    assert.equal(writes.length, 1);
    assert.deepEqual(slept, []);
    assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#1 arm:")));
  }
});

// main's own client over a stubbed fetch, so the arm's answer carries real
// headers and body: `arm` is the Response every arm gets.
async function served(pulls, arm) {
  const { github, verify } = world(pulls);
  const saved = globalThis.fetch;
  const lines = [];
  const log = console.log;
  globalThis.fetch = async (url, init) => {
    const body = init.body === undefined ? undefined : JSON.parse(init.body);
    if (body?.query === ARM_MUTATION) {
      return arm();
    }
    const answer = await github(init.method, new URL(url).pathname + new URL(url).search, body, init.headers);
    return new Response(answer == null ? "" : JSON.stringify(answer), { status: 200, headers: { "content-type": "application/json" } });
  };
  console.log = (line) => lines.push(line);
  try {
    // Its own latch: one case's rate limit neither refuses the next case's
    // calls nor fails this process.
    const latch = createRateLimitLatch({ log: () => {}, fail: () => {}, limits: () => ({}), stopFile: null });
    return { code: await main({ env: { ...ENV, GH_TOKEN: "t" }, verify, room: room(), sleep: async () => {}, latch }), lines };
  } finally {
    globalThis.fetch = saved;
    console.log = log;
  }
}

test("a refused arm's warning carries GitHub's own message", async () => {
  const { code, lines } = await served([pull(1)], () => Response.json({ errors: [{ message: "Pull request is in clean status" }] }));
  assert.equal(code, 0);
  assert.ok(lines.includes("::warning title=enable-auto-merge::#1 arm refused, skipped this run: POST /graphql (GraphQL errors) failed with status 200: Pull request is in clean status"));
});

test("a rate-limited GraphQL answer to an arm is not a refusal, and the run fails", async () => {
  for (const headers of [{ "x-ratelimit-remaining": "0" }, { "retry-after": "60" }]) {
    const { code, lines } = await served([pull(1)], () => Response.json({ errors: [{ message: "API rate limit exceeded" }] }, { headers }));
    assert.equal(code, 1);
    assert.ok(!lines.some((line) => line.includes("arm refused")));
  }
});

test("a GraphQL answer typed RATE_LIMITED is rate-limited without its headers, and the run fails", async () => {
  const { code, lines } = await served([pull(1)], () => Response.json({ errors: [{ type: "RATE_LIMITED", message: "API rate limit exceeded" }] }));
  assert.equal(code, 1);
  assert.ok(!lines.some((line) => line.includes("arm refused")));
});

test("a GraphQL answer typed FORBIDDEN or INSUFFICIENT_SCOPES is not a refusal of that pull request, and the run fails", async () => {
  for (const type of ["FORBIDDEN", "INSUFFICIENT_SCOPES"]) {
    const { code, lines } = await served([pull(1), pull(2)], () => Response.json({ errors: [{ type, message: "Resource not accessible by integration" }] }));
    assert.equal(code, 1);
    assert.ok(!lines.some((line) => line.includes("arm refused")));
    assert.ok(lines.some((line) => line.startsWith("::error title=enable-auto-merge::#1 arm:")));
  }
});

test("a logged cause has any token in it scrubbed", async () => {
  const leak = new TypeError("fetch failed", { cause: Object.assign(new Error("bad header Bearer ghs_abc123 sent github_pat_11AB_cd"), { code: "UND_ERR_SOCKET" }) });
  const { lines } = await run([pull(1)], {}, { armErrors: { PR_1: [leak, leak, leak] } });
  assert.ok(lines.includes("::warning title=enable-auto-merge::#1 arm failed on the network after its resends, skipped this run: fetch failed (cause: UND_ERR_SOCKET bad header *** sent ***)"));
  assert.ok(!lines.some((line) => line.includes("ghs_abc123") || line.includes("github_pat_")));
});

test("a bad bot login or repository fails red", async () => {
  assert.equal((await run([pull(1)], { LANES_BOT_LOGIN: "kyle-sexton" })).code, 1);
  assert.equal((await run([pull(1)], { GITHUB_REPOSITORY: "nope" })).code, 1);
});

test("decide leaves a pull request with no labels read alone", () => {
  assert.deepEqual(decide(pull(1, { labels: null }), { bot: LANES.login, humanGated: "needs-human" }), {
    action: "none",
    reason: "its labels could not all be read",
  });
});

test("the body hold agrees with the gate's BODY_MERGE_HOLD_RE", () => {
  const bodies = [
    "Hold: a human merges this",
    "Closes #1\n\nHold: x",
    "Closes #1\r\n   HOLD: x",
    "Closes #1\rhold: x",
    "Closes #1\n\nthe hold: is not at the line start",
    "Closes #1\n\nDon't merge",
    "Closes #1\n\ndon’t  merge this",
    "Closes #1\n\nDo NOT\nmerge",
    "Closes #1\n\ndonut merge",
    "Closes #1\n\nwhat to do: merge it",
    "Closes #1\n\nnothing here",
    "",
  ];
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const python = spawnSync(
    "python3",
    ["-c", "import json,sys\nfrom babysit_merge_policy import BODY_MERGE_HOLD_RE as R\nprint(json.dumps([bool(R.search(b)) for b in json.load(sys.stdin)]))"],
    { cwd: scripts, input: JSON.stringify(bodies), encoding: "utf8" },
  );
  assert.equal(python.status, 0, python.stderr);
  const expected = JSON.parse(python.stdout);
  assert.deepEqual(
    bodies.map((body) => BODY_HOLD.test(body)),
    expected,
  );
  assert.ok(expected.includes(true) && expected.includes(false));
});

// The body the issue lane opens its pull request with (report-outcome.mjs
// decide), so a change to either side that stops a clean lane pull request
// from arming, or arms a held one, fails here.
test("report-outcome's own Closes and Refs pull request bodies arm, and its hold bodies do not", () => {
  const plan = (overrides) =>
    decideOutcome({
      outcome: { exit: "done", reason: "", title: "docs(work-items): fix a typo", summary: "Fixed it." },
      issueNumber: 77,
      issueLabels: ["agent-ready"],
      branch: "work-resolve-issue/issue-77-123-1",
      changedFiles: ["plugins/work-items/README.md"],
      holdPaths: [".github/**"],
      checks: { tip: HEAD, results: [] },
      ...overrides,
    });
  const verdict = (overrides) => {
    const opened = plan(overrides);
    assert.equal(opened.action, "open-pr");
    // Files outside the hold paths, so only the body decides.
    return decide(pull(1, { body: opened.body }), { bot: "melodic-automation-lanes", humanGated: "needs-human", holdPaths: [".github/**"] }, { ...detail(), files: [], verify: PASSED });
  };
  assert.deepEqual(verdict({}), { action: "arm", reason: "no hold" });
  assert.equal(verdict({ humanMerge: true }).action, "none");
  assert.equal(verdict({ changedFiles: [".github/workflows/x.yml"] }).action, "none");
  const refs = { outcome: { exit: "done", reason: "", title: "t", summary: "s", remaining: ["Part B"] } };
  assert.ok(plan(refs).body.startsWith("Refs: #77\n"));
  assert.deepEqual(verdict(refs), { action: "arm", reason: "no hold" });
});

// The gate's human veto (babysit_merge.human_veto_logins): each member's
// newest comment, review or inline comment with text decides, so a later
// comment lifts the hold; a non-member's, a bot's or an empty one counts for
// nothing. Native auto-merge skips that gate, so the arm rule applies it.
test("a member's newest comment saying not to merge holds, and a later one lifts it", async () => {
  const veto = said("kyle-sexton", "Please don't merge this yet.", "2026-10-23T10:00:00Z");
  const { code, writes } = await run([
    pull(1, { discussion: { comments: [veto] } }),
    pull(2, { discussion: { comments: [veto, said("kyle-sexton", "Go ahead.", "2026-10-23T11:00:00Z")] } }),
    pull(3, { discussion: { comments: [said("someone", "do not merge", "2026-10-23T10:00:00Z", "CONTRIBUTOR")] } }),
    pull(4, { discussion: { comments: [said("codex", "do not merge", "2026-10-23T10:00:00Z", "NONE", "Bot")] } }),
    pull(5, { discussion: { reviews: [{ ...veto, createdAt: undefined, submittedAt: veto.createdAt }] } }),
    pull(6, { discussion: { inline: [said("kyle-sexton", "do-not merge until the canary", "2026-10-23T10:00:00Z", "MEMBER")] } }),
    pull(7, { discussion: { comments: [veto, said("kyle-sexton", "", "2026-10-23T11:00:00Z")] } }),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(
    writes.map(({ id }) => id),
    ["PR_2", "PR_3", "PR_4"],
  );
});

test("an armed pull request a member now vetoes is disarmed", async () => {
  const { writes } = await run([
    pull(1, { autoMergeRequest: {}, discussion: { comments: [said("kyle-sexton", "do not merge", "2026-10-23T10:00:00Z")] } }),
  ]);
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_1" }]);
});

test("a pull request whose discussion cannot all be read is not armed", async () => {
  const cut = { totalCount: 101, nodes: [] };
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  assert.equal(decide(pull(1), options, { ...detail(), files: [], verify: PASSED }).action, "arm");
  const held = (pr) => decide(pull(1), options, { ...detail(), files: [], ...pr });
  assert.equal(held({ comments: cut }).action, "none");
  assert.equal(held({ reviews: cut }).action, "none");
  assert.equal(held({ reviewThreads: cut }).action, "none");
  assert.equal(held({ reviewThreads: page([{ comments: cut }]) }).action, "none");
  // A read that failed leaves it as it is, armed or not, until the next run.
  assert.equal(decide(pull(1), options, null).action, "none");
  assert.equal(decide(pull(1, { autoMergeRequest: {} }), options, null).action, "none");
});

test("auto-merge a person turned off stays off; one the lanes App turned off is armed again", async () => {
  const { writes } = await run([
    pull(1, { discussion: { disabledBy: { __typename: "User", login: "kyle-sexton" } } }),
    pull(2, { discussion: { disabledBy: { __typename: "Bot", login: "melodic-automation-lanes" } } }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_2", head: HEAD }]);
});

test("the comment veto agrees with the gate's HUMAN_MERGE_VETO_RE", () => {
  const bodies = ["do not merge", "Don't merge", "don’t merge", "dont-merge", "do-not merge", "Do NOT\nmerge", "donut merge", "merge it", "doesn't merge", ""];
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const python = spawnSync(
    "python3",
    ["-c", "import json,sys\nfrom babysit_merge import HUMAN_MERGE_VETO_RE as R\nprint(json.dumps([bool(R.search(b)) for b in json.load(sys.stdin)]))"],
    { cwd: scripts, input: JSON.stringify(bodies), encoding: "utf8" },
  );
  assert.equal(python.status, 0, python.stderr);
  const expected = JSON.parse(python.stdout);
  assert.deepEqual(
    bodies.map((body) => HUMAN_VETO.test(body)),
    expected,
  );
  assert.ok(expected.includes(true) && expected.includes(false));
});

// The merge lane's denied paths (report-outcome.readHoldPaths), on the head's
// files now: report-outcome's Hold: line covers only the files at opening, and
// a later push can add a held path to a pull request that is already armed.
test("a pull request whose head now changes a hold path is not armed, or is disarmed", async () => {
  const { writes } = await run([
    pull(1, { files: [{ filename: "docs/conventions/pr-pipeline.yaml" }] }),
    pull(2, {
      autoMergeRequest: {},
      files: [{ filename: "plugins/a/README.md" }, { filename: "docs/a.md", previous_filename: ".github/standards/trusted-actors/trusted-actors.json" }],
    }),
    pull(3, { files: Array.from({ length: 301 }, (_, index) => ({ filename: `docs/${index}.md` })) }),
    pull(4, { files: [{ filename: "docs/held.md" }] }),
    pull(5),
    // The rest of .github merges on the review lanes.
    pull(6, { files: [{ filename: ".github/workflows/x.yml" }, { filename: ".github/scripts/pr-merge/merge-holds.mjs" }] }),
  ]);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_2" },
    { mutation: "arm", id: "PR_5", head: HEAD },
    { mutation: "arm", id: "PR_6", head: HEAD },
  ]);
});

// A manifest is no hold path: the gate's reader scores it (`evidence
// --lane-reviews`, babysit_risk manifest-review-required), so a manifest
// change the gate reviews is not armed, or is disarmed, and one it does not,
// such as a plugin.json userConfig default (#9483), arms.
test("a manifest change arms only when the gate's risk score allows it", () => {
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  const files = ["docs/a.md", ".claude-plugin/marketplace.json", "plugins/a/.claude-plugin/plugin.json"];
  const review = { ...PASSED, reviews: "manifest-review-required: plugins/a/.claude-plugin/plugin.json: hooks" };
  assert.deepEqual(decide(pull(1), options, { ...detail(), files, verify: review }), {
    action: "none",
    reason: "pr-merge's gate holds it on its risk score (manifest-review-required: plugins/a/.claude-plugin/plugin.json: hooks)",
    clears: "lane",
  });
  assert.equal(decide(pull(1, { autoMergeRequest: {} }), options, { ...detail(), files, verify: review }).action, "disarm");
  assert.deepEqual(decide(pull(1), options, { ...detail(), files, verify: PASSED }), { action: "arm", reason: "no hold" });
});

// The gate holds a cost path (babysit_risk.COST_PATHS) until the body links
// the owner's cost decision (babysit_merge_policy.cost_decision).
test("a cost path holds until the body links the owner's cost decision", async () => {
  const options = { bot: LANES.login, humanGated: "needs-human", holdPaths: [] };
  const files = ["infra/Pulumi.prod.yaml"];
  assert.deepEqual(decide(pull(1), options, { ...detail(), files, verify: PASSED }), {
    action: "none",
    reason: "it changes infra/Pulumi.prod.yaml, a cost path",
    clears: "person",
  });
  assert.equal(decide(pull(1, { autoMergeRequest: {} }), options, { ...detail(), files, verify: PASSED }).action, "disarm");
  assert.equal(decide(pull(1), options, { ...detail(), files, costDecision: COST_LINK, verify: PASSED }).action, "arm");

  const dir = mkdtempSync(join(tmpdir(), "enable-auto-merge-"));
  writeFileSync(join(dir, "actors.json"), JSON.stringify({ actors: [{ kind: "human", login: "kyle-sexton", id: 5 }] }));
  const cost = [{ filename: "infra/main.tf" }];
  const decided = `Closes #1040\n\nCost decision: ${COST_LINK}`;
  const { writes } = await run(
    [pull(40, { files: cost, body: decided }), pull(41, { files: cost }), pull(42, { files: cost, body: decided })],
    { TRUSTED_ACTORS: join(dir, "actors.json") },
  );
  // Pull request 41 links no decision; 42 closes a different issue, so pull
  // request 40's decision does not cover it.
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_40", head: HEAD }]);
  // A changed file's name cannot start a workflow command on its own line.
  const { lines } = await run([pull(43, { files: [{ filename: "x\n::warning::forged/main.tf" }] })]);
  assert.ok(lines.some((line) => line.includes("x ::warning::forged/main.tf, a cost path")));
  assert.ok(!lines.some((line) => /(^|\n)::warning::/.test(line)));
  // Not on the trusted-actor list, the commenter decides nothing.
  assert.deepEqual((await run([pull(40, { files: cost, body: decided })], { TRUSTED_ACTORS: "/nonexistent/actors.json" })).writes, []);
});

// ci-status runs merge-holds.mjs on the live files with the base config's
// denied paths, by the same pathHold that decides arming above.
test("merge-holds.mjs holds a changed or renamed-from hold path from the command line", () => {
  const dir = mkdtempSync(join(tmpdir(), "merge-holds-"));
  const head = "0123456789abcdef0123456789abcdef01234567";
  const cli = (files, denied, reviews = []) => {
    writeFileSync(join(dir, "body"), "Closes #1");
    writeFileSync(join(dir, "discussion"), reviews.map((row) => JSON.stringify(row)).join("\n"));
    writeFileSync(join(dir, "actors"), JSON.stringify({ actors: [{ kind: "human", login: "ana", id: 5 }] }));
    writeFileSync(join(dir, "files"), files.map((row) => JSON.stringify(row)).join("\n"));
    writeFileSync(join(dir, "denied"), JSON.stringify(denied));
    const args = [...["7", "body", "discussion", "files", "denied", "actors"].map((name, index) => (index ? join(dir, name) : name)), head];
    return spawnSync(process.execPath, [fileURLToPath(new URL("./merge-holds.mjs", import.meta.url)), ...args], { encoding: "utf8" });
  };
  assert.equal(cli([["docs/a.md"]], ["docs/held.md"]).status, 0);
  // No trusted path or manifest holds unless the config lists it.
  assert.equal(cli([[".github/actions/resolve-config/.x.mjs"]], []).status, 0);
  assert.match(cli([[".github/actions/resolve-config/.x.mjs"]], [".github/actions/**"]).stdout, /it changes \.github\/actions\/resolve-config\/\.x\.mjs, a hold path/);
  assert.equal(cli([[".github/workflows/x.yml"]], []).status, 0);
  assert.equal(cli([{ filename: "plugins/a/.claude-plugin/plugin.json", status: "modified" }], []).status, 0);
  assert.match(cli([["plugins/a/.hidden"]], ["plugins/**"]).stdout, /it changes plugins\/a\/\.hidden, a hold path/);
  assert.equal(cli([["plugins/a/x.md"]], ["plugins/*.md"]).status, 0);
  assert.equal(cli([["docs/a.md", ".github/actions/check-trusted-trigger/a.md"]], []).status, 0);
  const renamed = cli([["docs/a.md", ".github/actions/check-trusted-trigger/a.md"]], [".github/actions/check-trusted-trigger/**"]);
  assert.equal(renamed.status, 1);
  assert.match(renamed.stdout, /it changes \.github\/actions\/check-trusted-trigger\/a\.md, a hold path/);
  assert.match(cli([["docs/held.md"]], ["docs/held.md"]).stdout, /it changes docs\/held\.md, a hold path/);
  assert.match(cli([["docs/a.md"]], "docs/held.md").stdout, /the hold paths could not be read/);
  const approve = (id, commit) => ({ user: { login: `u${id}`, id, type: "User" }, state: "APPROVED", commit_id: commit, submitted_at: "2026-10-23T11:00:00Z" });
  assert.equal(cli([["docs/held.md"]], ["docs/held.md"], [approve(5, head)]).status, 0);
  assert.equal(cli([["docs/held.md"]], ["docs/held.md"], [approve(6, head)]).status, 1);
  assert.equal(cli([["docs/held.md"]], ["docs/held.md"], [approve(5, "f".repeat(40))]).status, 1);
  assert.equal(cli([["docs/a.md"]], "docs/held.md", [approve(5, head)]).status, 1);
});

test("hold paths that cannot be read arm nothing and label nothing", async () => {
  const { writes, notes, lines } = await run([pull(1), pull(2, { autoMergeRequest: {} })], { RESOLVED_CONFIG: "/nonexistent/resolved-config.json" });
  assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_2" }]);
  assert.deepEqual(notes, []);
  assert.ok(lines.some((line) => line.startsWith("::warning title=enable-auto-merge::the resolved config's hold paths did not read")));
});

// More than 100 labels is read whole, not refused.
test("a label list the listing cut is read whole", async () => {
  const many = Array.from({ length: 150 }, (_, index) => `area-${index}`);
  const cut = (all) => ({ totalCount: all.length, nodes: all.slice(0, 100).map((name) => ({ name })) });
  const { writes } = await run([
    pull(1, { labels: cut(many), allLabels: many }),
    pull(2, { labels: cut([...many, "do-not-merge"]), allLabels: [...many, "do-not-merge"] }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
});

// More than 100 comments is read whole, so a veto past the first page
// still holds and none there arms.
test("a comment list the detail cut is read whole", async () => {
  const chatter = Array.from({ length: 3 }, (_, index) => said("kyle-sexton", `note ${index}`, `2026-10-23T0${index}:00:00Z`));
  const veto = said("kyle-sexton", "do not merge", "2026-10-23T09:00:00Z");
  const cut = (comments) => ({ ...detail({ comments }), comments: { totalCount: comments.length, nodes: comments.slice(-1) } });
  const { writes, lines } = await run([
    pull(1, { discussion: { comments: chatter }, cutDiscussion: cut(chatter) }),
    pull(2, { discussion: { comments: [veto, ...chatter] }, cutDiscussion: cut([veto, ...chatter]) }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.ok(lines.includes("enable-auto-merge: #2 left: kyle-sexton asked not to merge it"), lines.join("\n"));
});

// A review thread whose comments the detail cut is read whole by its id, so
// a veto in its first comments still holds.
test("a review thread's comment list the detail cut is read whole, page by page", async () => {
  const chatter = Array.from({ length: 3 }, (_, index) => said("kyle-sexton", `note ${index}`, `2026-10-23T0${index}:00:00Z`));
  // Another member's only comment, the oldest, so only a whole read sees it.
  const veto = said("other-member", "do not merge", "2026-10-22T09:00:00Z", "MEMBER");
  const cut = (id, comments) => ({ ...detail(), reviewThreads: page([{ id, comments: { totalCount: comments.length, nodes: comments.slice(-1) } }]) });
  const { writes, lines, calls } = await run([
    pull(1, { cutDiscussion: cut("T1", chatter), threads: { T1: chatter } }),
    pull(2, { cutDiscussion: cut("T2", [veto, ...chatter]), threads: { T2: [veto, ...chatter] } }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.ok(lines.includes("enable-auto-merge: #2 left: other-member asked not to merge it"), lines.join("\n"));
  const pages = calls.filter(({ body }) => body?.query === THREAD_PAGE_QUERY).map(({ body }) => body.variables);
  assert.deepEqual(pages, [
    { id: "T1", after: null },
    { id: "T1", after: "2" },
    { id: "T2", after: null },
    { id: "T2", after: "2" },
  ]);
});

// A list longer than the read caps (30 discussion pages, 10 label pages, by
// enable-auto-merge.mjs's MAX_DISCUSSION_PAGES and MAX_LABEL_PAGES) stops the
// read, and a pull request it stopped on is not armed.
test("a discussion or label list past its page cap arms nothing", async () => {
  const comments = (count) => Array.from({ length: count }, (_, index) => said("kyle-sexton", `note ${index}`, "2026-10-23T01:00:00Z"));
  const cutOf = (all) => ({ ...detail({ comments: all }), comments: { totalCount: all.length, nodes: all.slice(-1) } });
  const names = (count) => Array.from({ length: count }, (_, index) => `area-${index}`);
  const cutLabels = (all) => ({ totalCount: all.length, nodes: all.slice(0, 100).map((name) => ({ name })) });
  const { writes, lines } = await run([
    // 60 comments are 30 pages of two; 62 need a 31st.
    pull(1, { discussion: { comments: comments(60) }, cutDiscussion: cutOf(comments(60)) }),
    pull(2, { discussion: { comments: comments(62) }, cutDiscussion: cutOf(comments(62)) }),
    // 999 labels end on a short 10th page; 1000 fill it, so an 11th is unread.
    pull(3, { labels: cutLabels(names(999)), allLabels: names(999) }),
    pull(4, { labels: cutLabels(names(1000)), allLabels: names(1000) }),
  ]);
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "arm", id: "PR_3", head: HEAD },
  ]);
  assert.ok(lines.some((line) => line.startsWith("enable-auto-merge: #2 discussion did not read: ") && line.includes("a discussion list longer than 3000")), lines.join("\n"));
  assert.ok(lines.some((line) => line.startsWith("enable-auto-merge: #4 labels did not read whole: ") && line.includes("more than 1000 labels")), lines.join("\n"));
});

// A deleted account reads as a null author or editor, which counts as a
// person (merge-holds.personWrote), so a hold it wrote still holds.
test("a deleted author or editor counts as a person who wrote the body", () => {
  const edits = (...editors) => ({ totalCount: editors.length, nodes: editors.map((editor) => ({ editor })) });
  const bot = { __typename: "Bot" };
  assert.equal(personWrote({ author: bot, userContentEdits: edits() }), false);
  assert.equal(personWrote({ author: bot, userContentEdits: edits(bot) }), false);
  assert.equal(personWrote({ author: null, userContentEdits: edits() }), true);
  assert.equal(personWrote({ author: bot, userContentEdits: edits(null) }), true);
  assert.equal(personWrote(null), true);
});

// The lanes App's own body text holds nothing; a person's edit does.
test("a body hold counts only when a person wrote some of the body", async () => {
  const body = "Closes #5\n\nHold: wait for the release.";
  const edits = (...typenames) => ({ totalCount: typenames.length, nodes: typenames.map((__typename) => ({ editor: { __typename } })) });
  const { writes } = await run([
    pull(1, { body, userContentEdits: edits() }),
    pull(2, { body, userContentEdits: edits("Bot") }),
    pull(3, { body, userContentEdits: edits("Bot", "User") }),
    pull(4, { body, userContentEdits: { totalCount: 101, nodes: [] } }),
    pull(5, { body }),
  ]);
  assert.deepEqual(writes, [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "arm", id: "PR_2", head: HEAD },
  ]);
});

// report-outcome's own hold line (untrusted-provenance work, a person's
// `merge: human`, a denied path) holds whoever wrote the body.
test("the lane's own hold line holds a lanes App body", async () => {
  assert.equal(`\n${HOLD_LINE}\n`.match(LANE_HOLD)?.[0].trim(), HOLD_LINE);
  const appOnly = { totalCount: 0, nodes: [] };
  const { writes } = await run([
    pull(1, { body: `Closes #5\n\n${HOLD_LINE}`, userContentEdits: appOnly }),
    pull(2, { body: `Closes #5\n\n${HOLD_LINE}\n\n## Summary`, userContentEdits: appOnly }),
    pull(3, { body: `Closes #5\n\nquoted: ${HOLD_LINE}`, userContentEdits: appOnly }),
  ]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_3", head: HEAD }]);
});

// The start moves with the run number, so the pull requests past the
// verify budget differ from run to run.
test("the run starts at an offset that moves with the run number", async () => {
  assert.deepEqual(rotated([1, 2, 3], 0), [1, 2, 3]);
  assert.deepEqual(rotated([1, 2, 3], 4), [2, 3, 1]);
  assert.deepEqual(rotated([1, 2, 3], 5), [3, 1, 2]);
  assert.deepEqual(rotated([1, 2, 3], Number.NaN), [1, 2, 3]);
  assert.deepEqual(rotated([], 7), []);
  const { verified } = await run([pull(1), pull(2), pull(3)], { GITHUB_RUN_NUMBER: "4" });
  assert.deepEqual(verified, [2, 3, 1]);
});

// pr-merge's gate merges only on a pr-verify pass at the head, FAILs at fewer
// than merge.max-verify-fails heads (babysit_verify_evidence.py), and native
// auto-merge must not merge what the gate would refuse.
test("no pass at the head, a FAIL or the repeated-FAIL cap arms nothing", async () => {
  const { code, writes, verified } = await run([
    pull(1, { verdict: { refusal: "verify:missing", head: HEAD } }),
    pull(2, { verdict: { refusal: "verify:fail", head: HEAD } }),
    pull(3, { verdict: { refusal: "verify:repeated-fail", head: HEAD, needsHuman: true } }),
    pull(4, { verdict: { refusal: "verify:earlier-fail", head: HEAD } }),
    pull(5, { verdict: { refusal: null, head: "c".repeat(40) } }),
    pull(6, { verdict: new Error("gh: rate limited") }),
    pull(7, { verdict: { refusal: "verify:unreadable", head: HEAD } }),
    pull(8),
  ]);
  assert.equal(code, 0);
  assert.deepEqual(verified, [1, 2, 3, 4, 5, 6, 7, 8]);
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_8", head: HEAD }]);
});

test("an armed pull request whose head lost its pass, or passed the cap, is disarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { writes, lines } = await run([
    // Armed on a passing head, then pushed: the gate finds no verdict at the new head.
    pull(1, { autoMergeRequest: armed, verdict: { refusal: "verify:missing", head: HEAD } }),
    pull(2, { autoMergeRequest: armed, verdict: { refusal: "verify:repeated-fail", head: HEAD } }),
    pull(3, { autoMergeRequest: armed, verdict: new Error("listing failed") }),
    pull(4, { autoMergeRequest: armed }),
  ]);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_1" },
    { mutation: "disarm", id: "PR_2" },
    { mutation: "disarm", id: "PR_3" },
  ]);
  assert.ok(lines.some((line) => /#2 disarmed: pr-merge's gate refuses its verifier verdict \(verify:repeated-fail\)/.test(line)));
});

test("the verdict is read only for a lanes App pull request nothing else holds", async () => {
  const { writes, verified } = await run([
    pull(1, { author: { __typename: "User", login: "kyle-sexton" } }),
    pull(2, { labels: labels("do-not-merge") }),
    pull(3, { isDraft: true }),
    pull(4, { discussion: { comments: [said("kyle-sexton", "do not merge", "2026-10-23T10:00:00Z")] } }),
    pull(5, { discussion: { disabledBy: { __typename: "User", login: "kyle-sexton" } } }),
  ]);
  assert.deepEqual(writes, []);
  assert.deepEqual(verified, []);
});

test("verifyHold allows only the reader's null refusal at the head read", () => {
  assert.equal(verifyHold(PASSED, HEAD), null);
  assert.match(verifyHold({ refusal: null, head: "c".repeat(40) }, HEAD), /another head/);
  assert.match(verifyHold(null, HEAD), /could not be read/);
  assert.match(verifyHold({ head: HEAD }, HEAD), /could not be read/);
  assert.match(verifyHold({ refusal: "verify:too-old", head: HEAD, ineligible: null }, HEAD), /verify:too-old/);
  // The link's answer: a refusal names it, and a line without one allows nothing.
  assert.match(verifyHold({ refusal: "verify:ineligible", head: HEAD, ineligible: "refs-issues:2" }, HEAD), /does not take its issue link \(refs-issues:2\)/);
  assert.match(verifyHold({ refusal: null, head: HEAD }, HEAD), /issue link could not be read/);
  assert.match(verifyHold({ refusal: null, head: HEAD, ineligible: false }, HEAD), /issue link could not be read/);
  // The review lanes' answer: a hold names it, and a line without one allows nothing.
  assert.match(verifyHold({ refusal: null, head: HEAD, ineligible: null, reviews: "security-finding: 1 open" }, HEAD), /holds it on its risk score \(security-finding: 1 open\)/);
  assert.match(verifyHold({ refusal: null, head: HEAD, ineligible: null }, HEAD), /risk score could not be read/);
});

// The merge queue's check (merge-holds.mjs verdictHold): a pass counts only
// from pr-verify.yml's completed, successful workflow_run run on main here.
test("verdictHold counts a pass only from a successful pr-verify run on main", () => {
  const run = (overrides = {}) => ({
    id: 11,
    path: VERIFY_PATH,
    event: "workflow_run",
    head_branch: "main",
    status: "completed",
    conclusion: "success",
    repository: { full_name: REPO },
    head_repository: { full_name: REPO },
    ...overrides,
  });
  const hold = (records) => verdictHold(Array.isArray(records) ? records.map((record) => ({ runId: 11, ...record })) : records, REPO);
  assert.equal(hold([{ verdict: "pass", run: run() }]), null);
  assert.equal(hold([{ verdict: "pass-notes", run: run() }]), null);
  assert.equal(hold([{ verdict: "pass", run: run({ conclusion: "failure" }) }, { verdict: "pass-notes", run: run() }]), null);
  for (const bad of [
    { path: ".github/workflows/other.yml" },
    { event: "pull_request" },
    { head_branch: "feature" },
    { status: "in_progress", conclusion: null },
    { conclusion: "failure" },
    { repository: { full_name: "fork/claude-code-plugins" } },
    { head_repository: { full_name: "fork/claude-code-plugins" } },
  ]) {
    assert.match(hold([{ verdict: "pass", run: run(bad) }]), /has not passed this head/, JSON.stringify(bad));
  }
  assert.match(hold([{ verdict: "fail", run: run() }]), /has not passed this head/);
  // A record of another run than the one its artifact names counts nothing.
  assert.match(hold([{ verdict: "pass", runId: 12, run: run() }]), /has not passed this head/);
  assert.match(hold([{ verdict: "pass", runId: "11", run: run() }]), /has not passed this head/);
  assert.match(hold([]), /has not passed this head/);
  assert.match(hold(null), /could not be read/);
  assert.match(verdictHold([], "not a repo"), /could not be read/);
});

// test_verify_rules_sync.py ties the resolver's path to the gate's WORKFLOW_PATH.
test("verdictHold names the verifier workflow the resolver and the gate name", () => {
  assert.equal(VERIFY_PATH, RESOLVER_VERIFY_PATH);
});

// Only the gate's full reader arms, so native merge refuses what the gate
// refuses; an event run disarms on a hold and reads no verdict.
test("only the scheduled run and a hand-started one read the verdict and arm", () => {
  assert.deepEqual([...READER_EVENTS], ["schedule", "workflow_dispatch"]);
});

test("an event run arms nothing and reads neither discussion nor verdict for an unarmed pull request", async () => {
  for (const event of ["workflow_run", "pull_request_target"]) {
    const { code, writes, verified, lines } = await run([pull(1)], { EVENT_NAME: event });
    assert.equal(code, 0);
    assert.deepEqual(writes, []);
    assert.deepEqual(verified, []);
    assert.ok(lines.some((line) => /#1 left: only a scheduled or hand-started run arms it/.test(line)), event);
  }
});

test("an event run still disarms an armed pull request that now holds", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { writes, verified } = await run(
    [
      pull(1, { autoMergeRequest: armed, labels: labels("do-not-merge") }),
      pull(2, { autoMergeRequest: armed, discussion: { comments: [said("kyle-sexton", "do not merge", "2026-10-23T10:00:00Z")] } }),
      pull(3, { autoMergeRequest: armed }),
    ],
    { EVENT_NAME: "pull_request_target" },
  );
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_1" },
    { mutation: "disarm", id: "PR_2" },
  ]);
  assert.deepEqual(verified, []);
});

test("a reader that fails, prints no JSON or reports another head arms nothing and disarms", async () => {
  const dir = mkdtempSync(join(tmpdir(), "enable-auto-merge-"));
  const scripts = {
    exits: "import sys\nsys.stderr.write('boom\\n')\nsys.exit(1)\n",
    garbage: "print('not json')\n",
    other: `import json\nprint(json.dumps({"refusal": None, "head": "${"c".repeat(40)}"}))\n`,
    unlinked: `import json, sys\nprint(json.dumps({"refusal": None, "head": sys.argv[-1]}))\n`,
    passes: `import json, sys\nassert sys.argv[2:4] == ["--lane-link", "--lane-reviews"] and sys.argv[-6:-2] == ["--base-sha", "${"d".repeat(40)}", "--rung", "C2"], sys.argv\nprint(json.dumps({"refusal": None, "head": sys.argv[-1], "ineligible": None, "reviews": None}))\n`,
  };
  for (const [name, body] of Object.entries(scripts)) {
    writeFileSync(join(dir, `${name}.py`), body);
  }
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  for (const [name, want] of [
    ["exits", [{ mutation: "disarm", id: "PR_2" }]],
    ["garbage", [{ mutation: "disarm", id: "PR_2" }]],
    ["other", [{ mutation: "disarm", id: "PR_2" }]],
    ["unlinked", [{ mutation: "disarm", id: "PR_2" }]],
    ["passes", [{ mutation: "arm", id: "PR_1", head: HEAD }]],
  ]) {
    const { github, writes } = world([pull(1), pull(2, { autoMergeRequest: armed })]);
    const env = { ...ENV, EVENT_NAME: "schedule", PATH: process.env.PATH, VERIFY_EVIDENCE_SCRIPT: join(dir, `${name}.py`) };
    const log = console.log;
    console.log = () => {};
    try {
      await main({ env, github, room: room() });
    } finally {
      console.log = log;
    }
    assert.deepEqual(writes(), want, name);
  }
});

// The issue link through the gate's own CLI (`evidence --lane-link`) and rule
// (babysit_merge_policy._linked_issue), GitHub's answers stubbed at gh and the
// verdict a pass at the head, so only the link decides. Expected values are
// docs/conventions/pr-pipeline/README.md "Eligibility": one closing issue, or
// one plain `Refs: #<n>` issue; two `Refs:` issues refuse; a failed read refuses.
test("the gate's link rule arms a Closes or one plain Refs pull request, not two Refs or a failed read", async () => {
  const dir = mkdtempSync(join(tmpdir(), "enable-auto-merge-link-"));
  const wrapper = join(dir, "lane_link.py");
  writeFileSync(
    wrapper,
    `import json, os, subprocess, sys
sys.path.insert(0, os.environ["SCRIPTS"])
from unittest import mock
import babysit_merge_policy as policy
import babysit_postmerge as postmerge
import babysit_verify_evidence as ve

PULLS = json.loads(os.environ["PULLS"])

def gh(args, **_):
    n = next(a for a in args if a.startswith("n="))[2:]
    def ok(data):
        return subprocess.CompletedProcess(args, 0, json.dumps({"data": {"repository": data}}), "")
    if any("issueOrPullRequest" in a for a in args):
        node = {"__typename": "Issue", "number": int(n), "repository": {"nameWithOwner": os.environ["GITHUB_REPOSITORY"]}}
        return ok({"issueOrPullRequest": node})
    found = PULLS[n]
    if found.get("error"):
        return subprocess.CompletedProcess(args, 1, "", "gh: boom (HTTP 502)")
    nodes = [{"number": c, "repository": {"nameWithOwner": os.environ["GITHUB_REPOSITORY"]}} for c in found["closing"]]
    return ok({"pullRequest": {"body": found["body"], "closingIssuesReferences": {"totalCount": len(nodes), "nodes": nodes}}})

def passes(self, number, head, pr=None):
    return ve.Evidence(None, head, (ve.Verdict(head, "pass", 1),), 0)

argv = sys.argv[1:]
pr = lambda repo, number: {"number": number, "head": {"sha": argv[-1]}}
with mock.patch.object(policy, "gh_capture", gh), mock.patch.object(postmerge, "gh_capture", gh), mock.patch.object(ve.Reader, "evidence", passes), mock.patch.object(policy, "pull_request", pr), mock.patch.object(ve, "lane_risk_refusal", lambda *args: None), mock.patch.object(policy, "read_config_at", lambda repo, sha: policy.PipelineConfig(sha, "C2", "pr-merge", "agent[bot]", None, (), "c2-mechanical")), mock.patch.object(policy, "with_default_branch", lambda repo, base, *rest: base):
    sys.exit(ve.main(argv))
`,
  );
  const body = (text) => `${text}\n\n## Summary\n\nDone.`;
  const pulls = {
    1: { body: body("Closes #11"), closing: [11] },
    2: { body: body("Refs: #12"), closing: [] },
    3: { body: body("Refs: #12\nRefs: #13"), closing: [] },
    4: { body: body("Refs: #12"), closing: [], error: true },
    5: { body: body("Refs: #12\nRefs: #13"), closing: [] },
  };
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { github, writes } = world([1, 2, 3, 4].map((n) => pull(n, { body: pulls[n].body })).concat(pull(5, { body: pulls[5].body, autoMergeRequest: armed })));
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const env = { ...ENV, PATH: process.env.PATH, SCRIPTS: scripts, PULLS: JSON.stringify(pulls), VERIFY_EVIDENCE_SCRIPT: wrapper };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    assert.equal(await main({ env, github, room: room() }), 0);
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "arm", id: "PR_2", head: HEAD },
    { mutation: "disarm", id: "PR_5" },
  ]);
  assert.ok(lines.some((line) => /#3 left: pr-merge's lane does not take its issue link \(refs-issues:2\)/.test(line)), lines.join("\n"));
  assert.ok(lines.some((line) => /#4 left: pr-merge's lane does not take its issue link \(unreadable: /.test(line)), lines.join("\n"));
});

// An event run reads no link and no verdict, so it never disarms an armed
// Refs pull request on its link; the scheduled run judges it.
test("an event run leaves an armed Refs pull request armed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { writes, verified } = await run([pull(1, { autoMergeRequest: armed, body: "Refs: #12\n\n## Summary" })], { EVENT_NAME: "pull_request_target" });
  assert.deepEqual(writes, []);
  assert.deepEqual(verified, []);
});

// The gate's run-level refusals, which native auto-merge would skip
// (babysit_merge_policy.lane_room): a demotion record or a rung held off
// stops the lane, and merge.max-in-flight caps what is in flight.
test("while the gate holds its lane off, nothing is armed and armed lane pull requests are disarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  for (const refusal of ["rung-off:demotion", "rung-off:rungCap", "post-merge:failure:red-main#40"]) {
    const { writes, verified, lines } = await run(
      [pull(1), pull(2, { autoMergeRequest: armed }), pull(3, { author: { __typename: "User", login: "kyle-sexton" }, autoMergeRequest: armed })],
      {},
      {},
      { ...ROOM, refusal },
    );
    assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_2" }], refusal);
    // A held lane reads no verdict.
    assert.deepEqual(verified, [], refusal);
    assert.ok(lines.some((line) => line.includes(`#1 left: pr-merge's gate holds its lane off (${refusal})`)), refusal);
  }
});

test("at merge.max-in-flight nothing more is armed, counting armed pull requests the queue has not taken", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  // Four in flight by the gate's count, one armed and not queued: the cap of five is reached.
  let result = await run([pull(1), pull(2, { autoMergeRequest: armed })], {}, {}, { ...ROOM, count: 4, cap: 5 });
  assert.deepEqual(result.writes, []);
  assert.deepEqual(result.verified, [2]);
  assert.ok(result.lines.some((line) => /#1 left: merge\.max-in-flight is 5 and 5 merges are in flight/.test(line)));
  // An armed pull request already in the queue is in the gate's count, not counted twice.
  result = await run([pull(1), pull(2, { autoMergeRequest: armed })], {}, {}, { ...ROOM, count: 4, cap: 5, queued: [2] });
  assert.deepEqual(result.writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  // Each arm in the run counts: three in flight of five arms two of three.
  result = await run([pull(1), pull(2), pull(3)], {}, {}, { ...ROOM, count: 3, cap: 5 });
  assert.deepEqual(
    result.writes.map(({ id }) => id),
    ["PR_1", "PR_2"],
  );
});

// Unknown holds: a room that cannot be read (no post-merge report, a failed
// read) holds as the gate's refusal does, so an armed lane pull request is
// disarmed rather than left to merge while the gate refuses.
test("a room that cannot be read arms nothing and disarms every armed lane pull request", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const pulls = [pull(1), pull(2, { autoMergeRequest: armed }), pull(3, { author: { __typename: "User", login: "kyle-sexton" }, autoMergeRequest: armed })];
  for (const lane of [{ ...ROOM, unreadable: "post-merge answer missing or unreadable" }, { refusal: null }, null]) {
    const { writes, verified, lines } = await run(pulls, {}, {}, lane);
    assert.deepEqual(writes, [{ mutation: "disarm", id: "PR_2" }], JSON.stringify(lane));
    assert.deepEqual(verified, [], JSON.stringify(lane));
    assert.ok(lines.some((line) => line.includes("#2 disarmed: the lane's room could not be read")), JSON.stringify(lane));
  }
  const { github, writes } = world(pulls);
  const log = console.log;
  console.log = () => {};
  try {
    await main({
      env: ENV,
      github,
      verify: async ({ headRefOid: head }) => ({ refusal: null, head, ineligible: null, reviews: null }),
      room: async () => {
        throw new Error("lane-room exited 1");
      },
    });
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), [{ mutation: "disarm", id: "PR_2" }]);
});

// A held room that logs only to the console leaves nothing on the run
// saying why nothing armed. One annotation and one summary
// line per run, naming the reason and every lane pull request left unarmed.
test("a held room raises one warning and one step-summary line naming why and each pull request left unarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const pulls = [pull(1), pull(2, { autoMergeRequest: armed }), pull(3, { author: { __typename: "User", login: "kyle-sexton" } }), pull(4, { isDraft: true })];
  const cases = [
    [{ ...ROOM, unreadable: "post-merge answer unverified-stale" }, "the lane's room could not be read (post-merge answer unverified-stale); left unarmed: #1, #2"],
    [{ ...ROOM, refusal: "rung-off:demotion" }, "pr-merge's gate holds its lane off (rung-off:demotion); left unarmed: #1, #2"],
  ];
  for (const [lane, expected] of cases) {
    const summary = join(mkdtempSync(join(tmpdir(), "enable-auto-merge-summary-")), "summary.md");
    writeFileSync(summary, "");
    const { lines } = await run(pulls, { GITHUB_STEP_SUMMARY: summary }, {}, lane);
    assert.deepEqual(
      lines.filter((line) => line.startsWith("::warning")),
      [`::warning title=enable-auto-merge::${expected}`],
    );
    assert.equal(readFileSync(summary, "utf8"), `enable-auto-merge: ${expected}\n`);
  }
  // A lane with room raises neither.
  const summary = join(mkdtempSync(join(tmpdir(), "enable-auto-merge-summary-")), "summary.md");
  writeFileSync(summary, "");
  const { lines, writes } = await run(pulls, { GITHUB_STEP_SUMMARY: summary });
  assert.deepEqual(writes, [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.deepEqual(
    lines.filter((line) => line.startsWith("::warning")),
    [],
  );
  assert.equal(readFileSync(summary, "utf8"), "");
});

// A pull request whose disarm failed, or that report-only left armed, is
// still armed: naming it "left unarmed" would say the hold was enforced when
// it was not.
test("a held room names a pull request whose disarm failed as still armed, at error level", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const summary = join(mkdtempSync(join(tmpdir(), "enable-auto-merge-summary-")), "summary.md");
  writeFileSync(summary, "");
  const lane = { ...ROOM, refusal: "rung-off:demotion" };
  const { lines, code } = await run([pull(1), pull(2, { autoMergeRequest: armed })], { GITHUB_STEP_SUMMARY: summary }, { disarmError: new Error("POST /graphql failed with status 502") }, lane);
  assert.equal(code, 1);
  const why = "pr-merge's gate holds its lane off (rung-off:demotion)";
  assert.deepEqual(
    lines.filter((line) => /^::(warning|error) title=enable-auto-merge::pr-merge/.test(line)),
    [`::warning title=enable-auto-merge::${why}; left unarmed: #1`, `::error title=enable-auto-merge::${why}; still armed, its disarm failed, so the hold is not enforced: #2`],
  );
  assert.equal(readFileSync(summary, "utf8"), `enable-auto-merge: ${why}; left unarmed: #1\nenable-auto-merge: ${why}; still armed, its disarm failed, so the hold is not enforced: #2\n`);
});

test("a held room in report-only names the armed pull request a disarm would have turned off, not as unarmed", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const summary = join(mkdtempSync(join(tmpdir(), "enable-auto-merge-summary-")), "summary.md");
  writeFileSync(summary, "");
  const lane = { ...ROOM, unreadable: "post-merge answer missing or unreadable" };
  const { lines, writes } = await run([pull(1), pull(2, { autoMergeRequest: armed })], { GITHUB_STEP_SUMMARY: summary, REPORT_ONLY: "true" }, {}, lane);
  assert.deepEqual(writes, []);
  const expected = "the lane's room could not be read (post-merge answer missing or unreadable); left unarmed: #1; report-only, a disarm would have run: #2";
  assert.deepEqual(
    lines.filter((line) => line.startsWith("::warning") || line.startsWith("::error")),
    [`::warning title=enable-auto-merge::${expected}`],
  );
  assert.equal(readFileSync(summary, "utf8"), `enable-auto-merge: ${expected}\n`);
});

// An event run reads no room, so it never disarms on one.
test("an event run leaves an armed lane pull request armed whatever the room", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const { writes } = await run([pull(2, { autoMergeRequest: armed })], { EVENT_NAME: "pull_request_target" }, {}, null);
  assert.deepEqual(writes, []);
});

test("an event run reads no room", async () => {
  let asked = 0;
  const { github } = world([pull(1)]);
  const log = console.log;
  console.log = () => {};
  try {
    await main({
      env: { ...ENV, EVENT_NAME: "pull_request_target" },
      github,
      room: async () => {
        asked += 1;
        return ROOM;
      },
    });
  } finally {
    console.log = log;
  }
  assert.equal(asked, 0);
});

test("readRoom takes only lane-room's shape", () => {
  assert.deepEqual(readRoom(ROOM), ROOM);
  for (const bad of [null, "x", { ...ROOM, cap: 0 }, { ...ROOM, count: -1 }, { ...ROOM, queued: ["3"] }, { ...ROOM, refusal: 1 }, { ...ROOM, unreadable: undefined }]) {
    assert.ok(readRoom(bad).unreadable, JSON.stringify(bad));
  }
});

test("pythonRoom passes the post-merge report, the rung cap as read, and the reader's token", async () => {
  const dir = mkdtempSync(join(tmpdir(), "enable-auto-merge-room-"));
  const script = join(dir, "room.py");
  writeFileSync(
    script,
    `import json, os, sys
print(json.dumps({"argv": sys.argv[1:], "token": os.environ.get("GH_TOKEN"), "budget": os.environ.get("API_BUDGET_TOKEN")}))
`,
  );
  const env = { PATH: process.env.PATH, GITHUB_REPOSITORY: REPO, VERIFY_EVIDENCE_SCRIPT: script, POSTMERGE_RESULT: "/tmp/post-merge.json", GH_TOKEN: "lane", BABYSIT_VERIFY_GH_TOKEN: "job" };
  // An empty cap is no cap, so it is passed; an unset one is not, which the gate reads as off.
  assert.deepEqual(await pythonRoom({ ...env, RUNG_CAP: "" })(), {
    argv: ["lane-room", "--repo", REPO, "--postmerge-result", "/tmp/post-merge.json", "--rung-cap", ""],
    token: "job",
    budget: "github-token",
  });
  assert.deepEqual((await pythonRoom(env)()).argv, ["lane-room", "--repo", REPO, "--postmerge-result", "/tmp/post-merge.json"]);
});

// The calls line as babysit_gh.py itself prints it, for three Actions-token
// reads (the paginated artifact listing and two run records) and one
// lane-token GraphQL read: 4 in all, 3 under GITHUB_TOKEN, 1 paginated.
const BABYSIT_SCRIPTS = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
function producedCallsLine() {
  const done = spawnSync(
    "python3",
    [
      "-c",
      `import sys
sys.path.insert(0, sys.argv[1])
import babysit_gh as g
job = {"GH_TOKEN": "job"}
for args, env in (
    (["api", "repos/o/r/actions/artifacts?per_page=100", "--paginate", "--slurp"], job),
    (["api", "repos/o/r/actions/runs/1"], job),
    (["api", "repos/o/r/actions/runs/2"], job),
    (["api", "graphql", "-f", "query=q"], None),
):
    kind = g.gh_call_kind(args, env)
    g._gh_call_counts[kind] = g._gh_call_counts.get(kind, 0) + 1
print(g.gh_call_summary())
g.reset_gh_call_counts()`,
      BABYSIT_SCRIPTS,
    ],
    { encoding: "utf8" },
  );
  assert.equal(done.status, 0, done.stderr);
  return done.stdout.trim();
}

test("ghCalls reads babysit_gh.py's calls line: in all, under GITHUB_TOKEN, and paginated", () => {
  const line = producedCallsLine();
  assert.deepEqual(ghCalls(`warning: something\n${line}\n`), { total: 4, githubToken: 3, paginated: 1 });
  assert.equal(ghCalls("no calls line\n"), null);
  assert.equal(ghCalls("babysit-gh-calls {not json\n"), null);
  assert.equal(costLine({ number: 7, calls: { total: 4, githubToken: 3, paginated: 1 }, ms: 1500 }), "#7 calls=4 github-token=3 paginated=1 ms=1500");
  assert.equal(costLine({ number: 7, calls: null, ms: 20 }), "#7 calls=unknown ms=20");
});

test("pythonVerify logs each read's calls and time, keeps them, and names the error line, not the calls line, on a failure", async () => {
  const line = producedCallsLine();
  const answers = [
    { status: 0, stdout: `${JSON.stringify(PASSED)}\n`, stderr: `${line}\n` },
    { status: 1, stdout: "", stderr: `Traceback\nRuntimeError: listing 502\n${line}\n` },
  ];
  const spawn = () => answers.shift();
  let at = 1000;
  const clock = () => (at += 250);
  const verify = pythonVerify({ GITHUB_REPOSITORY: REPO }, { spawn, clock });
  const lines = [];
  const log = console.log;
  console.log = (text) => lines.push(text);
  try {
    assert.deepEqual(await verify(pull(1)), PASSED);
    await assert.rejects(verify(pull(2)), /exited 1: RuntimeError: listing 502$/);
  } finally {
    console.log = log;
  }
  assert.deepEqual(lines, ["enable-auto-merge: #1 calls=4 github-token=3 paginated=1 ms=250", "enable-auto-merge: #2 calls=4 github-token=3 paginated=1 ms=250"]);
  assert.deepEqual(
    verify.costs.map(({ number, ms }) => [number, ms]),
    [
      [1, 250],
      [2, 250],
    ],
  );
});

test("the step summary carries each verifier read's cost even when the run raised nothing", async () => {
  const summary = join(mkdtempSync(join(tmpdir(), "enable-auto-merge-summary-")), "summary.md");
  writeFileSync(summary, "");
  const { github, writes } = world([pull(1)]);
  const verify = async ({ headRefOid: head }) => ({ ...PASSED, head });
  verify.costs = [{ number: 1, calls: { total: 9, githubToken: 7, paginated: 1 }, ms: 46800 }];
  const log = console.log;
  console.log = () => {};
  try {
    assert.equal(await main({ env: { ...ENV, GITHUB_STEP_SUMMARY: summary }, github, verify, room: room(), sleep: async () => {} }), 0);
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), [{ mutation: "arm", id: "PR_1", head: HEAD }]);
  assert.equal(readFileSync(summary, "utf8"), "enable-auto-merge: #1 calls=9 github-token=7 paginated=1 ms=46800\n");
});

test("pythonRoom gives the lane-room read its own 8 minute timeout and reads a kill as unreadable", async () => {
  const seen = [];
  const killed = (_cmd, _args, options) => {
    seen.push(options.timeout);
    return { status: null, signal: "SIGTERM", stdout: "", stderr: "" };
  };
  await assert.rejects(pythonRoom({ GITHUB_REPOSITORY: REPO }, killed)(), /lane-room exited SIGTERM/);
  assert.deepEqual(seen, [8 * 60_000]);
  assert.equal(LANE_ROOM_TIMEOUT_MS, 8 * 60_000);
  assert.equal(VERIFY_TIMEOUT_MS, 4 * 60_000);
});

// The gate holds on the security lane's open CRITICAL findings
// (babysit_risk LANES, security-finding) and on a review not bound to the
// head, whether or not the lane applied its hold label.
test("a review-lane hold the gate reads arms nothing and disarms an armed pull request", async () => {
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const held = { refusal: null, head: HEAD, ineligible: null, reviews: "security-finding: 1 open" };
  const { writes, lines } = await run([
    pull(1, { verdict: held }),
    pull(2, { autoMergeRequest: armed, verdict: { ...held, reviews: "evidence-unbound:claude-security-review: marker-missing" } }),
    pull(3, { verdict: { refusal: null, head: HEAD, ineligible: null } }),
    pull(4),
  ]);
  assert.deepEqual(writes, [
    { mutation: "disarm", id: "PR_2" },
    { mutation: "arm", id: "PR_4", head: HEAD },
  ]);
  assert.ok(lines.some((line) => line.includes("#1 left: pr-merge's gate holds it on its risk score (security-finding: 1 open)")));
  assert.ok(lines.some((line) => line.includes("#3 left: its risk score could not be read")));
});

// The gate's whole risk score through its own CLI and scorer
// (babysit_risk.score, holding), the reads stubbed: only a regular file that
// stays regular may rate below HIGH, so a symlink or a submodule pointer a
// lane pull request adds holds, and a plain documentation change arms.
test("a lane pull request adding a symlink or a submodule pointer is not armed, or is disarmed; a doc change arms", async () => {
  const dir = mkdtempSync(join(tmpdir(), "enable-auto-merge-risk-"));
  const wrapper = join(dir, "risk.py");
  writeFileSync(
    wrapper,
    `import json, os, sys
sys.path.insert(0, os.environ["SCRIPTS"])
from unittest import mock
import babysit_merge
import babysit_merge_policy as policy
import babysit_verify_evidence as ve
from babysit_risk import ChangedFile, LaneEvidence

KINDS = json.loads(os.environ["KINDS"])
DOC = ChangedFile("docs/guide.md", None, "modified", 1, 1, True, "100644", "100644", patch="@@ -1 +1 @@\\n-old\\n+new")
EXTRA = {
    "doc": (),
    "symlink": (ChangedFile("docs/link", None, "added", 1, 0, True, "120000", "000000"),),
    "submodule": (ChangedFile("vendor/lib", None, "modified", 1, 1, False, "160000", "160000"),),
}
number = int(sys.argv[-2])
pr = {"number": number, "head": {"sha": sys.argv[-1]}, "base": {"sha": "d" * 40, "repo": {"private": False}}}
lanes = (LaneEvidence("claude-review", True, None, 0), LaneEvidence("claude-security-review", True, None, 0, False, 0))
config = policy.PipelineConfig("c" * 40, "C2", "pr-merge", "agent[bot]", None, (), "c2-mechanical")
with mock.patch.object(ve.Reader, "link_refusal", lambda self, n: None), \\
    mock.patch.object(ve.Reader, "evidence", lambda self, n, h, pr=None: ve.Evidence(None, h, (), 0)), \\
    mock.patch.object(policy, "read_config_at", lambda repo, sha: config), \\
    mock.patch.object(policy, "with_default_branch", lambda repo, base, *rest: base), \\
    mock.patch.object(policy, "pull_request", lambda repo, n: pr), \\
    mock.patch.object(policy, "changed_files", lambda repo, p: ((DOC, *EXTRA[KINDS[str(number)]]), True)), \\
    mock.patch.object(policy, "with_contents", lambda repo, p, f: f), \\
    mock.patch.object(policy, "pulumi_dirs_at", lambda repo, p: ()), \\
    mock.patch.object(policy, "permission_reader", lambda repo: (lambda login: None)), \\
    mock.patch.object(babysit_merge, "_lane_evidence", lambda *args: (lanes, [])):
    sys.exit(ve.main(sys.argv[1:]))
`,
  );
  const armed = { enabledAt: "2026-10-23T10:00:00Z" };
  const kinds = { 1: "doc", 2: "symlink", 3: "submodule" };
  const { github, writes } = world([pull(1), pull(2), pull(3, { autoMergeRequest: armed })]);
  const scripts = fileURLToPath(new URL("../../../plugins/source-control/skills/babysit-prs/scripts", import.meta.url));
  const env = { ...ENV, PATH: process.env.PATH, SCRIPTS: scripts, KINDS: JSON.stringify(kinds), VERIFY_EVIDENCE_SCRIPT: wrapper };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  try {
    assert.equal(await main({ env, github, room: room() }), 0);
  } finally {
    console.log = log;
  }
  assert.deepEqual(writes(), [
    { mutation: "arm", id: "PR_1", head: HEAD },
    { mutation: "disarm", id: "PR_3" },
  ]);
  assert.ok(lines.some((line) => /#2 left: pr-merge's gate holds it on its risk score \(.*docs\/link/.test(line)), lines.join("\n"));
  assert.ok(lines.some((line) => /#3 disarmed: pr-merge's gate holds it on its risk score \(.*vendor\/lib/.test(line)), lines.join("\n"));
});
