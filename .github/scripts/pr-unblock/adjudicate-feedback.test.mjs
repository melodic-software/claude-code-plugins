import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { adjudicable, adjudicationReply, checkQuote, collect, contractIssues, DISPUTED, disputes, FINDING_STANDS_SKIP, MAX_THREADS, main, parseVerdicts, prepare, quoteSource, reviewerEvidence, settleDisputes, verdictOf } from "./adjudicate-feedback.mjs";
import { escalationRoute } from "./escalation-routes.mjs";
import { noteComments } from "./verify-notes.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const HEAD = "a".repeat(40);
const STANDS = "<!-- pr-unblock adjudicate-feedback: finding-stands -->\n**pr-unblock / adjudicate-feedback: the finding stands**";
// Review comment shapes the two review lanes post (claude-review and
// claude-security-review on #9504): a bold claim, or a severity line, then
// the rationale, a repro, a suggested fix and the lane footer.
const REVIEW = [
  "**A column-0 comment inside `remotes:` hides every entry after it.**",
  "",
  "The block regex only accepts continuation lines that start with whitespace.",
  "",
  "Fix: let the block continue across lines that start with `#`.",
  "",
  "claude-lane: claude-review",
].join("\n");
const SECURITY = [
  "severity: IMPORTANT",
  "",
  "This `remote` block writes `ref: main` with a 24h refetch into each consumer's `lefthook.yml`.",
  "",
  "Exploit path: anyone who can land a change on `main` runs code in every consumer clone.",
  "",
  "claude-lane: claude-security-review",
].join("\n");

const thread = (id, comments = [{ id: 1, author: "reviewer", lane: "claude-review", body: REVIEW }], path = "lib/install.mjs") => ({ id, path, line: 579, comments });
const fileOf = (...threads) => ({ version: 1, head_sha: HEAD, threads });
const incorrect = (id, fields = {}) => JSON.stringify({ thread: id, disposition: "INCORRECT", evidence: ["lib/install.mjs:12", "lib/other.mjs:3"], fix_sha: "", note: "The lane's argument.", ...fields });

test("disputes takes each INCORRECT reply's whole review comment and both sides' cited locations, never the lane's note", () => {
  const { slots, over } = disputes(fileOf(thread("PRRT_a"), thread("PRRT_b")), [incorrect("PRRT_a"), JSON.stringify({ thread: "PRRT_b", disposition: "VALID", evidence: ["a:1"] })].join("\n"));
  assert.deepEqual(over, []);
  assert.deepEqual(slots, [
    {
      thread: "PRRT_a",
      finding: { path: "lib/install.mjs", line: 579, comment: REVIEW },
      evidence: [
        { path: "lib/install.mjs", line: 12 },
        { path: "lib/other.mjs", line: 3 },
      ],
      cited: [],
      paths: ["lib/install.mjs", "lib/other.mjs"],
    },
  ]);
  assert.doesNotMatch(JSON.stringify(slots), /argument/);
});

// The post-hoc review of #9565: the judge saw the lane's cited files but only
// the review comment's first paragraph, so the inputs favored the lane.
const CITING = [
  "**The lock is read before it is written.**",
  "",
  "`lib/lock.mjs:40` reads it, and lib/write.mjs:7 writes it later; see also",
  `https://github.com/o/r/blob/${"c".repeat(40)}/lib/order.mjs#L9 and https://github.com/x/y/blob/${"c".repeat(40)}/lib/other-repo.mjs#L1.`,
  "Not paths: https://example.com:443/a, severity:1, ../etc/passwd:1, a/./b:2.",
  "",
  "claude-lane: claude-review",
].join("\n");

test("reviewerEvidence takes the review comment's path:line tokens and this repository's permalinks, each safe path once, at most ten", () => {
  assert.deepEqual(reviewerEvidence(CITING, "o/r"), [
    { path: "lib/lock.mjs", line: 40 },
    { path: "lib/write.mjs", line: 7 },
    { path: "lib/order.mjs", line: 9 },
  ]);
  assert.deepEqual(reviewerEvidence(CITING, ""), [
    { path: "lib/lock.mjs", line: 40 },
    { path: "lib/write.mjs", line: 7 },
  ], "no repository, no permalink");
  assert.deepEqual(reviewerEvidence("lib/a.mjs:1 and lib/a.mjs:1 again", "o/r"), [{ path: "lib/a.mjs", line: 1 }]);
  const many = Array.from({ length: 50 }, (_, i) => `lib/f${i}.mjs:1`).join(" ");
  assert.equal(reviewerEvidence(many, "o/r").length, 10);
});

test("disputes stages the files the reviewer cited beside the lane's, and keeps the two sides apart", () => {
  const citing = thread("PRRT_a", [{ id: 1, author: "reviewer", lane: "claude-review", body: CITING }]);
  const [slot] = disputes(fileOf(citing), incorrect("PRRT_a"), "o/r").slots;
  assert.deepEqual(slot.evidence, [
    { path: "lib/install.mjs", line: 12 },
    { path: "lib/other.mjs", line: 3 },
  ]);
  assert.deepEqual(slot.cited, [
    { path: "lib/lock.mjs", line: 40 },
    { path: "lib/write.mjs", line: 7 },
    { path: "lib/order.mjs", line: 9 },
  ]);
  assert.deepEqual(slot.paths, ["lib/install.mjs", "lib/other.mjs", "lib/lock.mjs", "lib/write.mjs", "lib/order.mjs"]);
  assert.equal(slot.finding.comment, CITING);
});

// A CRITICAL finding, which the code-review lane reports for security where
// no security lane runs, goes to a person: no slot, and any verdict ignored.
const CRITICAL_REVIEW = ["**The token reaches the log.**", "", "Repro: run the job.", "", "Severity: critical", "claude-lane: claude-review"].join("\n");
const criticalThread = (id) => thread(id, [{ id: 1, author: "reviewer", lane: "claude-review", body: CRITICAL_REVIEW }]);
// A pr-verify verifier note: a lane verdict would resolve the thread while
// the FAIL still holds the merge, and nothing re-judges that head.
const verifierThread = (id) => {
  const [note] = noteComments({ head: HEAD, summary: "s", notes: ["lib/install.mjs:4 x"], files: ["lib/install.mjs"] });
  return thread(id, [{ id: 1, author: "verifier", body: note.body }]);
};

