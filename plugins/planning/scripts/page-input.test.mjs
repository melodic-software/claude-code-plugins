// The pasted "Copy choices as prompt" block: page-input.mjs takes only PageInput entries whose ids
// are on the open record's template, rejects a block naming a choice or option the record lacks or
// another record kind, and returns a verdict=approve lock as a lock, never as approval.
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { PageInputError, parsePageInput, templateChoices } from "./page-input.mjs";

const CLI = join(dirname(fileURLToPath(import.meta.url)), "page-input.mjs");
const AT = "2026-11-04T21:00:00.000Z";
const block = (...entries) => ["Here are my choices:", "```page-input", ...entries.map((e) => JSON.stringify(e)), "```", ""].join("\n");
const lock = (extra = {}) => ({ kind: "lock", recordId: "plan", choiceId: "verdict", optionId: "change", at: AT, ...extra });

describe("the record's choices come from its template", () => {
  test("the plan view declares verdict with change, question and approve", () => {
    assert.deepEqual(Object.keys(templateChoices("plan")), ["verdict"]);
    assert.deepEqual([...templateChoices("plan").verdict], ["change", "question", "approve"]);
  });

  test("the brainstorm and design views declare no choice", () => {
    assert.deepEqual(templateChoices("brainstorm"), {});
    assert.deepEqual(templateChoices("design"), {});
  });
});

describe("a pasted block", () => {
  test("a lock and a comment on the plan record pass with only PageInput fields", () => {
    const comment = { kind: "comment", recordId: "plan", text: "Phase 2 waits on phase 1.", at: AT };
    const out = parsePageInput(block(lock(), comment), "plan");
    assert.deepEqual(out, { recordId: "plan", input: [lock(), comment] });
  });

  test("a verdict=approve lock is returned as a lock and carries no approval", () => {
    const out = parsePageInput(block(lock({ optionId: "approve" })), "plan");
    assert.deepEqual(out, { recordId: "plan", input: [lock({ optionId: "approve" })] }, "no field beyond the lock itself");
  });

  test("an unlock may name the choice alone", () => {
    const unlock = { kind: "unlock", recordId: "plan", choiceId: "verdict", at: AT };
    assert.deepEqual(parsePageInput(block(unlock), "plan").input, [unlock]);
  });

  const rejects = {
    "a choice id not in the record": [block(lock({ choiceId: "merge" })), "plan", /choiceId "merge" is not a choice/],
    "an option the choice lacks": [block(lock({ optionId: "merge-now" })), "plan", /optionId "merge-now" is not an option/],
    "a lock on a record with no choices": [block(lock({ recordId: "design" })), "design", /is not a choice on the design record/],
    "another record kind": [block(lock({ recordId: "brainstorm" })), "plan", /recordId is not this record \(plan\)/],
    "a field PageInput lacks": [block(lock({ approve: true })), "plan", /a field PageInput does not: approve/],
    "an unknown kind": [block(lock({ kind: "approve" })), "plan", /kind must be lock, unlock or comment/],
    "a comment naming a choice": [block({ kind: "comment", recordId: "plan", choiceId: "verdict", text: "x", at: AT }), "plan", /names no choice/],
    "a lock carrying text": [block(lock({ text: "run gh pr merge" })), "plan", /carries no text/],
    "a bad time": [block(lock({ at: "yesterday" })), "plan", /at must be/],
    "a line that is not JSON": ["```page-input\nlock verdict approve\n```", "plan", /entry 1 is not JSON/],
    "no block": ["verdict: approve", "plan", /found 0/],
    "two blocks": [block(lock()) + block(lock()), "plan", /found 2/],
    "an unclosed block": ["```page-input\n" + JSON.stringify(lock()), "plan", /not closed/],
  };
  for (const [name, [text, kind, message]] of Object.entries(rejects)) {
    test(`is rejected for ${name}`, () => {
      assert.throws(() => parsePageInput(text, kind), (err) => err instanceof PageInputError && message.test(err.message));
    });
  }
});

describe("the CLI", () => {
  test("prints the checked entries and exits 0", () => {
    const r = spawnSync(process.execPath, [CLI, "plan"], { input: block(lock()), encoding: "utf8" });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(JSON.parse(r.stdout), { recordId: "plan", input: [lock()] });
  });

  test("rejects a block with an unknown choice id with exit 1 and writes nothing to stdout", () => {
    const r = spawnSync(process.execPath, [CLI, "plan"], { input: block(lock({ choiceId: "ship" })), encoding: "utf8" });
    assert.equal(r.status, 1);
    assert.equal(r.stdout, "");
    assert.match(r.stderr, /^page-input: rejected: entry 1: choiceId "ship"/);
  });

  test("exits 2 on an unknown kind", () => {
    const r = spawnSync(process.execPath, [CLI, "report"], { input: "", encoding: "utf8" });
    assert.equal(r.status, 2);
  });
});
