// The job if: gates that keep a pipeline workflow from starting a runner that
// could only skip or fail: pr-feedback-dispatch.yml on a review run GitHub
// skipped (a draft) or cancelled (a newer push superseded it). And the gates
// of pr-unblock.yml's address-feedback jobs, which a skipped subscription
// call or a forged model-call output must not turn.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

// A job's folded `if: >-` scalar, joined the way YAML folds it.
function jobIf(file, job) {
  const text = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
  const block = new RegExp(`\\n  ${job}:\\n(?: {4}#.*\\n)*    if: >-\\n((?: {6}.*\\n)+)`).exec(text);
  assert.ok(block, `${file}: job ${job} has a folded if:`);
  return block[1]
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .join(" ");
}

// A job's block of the workflow text: from `  <job>:` to the next job.
function jobBlock(file, job) {
  const lines = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8").split("\n");
  const start = lines.indexOf(`  ${job}:`);
  assert.notEqual(start, -1, `${file}: job ${job}`);
  const end = lines.findIndex((line, i) => i > start && /^ {2}[a-z][\w-]*:$/.test(line));
  return lines.slice(start + 1, end === -1 ? undefined : end);
}

// A job's if:, single-line or folded, and its needs, as written.
function jobGate(file, job) {
  const block = jobBlock(file, job);
  const at = block.findIndex((line) => /^ {4}if: /.test(line));
  assert.notEqual(at, -1, `${file}: job ${job} has an if:`);
  let gate = block[at].slice("    if: ".length);
  if (gate === ">-") {
    const folded = [];
    for (const line of block.slice(at + 1)) {
      if (!/^ {6}/.test(line)) break;
      folded.push(line.trim());
    }
    gate = folded.join(" ");
  }
  const needsLine = block.find((line) => /^ {4}needs: /.test(line)) ?? "    needs: []";
  const needs = needsLine.slice("    needs: ".length).replace(/^\[|\]$/g, "").split(",").map((name) => name.trim()).filter(Boolean);
  return { gate, needs };
}

// Evaluates the expression with each context reference replaced by its value.
// Covers only the operators and function these gates use (&&, ||, ==, !=, !,
// format('{0}', x)); GitHub compares strings case-insensitively, and every
// value here is already in the case the gate names.
function evaluate(expression, context) {
  let body = expression.replace(/^\$\{\{([\s\S]*)\}\}$/, "$1").replaceAll("!cancelled()", "true");
  for (const name of Object.keys(context).sort((a, b) => b.length - a.length)) {
    body = body.replaceAll(name, JSON.stringify(context[name]));
  }
  body = body.replace(/format\('\{0\}', ([^)]*)\)/g, "String($1)");
  // String literals, a workflow path among them, hold no reference.
  assert.doesNotMatch(body.replace(/'[^']*'|"[^"]*"/g, "''"), /[A-Za-z_][\w-]*\.[\w.-]+/, `an unresolved context reference in ${body}`);
  return Function(`return (${body});`)();
}

test("pr-feedback-dispatch.yml starts no runner for a skipped or cancelled review run", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "dispatch");
  const runs = (conclusion, event = "pull_request", posted = "") =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.event": event,
      "github.event.workflow_run.head_repository.full_name": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.conclusion": conclusion,
      "needs.post-verify-notes.outputs.head-sha": posted,
    });
  assert.equal(runs("skipped"), false);
  assert.equal(runs("cancelled"), false);
  for (const conclusion of ["success", "failure"]) {
    assert.equal(runs(conclusion), true, conclusion);
  }
  // A pr-verify run dispatches only once its notes are on the PR.
  assert.equal(runs("success", "workflow_run"), false);
  assert.equal(runs("success", "workflow_run", "a".repeat(40)), true);
});

test("pr-feedback-dispatch.yml posts verifier notes only for a pr-verify run of main", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "post-verify-notes");
  const repo = "melodic-software/claude-code-plugins";
  const runs = (overrides = {}) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": repo,
      "github.event.workflow_run.path": ".github/workflows/pr-verify.yml",
      "github.event.workflow_run.event": "workflow_run",
      "github.event.workflow_run.head_branch": "main",
      "github.event.workflow_run.repository.full_name": repo,
      "github.event.workflow_run.head_repository.full_name": repo,
      ...overrides,
    });
  assert.equal(runs(), true);
  assert.equal(runs({ "github.event.workflow_run.path": ".github/workflows/pr-review-hosted.yml" }), false);
  assert.equal(runs({ "github.event.workflow_run.event": "pull_request" }), false);
  assert.equal(runs({ "github.event.workflow_run.head_branch": "feat/x" }), false);
  assert.equal(runs({ "github.event.workflow_run.head_repository.full_name": "fork/repo" }), false);
});

const UNBLOCK = "pr-unblock.yml";
const JOBS = ["address-feedback-select", "address-feedback-not-run", "address-feedback", "address-feedback-subscription", "apply-feedback-patch", "publish-feedback"];

// Run 39783964241's shape: an API-key run skips the subscription call, and a
// job that needs a skipped job and lacks !cancelled() (or always()) is skipped
// too, so the push and the reply would never run.
test("pr-unblock.yml: every address-feedback job after a model call starts its if: with !cancelled()", () => {
  const after = JOBS.filter((job) => jobGate(UNBLOCK, job).needs.some((need) => need === "address-feedback" || need === "address-feedback-subscription"));
  assert.deepEqual(after, ["address-feedback-subscription", "apply-feedback-patch", "publish-feedback"]);
  for (const job of [...after, "address-feedback", "address-feedback-not-run"]) {
    assert.match(jobGate(UNBLOCK, job).gate, /^\$\{\{ !cancelled\(\) && /, job);
  }
});

// The reply job decides on the select job's proceed alone: a hostile model
// job can forge a handoff, a neutral check or any output of its own, and the
// round still posts its marker, so the round cap holds.
test("pr-unblock.yml: publish-feedback runs exactly when the select job proceeded, whatever a model call reports", () => {
  const { gate, needs } = jobGate(UNBLOCK, "publish-feedback");
  assert.deepEqual(needs, ["address-feedback-select", "address-feedback", "address-feedback-subscription", "apply-feedback-patch"]);
  // The evaluator refuses any reference left unset: the gate reads nothing else.
  for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(gate, { "needs.address-feedback-select.outputs.proceed": proceed }), runs, JSON.stringify(proceed));
  }
});

test("pr-unblock.yml: apply-feedback-patch runs only on a written patch with replies from the leg that answered, not after a skip or an empty patch", () => {
  const { gate } = jobGate(UNBLOCK, "apply-feedback-patch");
  const runs = (subResult, sub, first, replies = "1") =>
    evaluate(gate, {
      "needs.address-feedback-subscription.result": subResult,
      "needs.address-feedback-subscription.outputs.scan-patch-state": sub,
      "needs.address-feedback.outputs.scan-patch-state": first,
      "needs.address-feedback-subscription.outputs.feedback-attempt": subResult === "skipped" ? "" : replies,
      "needs.address-feedback.outputs.feedback-attempt": subResult === "skipped" ? replies : "",
    });
  assert.equal(runs("skipped", "", "written"), true, "the key call's patch, its subscription call skipped");
  assert.equal(runs("success", "written", ""), true, "the subscription call's patch after a handoff");
  assert.equal(runs("success", "", "written"), false, "the key call's patch is not taken once the subscription call ran");
  assert.equal(runs("skipped", "", "written", ""), false, "a patch with no replies");
  assert.equal(runs("skipped", "", "empty"), false);
  assert.equal(runs("skipped", "", ""), false);
});
