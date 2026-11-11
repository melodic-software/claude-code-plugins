import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { checkBody } from "./check-body.mjs";

const contract = {
  headingLevels: [2, 3],
  emptyAnswer: "_No response_",
  types: {
    task: {
      fields: [
        { heading: "Context", required: true },
        { heading: "Proposed work", required: true },
        { heading: "References", required: false },
      ],
    },
  },
};

describe("checkBody", () => {
  it("accepts `##` headings a skill writes", () => {
    const body = "## Context\n\nWhy.\n\n## Proposed work\n\n- do it\n";
    assert.deepEqual(checkBody(contract, "task", body), {
      type: "task",
      unknownType: false,
      missing: [],
      empty: [],
    });
  });

  it("accepts `###` headings an issue form renders, matching heading case loosely", () => {
    const body = "### context\n\nWhy.\n\n### Proposed  work\n\n- do it\n\n### References\n\n_No response_\n";
    assert.deepEqual(checkBody(contract, "task", body).missing, []);
    assert.deepEqual(checkBody(contract, "task", body).empty, []);
  });

  it("reports a missing required heading and ignores a missing optional one", () => {
    assert.deepEqual(checkBody(contract, "task", "## Context\n\nWhy.\n").missing, ["Proposed work"]);
  });

  it("reports a form's skipped field and an empty section as empty", () => {
    const body = "### Context\n\n_No response_\n\n### Proposed work\n\n### References\n\nx\n";
    assert.deepEqual(checkBody(contract, "task", body).empty, ["Context", "Proposed work"]);
  });

  it("does not count a heading at a level the contract does not accept", () => {
    const body = "# Context\n\nWhy.\n\n#### Proposed work\n\n- do it\n";
    assert.deepEqual(checkBody(contract, "task", body).missing, ["Context", "Proposed work"]);
  });

  it("does not count headings inside fenced code or HTML comments", () => {
    const body = "```markdown\n## Context\n\nWhy.\n```\n\n<!--\n## Proposed work\nx\n-->\n";
    assert.deepEqual(checkBody(contract, "task", body).missing, ["Context", "Proposed work"]);
  });

  it("keeps a deeper sub-heading's text inside its section", () => {
    const body = "## Context\n\n#### Detail\n\nWhy.\n\n## Proposed work\n\n- x\n";
    assert.deepEqual(checkBody(contract, "task", body).empty, []);
  });

  it("counts an allowed-level sub-heading's text toward its parent field", () => {
    const body = "## Context\n\n### Background\n\nWhy.\n\n## Proposed work\n\n- x\n";
    assert.deepEqual(checkBody(contract, "task", body).empty, []);
  });

  it("closes a sub-section at the next parent-level heading", () => {
    const body = "## Context\n\n### Background\n\nWhy.\n\n## Proposed work\n\n_No response_\n";
    assert.deepEqual(checkBody(contract, "task", body).empty, ["Proposed work"]);
  });

  it("flags an unknown type", () => {
    assert.equal(checkBody(contract, "epic", "").unknownType, true);
  });
});
