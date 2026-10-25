// The job if: gates that keep a pipeline workflow from starting a runner that
// could only skip or fail: pr-feedback-dispatch.yml on a review run GitHub
// skipped (a draft) or cancelled (a newer push superseded it). And the gates
// of pr-unblock.yml's address-feedback and review-dependency jobs, which a
// skipped subscription call or a forged model-call output must not turn.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { laneBranchIssue } from "../work-resolve-issue/report-outcome.mjs";
import { MAX_THREADS } from "./adjudicate-feedback.mjs";

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

// The if: at lines[at], indented by `indent` spaces, single-line or folded.
function ifAt(lines, at, indent) {
  const gate = lines[at].slice(indent + "if: ".length);
  if (gate !== ">-") {
    return gate;
  }
  const folded = [];
  for (const line of lines.slice(at + 1)) {
    if (!line.startsWith(" ".repeat(indent + 2))) break;
    folded.push(line.trim());
  }
  return folded.join(" ");
}

// A job's if:, single-line or folded, and its needs, as written.
function jobGate(file, job) {
  const block = jobBlock(file, job);
  const at = block.findIndex((line) => /^ {4}if: /.test(line));
  assert.notEqual(at, -1, `${file}: job ${job} has an if:`);
  const gate = ifAt(block, at, 4);
  const needsLine = block.find((line) => /^ {4}needs: /.test(line)) ?? "    needs: []";
  const needs = needsLine.slice("    needs: ".length).replace(/^\[|\]$/g, "").split(",").map((name) => name.trim()).filter(Boolean);
  return { gate, needs };
}

// Evaluates the expression with each context reference replaced by its value.
// Covers only the operators and functions these gates use (&&, ||, ==, !=, !,
// format('{0}', x), startsWith(x, 'y')); GitHub compares strings
// case-insensitively, and every value here is already in the case the gate
// names.
function evaluate(expression, context) {
  let body = expression.replace(/^\$\{\{([\s\S]*)\}\}$/, "$1").replaceAll("!cancelled()", "true");
  for (const name of Object.keys(context).sort((a, b) => b.length - a.length)) {
    body = body.replaceAll(name, JSON.stringify(context[name]));
  }
  body = body.replace(/format\('\{0\}', ([^)]*)\)/g, "String($1)");
  body = body.replace(/startsWith\(([^,]*), ('[^']*')\)/g, "String($1).startsWith($2)");
  // String literals, a workflow path among them, hold no reference.
  assert.doesNotMatch(body.replace(/'[^']*'|"[^"]*"/g, "''"), /[A-Za-z_][\w-]*\.[\w.-]+/, `an unresolved context reference in ${body}`);
  return Function(`return (${body});`)();
}

const LANE_BRANCH = "work-resolve-issue/issue-12-345-1";

test("pr-feedback-dispatch.yml starts no runner for a skipped or cancelled review run", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "dispatch");
  const runs = (conclusion, event = "pull_request", posted = "", branch = LANE_BRANCH) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.path": ".github/workflows/pr-review-hosted.yml",
      "github.event.workflow_run.event": event,
      "github.event.workflow_run.repository.full_name": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.head_repository.full_name": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.head_branch": branch,
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
  // A pr-verify run's branch is main, and its notes still dispatch.
  assert.equal(runs("success", "workflow_run", "a".repeat(40), "main"), true);
});

test("pr-feedback-dispatch.yml starts no runner for a review run off a lane branch", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "dispatch");
  const prefix = /startsWith\(github\.event\.workflow_run\.head_branch, '([^']+)'\)/.exec(gate)?.[1];
  assert.ok(prefix, "the dispatch gate checks the head branch");
  const runs = (branch) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.path": ".github/workflows/pr-review-hosted.yml",
      "github.event.workflow_run.event": "pull_request",
      "github.event.workflow_run.repository.full_name": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.head_repository.full_name": "melodic-software/claude-code-plugins",
      "github.event.workflow_run.head_branch": branch,
      "github.event.workflow_run.conclusion": "success",
      "needs.post-verify-notes.outputs.head-sha": "",
    });
  // Every branch the issue lane opens a PR from passes; a rename of the lane
  // branch fails here instead of silently stopping dispatches.
  assert.equal(laneBranchIssue(LANE_BRANCH), 12);
  assert.ok(LANE_BRANCH.startsWith(prefix), `${LANE_BRANCH} starts with ${prefix}`);
  assert.equal(laneBranchIssue(`x${LANE_BRANCH}`), null);
  assert.equal(runs(LANE_BRANCH), true);
  for (const branch of ["feat/x", "release/plugins", "dependabot/npm/x", "work-resolve-issue"]) {
    assert.equal(laneBranchIssue(branch), null, branch);
    assert.equal(runs(branch), false, branch);
  }
});

