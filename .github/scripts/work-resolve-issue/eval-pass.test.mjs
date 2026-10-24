// The positive lines are the done-when wording of the concise-skills rollout
// issues, copied as written; the negatives are the no-spend steps those
// issues also list.
import assert from "node:assert/strict";
import { test } from "node:test";

import { EVAL_PASS, doneWhenItems, needsMeasuredEval } from "./eval-pass.mjs";

const MEASURED = [
  "The PR merges with a per-skill decision table in its body, and every shipped description and body was measured.",
  "The PR body holds a per-skill decision table, description and body decided separately, with the before and after numbers behind each row.",
  "Run a measured `claude plugin eval` pass on the changed skills.",
  "Run `claude plugin eval plugins/testing` with `--max-cost-usd 5` and record the delta.",
];
const NOT_MEASURED = [
  "`/evals:validate` passes on `plugins/improvement`'s eval suite at the PR head.",
  "Run `claude plugin eval` with `--dry-run` and record the estimate.",
  "Run `claude plugin eval` as a no-spend check of the suite.",
  "`/skill-quality:check plugins/improvement` on the PR head reports no FAIL that the run on main does not.",
  "The plugin's version or changelog entry is in the PR, per the plugin's release mode.",
  "Each model-invoked skill has a probe file.",
];

for (const line of MEASURED) {
  test(`asks for a measured eval: ${line}`, () => {
    assert.ok(EVAL_PASS.test(line));
    assert.ok(needsMeasuredEval(`## Done when\n\n- [ ] ${line}\n`));
  });
}

for (const line of NOT_MEASURED) {
  test(`asks for no measured eval: ${line}`, () => {
    assert.equal(needsMeasuredEval(`## Done when\n\n- [ ] ${line}\n`), false);
  });
}

test("plain bullets count under a Done when heading and nowhere else", () => {
  const body = [
    "## Scope",
    "",
    "- every shipped description and body was measured",
    "",
    "## Done when",
    "",
    "- every shipped description and body was measured.",
    "",
    "## Needs a person",
    "",
    "- Approve the eval spend before the measured passes.",
  ].join("\n");
  assert.deepEqual(doneWhenItems(body), ["every shipped description and body was measured."]);
});

test("a task-list item counts outside the Done when section", () => {
  assert.deepEqual(doneWhenItems("## Steps\n\n- [x] run it\n- not a task\n"), ["run it"]);
});

test("a body with no done-when asks for no measured eval", () => {
  assert.equal(needsMeasuredEval("Part of the rollout. Fix a typo."), false);
  assert.equal(needsMeasuredEval(undefined), false);
});
