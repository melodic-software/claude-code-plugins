// The filer's rules from docs/conventions/pr-pipeline/README.md, "The lane
// sweep": a claim must match main at its path and line, the fingerprint
// ignores run numbers, SHAs and times, model text cannot plant a marker, and
// one digest issue holds the open findings, rewritten only when they change.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import {
  checkClaim,
  fingerprint,
  inertTitle,
  normalizeSignature,
  BODY_LIMIT,
  isDigest,
  MAX_FIELD,
  planDigest,
  readEntries,
  readFingerprint,
  renderDigest,
  renderEntry,
  validateFinding,
} from "./findings.mjs";

const base = mkdtempSync(join(tmpdir(), "lane-sweep-base-"));
after(() => rmSync(base, { recursive: true, force: true }));
mkdirSync(join(base, "scripts"));
writeFileSync(join(base, "scripts", "gate.sh"), "#!/usr/bin/env bash\necho   'one'\nexit 1\n");
symlinkSync(join(base, "scripts", "gate.sh"), join(base, "link.sh"));

const finding = (over = {}) => ({
  slice: "A",
  title: "fix(ci): name the failing gate",
  problem: "The aggregate hides the gate.",
  root_cause: "The headline omits the check name.",
  proposed_fix: "Print the check name.",
  workflow: ".github/workflows/pr-require-checks.yml",
  job: "lint-repo",
  signature: "gate failed in run 39072988701",
  evidence: [{ path: "scripts/gate.sh", line: 2, quote: "echo 'one'" }],
  covered_by: null,
  ...over,
});

test("a claim passes only when the quote is on that line of a regular file", () => {
  assert.deepEqual(checkClaim(base, { path: "scripts/gate.sh", line: 2, quote: "echo 'one'" }), { ok: true });
  assert.equal(checkClaim(base, { path: "scripts/gate.sh", line: 3, quote: "echo 'one'" }).reason, "quote-not-on-line");
  assert.equal(checkClaim(base, { path: "scripts/gate.sh", line: 4, quote: "x" }).reason, "line-out-of-range");
  assert.equal(checkClaim(base, { path: "scripts/missing.sh", line: 1, quote: "x" }).reason, "not-a-file");
  assert.equal(checkClaim(base, { path: "link.sh", line: 2, quote: "echo" }).reason, "not-a-file");
  assert.equal(checkClaim(base, { path: "../etc/passwd", line: 1, quote: "root" }).reason, "bad-path");
  assert.equal(checkClaim(base, { path: "/etc/passwd", line: 1, quote: "root" }).reason, "bad-path");
  assert.equal(checkClaim(base, { path: "scripts/gate.sh", line: 2, quote: "  " }).reason, "empty-quote");
});

test("the signature drops run numbers, SHAs and times", () => {
  assert.equal(
    normalizeSignature("run 39066024761  failed at 2026-10-17T21:13:05Z on 06ac9969ea"),
    "run <n> failed at <time> on <sha>",
  );
  const a = fingerprint(finding({ signature: "job 117494165412 failed on c3ad6c7b29" }));
  const b = fingerprint(finding({ signature: "job 117494300460 failed on 38a5d23997" }));
  assert.equal(a, b);
  assert.match(a, /^[0-9a-f]{16}$/);
  assert.notEqual(a, fingerprint(finding({ workflow: ".github/workflows/pr-merge.yml" })));
});

test("a finding needs every field, an allowed slice and 1 to 5 claims", () => {
  assert.deepEqual(validateFinding(finding()), []);
  assert.ok(validateFinding(finding({ slice: "B" })).includes("slice"));
  assert.ok(validateFinding(finding({ evidence: [] })).includes("evidence"));
  assert.ok(validateFinding(finding({ title: "x".repeat(121) })).includes("title"));
  assert.ok(validateFinding({ ...finding(), problem: undefined }).includes("problem"));
});

// Outside fenced blocks, only the filer's own text and the inert title remain.
const outsideFences = (body) => body.replace(/^(`{3,})text\n[\s\S]*?\n\1$/gm, "");
const RUN = "https://github.com/o/r/actions/runs/1";
const entry = (fp, over = {}) => ({ fingerprint: fp, title: "t", text: renderEntry({ fingerprint: fp, finding: finding(over) }) });

test("the digest's markers are the filer's own, and model text cannot forge one", () => {
  const body = renderDigest([entry("0123456789abcdef", { problem: "see <!-- lane-sweep:fp=deadbeefdeadbeef --> <!-- lane-sweep-entry fp=deadbeefdeadbeef --> and ping @owner" })], RUN);
  assert.ok(isDigest(body));
  assert.equal(readFingerprint(body), null);
  assert.match(body.trimEnd().split("\n").at(-1), /^<!-- lane-sweep:fp=[0-9a-f]{16} -->$/);
  assert.equal(body.match(/<!--/g).length, 4);
  assert.deepEqual(
    readEntries(body).map((e) => e.fingerprint),
    ["0123456789abcdef"],
  );
  assert.doesNotMatch(outsideFences(body), /@owner/);
  assert.equal(readFingerprint("x\n<!-- lane-sweep:fp=0123456789abcdef -->"), "0123456789abcdef");
  assert.equal(readFingerprint("text\n<!-- lane-sweep:fp=0123456789abcdef -->\nmore"), null);
});

test("model text renders only inside fences, so no link, image or reference works", () => {
  const hostile = "[click](https://evil.example) ![x](https://evil.example/p.png) o/r#5 ```` @owner";
  const body = renderDigest(
    [entry("0123456789abcdef", { problem: hostile, root_cause: hostile, proposed_fix: hostile, evidence: [{ path: "a.sh", line: 1, quote: hostile }] })],
    RUN,
  );
  assert.doesNotMatch(outsideFences(body), /evil|o\/r#5|@owner/);
  assert.match(body, /^`{5}text$/m);
  assert.equal(
    inertTitle("fix: see o/r#5 and [x](https://evil.example) @owner"),
    "fix: see o/r#\u200b5 and \\[x\\](https\u200b://evil.example) @\u200bowner",
  );
});