test("disputes never adjudicates a CRITICAL code-review finding or a verifier note, and they take no slot", () => {
  const { slots } = disputes(fileOf(criticalThread("PRRT_c"), verifierThread("PRRT_v"), thread("PRRT_a")), [incorrect("PRRT_c"), incorrect("PRRT_v"), incorrect("PRRT_a")].join("\n"));
  assert.deepEqual(slots.map((slot) => slot.thread), ["PRRT_a"]);
  // A severity line other than CRITICAL is adjudicable as before.
  const important = thread("PRRT_i", [{ id: 1, author: "reviewer", lane: "claude-review", body: "x\n\nseverity: IMPORTANT\nclaude-lane: claude-review" }]);
  assert.deepEqual(disputes(fileOf(important), incorrect("PRRT_i")).slots.map((slot) => slot.thread), ["PRRT_i"]);
});

// settleDisputes with no API call allowed, on one posted thread.
const settleOffline = (now, disposition, verdicts = new Map([["PRRT_a", { verdict: "lane", question: "none" }]]), escalationReason = "") =>
  settleDisputes({
    api: new Proxy({}, { get: (_, name) => () => assert.fail(`no API call expected, got ${String(name)}`) }),
    pr: 42,
    adjudicatedSha: HEAD,
    posted: [{ thread: "PRRT_a", disposition }],
    replies: [],
    shown: new Map([["PRRT_a", { comment_ids: [1, 2] }]]),
    now,
    verdicts,
    pushed: false,
    headMoved: async () => false,
    resolveAfterReply: async () => assert.fail("not resolved"),
    escalationReason,
    log: () => {},
  });

test("settleDisputes holds a CRITICAL code-review finding left open for a person, whatever verdict arrived: disputed when INCORRECT, else uncertain", async () => {
  const now = new Map([["PRRT_a", criticalThread("PRRT_a")]]);
  assert.deepEqual(await settleOffline(now, "INCORRECT"), { escalationReason: "feedback-disputed", skipReason: "" });
  for (const disposition of ["UNCERTAIN", "VALID-defer"]) {
    assert.deepEqual(await settleOffline(now, disposition), { escalationReason: "feedback-uncertain", skipReason: "" }, disposition);
  }
});

test("settleDisputes ends a verifier note left open in feedback-verifier-open, a failing status and no person, whatever verdict arrived", async () => {
  const now = new Map([["PRRT_a", verifierThread("PRRT_a")]]);
  for (const disposition of DISPUTED) {
    assert.deepEqual(await settleOffline(now, disposition), { escalationReason: "feedback-verifier-open", skipReason: "" }, disposition);
  }
});

test("a reason held for a person outranks every fail-routed reason in one round", async () => {
  const now = new Map([["PRRT_a", criticalThread("PRRT_a")]]);
  assert.deepEqual(await settleOffline(now, "UNCERTAIN", undefined, "feedback-partial"), { escalationReason: "feedback-uncertain", skipReason: "" });
  const verifier = new Map([["PRRT_a", verifierThread("PRRT_a")]]);
  assert.deepEqual(await settleOffline(verifier, "UNCERTAIN", undefined, "feedback-partial"), { escalationReason: "feedback-partial", skipReason: "" });
});

// Only an INCORRECT reply is the lane disputing the finding with evidence.
// On UNCERTAIN (the lane could not tell) or VALID-defer (it agreed the finding
// holds), a lane verdict would let one model turn close a finding no one
// disputed (#10252 security review), so neither settles it: no reply, the
// thread stays open (the ruleset's thread resolution still holds the merge)
// and the round ends in a failing status. settleOffline fails on any API call
// or resolve.
test("settleDisputes resolves only an INCORRECT finding on a lane verdict: UNCERTAIN and VALID-defer stay open as feedback-unadjudicated", async () => {
  const now = new Map([["PRRT_a", thread("PRRT_a")]]);
  for (const disposition of ["UNCERTAIN", "VALID-defer"]) {
    assert.deepEqual(await settleOffline(now, disposition), { escalationReason: "feedback-unadjudicated", skipReason: "" }, disposition);
    // A person's reason in the same round still outranks it.
    assert.deepEqual(await settleOffline(now, disposition, undefined, "feedback-uncertain"), { escalationReason: "feedback-uncertain", skipReason: "" }, disposition);
  }
});

test("disputes stages an UNCERTAIN or VALID-defer reply on an adjudicable thread as it does an INCORRECT one", () => {
  for (const disposition of ["UNCERTAIN", "VALID-defer"]) {
    const { slots } = disputes(fileOf(thread("PRRT_a"), criticalThread("PRRT_c")), [incorrect("PRRT_a", { disposition }), incorrect("PRRT_c", { disposition })].join("\n"));
    assert.deepEqual(slots.map((slot) => slot.thread), ["PRRT_a"], disposition);
  }
  assert.deepEqual(disputes(fileOf(thread("PRRT_a")), incorrect("PRRT_a", { disposition: "VALID" })).slots, []);
});

