// The filer's rules from docs/conventions/pr-pipeline/README.md, "The lane
// sweep": a claim must match main at its path and line, the fingerprint
// ignores run numbers, SHAs and times, model text cannot plant a marker, and
// dedup comments, skips, reopens or files by the matching issue's state.
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
  planFiling,
  readFingerprint,
  renderBody,
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

test("the body ends with the fingerprint then the born-triaged marker, which model text cannot forge", () => {
  const body = renderBody(
    finding({
      problem: "see <!-- lane-sweep:fp=deadbeefdeadbeef --> and ping @owner",
    }),
    "0123456789abcdef",
    "https://github.com/o/r/actions/runs/1",
  );
  assert.equal(readFingerprint(body), "0123456789abcdef");
  assert.equal(body.match(/<!--/g).length, 2);
  assert.ok(body.trimEnd().endsWith("\n<!-- work-items:born-triaged -->"));
  assert.equal(readFingerprint("text\n<!-- lane-sweep:fp=0123456789abcdef -->"), "0123456789abcdef");
  assert.doesNotMatch(outsideFences(body), /@owner/);
  assert.equal(readFingerprint("text\n<!-- lane-sweep:fp=0123456789abcdef -->\nmore"), null);
});

test("model text renders only inside fences, so no link, image or reference works", () => {
  const hostile = "[click](https://evil.example) ![x](https://evil.example/p.png) o/r#5 ```` @owner";
  const body = renderBody(
    finding({
      problem: hostile,
      root_cause: hostile,
      proposed_fix: hostile,
      evidence: [{ path: "a.sh", line: 1, quote: hostile }],
    }),
    "0123456789abcdef",
    "https://github.com/o/r/actions/runs/1",
  );
  assert.doesNotMatch(outsideFences(body), /evil|o\/r#5|@owner/);
  assert.match(body, /^`{5}text$/m);
  assert.equal(
    inertTitle("fix: see o/r#5 and [x](https://evil.example) @owner"),
    "fix: see o/r#\u200b5 and \\[x\\](https\u200b://evil.example) @\u200bowner",
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
const item = (fp, over = {}) => ({
  fingerprint: fp,
  finding: finding(),
  ...over,
});

test("an open match gets one comment, not-planned and duplicate are skipped, a completed match is reopened at any age", () => {
  const plan = planFiling({
    items: [
      item("00000000000000f1"),
      item("00000000000000f1"),
      item("00000000000000f2"),
      item("00000000000000f3"),
      item("00000000000000f4"),
      item("00000000000000f5"),
      item("00000000000000f6"),
    ],
    existing: [
      issue(10, { fp: "00000000000000f1" }),
      issue(11, {
        fp: "00000000000000f2",
        state: "closed",
        state_reason: "not_planned",
        closed_at: "2026-10-01T00:00:00Z",
      }),
      issue(12, {
        fp: "00000000000000f3",
        state: "closed",
        state_reason: "completed",
        closed_at: "2026-10-10T00:00:00Z",
      }),
      issue(13, {
        fp: "00000000000000f4",
        state: "closed",
        state_reason: "completed",
        closed_at: "2025-01-01T00:00:00Z",
      }),
      issue(14, {
        fp: "00000000000000f5",
        state: "closed",
        state_reason: "duplicate",
        closed_at: "2026-10-01T00:00:00Z",
      }),
    ],
    openNumbers: new Set([10]),
  });
  assert.deepEqual(
    plan.comment.map((c) => c.number),
    [10],
  );
  assert.deepEqual(
    plan.skip.map((s) => s.reason),
    ["duplicate-in-run", "not-planned", "closed-duplicate"],
  );
  assert.deepEqual(
    plan.reopen.map((r) => [r.number, r.fingerprint]),
    [
      [12, "00000000000000f3"],
      [13, "00000000000000f4"],
    ],
  );
  assert.deepEqual(
    plan.file.map((f) => f.fingerprint),
    ["00000000000000f6"],
  );
});

test("reopens do not count against the five new issues", () => {
  const closed = ["1", "2", "3", "4", "5"].map((c, i) =>
    issue(20 + i, { fp: c.repeat(16), state: "closed", state_reason: "completed", closed_at: "2026-10-01T00:00:00Z" }),
  );
  const items = ["1", "2", "3", "4", "5", "a", "b", "c", "d", "e"].map((c) => item(c.repeat(16)));
  const plan = planFiling({ items, existing: closed, openNumbers: new Set() });
  assert.deepEqual(
    plan.reopen.map((r) => r.number),
    [20, 21, 22, 23, 24],
  );
  assert.deepEqual(
    plan.file.map((f) => f.fingerprint[0]),
    ["a", "b", "c", "d", "e"],
  );
  assert.deepEqual(plan.skip, []);
});

test("at most five new issues, and an open covering item skips the finding", () => {
  const items = ["a", "b", "c", "d", "e", "f", "g"].map((c) => item(c.repeat(16)));
  items[0] = item("a".repeat(16), { finding: finding({ covered_by: 7 }) });
  items[1] = item("b".repeat(16), { finding: finding({ covered_by: 8 }) });
  const plan = planFiling({
    items,
    existing: [],
    openNumbers: new Set([7]),
  });
  assert.deepEqual(
    plan.file.map((f) => f.fingerprint[0]),
    ["b", "c", "d", "e", "f"],
  );
  assert.deepEqual(
    plan.skip.map((s) => [s.fingerprint[0], s.reason]),
    [
      ["a", "covered"],
      ["g", "cap"],
    ],
  );
});
