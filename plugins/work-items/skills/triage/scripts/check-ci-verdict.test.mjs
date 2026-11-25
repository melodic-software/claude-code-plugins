import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";

import { checkVerdict, LANE_MARKER, verdictLines } from "./check-ci-verdict.mjs";

const SCRIPT = fileURLToPath(new URL("./check-ci-verdict.mjs", import.meta.url));

const verdict = (overrides = {}) => {
  const base = {
    labels: ["priority: medium"],
    needs_human: false,
    size: "small",
    complexity: "low",
    uncertainty: "known",
    flags: [],
    blocked_by: [],
    ...overrides,
  };
  const body = "Blast radius: one skill file.\nReversible: yes; revert the commit.\nClaims checked: none\nOpen questions: none";
  return { ...base, comment: overrides.comment ?? `${verdictLines(base).join("\n")}\n${body}` };
};

describe("checkVerdict", () => {
  it("accepts a verdict whose comment opens with the five lines its fields give", () => {
    assert.deepEqual(checkVerdict(verdict()), []);
  });

  it("writes none for empty flags and blocked_by, and a comma list otherwise", () => {
    assert.deepEqual(verdictLines(verdict({ flags: ["intent", "cost"], blocked_by: [12, 40] })).slice(3), [
      "Flags: intent, cost",
      "Blocked by: #12, #40",
    ]);
    assert.deepEqual(checkVerdict(verdict({ flags: ["intent", "cost"], blocked_by: [12, 40] })), []);
  });

  it("refuses a comment line that disagrees with its typed field", () => {
    const good = verdict();
    const comment = good.comment.replace("Size: small", "Size: large");
    assert.deepEqual(checkVerdict({ ...good, comment }), ["comment line 1 is not `Size: small`"]);
  });

  it("refuses a second verdict line further down the comment", () => {
    const good = verdict();
    assert.deepEqual(checkVerdict({ ...good, comment: `${good.comment}\nFlags: security` }), [
      "comment line 10 repeats a verdict line",
    ]);
  });

  it("leaves the lane marker to the lane", () => {
    const good = verdict();
    assert.deepEqual(checkVerdict({ ...good, comment: `${LANE_MARKER}\n${good.comment}` }), [
      "comment holds the lane marker, which the lane adds",
    ]);
  });

  it("refuses a flag outside the closed set and a repeated flag", () => {
    assert.match(checkVerdict(verdict({ flags: ["urgent"] }))[0], /^flags is not/);
    assert.match(checkVerdict(verdict({ flags: ["cost", "cost"] }))[0], /^flags is not/);
  });

  it("refuses blocked_by entries that are not distinct positive issue numbers", () => {
    for (const blocked of [[0], [1.5], ["#3"], [3, 3], Array.from({ length: 21 }, (_, i) => i + 1)]) {
      assert.match(checkVerdict(verdict({ blocked_by: blocked }))[0], /^blocked_by is not/, JSON.stringify(blocked));
    }
  });

  it("refuses a missing field, an unknown field and a non-boolean needs_human", () => {
    const { flags, ...rest } = verdict();
    assert.deepEqual(checkVerdict(rest), ["missing fields: flags"]);
    assert.deepEqual(checkVerdict({ ...verdict(), status: "ready" }), ["unknown fields: status"]);
    assert.deepEqual(checkVerdict(verdict({ needs_human: "no" })), ["needs_human is not true or false"]);
  });

  it("refuses a dimension that is not one option key", () => {
    assert.deepEqual(checkVerdict(verdict({ size: "small or medium" })), ["size is not one option key"]);
  });

  it("refuses something other than an object", () => {
    assert.deepEqual(checkVerdict([]), ["the verdict is not a JSON object"]);
  });
});

describe("check-ci-verdict.mjs", () => {
  const run = (args) => {
    try {
      return { code: 0, out: execFileSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8", stdio: "pipe" }) };
    } catch (error) {
      return { code: error.status, out: error.stdout };
    }
  };

  it("exits 0 on a valid file, 1 on an invalid one and 2 on a usage error", () => {
    const dir = mkdtempSync(join(tmpdir(), "ci-verdict-"));
    try {
      const good = join(dir, "good.json");
      const bad = join(dir, "bad.json");
      writeFileSync(good, JSON.stringify(verdict()));
      writeFileSync(bad, JSON.stringify(verdict({ needs_human: 1 })));
      assert.deepEqual({ ...run(["--verdict", good]), out: JSON.parse(run(["--verdict", good]).out) }, {
        code: 0,
        out: { ok: true, problems: [] },
      });
      const failed = run(["--verdict", bad]);
      assert.equal(failed.code, 1);
      assert.equal(JSON.parse(failed.out).ok, false);
      assert.equal(run([]).code, 2);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