test("the adjudication reply says what the adjudicator read: the review comment, not the lane's reasoning", () => {
  const reply = adjudicationReply("lane", ["a.js:1"], HEAD);
  assert.match(reply, /read the review comment, the locations both sides cited and the code at/);
  assert.match(reply, /without the fixing lane's reasoning/);
  assert.doesNotMatch(reply, /either side/);
});

test("disputes skips a thread whose finding already stood, a thread the select job did not keep, and unsafe paths", () => {
  const stoodThread = thread("PRRT_a", [
    { id: 1, author: "reviewer", lane: "claude-review", body: REVIEW },
    { id: 2, author: "lane", body: "**pr-unblock / address-feedback: INCORRECT, left open**" },
    { id: 3, author: "lane", body: STANDS },
  ]);
  const replies = [incorrect("PRRT_a"), incorrect("PRRT_x"), incorrect("PRRT_b", { evidence: ["../etc/passwd:1", "a/./b:2", "ok.js:4"] })].join("\n");
  const { slots } = disputes(fileOf(stoodThread, thread("PRRT_b")), replies);
  assert.deepEqual(slots.map((slot) => slot.thread), ["PRRT_b"]);
  assert.deepEqual(slots[0].evidence, [{ path: "ok.js", line: 4 }]);
  // A finding-stands line from anyone but the lane, or not first, is no stand.
  const quoted = thread("PRRT_a", [
    { id: 1, author: "reviewer", lane: "claude-review", body: REVIEW },
    { id: 2, author: "trusted-human", body: STANDS },
    { id: 3, author: "lane", body: `quoted:\n${STANDS}` },
  ]);
  assert.equal(disputes(fileOf(quoted), incorrect("PRRT_a")).slots.length, 1);
});

// A trusted person's fix request (threadAuthors tags it direction) outranks
// the adjudicator: the thread is not adjudicated, and an INCORRECT reply on
// it goes back to that person as feedback-disputed.
const directedThread = (id) =>
  thread(id, [
    { id: 1, author: "reviewer", lane: "claude-review", body: REVIEW },
    { id: 2, author: "trusted-human", direction: true, body: "PR-fix lane: please fix this finding" },
  ]);

test("disputes skips a thread a trusted person directed, and gives one thread one slot", () => {
  assert.deepEqual(disputes(fileOf(directedThread("PRRT_a"), thread("PRRT_b")), [incorrect("PRRT_a"), incorrect("PRRT_b"), incorrect("PRRT_b")].join("\n")).slots.map((slot) => slot.thread), ["PRRT_b"]);
});

test("disputes stages at most 10 cited locations, the limit publish-feedback accepts", () => {
  const evidence = Array.from({ length: 5000 }, (_, i) => `lib/f${i}.mjs:1`);
  const [slot] = disputes(fileOf(thread("PRRT_a")), incorrect("PRRT_a", { evidence })).slots;
  assert.equal(slot.evidence.length, 10);
  assert.equal(slot.paths.length, 11, "the finding's file and ten cited files");
});

test("settleDisputes hands an INCORRECT reply on a directed thread back as feedback-disputed, with no adjudication", async () => {
  const api = new Proxy({}, { get: (_, name) => () => assert.fail(`no API call expected, got ${String(name)}`) });
  const result = await settleDisputes({
    api,
    pr: 42,
    adjudicatedSha: HEAD,
    posted: [{ thread: "PRRT_a", disposition: "INCORRECT" }],
    replies: [],
    shown: new Map([["PRRT_a", { comment_ids: [1, 2] }]]),
    now: new Map([["PRRT_a", directedThread("PRRT_a")]]),
    verdicts: new Map([["PRRT_a", { verdict: "lane", question: "none" }]]),
    pushed: false,
    headMoved: async () => false,
    resolveAfterReply: async () => assert.fail("not resolved"),
    escalationReason: "",
    log: () => {},
  });
  assert.deepEqual(result, { escalationReason: "feedback-disputed", skipReason: "" });
});

test(`disputes adjudicates at most ${MAX_THREADS} threads and names the rest`, () => {
  const ids = ["PRRT_a", "PRRT_b", "PRRT_c", "PRRT_d"];
  const { slots, over } = disputes(fileOf(...ids.map((id) => thread(id))), ids.map((id) => incorrect(id)).join("\n"));
  assert.deepEqual(slots.map((slot) => slot.thread), ["PRRT_a", "PRRT_b", "PRRT_c"]);
  assert.deepEqual(over, ["PRRT_d"]);
});

// A security-review finding always goes to a person, and so does a finding
// whose lane its root comment does not name; neither takes a slot.
const securityThread = (id) => thread(id, [{ id: 1, author: "reviewer", lane: "claude-security-review", body: SECURITY }]);
// claude[bot] wrote its own footer: keepThreads gives it no lane.
const claudeBotThread = (id) => thread(id, [{ id: 1, author: "reviewer", body: REVIEW }]);
const unnamedThread = (id) => thread(id, [{ id: 1, author: "reviewer", body: "The guard is missing." }]);

test("disputes never adjudicates a security-review finding or one of unknown lane, and they take no slot", () => {
  const ids = ["PRRT_s", "PRRT_u", "PRRT_a", "PRRT_b", "PRRT_c", "PRRT_d"];
  const file = fileOf(securityThread("PRRT_s"), claudeBotThread("PRRT_u"), ...ids.slice(2).map((id) => thread(id)));
  const { slots, over } = disputes(file, ids.map((id) => incorrect(id)).join("\n"));
  assert.deepEqual(slots.map((slot) => slot.thread), ["PRRT_a", "PRRT_b", "PRRT_c"]);
  assert.deepEqual(over, ["PRRT_d"]);
});

test("settleDisputes sends an INCORRECT reply on a security-review or unknown-lane thread to a person, whatever verdict arrived", async () => {
  const api = new Proxy({}, { get: (_, name) => () => assert.fail(`no API call expected, got ${String(name)}`) });
  for (const now of [new Map([["PRRT_a", securityThread("PRRT_a")]]), new Map([["PRRT_a", unnamedThread("PRRT_a")]]), new Map([["PRRT_a", claudeBotThread("PRRT_a")]]), new Map()]) {
    const result = await settleDisputes({
      api,
      pr: 42,
      adjudicatedSha: HEAD,
      posted: [{ thread: "PRRT_a", disposition: "INCORRECT" }],
      replies: [],
      shown: new Map([["PRRT_a", { comment_ids: [1, 2] }]]),
      now,
      verdicts: new Map([["PRRT_a", { verdict: "lane", question: "none" }]]),
      pushed: false,
      headMoved: async () => false,
      resolveAfterReply: async () => assert.fail("not resolved"),
      escalationReason: "",
      log: () => {},
    });
    assert.deepEqual(result, { escalationReason: "feedback-disputed", skipReason: "" });
  }
});

// The floor for a reply the lane could not settle: on a security-review,
// unknown-lane or claude[bot] finding an UNCERTAIN or VALID-defer reply holds
// for a person whatever verdict arrived, and that reason routes `hold` (the
// needs-human label), not a failing status a new head would clear.
test("settleDisputes holds an UNCERTAIN or VALID-defer security-review or unknown-lane finding for a person, whatever verdict arrived", async () => {
  for (const [label, make] of [["security-review", securityThread], ["unknown lane", unnamedThread], ["claude[bot]", claudeBotThread]]) {
    for (const disposition of ["UNCERTAIN", "VALID-defer"]) {
      for (const verdict of ["lane", "reviewer"]) {
        const now = new Map([["PRRT_a", make("PRRT_a")]]);
        const verdicts = new Map([["PRRT_a", { verdict, question: "none" }]]);
        assert.deepEqual(await settleOffline(now, disposition, verdicts), { escalationReason: "feedback-uncertain", skipReason: "" }, `${label} ${disposition} ${verdict}`);
      }
    }
    assert.deepEqual(disputes(fileOf(make("PRRT_s")), ["UNCERTAIN", "VALID-defer"].map((disposition) => incorrect("PRRT_s", { disposition })).join("\n")).slots, [], `${label}: no slot`);
  }
  assert.equal(escalationRoute("feedback-uncertain"), "hold");
  assert.equal(escalationRoute("feedback-disputed"), "hold");
});

// A person decides only a security-review finding rated IMPORTANT or above
// (this repository's HIGH), or one with no rating it can read. The #10810
// shape: a SUGGESTION whose text says no change is required is settled like
// a code-review dispute, by the adjudicator or a failing status.
const SUGGESTION = SECURITY.replace("severity: IMPORTANT", "severity: SUGGESTION");
const ratedThread = (id, body) => thread(id, [{ id: 1, author: "reviewer", lane: "claude-security-review", body }]);
const UNRATED = [
  SECURITY.replace("severity: IMPORTANT\n", ""),
  SECURITY.replace("severity: IMPORTANT", "severity: LOW"),
  SECURITY.replace("severity: IMPORTANT", "severity: SUGGESTION\nseverity: IMPORTANT"),
];

test("disputes stages a SUGGESTION security-review finding, never an IMPORTANT, CRITICAL or unrated one", () => {
  assert.equal(adjudicable(ratedThread("PRRT_s", SUGGESTION).comments), true);
  assert.equal(adjudicable(ratedThread("PRRT_s", SUGGESTION.replace("SUGGESTION", "suggestion")).comments), true);
  for (const body of [SECURITY, SECURITY.replace("IMPORTANT", "CRITICAL"), ...UNRATED]) {
    assert.equal(adjudicable(ratedThread("PRRT_s", body).comments), false, body.split("\n")[0]);
    assert.deepEqual(disputes(fileOf(ratedThread("PRRT_s", body)), incorrect("PRRT_s")).slots, []);
  }
  assert.deepEqual(disputes(fileOf(ratedThread("PRRT_s", SUGGESTION)), incorrect("PRRT_s")).slots.map((slot) => slot.thread), ["PRRT_s"]);
  // A SUGGESTION line on a comment whose lane keepThreads did not tag is no lane finding.
  assert.equal(adjudicable(thread("PRRT_u", [{ id: 1, author: "reviewer", body: SUGGESTION }]).comments), false);
});

test("settleDisputes settles a disputed SUGGESTION security-review finding without a person", async () => {
  const now = new Map([["PRRT_a", ratedThread("PRRT_a", SUGGESTION)]]);
  // No verdict: a failing status, not a person.
  assert.deepEqual(await settleOffline(now, "INCORRECT", new Map()), { escalationReason: "feedback-unadjudicated", skipReason: "" });
  for (const disposition of ["UNCERTAIN", "VALID-defer"]) {
    assert.deepEqual(await settleOffline(now, disposition), { escalationReason: "feedback-unadjudicated", skipReason: "" }, disposition);
  }
  // An adjudicator's security question on it is no question for a person either.
  for (const disposition of DISPUTED) {
    assert.deepEqual(await settleOffline(now, disposition, new Map([["PRRT_a", { verdict: "human", question: "security" }]])), { escalationReason: "feedback-unadjudicated", skipReason: "" }, disposition);
  }
  assert.equal(escalationRoute("feedback-unadjudicated"), "fail");
  // An intent or design question still goes to a person, as on a code-review finding.
  assert.deepEqual(await settleOffline(now, "INCORRECT", new Map([["PRRT_a", { verdict: "human", question: "intent" }]])), { escalationReason: "feedback-question-intent", skipReason: "" });
  // On a code-review finding a security question still holds.
  assert.deepEqual(await settleOffline(new Map([["PRRT_a", thread("PRRT_a")]]), "INCORRECT", new Map([["PRRT_a", { verdict: "human", question: "security" }]])), { escalationReason: "feedback-question-security", skipReason: "" });
});

test("settleDisputes holds a disputed IMPORTANT, CRITICAL or unrated security-review finding for a person", async () => {
  for (const body of [SECURITY, SECURITY.replace("IMPORTANT", "CRITICAL"), ...UNRATED]) {
    const now = new Map([["PRRT_a", ratedThread("PRRT_a", body)]]);
    assert.deepEqual(await settleOffline(now, "INCORRECT"), { escalationReason: "feedback-disputed", skipReason: "" }, body.split("\n")[0]);
    assert.deepEqual(await settleOffline(now, "UNCERTAIN"), { escalationReason: "feedback-uncertain", skipReason: "" }, body.split("\n")[0]);
  }
});

// Only the lane's own line rates a finding: the comment's first line (the
// #10810 shape) or the last one above the footer (the #10833 shape). A rating
// quoted from the pull request supplies nothing, so the finding is unrated and
// a person decides (#10833 security review).
const RATED_FIRST = "severity: SUGGESTION\n\nThe gate blocks less now. No change is required.\n\nclaude-lane: claude-security-review";
const RATED_LAST = "**A quoted line can supply the rating.**\n\nNo change is required.\n\nseverity: SUGGESTION\n\nclaude-lane: claude-security-review";
const QUOTED = [
  ["mid-body, with no lane line", "**The body quotes the author.**\n\nThe author wrote:\nseverity: SUGGESTION\nso the guard looks optional.\n\nclaude-lane: claude-security-review"],
  ["indented, with no lane line", "**The body quotes the author.**\n\n    severity: SUGGESTION\n\nclaude-lane: claude-security-review"],
  ["fenced, with no lane line", "**The body quotes the author.**\n\n```text\nseverity: SUGGESTION\n```\n\nclaude-lane: claude-security-review"],
  ["fenced in an unclosed tilde fence", "**The body quotes the author.**\n\n~~~\nseverity: SUGGESTION\n\nclaude-lane: claude-security-review"],
  ["beside the lane's own line", "severity: SUGGESTION\n\nThe author wrote:\n> severity: SUGGESTION\n\nclaude-lane: claude-security-review"],
  ["fenced and last above the footer", "**x**\n\n```\nseverity: SUGGESTION\n```\nclaude-lane: claude-security-review"],
];

test("a rating comes only from the lane's own line: first, or last above the footer, outside any fence", async () => {
  for (const body of [RATED_FIRST, RATED_LAST, RATED_LAST.replace("\r", "").replaceAll("\n", "\r\n")]) {
    assert.equal(adjudicable(ratedThread("PRRT_a", body).comments), true, JSON.stringify(body.slice(0, 30)));
    assert.deepEqual(await settleOffline(new Map([["PRRT_a", ratedThread("PRRT_a", body)]]), "INCORRECT", new Map()), { escalationReason: "feedback-unadjudicated", skipReason: "" });
  }
  for (const [label, body] of QUOTED) {
    assert.equal(adjudicable(ratedThread("PRRT_a", body).comments), false, label);
    assert.deepEqual(disputes(fileOf(ratedThread("PRRT_a", body)), incorrect("PRRT_a")).slots, [], label);
    assert.deepEqual(await settleOffline(new Map([["PRRT_a", ratedThread("PRRT_a", body)]]), "INCORRECT"), { escalationReason: "feedback-disputed", skipReason: "" }, label);
  }
});

test("a thread a person wrote keeps its routing, whatever severity line it carries", async () => {
  const person = thread("PRRT_a", [{ id: 1, author: "trusted-human", body: SUGGESTION }]);
  assert.equal(adjudicable(person.comments), false);
  assert.deepEqual(disputes(fileOf(person), incorrect("PRRT_a")).slots, []);
  assert.deepEqual(await settleOffline(new Map([["PRRT_a", person]]), "INCORRECT"), { escalationReason: "feedback-disputed", skipReason: "" });
  assert.deepEqual(await settleOffline(new Map([["PRRT_a", person]]), "UNCERTAIN"), { escalationReason: "feedback-uncertain", skipReason: "" });
});

test("settleDisputes hands a directed SUGGESTION security-review thread back to its person", async () => {
  const directed = ratedThread("PRRT_a", SUGGESTION);
  directed.comments.push({ id: 2, author: "trusted-human", direction: true, body: "PR-fix lane: please fix this finding" });
  assert.deepEqual(await settleOffline(new Map([["PRRT_a", directed]]), "INCORRECT"), { escalationReason: "feedback-disputed", skipReason: "" });
});

test("prepare writes one slot per dispute with the files at the head, and refuses another head's thread file", async (t) => {
  const dir = tempDir("adjudicate-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const reads = [];
  const getText = async (path, ref) => {
    reads.push([path, ref]);
    return { "lib/install.mjs": "const x = 1;\n", "lib/other.mjs": "y".repeat(204801) }[path] ?? null;
  };
  const threadsText = JSON.stringify(fileOf(thread("PRRT_a")));
  const result = await prepare({ threadsText, repliesText: incorrect("PRRT_a", { evidence: ["lib/install.mjs:1", "lib/other.mjs:3", "gone.js:9"] }), headSha: HEAD, outDir: dir, getText });
  assert.equal(result.count, 1);
  assert.deepEqual(reads, [["lib/install.mjs", HEAD], ["lib/other.mjs", HEAD], ["gone.js", HEAD]]);
  assert.equal(readFileSync(join(dir, "0", "files", "lib", "install.mjs.txt"), "utf8"), "const x = 1;\n");
  assert.equal(existsSync(join(dir, "0", "files", "lib", "install.mjs")), false, "every staged file carries the suffix");
  assert.equal(existsSync(join(dir, "0", "files", "lib", "other.mjs.txt")), false, "a file over 200 KiB is not staged");
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "0", "evidence.json"), "utf8")), [
    { location: "lib/install.mjs:1", file: "present" },
    { location: "lib/other.mjs:3", file: "too-large" },
    { location: "gone.js:9", file: "absent" },
  ]);
  const finding = JSON.parse(readFileSync(join(dir, "0", "finding.json"), "utf8"));
  assert.equal(finding.head_sha, HEAD);
  assert.equal(finding.file, "present");
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "index.json"), "utf8")), { version: 1, head_sha: HEAD, slots: [{ slot: 0, thread: "PRRT_a" }], over: [] });

  await assert.rejects(prepare({ threadsText: JSON.stringify({ ...fileOf(), head_sha: "b".repeat(40) }), repliesText: "", headSha: HEAD, outDir: dir, getText }), /head/);
});

