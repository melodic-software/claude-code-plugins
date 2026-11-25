// test-scope: plugins/work-items/skills/triage/scripts/check-ci-verdict.mjs
import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { checkVerdict, LANE_MARKER, verdictLines } from "../../../plugins/work-items/skills/triage/scripts/check-ci-verdict.mjs";
import { MARKER, parseVerdict } from "./apply-verdict.mjs";

const DIMS = {
  fields: {
    size: { options: { 27053568: "small", 27053567: "medium", 27053566: "large" } },
    complexity: { options: { 85127651: "low", 85127652: "medium", 85127653: "high" } },
    uncertainty: { options: { 85127654: "known", 85127655: "knowable", 85127656: "unknown" } },
  },
};
const FOOTER = "<sub>Automated triage. A maintainer reviews it.</sub>";

const skillVerdict = (fields) => {
  const verdict = { labels: ["priority: medium"], needs_human: false, ...fields };
  return { ...verdict, comment: [...verdictLines(verdict), "Blast radius: one file.", "Reversible: yes; revert."].join("\n") };
};

const laneComment = (verdict) => [MARKER, verdict.comment, FOOTER].join("\n\n");
const typed = ({ size, complexity, uncertainty, flags, blocked_by }) => JSON.stringify({ size, complexity, uncertainty, flags, blocked_by });

describe("a /work-items:triage --ci verdict reads as the intake lane's", () => {
  test("the skill's marker is apply-verdict's", () => {
    assert.equal(LANE_MARKER, MARKER);
  });

  for (const fields of [
    { size: "small", complexity: "low", uncertainty: "known", flags: [], blocked_by: [] },
    { size: "large", complexity: "high", uncertainty: "unknown", flags: ["intent", "cost"], blocked_by: [12, 40] },
  ]) {
    test(`fields ${JSON.stringify(fields)} parse from the comment alone and with the typed fields`, () => {
      const verdict = skillVerdict(fields);
      assert.deepEqual(checkVerdict(verdict), []);
      for (const parsed of [parseVerdict(laneComment(verdict), DIMS), parseVerdict(laneComment(verdict), DIMS, typed(verdict))]) {
        assert.deepEqual(parsed.problems, []);
        assert.deepEqual(parsed.dimensions, { size: fields.size, complexity: fields.complexity, uncertainty: fields.uncertainty });
        assert.deepEqual(parsed.flags, fields.flags);
        assert.deepEqual(parsed.blockedBy, fields.blocked_by);
        assert.equal(parsed.untrusted, false);
      }
    });
  }

  test("an untrusted flag reads as untrusted provenance and names no blocker", () => {
    const verdict = skillVerdict({ size: "small", complexity: "low", uncertainty: "known", flags: ["untrusted"], blocked_by: [] });
    assert.deepEqual(checkVerdict(verdict), []);
    const parsed = parseVerdict(laneComment(verdict), DIMS, typed(verdict));
    assert.equal(parsed.untrusted, true);
    assert.deepEqual(parsed.flags, []);
    assert.deepEqual(parsed.blockedBy, []);
  });
});
