import assert from "node:assert/strict";
import { test } from "node:test";

import { ifOf, stepsOf, workflowText } from "./workflow-text.mjs";

const TEXT = `on:
  build:
    types: [x]
jobs:
  build:
    if: >-
      !cancelled()
      && needs.a.result == 'success'
    outputs:
      ready: \${{ steps.check.outputs.ready }}
    steps:
      - name: Check
        id: check
        if: >-
          always()
          && inputs.x != ''
        with:
          path: .base
        env:
          TOKEN: \${{ github.token }}
      # Reports the check.
      - name: Report
        if: steps.check.outputs.ready == 'true'
        run: echo ok
  # The second job.
  test:
    needs: [build]
    steps:
      - uses: actions/checkout@v4
      - name: Run
        run: npm test
`;

test("a job runs from its id line to the next line at its indent, found under jobs: only", () => {
  const wf = workflowText(TEXT);
  assert.deepEqual(wf.ids, ["build", "test"]);
  assert.ok(wf.job("build").startsWith("  build:\n    if: >-\n"));
  assert.ok(wf.job("build").endsWith("        run: echo ok\n"));
  assert.equal(wf.job("test"), "  test:\n    needs: [build]\n    steps:\n      - uses: actions/checkout@v4\n      - name: Run\n        run: npm test\n");
  assert.throws(() => wf.job("deploy"), /job deploy/);
});

test("a job's if: folds as YAML folds it, and a job with none reads true", () => {
  const wf = workflowText(TEXT);
  assert.equal(wf.jobIf("build"), "!cancelled() && needs.a.result == 'success'");
  assert.equal(wf.jobIf("test"), "true");
  assert.deepEqual(wf.outputs("build"), { ready: "${{ steps.check.outputs.ready }}" });
});

test("steps read by id or name carry their if:, with: and env:", () => {
  const wf = workflowText(TEXT);
  assert.deepEqual(wf.steps("build").map((s) => s.name), ["Check", "Report"]);
  assert.deepEqual(stepsOf(wf.job("test")).map((s) => s.name), ["Run"]);
  const check = wf.step("build", "check");
  assert.equal(check.name, "Check");
  assert.equal(check.if, "always() && inputs.x != ''");
  assert.deepEqual(check.inputs, { path: ".base" });
  assert.deepEqual(check.env, { TOKEN: "${{ github.token }}" });
  assert.ok(check.text.endsWith("\n          TOKEN: ${{ github.token }}\n"), "the next step's comment is the next step's");
  const report = wf.stepNamed("build", "Report");
  assert.equal(report.if, "steps.check.outputs.ready == 'true'");
  assert.deepEqual(report.inputs, {});
  assert.equal(wf.stepNamed("test", "Run").if, "");
  assert.throws(() => wf.stepNamed("build", "Missing"), /build step Missing/);
});

test("ifOf reads a single-line or folded if: at the given indent only", () => {
  assert.equal(ifOf("    if: a == 'b'\n        if: c\n", 4), "a == 'b'");
  assert.equal(ifOf("    if: a == 'b'\n        if: c\n", 8), "c");
  assert.equal(ifOf("\n        if: >-\n          a\n          && b\n", 8), "a && b");
  assert.equal(ifOf("        name: x\n", 8), "");
  assert.equal(ifOf("        if: first\n      - name: y\n        if: >-\n          second\n", 8), "first");
});