test("prepare stages the whole review comment and the reviewer's cited files, recorded apart from the lane's", async (t) => {
  const dir = tempDir("adjudicate-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const citing = thread("PRRT_a", [{ id: 1, author: "reviewer", lane: "claude-review", body: CITING }]);
  const files = { "lib/install.mjs": "a\n", "lib/lock.mjs": "lock\n", "lib/order.mjs": "order\n" };
  const result = await prepare({ threadsText: JSON.stringify(fileOf(citing)), repliesText: incorrect("PRRT_a", { evidence: ["lib/install.mjs:1"] }), headSha: HEAD, outDir: dir, repository: "o/r", getText: async (path) => files[path] ?? null });
  assert.equal(result.count, 1);
  assert.equal(JSON.parse(readFileSync(join(dir, "0", "finding.json"), "utf8")).comment, CITING);
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "0", "evidence.json"), "utf8")), [{ location: "lib/install.mjs:1", file: "present" }]);
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "0", "review-evidence.json"), "utf8")), [
    { location: "lib/lock.mjs:40", file: "present" },
    { location: "lib/write.mjs:7", file: "absent" },
    { location: "lib/order.mjs:9", file: "present" },
  ]);
  assert.equal(readFileSync(join(dir, "0", "files", "lib", "order.mjs.txt"), "utf8"), "order\n");
});