test("pr-feedback-dispatch.yml sweeps only after a scheduled pr-unblock-dispatch.yml run on main of this repository", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "dispatch");
  const repo = "melodic-software/claude-code-plugins";
  const runs = (overrides = {}) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": repo,
      "github.event.workflow_run.path": ".github/workflows/pr-unblock-dispatch.yml",
      "github.event.workflow_run.event": "schedule",
      "github.event.workflow_run.repository.full_name": repo,
      "github.event.workflow_run.head_repository.full_name": repo,
      "github.event.workflow_run.head_branch": "main",
      "github.event.workflow_run.conclusion": "success",
      "needs.post-verify-notes.outputs.head-sha": "",
      ...overrides,
    });
  assert.equal(runs(), true);
  assert.equal(runs({ "github.event.workflow_run.conclusion": "failure" }), true, "a failed tick still sweeps");
  for (const [label, overrides] of [
    ["a push to main", { "github.event.workflow_run.event": "push" }],
    ["a hand-started tick", { "github.event.workflow_run.event": "workflow_dispatch" }],
    ["another branch", { "github.event.workflow_run.head_branch": "feat/x" }],
    ["another repository", { "github.event.workflow_run.repository.full_name": "fork/claude-code-plugins" }],
    ["another workflow's schedule", { "github.event.workflow_run.path": ".github/workflows/maintenance-reconcile-lost-runs.yml" }],
  ]) {
    assert.equal(runs(overrides), false, label);
  }
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
      "github.event.workflow_run.conclusion": "success",
      "github.event.workflow_run.repository.full_name": repo,
      "github.event.workflow_run.head_repository.full_name": repo,
      ...overrides,
    });
  assert.equal(runs(), true);
  assert.equal(runs({ "github.event.workflow_run.path": ".github/workflows/pr-review-hosted.yml" }), false);
  assert.equal(runs({ "github.event.workflow_run.event": "pull_request" }), false);
  assert.equal(runs({ "github.event.workflow_run.head_branch": "feat/x" }), false);
  assert.equal(runs({ "github.event.workflow_run.head_repository.full_name": "fork/repo" }), false);
  // A skipped pr-verify run judged nothing and uploaded no verdict.
  assert.equal(runs({ "github.event.workflow_run.conclusion": "skipped" }), false);
  for (const conclusion of ["success", "failure", "cancelled"]) {
    assert.equal(runs({ "github.event.workflow_run.conclusion": conclusion }), true, conclusion);
  }
});

// Every same-repository PR's completed review re-runs its head's ci-status,
// whatever the branch: ci-status needs both review lanes on the head.
test("pr-feedback-dispatch.yml re-runs ci-status for a completed review run of a same-repository PR only", () => {
  const gate = jobIf("pr-feedback-dispatch.yml", "rerun-ci-status");
  const repo = "melodic-software/claude-code-plugins";
  const runs = (overrides = {}) =>
    evaluate(gate, {
      "github.ref": "refs/heads/main",
      "github.repository": repo,
      "github.event.workflow_run.path": ".github/workflows/pr-review-hosted.yml",
      "github.event.workflow_run.event": "pull_request",
      "github.event.workflow_run.conclusion": "success",
      "github.event.workflow_run.repository.full_name": repo,
      "github.event.workflow_run.head_repository.full_name": repo,
      ...overrides,
    });
  assert.equal(runs(), true);
  assert.equal(runs({ "github.event.workflow_run.path": ".github/workflows/pr-review-security-hosted.yml" }), true);
  for (const conclusion of ["failure", "cancelled", "timed_out"]) {
    assert.equal(runs({ "github.event.workflow_run.conclusion": conclusion }), true, conclusion);
  }
  // A draft's review run is skipped: it reviewed nothing.
  assert.equal(runs({ "github.event.workflow_run.conclusion": "skipped" }), false);
  assert.equal(runs({ "github.event.workflow_run.path": ".github/workflows/pr-verify.yml" }), false);
  assert.equal(runs({ "github.event.workflow_run.event": "workflow_dispatch" }), false);
  assert.equal(runs({ "github.event.workflow_run.event": "push" }), false);
  assert.equal(runs({ "github.event.workflow_run.head_repository.full_name": "fork/repo" }), false);
  assert.equal(runs({ "github.ref": "refs/heads/feat/x" }), false);
  // Not gated on a lanes App branch: a person's PR needs its ci-status re-run too.
  assert.doesNotMatch(gate, /head_branch/);
});

