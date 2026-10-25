import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { adjudicationReply, collect, disputes, MAX_THREADS, main, parseVerdicts, prepare, reviewerEvidence, settleDisputes, verdictOf } from "./adjudicate-feedback.mjs";
import { noteComments } from "./verify-notes.mjs";

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

test("settleDisputes sends an INCORRECT reply on a CRITICAL code-review finding or a verifier note to a person, whatever verdict arrived", async () => {
  const api = new Proxy({}, { get: (_, name) => () => assert.fail(`no API call expected, got ${String(name)}`) });
  for (const now of [new Map([["PRRT_a", criticalThread("PRRT_a")]]), new Map([["PRRT_a", verifierThread("PRRT_a")]])]) {
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

test("prepare writes one slot per dispute with the files at the head, and refuses another head's thread file", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "adjudicate-"));
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
  const dir = mkdtempSync(join(tmpdir(), "adjudicate-"));
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
  const dir = mkdtempSync(join(tmpdir(), "adjudicate-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const outDir = join(dir, "adjudicate");
  const result = await prepare({ threadsText: JSON.stringify(fileOf(thread("PRRT_a"))), repliesText: "", headSha: HEAD, outDir, getText: async () => null });
  assert.equal(result.count, 0);
  assert.deepEqual(JSON.parse(readFileSync(join(outDir, "index.json"), "utf8")), { version: 1, head_sha: HEAD, slots: [], over: [] });
});

test("prepare stages a cited CLAUDE.md under the suffix, and a path that cannot be staged is absent, not a failed round", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "adjudicate-"));
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
  const dir = mkdtempSync(join(tmpdir(), "adjudicate-"));
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
  const dir = mkdtempSync(join(tmpdir(), "adjudicate-"));
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
