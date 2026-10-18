// The job if: gates that keep a pipeline workflow from starting a runner, or
// a lane, that could only skip or fail: pr-feedback-dispatch.yml on a review
// run GitHub skipped (a draft), and pr-refine.yml on a pull_request event a
// bot sent, which claude-code-action refuses.
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

// Evaluates the expression with each context reference replaced by its value.
// Covers only the operators and function these gates use (&&, ||, ==, !=, !,
// format('{0}', x)); GitHub compares strings case-insensitively, and every
// value here is already in the case the gate names.
function evaluate(expression, context) {
  let body = expression;
  for (const name of Object.keys(context).sort((a, b) => b.length - a.length)) {
    body = body.replaceAll(name, JSON.stringify(context[name]));
  }
  body = body.replace(/format\('\{0\}', ([^)]*)\)/g, "String($1)");
  assert.doesNotMatch(body, /[A-Za-z_][\w-]*\.[\w.-]+/, `an unresolved context reference in ${body}`);
  return Function(`return (${body});`)();
}

test("pr-feedback-dispatch.yml starts no runner for a skipped review run", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "dispatch");
  const runs = (conclusion) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.event": "pull_request",
      "github.event.workflow_run.head_repository.full_name": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.conclusion": conclusion,
    });
  assert.equal(runs("skipped"), false);
  for (const conclusion of ["success", "failure", "cancelled"]) {
    assert.equal(runs(conclusion), true, conclusion);
  }
});

test("pr-refine.yml skips fix-docs on a bot's event and runs it on a human's, whoever opened the PR", () => {
  const gate = jobIf("pr-refine.yml", "fix-docs");
  const APP = "337595936";
  const HUMAN = { id: 153232337, type: "User" };
  const SYNC_BOT = { id: 210000001, type: "Bot" };
  const runs = (event, { draft = false, sender = HUMAN } = {}) =>
    evaluate(gate, {
      "github.event_name": event,
      "github.event.pull_request.draft": event === "pull_request" ? draft : null,
      "github.event.sender.id": sender.id,
      "github.event.sender.type": sender.type,
      "vars.AUTOMATION_LANES_APP_SENDER_ID": APP,
    });
  assert.equal(runs("pull_request"), true, "a human's push, including to a bot-opened PR");
  assert.equal(runs("pull_request", { sender: SYNC_BOT }), false, "a standards-sync bot's push");
  assert.equal(runs("pull_request", { draft: true }), false, "a draft");
  assert.equal(runs("pull_request", { sender: { id: Number(APP), type: "Bot" } }), false, "the lanes App's own push");
  assert.equal(runs("workflow_dispatch"), true, "a dispatch");
});
