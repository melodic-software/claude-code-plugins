import assert from "node:assert/strict";
import { test } from "node:test";

import { readRecord, validRecord } from "./lane-outcome.mjs";

const BASE = {
  v: 1,
  lane: "pr-review",
  outcome: "failure",
  credential: { secret: "CLAUDE_CODE_OAUTH_TOKEN", kind: "oauth-token" },
};

test("review-unposted and shell-failed are known classes", () => {
  for (const cls of ["review-unposted", "shell-failed"]) {
    assert.equal(validRecord({ ...BASE, class: cls }).class, cls, cls);
  }
});

test("a shell-failed success record keeps shellFailed", () => {
  const record = validRecord({ ...BASE, outcome: "success", shellFailed: true });
  assert.equal(record.shellFailed, true);
  assert.equal(validRecord({ ...BASE, outcome: "success", shellFailed: "yes" }), null);
});

// docs/lane-outcome.md, Compatibility: a reader ignores class values it does
// not know, since a later v1 may add one.
test("an unknown class in the enum's kebab shape is kept as written, with the record", () => {
  const record = validRecord({ ...BASE, class: "later-class", turns: 3 });
  assert.equal(record.class, "later-class");
  assert.equal(record.turns, 3);
  assert.equal(readRecord(`x lane-outcome ${JSON.stringify({ ...BASE, class: "later-class" })} tail`).class, "later-class");
});

// report-check-run posts validRecord's result, which limit-stop.mjs reads back
// through validRecord: a record must survive the second read unchanged.
test("a validated record reads back unchanged", () => {
  for (const fields of [{ class: "later-class" }, { class: "review-unposted" }, { outcome: "success", shellFailed: true }]) {
    const once = validRecord({ ...BASE, ...fields, unknownKey: 1 });
    assert.deepEqual(validRecord(JSON.parse(JSON.stringify(once))), once, JSON.stringify(fields));
  }
});

test("a class that is not an enum-shaped token makes the record unreadable", () => {
  for (const cls of ["rate limited", "Rate-Limit", "x".repeat(41), 7, null]) {
    assert.equal(validRecord({ ...BASE, class: cls }), null, String(cls));
  }
});

test("a failure with no class at all is still no record", () => {
  assert.equal(validRecord(BASE), null);
});