test("prepare writes an empty index into an output directory that does not exist yet, as the workflow passes it", async (t) => {
  const dir = tempDir("adjudicate-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const outDir = join(dir, "adjudicate");
  const result = await prepare({ threadsText: JSON.stringify(fileOf(thread("PRRT_a"))), repliesText: "", headSha: HEAD, outDir, getText: async () => null });
  assert.equal(result.count, 0);
  assert.deepEqual(JSON.parse(readFileSync(join(outDir, "index.json"), "utf8")), { version: 1, head_sha: HEAD, slots: [], over: [] });
});

test("prepare stages a cited CLAUDE.md under the suffix, and a path that cannot be staged is absent, not a failed round", async (t) => {
  const dir = tempDir("adjudicate-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  // `lib` is a file in this staging, so `lib/install.mjs.txt` cannot be written beside it.
  const getText = async () => "text\n";
  mkdirSync(join(dir, "0", "files"), { recursive: true });
  writeFileSync(join(dir, "0", "files", "lib"), "a file where a directory goes\n");
  const result = await prepare({
    threadsText: JSON.stringify(fileOf(thread("PRRT_a"))),
    repliesText: incorrect("PRRT_a", { evidence: ["CLAUDE.md:1"] }),
    headSha: HEAD,
    outDir: dir,
    getText,
  });
  assert.equal(result.count, 1);
  assert.equal(existsSync(join(dir, "0", "files", "CLAUDE.md")), false);
  assert.equal(readFileSync(join(dir, "0", "files", "CLAUDE.md.txt"), "utf8"), "text\n");
  assert.equal(JSON.parse(readFileSync(join(dir, "0", "finding.json"), "utf8")).file, "absent");
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "0", "evidence.json"), "utf8")), [{ location: "CLAUDE.md:1", file: "present" }]);
});