const UNBLOCK = "pr-unblock.yml";
const JOBS = [
  "address-feedback-select",
  "address-feedback-not-run",
  "address-feedback",
  "address-feedback-handoff",
  "address-feedback-subscription",
  "apply-feedback-patch",
  "adjudicate-feedback",
  "publish-feedback",
];

// Run 39783964241's shape: an API-key run skips the subscription call, and a
// job that needs a skipped job and lacks !cancelled() (or always()) is skipped
// too, so the push and the reply would never run.
test("pr-unblock.yml: every address-feedback job after a model call starts its if: with !cancelled()", () => {
  const after = JOBS.filter((job) => jobGate(UNBLOCK, job).needs.some((need) => need === "address-feedback" || need === "address-feedback-subscription"));
  assert.deepEqual(after, ["address-feedback-handoff", "address-feedback-subscription", "apply-feedback-patch", "adjudicate-feedback", "publish-feedback"]);
  for (const job of [...after, "address-feedback", "address-feedback-not-run"]) {
    assert.match(jobGate(UNBLOCK, job).gate, /^\$\{\{ !cancelled\(\) && /, job);
  }
});

// The reply job decides on the select job's proceed alone: a hostile model
// job can forge a handoff, a neutral check or any output of its own, and the
// round still posts its marker, so the round cap holds.
test("pr-unblock.yml: publish-feedback runs exactly when the select job proceeded, whatever a model call reports", () => {
  const { gate, needs } = jobGate(UNBLOCK, "publish-feedback");
  assert.deepEqual(needs, ["address-feedback-select", "address-feedback", "address-feedback-subscription", "apply-feedback-patch", "adjudicate-feedback"]);
  // The evaluator refuses any reference left unset: the gate reads nothing else.
  for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(gate, { "needs.address-feedback-select.outputs.proceed": proceed }), runs, JSON.stringify(proceed));
  }
});

// The post-hoc review of #9565: the job checked out, set up and staged on
// every round, though only an INCORRECT reply gives it work. Skipping it is
// fail-closed: an INCORRECT reply with no verdict escalates
// feedback-unadjudicated (adjudicate-feedback.mjs settleDisputes).
test("pr-unblock.yml: adjudicate-feedback runs on an INCORRECT reply from the leg that answered, whatever its patch", () => {
  const { gate } = jobGate(UNBLOCK, "adjudicate-feedback");
  const runs = (proceed, subResult, replies, disputed = "true", other = "") =>
    evaluate(gate, {
      "needs.address-feedback-select.outputs.proceed": proceed,
      "needs.address-feedback-subscription.result": subResult,
      "needs.address-feedback-subscription.outputs.feedback-attempt": subResult === "skipped" ? "" : replies,
      "needs.address-feedback.outputs.feedback-attempt": subResult === "skipped" ? replies : "",
      "needs.address-feedback-subscription.outputs.feedback-disputed": subResult === "skipped" ? other : disputed,
      "needs.address-feedback.outputs.feedback-disputed": subResult === "skipped" ? disputed : other,
    });
  assert.equal(runs("true", "skipped", "1"), true, "the key call's INCORRECT reply");
  assert.equal(runs("true", "success", "1"), true, "the subscription call's INCORRECT reply after a handoff");
  assert.equal(runs("true", "skipped", "1", ""), false, "replies with no INCORRECT one");
  assert.equal(runs("true", "success", "1", "", "true"), false, "the other leg's INCORRECT reply never counts");
  assert.equal(runs("true", "skipped", ""), false, "no replies");
  assert.equal(runs("false", "skipped", "1"), false, "a select job that did not proceed");
});