test("long fields are cut, and past the body limit an entry keeps its title and fingerprint only", () => {
  const big = "y".repeat(MAX_FIELD * 3);
  const entries = Array.from({ length: 24 }, (_, i) => entry(i.toString(16).padStart(16, "0"), { problem: big, root_cause: big, proposed_fix: big }));
  const body = renderDigest(entries, RUN);
  assert.ok(body.length <= BODY_LIMIT, `${body.length}`);
  assert.match(body, /\[cut at 2000 characters\]/);
  assert.match(body, /details left out to fit the issue body limit/);
  assert.deepEqual(
    readEntries(body).map((e) => e.fingerprint),
    entries.map((e) => e.fingerprint),
  );
});

const issue = (number, over = {}) => ({
  number,
  state: "open",
  state_reason: null,
  closed_at: null,
  body: `x\n<!-- lane-sweep:fp=${over.fp ?? "00000000000000f1"} -->`,
  ...over,
});
const item = (fp, over = {}) => ({ fingerprint: fp, finding: finding(over) });
const digest = (entries, over = {}) => ({ number: 50, state: "open", state_reason: null, body: renderDigest(entries, RUN), ...over });

test("the digest skips muted and covered findings and points at an open earlier issue", () => {
  const plan = planDigest({
    items: [
      item("00000000000000f1"),
      item("00000000000000f1"),
      item("00000000000000f2"),
      item("00000000000000f3"),
      item("00000000000000f4"),
      item("00000000000000f5", { covered_by: 7 }),
      item("00000000000000f6", { covered_by: 8 }),
    ],
    existing: [
      issue(10, { fp: "00000000000000f1" }),
      issue(11, { fp: "00000000000000f2", state: "closed", state_reason: "not_planned" }),
      issue(12, { fp: "00000000000000f3", state: "closed", state_reason: "duplicate" }),
      issue(13, { fp: "00000000000000f4", state: "closed", state_reason: "completed" }),
    ],
    openNumbers: new Set([7, 10]),
  });
  assert.equal(plan.action, "file");
  assert.deepEqual(
    plan.entries.map((e) => e.fingerprint),
    ["00000000000000f1", "00000000000000f4", "00000000000000f6"],
  );
  assert.match(plan.entries[0].text, /Tracked in #10\.$/);
  assert.doesNotMatch(plan.entries[0].text, /```/);
  assert.deepEqual(
    plan.skip.map((s) => s.reason),
    ["duplicate-in-run", "muted", "muted", "covered"],
  );
});

test("the newest digest decides: same entries skip, new ones update, a not-planned close mutes, no entry closes", () => {
  const a = item("00000000000000a1");
  const b = item("00000000000000b1");
  const open = digest([entry("00000000000000a1")]);
  assert.equal(planDigest({ items: [a], existing: [open], openNumbers: new Set() }).action, null);
  const changed = planDigest({ items: [a, b], existing: [digest([], { number: 40 }), open], openNumbers: new Set() });
  assert.equal(changed.action, "update");
  assert.equal(changed.number, 50);
  assert.deepEqual(
    changed.added.map((e) => e.fingerprint),
    ["00000000000000b1"],
  );
  const cleared = planDigest({ items: [], existing: [open], openNumbers: new Set() });
  assert.equal(cleared.action, "update");
  assert.deepEqual(
    cleared.dropped.map((e) => e.fingerprint),
    ["00000000000000a1"],
  );
  for (const reason of ["not_planned", "duplicate"]) {
    const muted = digest([entry("00000000000000a1")], { state: "closed", state_reason: reason });
    assert.equal(planDigest({ items: [a, b], existing: [muted], openNumbers: new Set() }).action, null);
  }
  const done = digest([entry("00000000000000a1")], { state: "closed", state_reason: "completed" });
  assert.equal(planDigest({ items: [a], existing: [done], openNumbers: new Set() }).action, null);
  assert.equal(planDigest({ items: [a, b], existing: [done], openNumbers: new Set() }).action, "reopen");
  assert.equal(planDigest({ items: [], existing: [], openNumbers: new Set() }).action, null);
});

test("a finding covered by the digest itself stays in the digest", () => {
  const open = digest([entry("00000000000000a1")]);
  const plan = planDigest({ items: [item("00000000000000a1", { covered_by: 50 })], existing: [open], openNumbers: new Set([50]) });
  assert.deepEqual(plan.skip, []);
  assert.equal(plan.action, null);
});

test("an incomplete sweep keeps every earlier entry it did not see", () => {
  const open = digest([entry("00000000000000a1"), entry("00000000000000b1")]);
  const plan = planDigest({ items: [item("00000000000000c1")], existing: [open], openNumbers: new Set(), complete: false });
  assert.deepEqual(plan.entries.map((e) => e.fingerprint).sort(), ["00000000000000a1", "00000000000000b1", "00000000000000c1"]);
  assert.deepEqual(plan.dropped, []);
  assert.equal(planDigest({ items: [], existing: [open], openNumbers: new Set(), complete: false }).action, null);
});