test("verdictOf takes only the schema's closed sets", () => {
  assert.deepEqual(verdictOf({ verdict: "lane", question: "none" }), { verdict: "lane", question: "none" });
  assert.deepEqual(verdictOf({ verdict: "human", question: "security" }), { verdict: "human", question: "security" });
  for (const bad of [
    { verdict: "human", question: "none" },
    { verdict: "reviewer", question: "design" },
    { verdict: "merge", question: "none" },
    { verdict: "lane", question: "none", reason: "extra" },
    { verdict: "lane" },
    ["lane", "none"],
    null,
  ]) {
    assert.equal(verdictOf(bad), null, JSON.stringify(bad));
  }
});

test("collect pairs each slot's structured output with the thread the index names; a missing or bad one is null", (t) => {
  const dir = tempDir("adjudicate-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, "index.json"), JSON.stringify({ version: 1, head_sha: HEAD, slots: [0, 1, 2].map((slot) => ({ slot, thread: `PRRT_${slot}` })), over: [] }));
  for (const [slot, text] of [[0, '{"verdict":"reviewer","question":"none"}'], [1, '{"verdict":"lane","question":"intent"}']]) {
    mkdirSync(join(dir, String(slot)));
    writeFileSync(join(dir, String(slot), "verdict.json"), text);
  }
  assert.deepEqual(collect({ outDir: dir }), {
    version: 1,
    head_sha: HEAD,
    threads: [
      { thread: "PRRT_0", verdict: "reviewer", question: "none" },
      { thread: "PRRT_1", verdict: null, question: null },
      { thread: "PRRT_2", verdict: null, question: null },
    ],
  });
});

test("parseVerdicts keeps valid entries for the gated head only", () => {
  const text = JSON.stringify({ version: 1, head_sha: HEAD, threads: [{ thread: "PRRT_a", verdict: "lane", question: "none" }, { thread: "PRRT_b", verdict: null, question: null }, { thread: "x", verdict: "lane", question: "none" }] });
  assert.deepEqual([...parseVerdicts(text, HEAD)], [["PRRT_a", { verdict: "lane", question: "none" }]]);
  assert.equal(parseVerdicts(text, "b".repeat(40)).size, 0);
  assert.equal(parseVerdicts("{", HEAD).size, 0);
  assert.equal(parseVerdicts(null, HEAD).size, 0);
});

test("main prepare reads its inputs only as the bytes their writers hashed", async (t) => {
  const dir = tempDir("adjudicate-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const threadsText = JSON.stringify(fileOf(thread("PRRT_a")));
  const repliesText = incorrect("PRRT_a");
  writeFileSync(join(dir, "threads.json"), threadsText);
  writeFileSync(join(dir, "replies.jsonl"), repliesText);
  const sum = (text) => createHash("sha256").update(text).digest("hex");
  const env = {
    GITHUB_OUTPUT: join(dir, "out"),
    OUT_DIR: join(dir, "slots"),
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    HEAD_SHA: HEAD,
    THREADS_FILE: join(dir, "threads.json"),
    THREADS_SHA256: sum(threadsText),
    REPLIES_FILE: join(dir, "replies.jsonl"),
    REPLIES_SHA256: sum(repliesText),
  };
  const api = { getText: async () => "code\n" };
  assert.equal(await main(["prepare"], env, { api, log: () => {} }), 0);
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "count=1\n");
  await assert.rejects(main(["prepare"], { ...env, REPLIES_SHA256: "0".repeat(64) }, { api, log: () => {} }), /replies.jsonl/);
  await assert.rejects(main(["prepare"], { ...env, THREADS_SHA256: "" }, { api, log: () => {} }), /THREADS_SHA256/);

  writeFileSync(join(env.OUT_DIR, "0", "verdict.json"), '{"verdict":"lane","question":"none"}');
  const verdicts = join(dir, "verdicts.json");
  assert.equal(await main(["collect"], { ...env, VERDICTS_FILE: verdicts }, { log: () => {} }), 0);
  const text = readFileSync(verdicts, "utf8");
  assert.deepEqual([...parseVerdicts(text, HEAD)], [["PRRT_a", { verdict: "lane", question: "none" }]]);
  assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), new RegExp(`\nsha256=${sum(text)}\n$`));
});

