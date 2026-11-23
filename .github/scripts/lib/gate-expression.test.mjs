// The expression rules gate-expression.mjs follows, each case from
// https://docs.github.com/en/actions/reference/workflows-and-actions/expressions.
import assert from "node:assert/strict";
import { test } from "node:test";

import { admits, evaluate, truthy } from "./gate-expression.mjs";

test("strings compare ignoring case, and mismatched types compare as numbers", () => {
  assert.equal(evaluate("'ABC' == 'abc'"), true);
  assert.equal(evaluate("'abc' != 'abd'"), true);
  assert.equal(evaluate("1 == '1'"), true);
  assert.equal(evaluate("null == ''"), true);
  assert.equal(evaluate("true == 1"), true);
  assert.equal(evaluate("true == 'true'"), false);
  assert.equal(evaluate("fromJSON('[]') == fromJSON('[]')"), false);
});

test("&& and || return an operand, ! negates truthiness, and parentheses group", () => {
  const branch = (ref) => evaluate("${{ github.ref == 'refs/heads/main' && 'value_for_main_branch' || 'value_for_other_branches' }}", { github: { ref } });
  assert.equal(branch("refs/heads/main"), "value_for_main_branch");
  assert.equal(branch("refs/heads/x"), "value_for_other_branches");
  assert.equal(evaluate("!'' && !(0 || null)"), true);
  assert.equal(evaluate("!('a' == 'a' || 'b' == 'c')"), false);
  assert.equal(evaluate("'it''s'"), "it's");
  for (const falsy of [false, 0, -0, "", null, NaN]) assert.equal(truthy(falsy), false, String(falsy));
  for (const value of [true, 1, "0", "false", [], {}]) assert.equal(truthy(value), true, JSON.stringify(value));
});

test("context paths read from a flat map, a nested object or a function, and an unset path reads as ''", () => {
  assert.equal(evaluate("needs.a.outputs.b-c", { "needs.a.outputs.b-c": "x" }), "x");
  assert.equal(evaluate("needs.a.outputs.b-c", { needs: { a: { outputs: { "b-c": "y" } } } }), "y");
  assert.equal(evaluate("steps.s.outcome", (path) => `read ${path}`), "read steps.s.outcome");
  assert.equal(evaluate("needs.a.outputs.unset == ''", {}), true);
});

test("contains, startsWith, format and fromJSON", () => {
  assert.equal(evaluate("contains('Hello world', 'LLO')"), true);
  assert.equal(evaluate("contains(fromJSON('[\"push\", \"pull_request\"]'), github.event_name)", { github: { event_name: "Push" } }), true);
  assert.equal(evaluate("contains(fromJSON('[\"push\"]'), github.event_name)", { github: { event_name: "issues" } }), false);
  assert.equal(evaluate("startsWith('Hello world', 'he')"), true);
  assert.equal(evaluate("format('Hello {0} {1} {2}', 'Mona', 'the', 'Octocat')"), "Hello Mona the Octocat");
  assert.equal(evaluate("format('{0}', github.run_id)", { github: { run_id: 7 } }), "7");
});

test("the status functions read the job's status so far", () => {
  for (const [status, expected] of Object.entries({ success: [true, true, false, false], failure: [true, false, true, false], cancelled: [true, false, false, true] })) {
    assert.deepEqual(["always()", "success()", "failure()", "cancelled()"].map((fn) => evaluate(fn, {}, { status })), expected, status);
  }
});

test("a condition with no status function runs only on success, as if it began success() &&", () => {
  const ctx = { steps: { a: { outputs: { go: "true" } } } };
  assert.equal(admits("steps.a.outputs.go == 'true'", ctx), true);
  assert.equal(admits("steps.a.outputs.go == 'true'", ctx, { status: "failure" }), false);
  assert.equal(admits("", ctx), true);
  assert.equal(admits("", ctx, { status: "failure" }), false);
  assert.equal(admits("always() && steps.a.outputs.go == 'true'", ctx, { status: "failure" }), true);
  assert.equal(admits("!cancelled() && steps.a.outputs.go == 'true'", ctx, { status: "failure" }), true);
  assert.equal(admits("!cancelled() && steps.a.outputs.go == 'true'", ctx, { status: "cancelled" }), false);
  assert.equal(admits("failure()", ctx, { status: "failure" }), true);
  assert.equal(admits("${{ steps.a.outputs.go }}", ctx), true);
});

test("a shape the evaluator does not know fails the test", () => {
  assert.throws(() => evaluate("github.event.commits[0]", {}), /a known token/);
  assert.throws(() => evaluate("1 < 2"), /a known token/);
  assert.throws(() => evaluate("toJSON(github)", {}), /a known function/);
  assert.throws(() => evaluate("event.name == 'x'", {}), /a context path/);
  assert.throws(() => evaluate("'a' == 'a' 'b'"), /the whole expression parsed/);
  assert.throws(() => evaluate("'a' =="), /an operand/);
});