// prepare's contents reads go through request-budget.mjs, which records each
// reading under API_BUDGET_TOKEN; the job ends by logging them.
test("pr-unblock.yml: adjudicate-feedback logs the API budget its prepare step spends", () => {
  const block = jobBlock(UNBLOCK, "adjudicate-feedback").join("\n");
  assert.match(block, /\n {6}- name: Stage the disputed threads\n(?: {8}.*\n)*? {10}API_BUDGET_TOKEN: github-token\n/);
  assert.match(block, /\n {6}- name: Log the API budget at the end\n {8}if: always\(\)\n {8}continue-on-error: true\n(?: {8}.*\n)*? {8}uses: \.\/\.base\/\.github\/actions\/log-api-budget.*\n {8}with:\n {10}tokens: github-token\n/);
});

// adjudicate-feedback.mjs stages up to MAX_THREADS slots, and the job has one
// stage, judge and keep step per slot; a slot with no steps would read as
// unadjudicated with no error.
test("pr-unblock.yml: adjudicate-feedback judges every slot prepare stages, each with the same grants", () => {
  const steps = [];
  for (const line of jobBlock(UNBLOCK, "adjudicate-feedback")) {
    if (line.startsWith("      - ")) steps.push([]);
    steps.at(-1)?.push(line);
  }
  const field = (step, key) => step.find((line) => line.startsWith(`        ${key}: `))?.slice(`        ${key}: `.length);
  const nameOf = (step) => step[0].slice("      - name: ".length);
  const gateOf = (step) => ifAt(step, step.findIndex((line) => line.startsWith("        if: ")), 8);
  const slotOf = (step) => /\/adjudicate\/(\d+)$/.exec(step.find((line) => line.includes("SLOT_DIR:")) ?? "")?.[1];
  const judges = steps.filter((step) => /run-claude-cli@/.test(field(step, "uses") ?? ""));
  const slots = Array.from({ length: MAX_THREADS }, (_, n) => n);
  assert.deepEqual(judges.map((step) => field(step, "id")), slots.map((n) => `judge-${n}`));
  for (const n of slots) {
    const stage = steps.find((step) => nameOf(step) === `Stage disputed thread ${n}`);
    const judge = judges[n];
    const keep = steps.find((step) => nameOf(step) === `Keep disputed thread ${n}'s verdict`);
    const counted = `steps.key.outputs.present == 'true' && fromJSON(steps.prepare.outputs.count || '0') > ${n}`;
    assert.equal(gateOf(stage), counted, `stage ${n}`);
    assert.equal(gateOf(judge), counted, `judge ${n}`);
    assert.equal(gateOf(keep), `always() && steps.judge-${n}.outputs.structured-output-file != ''`, `keep ${n}`);
    assert.equal(slotOf(stage), String(n), `stage ${n} copies its own slot`);
    assert.equal(slotOf(keep), String(n), `keep ${n} writes its own slot`);
  }
  const withOf = (step) => step.slice(step.indexOf("        with:")).join("\n");
  for (const judge of judges.slice(1)) {
    assert.equal(withOf(judge), withOf(judges[0]), "every slot's model call has the same inputs and grants");
  }
  assert.match(withOf(judges[0]), /\n {10}allowed-tools: Read\(\.\/adjudicate\/\*\*\)\n/, "Read is allowed in the slot alone");
  assert.match(withOf(judges[0]), /\n {10}tools: Read\n/, "the judge's one tool is Read");
  const denied = withOf(judges[0]).match(/\n {10}disallowed-tools: \|\n((?: {12}.*\n)+)/)?.[1].trim().split(/\n\s*/) ?? [];
  for (const rule of ["Read(./.base/**)", "Read(/${{ runner.temp }}/**)", "Glob", "Grep", "mcp__*", "Bash", "WebFetch"]) {
    assert.ok(denied.includes(rule), `the judge denies ${rule}`);
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

const DEPENDENCY_JOBS = [
  "review-dependency-select",
  "review-dependency-not-run",
  "review-dependency",
  "review-dependency-handoff",
  "review-dependency-subscription",
  "apply-dependency-patch",
  "apply-dependency-verdict",
];

// As for address-feedback: a job that needs a skipped subscription call and
// lacks !cancelled() is skipped too, so the push and the verdict would never run.
test("pr-unblock.yml: every review-dependency job after a model call starts its if: with !cancelled()", () => {
  const after = DEPENDENCY_JOBS.filter((job) => jobGate(UNBLOCK, job).needs.some((need) => need === "review-dependency" || need === "review-dependency-subscription"));
  assert.deepEqual(after, ["review-dependency-handoff", "review-dependency-subscription", "apply-dependency-patch", "apply-dependency-verdict"]);
  for (const job of [...after, "review-dependency", "review-dependency-not-run"]) {
    assert.match(jobGate(UNBLOCK, job).gate, /^\$\{\{ !cancelled\(\) && /, job);
  }
});

// The verdict job decides on the select job's proceed alone: a hostile model
// job can forge a handoff, a neutral check or any output of its own, and the
// round still posts its marker, so the round cap holds.
test("pr-unblock.yml: apply-dependency-verdict runs exactly when the select job proceeded, whatever a model call reports", () => {
  const { gate, needs } = jobGate(UNBLOCK, "apply-dependency-verdict");
  assert.deepEqual(needs, ["review-dependency-select", "review-dependency", "review-dependency-subscription", "apply-dependency-patch"]);
  // The evaluator refuses any reference left unset: the gate reads nothing else.
  for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(gate, { "needs.review-dependency-select.outputs.proceed": proceed }), runs, JSON.stringify(proceed));
  }
});

// A select that does not proceed posts the review-dependency check neutral on
// the head it read, so dependency-dispatch.mjs does not send that head again.
test("pr-unblock.yml: review-dependency-not-run posts only when the select job decided not to proceed on a head it read", () => {
  const { gate, needs } = jobGate(UNBLOCK, "review-dependency-not-run");
  assert.deepEqual(needs, ["review-dependency-select"]);
  const runs = (proceed, head, activity = "review-dependency") =>
    evaluate(gate, {
      "inputs.activity": activity,
      "needs.review-dependency-select.outputs.proceed": proceed,
      "needs.review-dependency-select.outputs.head-sha": head,
    });
  assert.equal(runs("false", "a".repeat(40)), true);
  assert.equal(runs("true", "a".repeat(40)), false);
  assert.equal(runs("", ""), false, "a kill-switch stop reads no head");
  assert.equal(runs("false", ""), false);
  assert.equal(runs("false", "a".repeat(40), "fix-ci"), false);
});

test("pr-unblock.yml: apply-dependency-patch runs only on a written patch beside a fix verdict from the leg that answered", () => {
  const { gate } = jobGate(UNBLOCK, "apply-dependency-patch");
  const runs = (subResult, sub, first) =>
    evaluate(gate, {
      "needs.review-dependency-subscription.result": subResult,
      "needs.review-dependency-subscription.outputs.scan-patch-state": sub[0] ?? "",
      "needs.review-dependency-subscription.outputs.dependency-verdict": sub[1] ?? "",
      "needs.review-dependency.outputs.scan-patch-state": first[0] ?? "",
      "needs.review-dependency.outputs.dependency-verdict": first[1] ?? "",
    });
  assert.equal(runs("skipped", [], ["written", "fix"]), true, "the key call's fix, its subscription call skipped");
  assert.equal(runs("success", ["written", "fix"], []), true, "the subscription call's fix after a handoff");
  assert.equal(runs("success", [], ["written", "fix"]), false, "the key call's fix is not taken once the subscription call ran");
  assert.equal(runs("success", ["written", ""], ["written", "fix"]), false, "one leg's patch never pairs with the other's verdict");
  for (const verdict of ["merge", "close", "escalate", ""]) assert.equal(runs("skipped", [], ["written", verdict]), false, verdict);
  assert.equal(runs("skipped", [], ["empty", "fix"]), false);
  assert.equal(runs("skipped", [], ["", "fix"]), false);
});

const CONFLICT_JOBS = [
  "resolve-conflicts-select",
  "resolve-conflicts-not-run",
  "resolve-conflicts",
  "resolve-conflicts-handoff",
  "resolve-conflicts-subscription",
  "apply-conflict-patch",
  "report-conflict-status",
];

// As for review-dependency: a job that needs a skipped subscription call and
// lacks !cancelled() is skipped too, so a clean merge would never be pushed.
test("pr-unblock.yml: every resolve-conflicts job after the select job starts its if: with !cancelled()", () => {
  for (const job of CONFLICT_JOBS.slice(1)) {
    assert.match(jobGate(UNBLOCK, job).gate, /^\$\{\{ !cancelled\(\) && /, job);
  }
  assert.deepEqual(jobGate(UNBLOCK, "apply-conflict-patch").needs, ["resolve-conflicts-select", "resolve-conflicts", "resolve-conflicts-subscription"]);
});

// The push job decides on the select job's merge state, proceed and the
// answering leg's scanned patch state; a forged run-job output reaches none.
// The evaluator refuses any reference left unset, so the gate reads nothing else.
test("pr-unblock.yml: apply-conflict-patch runs on a clean merge or a conflicted one with the answering leg's patch, whatever else a model call reports", () => {
  const { gate } = jobGate(UNBLOCK, "apply-conflict-patch");
  const runs = (state, proceed, subResult = "skipped", sub = "", first = "") =>
    evaluate(gate, {
      "needs.resolve-conflicts-select.outputs.merge-state": state,
      "needs.resolve-conflicts-select.outputs.proceed": proceed,
      "needs.resolve-conflicts-subscription.result": subResult,
      "needs.resolve-conflicts-subscription.outputs.scan-patch-state": sub,
      "needs.resolve-conflicts.outputs.scan-patch-state": first,
    });
  assert.equal(runs("clean", "false"), true);
  assert.equal(runs("conflicted", "true", "skipped", "", "written"), true);
  assert.equal(runs("conflicted", "true", "skipped", "", "empty"), true);
  assert.equal(runs("conflicted", "true", "success", "written"), true);
  assert.equal(runs("conflicted", "true", "success", "", "written"), false);
  assert.equal(runs("escalate", "false", "skipped", "", "written"), false);
  assert.equal(runs("", "", "skipped", "", "written"), false, "a kill-switch stop");
  assert.equal(runs("conflicted", "true", "skipped", "", "garbage"), false);
});

test("pr-unblock.yml: the resolve-conflicts model calls run only when the select job found a conflicted merge", () => {
  const { gate, needs } = jobGate(UNBLOCK, "resolve-conflicts");
  assert.deepEqual(needs, ["resolve-conflicts-select"]);
  for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(gate, { "needs.resolve-conflicts-select.outputs.proceed": proceed }), runs, JSON.stringify(proceed));
  }
});

const FIX_CI_JOBS = [
  "fix-ci-context",
  "fix-ci",
  "fix-ci-handoff",
  "fix-ci-subscription",
  "apply-patch",
  "fix-ci-rung-up",
  "fix-ci-rung-up-handoff",
  "fix-ci-rung-up-subscription",
  "apply-patch-rung-up",
  "fix-ci-unreported",
];
const FIX_CI_CALLS = ["fix-ci", "fix-ci-subscription", "fix-ci-rung-up", "fix-ci-rung-up-subscription"];

// As for address-feedback: a job that needs a skipped call and lacks
// !cancelled() is skipped too, so the fallback, the push and the unreported
// post would never run.
test("pr-unblock.yml: every fix-ci job after a model call starts its if: with !cancelled()", () => {
  const after = FIX_CI_JOBS.filter((job) => jobGate(UNBLOCK, job).needs.some((need) => FIX_CI_CALLS.includes(need)));
  assert.deepEqual(after, ["fix-ci-handoff", "fix-ci-subscription", "apply-patch", "fix-ci-rung-up-handoff", "fix-ci-rung-up-subscription", "apply-patch-rung-up", "fix-ci-unreported"]);
  for (const job of after) assert.match(jobGate(UNBLOCK, job).gate, /^\$\{\{ !cancelled\(\) && /, job);
});

// A hostile model job can forge handed-off, lane-class, credential-present or
// any output of its own. The fallback calls start on the handoff jobs' reads,
// and the unreported post on fix-ci-context alone, so no forged output turns them.
test("pr-unblock.yml: fix-ci's fallback calls and unreported post decide on base jobs alone, whatever a model call reports", () => {
  const forged = /needs\.fix-ci(?:-rung-up)?(?:-subscription)?\.outputs\./;
  for (const job of ["fix-ci-handoff", "fix-ci-subscription", "fix-ci-rung-up-handoff", "fix-ci-rung-up-subscription", "fix-ci-unreported"]) {
    assert.doesNotMatch(jobGate(UNBLOCK, job).gate, forged, job);
  }
  // The evaluator refuses any reference left unset: each gate reads nothing else.
  const sub = (posted, proceed = "true") =>
    evaluate(jobGate(UNBLOCK, "fix-ci-subscription").gate, { "needs.fix-ci-context.outputs.proceed": proceed, "needs.fix-ci-handoff.outputs.posted": posted });
  assert.equal(sub("false"), true);
  assert.equal(sub("true"), false);
  assert.equal(sub("false", "false"), false);
  const rungUp = (result, posted) =>
    evaluate(jobGate(UNBLOCK, "fix-ci-rung-up-subscription").gate, {
      "needs.fix-ci-context.outputs.proceed": "true",
      "needs.fix-ci-rung-up.result": result,
      "needs.fix-ci-rung-up-handoff.outputs.posted": posted,
    });
  assert.equal(rungUp("success", "false"), true);
  assert.equal(rungUp("success", "true"), false);
  assert.equal(rungUp("skipped", ""), false, "no rung-up call, no rung-up fallback");
  for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(jobGate(UNBLOCK, "fix-ci-unreported").gate, { "needs.fix-ci-context.outputs.proceed": proceed }), runs, JSON.stringify(proceed));
  }
});

test("pr-unblock.yml: apply-patch runs on a written or empty patch, or a refused collection, from the leg that answered", () => {
  const { gate } = jobGate(UNBLOCK, "apply-patch");
  const runs = (subResult, sub, first) =>
    evaluate(gate, {
      "needs.fix-ci-subscription.result": subResult,
      "needs.fix-ci-subscription.outputs.scan-patch-state": sub[0] ?? "",
      "needs.fix-ci-subscription.outputs.scan-collect-refused": sub[1] ?? "",
      "needs.fix-ci.outputs.scan-patch-state": first[0] ?? "",
      "needs.fix-ci.outputs.scan-collect-refused": first[1] ?? "",
    });
  assert.equal(runs("skipped", [], ["written"]), true, "the key call's patch, its subscription call skipped");
  assert.equal(runs("skipped", [], ["empty"]), true, "an empty patch escalates");
  assert.equal(runs("success", ["written"], []), true, "the subscription call's patch after a handoff");
  assert.equal(runs("skipped", [], ["", "true"]), true, "a refused collection escalates");
  assert.equal(runs("success", ["", "true"], []), true, "the subscription call's refused collection");
  assert.equal(runs("success", [], ["written"]), false, "the key call's patch is not taken once the subscription call ran");
  assert.equal(runs("success", [], ["", "true"]), false, "nor its refusal");
  assert.equal(runs("skipped", [], ["", ""]), false, "a call that left no patch and refused none");
});

// #9365: a hostile model job can forge lane-class, credential-present,
// handed-off or any output of its own. address-feedback's and
// review-dependency's fallback calls start on their handoff jobs' reads, so
// no forged output starts or suppresses them.
test("pr-unblock.yml: address-feedback's and review-dependency's fallback calls start on base jobs alone, whatever a model call reports", () => {
  for (const [first, handoff, sub, select] of [
    ["address-feedback", "address-feedback-handoff", "address-feedback-subscription", "address-feedback-select"],
    ["review-dependency", "review-dependency-handoff", "review-dependency-subscription", "review-dependency-select"],
  ]) {
    const forged = new RegExp(`needs\\.${first}(?:-subscription)?\\.outputs\\.`);
    assert.doesNotMatch(jobGate(UNBLOCK, sub).gate, forged, sub);
    // Every forged pair a run job can report: a credit stop, an empty key, a
    // clean run. The start follows the handoff job's read alone.
    const forgeries = [
      { "lane-class": "credit-stop", "credential-present": "true", "handed-off": "true" },
      { "lane-class": "", "credential-present": "false", "handed-off": "true" },
      { "lane-class": "", "credential-present": "true", "handed-off": "false" },
    ];
    for (const outputs of forgeries) {
      const context = (posted, proceed = "true") => ({
        ...Object.fromEntries(Object.entries(outputs).map(([name, value]) => [`needs.${first}.outputs.${name}`, value])),
        [`needs.${select}.outputs.proceed`]: proceed,
        [`needs.${handoff}.outputs.posted`]: posted,
      });
      const label = JSON.stringify(outputs);
      assert.equal(evaluate(jobGate(UNBLOCK, sub).gate, context("true")), false, `${sub} after a posted check, ${label}`);
      assert.equal(evaluate(jobGate(UNBLOCK, sub).gate, context("false")), true, `${sub} after no posted check, ${label}`);
      assert.equal(evaluate(jobGate(UNBLOCK, sub).gate, context("false", "false")), false, `${sub} with no proceed, ${label}`);
    }
    assert.deepEqual(jobGate(UNBLOCK, sub).needs, [select, first, handoff]);
    assert.doesNotMatch(jobGate(UNBLOCK, handoff).gate, forged, handoff);
    // The handoff job runs whenever the select job proceeded.
    for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
      assert.equal(evaluate(jobGate(UNBLOCK, handoff).gate, { [`needs.${select}.outputs.proceed`]: proceed }), runs, `${handoff} ${JSON.stringify(proceed)}`);
    }
  }
});

// A step's if:, single-line or folded, by its name.
function stepIf(file, name) {
  const lines = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8").split("\n");
  const start = lines.indexOf(`      - name: ${name}`);
  assert.notEqual(start, -1, `${file}: step ${name}`);
  const end = lines.findIndex((line, i) => i > start && /^ {6}- /.test(line));
  const step = lines.slice(start + 1, end === -1 ? undefined : end);
  const at = step.findIndex((line) => /^ {8}if: /.test(line));
  assert.notEqual(at, -1, `${file}: step ${name} has an if:`);
  return ifAt(step, at, 8);
}

// The minutes of a workflow's one `cron:` line.
function cronMinutes(file) {
  const text = readFileSync(new URL(`../../workflows/${file}`, import.meta.url), "utf8");
  const crons = [...text.matchAll(/^ {4}- cron: "([0-9,]+) \* \* \* \*"$/gm)];
  assert.equal(crons.length, 1, `${file}: one hourly cron line`);
  return crons[0][1].split(",").map(Number);
}

const DISPATCHER = "pr-unblock-dispatch.yml";

test("pr-unblock-dispatch.yml gates a hand run and every re-run, and no first push or scheduled attempt", () => {
  const gate = stepIf(DISPATCHER, "Check the trigger");
  const runs = (event, attempt, kill = "true") =>
    evaluate(gate, { "steps.kill.outputs.proceed": kill, "github.event_name": event, "github.run_attempt": attempt });
  assert.equal(runs("push", "1"), false);
  assert.equal(runs("schedule", "1"), false);
  assert.equal(runs("workflow_dispatch", "1"), true);
  assert.equal(runs("push", "2"), true);
  assert.equal(runs("schedule", "2"), true);
  assert.equal(runs("schedule", "1", "false"), false);
  // A skipped gate lets the dispatch step run; a checked one must proceed.
  const dispatches = (outcome, proceed = "") =>
    evaluate(stepIf(DISPATCHER, "Dispatch pr-unblock for conflicting, review-tier Dependabot, failing lanes App and Markdown-changing PRs"), {
      "steps.kill.outputs.proceed": "true",
      "steps.gate.outcome": outcome,
      "steps.gate.outputs.proceed": proceed,
    });
  assert.equal(dispatches("skipped"), true);
  assert.equal(dispatches("success", "true"), true);
  assert.equal(dispatches("success", "false"), false);
});

test("pr-unblock-dispatch.yml ticks five minutes after each lost-run reconciler tick", () => {
  const reconciler = cronMinutes("maintenance-reconcile-lost-runs.yml");
  assert.deepEqual(cronMinutes(DISPATCHER), reconciler.map((minute) => (minute + 5) % 60));
});

test("pr-unblock-dispatch.yml: only a push cancels the dispatcher run going; a tick or hand run waits", () => {
  const block = jobBlock(DISPATCHER, "dispatch");
  const at = block.findIndex((line) => line === "    concurrency:");
  assert.notEqual(at, -1, "the dispatch job sets concurrency");
  assert.equal(block[at + 1], "      group: pr-unblock-dispatch");
  const cancel = /^ {6}cancel-in-progress: (.+)$/.exec(block[at + 2]);
  assert.ok(cancel, "cancel-in-progress follows the group");
  const cancels = (event) => evaluate(cancel[1], { "github.event_name": event });
  assert.equal(cancels("push"), true);
  assert.equal(cancels("schedule"), false);
  assert.equal(cancels("workflow_dispatch"), false);
});