// A finding a listed review bot (pr-pipeline.yaml review-threads.reviewer-ids)
// opened: keepThreads tags it listed from the account id, never from its text,
// with the security-review lane's state for it (held, clear or pending). The
// badge line is Codex's, as on #10092 (P1) and #10293 (P2); its level is the
// bot's own pick.
const badged = (level, color, title = "The lock is read first") =>
  `**<sub><sub>![${level} Badge](https://img.shields.io/badge/${level}-${color}?style=flat)</sub></sub>  ${title}**\n\n\`lib/lock.mjs:40\` reads it.`;
const listedThread = (id, body = badged("P2", "yellow"), security = "clear") => thread(id, [{ id: 1, author: "reviewer", listed: true, security, body }]);
const slotted = (t) => disputes(fileOf(t), incorrect(t.id)).slots.map((slot) => slot.thread);
const settle = (t, { verdict = { verdict: "lane", question: "none" }, pushed = false } = {}) =>
  settleDisputes({
    api: new Proxy({}, { get: (_, name) => () => assert.fail(`no API call expected, got ${String(name)}`) }),
    pr: 42,
    adjudicatedSha: HEAD,
    posted: [{ thread: t.id, disposition: "INCORRECT" }],
    replies: [],
    shown: new Map([[t.id, { comment_ids: [1] }]]),
    now: new Map([[t.id, t]]),
    verdicts: new Map([[t.id, verdict]]),
    pushed,
    headMoved: async () => false,
    resolveAfterReply: async () => assert.fail("not resolved"),
    escalationReason: "",
    log: () => {},
  });

test("a listed review bot's dispute is adjudicated at any badge once the security lane reviewed its head and holds nothing", () => {
  for (const body of [
    badged("P3", "green"),
    badged("P2", "yellow"),
    badged("P1", "orange"),
    badged("P0", "red"),
    "No badge at all.\n\n`lib/lock.mjs:40` reads it.",
    // Security wording no keyword list catches: the security lane's rating,
    // not the bot's words, decides, and it held nothing here.
    badged("P2", "yellow", "The helper trusts the caller's ref"),
  ]) {
    assert.equal(adjudicable(listedThread("PRRT_l", body).comments), true, body);
    assert.deepEqual(slotted(listedThread("PRRT_l", body)), ["PRRT_l"], body);
  }
  // The CRITICAL guard still holds for a listed finding.
  assert.deepEqual(slotted(listedThread("PRRT_c", `${badged("P3", "green")}\n\nseverity: critical`)), []);
});

test("a listed review bot's dispute the security lane held, or has not reviewed yet, is never adjudicated", () => {
  for (const security of ["held", "pending", undefined]) {
    const t = thread("PRRT_h", [{ id: 1, author: "reviewer", listed: true, ...(security ? { security } : {}), body: badged("P3", "green") }]);
    assert.equal(adjudicable(t.comments), false, String(security));
    assert.deepEqual(slotted(t), [], String(security));
  }
  // The state means nothing on the code lane's own finding.
  assert.equal(adjudicable([{ id: 1, author: "reviewer", lane: "claude-review", security: "held", body: "The token is logged." }]), true);
});

test("settleDisputes sends a held listed dispute to a person as a security question, whatever verdict arrived", async () => {
  assert.deepEqual(await settle(listedThread("PRRT_h", badged("P3", "green"), "held")), { escalationReason: "feedback-question-security", skipReason: "" });
  assert.equal(escalationRoute("feedback-question-security"), "hold");
  assert.deepEqual(await settle(listedThread("PRRT_h", badged("P3", "green"), "held"), { verdict: { verdict: "reviewer", question: "none" } }), { escalationReason: "feedback-question-security", skipReason: "" });
});

test("settleDisputes defers a listed dispute the security lane has not reviewed yet: no escalation, no verdict, the head released for the next round", async () => {
  const pending = listedThread("PRRT_p", badged("P2", "yellow", "The helper trusts the caller's ref"), "pending");
  // The verdict is ignored; nothing is posted or resolved (the API fails on any call).
  assert.deepEqual(await settle(pending), { escalationReason: "", skipReason: FINDING_STANDS_SKIP });
  assert.deepEqual(await settle(pending, { verdict: { verdict: "human", question: "security" } }), { escalationReason: "", skipReason: FINDING_STANDS_SKIP });
  // A round that pushed moved the head; its review run starts the next round.
  assert.deepEqual(await settle(pending, { pushed: true }), { escalationReason: "", skipReason: "" });
  // A pending listed finding that carries `severity: CRITICAL` still goes to a person.
  assert.deepEqual(await settle(listedThread("PRRT_c", `${badged("P3", "green")}\n\nseverity: critical`, "pending")), { escalationReason: "feedback-disputed", skipReason: "" });
});

test("settleDisputes leaves a clear listed dispute to the adjudicator, whose own security question still reaches a person", async () => {
  assert.deepEqual(await settle(listedThread("PRRT_q", badged("P2", "yellow", "The helper trusts the caller's ref")), { verdict: { verdict: "human", question: "security" } }), {
    escalationReason: "feedback-question-security",
    skipReason: "",
  });
});

// Contract settling: the done-when line and URL below are a hand-written
// fixture, not output of the code under test.
const DONE_WHEN = "Done when: the install step reads the lock file before it resolves any version.";
const ISSUE = { number: 7, body: `## Done when\n\n- ${DONE_WHEN}\n`, comments: ["The owner decided: keep the cache key per lock file."] };
const ISSUE_URL_7 = "https://github.com/o/r/issues/7";

