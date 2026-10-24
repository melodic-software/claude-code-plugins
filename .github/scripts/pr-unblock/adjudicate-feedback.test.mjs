import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { claimOf, collect, disputes, MAX_THREADS, main, parseVerdicts, prepare, verdictOf } from "./adjudicate-feedback.mjs";

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

test("claimOf keeps the first paragraph and the severity line, never the rationale, the fix or the footer", () => {
  assert.deepEqual(claimOf(REVIEW), { severity: null, claim: "**A column-0 comment inside `remotes:` hides every entry after it.**" });
  assert.deepEqual(claimOf(SECURITY), {
    severity: "severity: IMPORTANT",
    claim: "This `remote` block writes `ref: main` with a 24h refetch into each consumer's `lefthook.yml`.",
  });
  assert.deepEqual(claimOf("severity: HIGH\nThe guard is missing.\n\nWhy: x"), { severity: "severity: HIGH", claim: "The guard is missing." });
  assert.equal(claimOf("x".repeat(3000)).claim.length, 2000);
  assert.deepEqual(claimOf(""), { severity: null, claim: "" });
});

const thread = (id, comments = [{ id: 1, author: "reviewer", body: REVIEW }], path = "lib/install.mjs") => ({ id, path, line: 579, comments });
const fileOf = (...threads) => ({ version: 1, head_sha: HEAD, threads });
const incorrect = (id, fields = {}) => JSON.stringify({ thread: id, disposition: "INCORRECT", evidence: ["lib/install.mjs:12", "lib/other.mjs:3"], fix_sha: "", note: "The lane's argument.", ...fields });

test("disputes takes each INCORRECT reply's claim and cited locations, never the lane's note", () => {
  const { slots, over } = disputes(fileOf(thread("PRRT_a"), thread("PRRT_b")), [incorrect("PRRT_a"), JSON.stringify({ thread: "PRRT_b", disposition: "VALID", evidence: ["a:1"] })].join("\n"));
  assert.deepEqual(over, []);
  assert.deepEqual(slots, [
    {
      thread: "PRRT_a",
      finding: { path: "lib/install.mjs", line: 579, severity: null, claim: "**A column-0 comment inside `remotes:` hides every entry after it.**" },
      evidence: [
        { path: "lib/install.mjs", line: 12 },
        { path: "lib/other.mjs", line: 3 },
      ],
      paths: ["lib/install.mjs", "lib/other.mjs"],
    },
  ]);
  assert.doesNotMatch(JSON.stringify(slots), /argument/);
});

test("disputes skips a thread whose finding already stood, a thread the select job did not keep, and unsafe paths", () => {
  const stoodThread = thread("PRRT_a", [
    { id: 1, author: "reviewer", body: REVIEW },
    { id: 2, author: "lane", body: "**pr-unblock / address-feedback: INCORRECT, left open**" },
    { id: 3, author: "lane", body: STANDS },
  ]);
  const replies = [incorrect("PRRT_a"), incorrect("PRRT_x"), incorrect("PRRT_b", { evidence: ["../etc/passwd:1", "a/./b:2", "ok.js:4"] })].join("\n");
  const { slots } = disputes(fileOf(stoodThread, thread("PRRT_b")), replies);
  assert.deepEqual(slots.map((slot) => slot.thread), ["PRRT_b"]);
  assert.deepEqual(slots[0].evidence, [{ path: "ok.js", line: 4 }]);
  // A finding-stands line from anyone but the lane, or not first, is no stand.
  const quoted = thread("PRRT_a", [
    { id: 1, author: "reviewer", body: REVIEW },
    { id: 2, author: "trusted-human", body: STANDS },
    { id: 3, author: "lane", body: `quoted:\n${STANDS}` },
  ]);
  assert.equal(disputes(fileOf(quoted), incorrect("PRRT_a")).slots.length, 1);
});

test(`disputes adjudicates at most ${MAX_THREADS} threads and names the rest`, () => {
  const ids = ["PRRT_a", "PRRT_b", "PRRT_c", "PRRT_d"];
  const { slots, over } = disputes(fileOf(...ids.map((id) => thread(id))), ids.map((id) => incorrect(id)).join("\n"));
  assert.deepEqual(slots.map((slot) => slot.thread), ["PRRT_a", "PRRT_b", "PRRT_c"]);
  assert.deepEqual(over, ["PRRT_d"]);
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
  assert.equal(readFileSync(join(dir, "0", "files", "lib", "install.mjs"), "utf8"), "const x = 1;\n");
  assert.equal(existsSync(join(dir, "0", "files", "lib", "other.mjs")), false, "a file over 200 KiB is not staged");
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