// settleDisputes with a reply API that records each reply it posts.
const settleWithReply = async (now, disposition, verdicts) => {
  const posted = [];
  const result = await settleDisputes({
    api: {
      readThread: async () => ({ isResolved: false, pr: 42, commentIds: [1, 2, 3] }),
      replyToComment: async (_pr, id, body) => {
        posted.push(body);
        return { in_reply_to_id: id, id: 9 };
      },
    },
    pr: 42,
    adjudicatedSha: HEAD,
    posted: [{ thread: "PRRT_a", disposition }],
    replies: [],
    shown: new Map([["PRRT_a", { comment_ids: [1, 2] }]]),
    now,
    verdicts,
    pushed: false,
    headMoved: async () => false,
    resolveAfterReply: async () => true,
    escalationReason: "",
    log: () => {},
  });
  return { result, posted };
};

test("prepare stages the linked issues' spec text as contract.json, empty when there is none", async (t) => {
  const dir = tempDir("adjudicate-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const args = { threadsText: JSON.stringify(fileOf(thread("PRRT_a"))), repliesText: incorrect("PRRT_a"), headSha: HEAD, repository: "o/r", getText: async () => "code\n" };
  await prepare({ ...args, outDir: join(dir, "with"), contract: [{ ...ISSUE, spec_kind: "closes" }] });
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "with", "0", "contract.json"), "utf8")), { issues: [{ number: 7, url: ISSUE_URL_7, body: ISSUE.body, comments: ISSUE.comments }] });
  await prepare({ ...args, outDir: join(dir, "without") });
  assert.deepEqual(JSON.parse(readFileSync(join(dir, "without", "0", "contract.json"), "utf8")), { issues: [] });
});

test("a quote that is the linked issue's own text settles an intent or design question: the reply quotes it with the issue URL", async (t) => {
  const dir = tempDir("adjudicate-");
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  writeFileSync(join(dir, "index.json"), JSON.stringify({ version: 1, head_sha: HEAD, slots: [{ slot: 0, thread: "PRRT_a" }], over: [] }));
  mkdirSync(join(dir, "0"));
  writeFileSync(join(dir, "0", "contract.json"), JSON.stringify({ issues: [{ number: 7, url: ISSUE_URL_7, body: ISSUE.body, comments: ISSUE.comments }] }));
  writeFileSync(join(dir, "0", "verdict.json"), JSON.stringify({ verdict: "reviewer", question: "intent", quote: DONE_WHEN }));
  const verdicts = parseVerdicts(JSON.stringify(collect({ outDir: dir })), HEAD);
  assert.deepEqual(verdicts.get("PRRT_a"), { verdict: "reviewer", question: "intent", quote: DONE_WHEN, url: ISSUE_URL_7 });
  const { result, posted } = await settleWithReply(new Map([["PRRT_a", thread("PRRT_a")]]), "INCORRECT", verdicts);
  assert.deepEqual(result, { escalationReason: "", skipReason: FINDING_STANDS_SKIP });
  assert.equal(posted.length, 1);
  assert.match(posted[0], /^<!-- pr-unblock adjudicate-feedback: finding-stands -->/);
  assert.ok(posted[0].includes(`The linked issue settles this intent question (${ISSUE_URL_7}):`));
  assert.ok(posted[0].includes(`> ${DONE_WHEN}`));
  // A comment's text settles too.
  assert.equal(checkQuote({ verdict: "lane", question: "design", quote: ISSUE.comments[0] }, [{ ...ISSUE, url: ISSUE_URL_7 }]).url, ISSUE_URL_7);
});

test("a quote that is not an exact substring of the staged text settles nothing: the question stays a person's", async () => {
  const issues = [{ ...ISSUE, url: ISSUE_URL_7 }];
  for (const quote of [DONE_WHEN.replace("lock file", "lockfile"), "the install step", `${DONE_WHEN} And more.`]) {
    assert.deepEqual(checkQuote({ verdict: "lane", question: "design", quote }, issues), { verdict: "human", question: "design" }, quote);
  }
  const verdicts = new Map([["PRRT_a", checkQuote({ verdict: "lane", question: "design", quote: "the install step" }, issues)]]);
  assert.deepEqual(await settleOffline(new Map([["PRRT_a", thread("PRRT_a")]]), "INCORRECT", verdicts), { escalationReason: "feedback-question-design", skipReason: "" });
  // A verdict file that names a settling quote without the URL collect found it at holds too.
  const text = JSON.stringify({ version: 1, head_sha: HEAD, threads: [{ thread: "PRRT_a", verdict: "lane", question: "intent", quote: DONE_WHEN }] });
  assert.deepEqual(parseVerdicts(text, HEAD).get("PRRT_a"), { verdict: "human", question: "intent" });
});

test("with no contract text no quote settles: the question stays a person's", async () => {
  assert.deepEqual(checkQuote({ verdict: "reviewer", question: "intent", quote: DONE_WHEN }, []), { verdict: "human", question: "intent" });
  assert.equal(quoteSource(DONE_WHEN, [{ number: 7, url: ISSUE_URL_7, body: null, comments: [] }]), null);
  assert.deepEqual(contractIssues(undefined, "o/r"), []);
  // A lane or reviewer verdict on a question with no quote is malformed.
  assert.equal(verdictOf({ verdict: "lane", question: "intent", quote: "" }), null);
  // A security question never settles by quote.
  assert.equal(verdictOf({ verdict: "lane", question: "security", quote: DONE_WHEN }), null);
  assert.deepEqual(verdictOf({ verdict: "human", question: "security", quote: DONE_WHEN }), { verdict: "human", question: "security" });
});

test("a security-review IMPORTANT or a CRITICAL finding stays held even with a settling quote", async () => {
  const settled = new Map([["PRRT_a", { verdict: "lane", question: "intent", quote: DONE_WHEN, url: ISSUE_URL_7 }]]);
  for (const [label, make, reason] of [
    ["security-review IMPORTANT", (id) => ratedThread(id, SECURITY), "feedback-disputed"],
    ["CRITICAL code-review", criticalThread, "feedback-disputed"],
  ]) {
    assert.deepEqual(await settleOffline(new Map([["PRRT_a", make("PRRT_a")]]), "INCORRECT", settled), { escalationReason: reason, skipReason: "" }, label);
    assert.deepEqual(await settleOffline(new Map([["PRRT_a", make("PRRT_a")]]), "UNCERTAIN", settled), { escalationReason: "feedback-uncertain", skipReason: "" }, label);
  }
});
