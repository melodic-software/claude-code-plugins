// The workflows that resolve a model route for a reusable lane. Contract: the
// review callers read the models block from the default branch, never the PR
// head, so a PR cannot choose the model through its own pr-pipeline.yaml
// (the caller workflow itself stays editable in a same-repo PR); a failed resolution
// leaves the review on the reusable's defaults; intake never runs without
// resolved arguments; and each sparse checkout holds what this action loads.
// Also: pr-unblock.yml leaves address-feedback and publish-feedback checks on
// the head whether or not its model and reply jobs run, and a fix-ci check when
// fix-ci-context skips, and
// work-resolve-issue.yml caps its concurrent runs.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

import Ajv2020 from "ajv/dist/2020.js";
import { parse } from "yaml";

import { loadRules, rowFor, select as selectPatch } from "../../scripts/apply-patch/apply-patch.mjs";
import { DEFAULTS as CI_FIX_DEFAULTS, skipReason } from "../../scripts/pr-unblock/fix-ci-dispatch.mjs";
import { VERDICTS } from "../../scripts/pr-unblock/review-dependency.mjs";
import { main as checkTrustedTrigger } from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { generate as generateCarrierKey } from "../open-lane-output/keygen.mjs";
import { decide } from "../report-check-run/decide.mjs";
import { main as reportCheckRun } from "../report-check-run/report-check-run.mjs";

const read = (relative) => readFileSync(new URL(relative, import.meta.url), "utf8");
const workflow = (name) => parse(read(`../../workflows/${name}`));
const RESOLVE = "./.base/.github/actions/resolve-config";

// Sibling action directories this action's modules import, followed
// transitively: the sparse checkout must hold each of them.
function importedActionDirs() {
  const actions = new URL("../", import.meta.url);
  const files = new Set(["resolve-config/resolve-config.mjs"]);
  for (const file of files) {
    for (const [, spec] of read(`../${file}`).matchAll(/from "(\.{1,2}\/[^"]+)"/g)) {
      files.add(new URL(spec, new URL(file, actions)).pathname.slice(actions.pathname.length));
    }
  }
  return [...new Set([...files].map((file) => `/.github/actions/${file.split("/")[0]}/`))];
}

const BASE_FILES = [
  "/.github/CODEOWNERS",
  "/.github/standards/github-actions-conventions/vocabulary.json",
  "/.node-version",
  "/docs/conventions/pr-pipeline.yaml",
  "/docs/conventions/pr-pipeline/",
];

function assertSparseHoldsResolver(checkout) {
  const sparse = checkout.with["sparse-checkout"].trim().split("\n");
  for (const path of [...importedActionDirs(), ...BASE_FILES]) {
    assert.ok(sparse.includes(path), `sparse checkout lacks ${path}`);
  }
}

const runRefusal = (step, settingsJson) =>
  spawnSync("bash", ["-c", step.run], { env: { ...process.env, SETTINGS_JSON: settingsJson } }).status;

// Evaluates a workflow expression in a run that was not cancelled, with each
// context reference replaced by its value. Covers only the operators these
// callers use (&&, ||, ==, !=, !), which JavaScript evaluates the same way
// for the string and boolean operands here.
function evaluate(expression, context) {
  let body = expression.trim().replace(/^\$\{\{([\s\S]*)\}\}$/, "$1").replaceAll("!cancelled()", "true").replaceAll("always()", "true");
  for (const [name, value] of Object.entries(context)) {
    body = body.replaceAll(name, JSON.stringify(value));
  }
  assert.doesNotMatch(body, /[A-Za-z_][\w-]*\.[\w.-]+/, `an unresolved context reference in ${body}`);
  return Function(`return (${body});`)();
}

// The secret names one step or job references, sorted.
const stepSecrets = (node) => [...new Set([...JSON.stringify(node).matchAll(/secrets\.([\w-]+)/g)].map((m) => m[1]))].sort();

const SUBAGENT = '{"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"haiku"}}';
const ARGS = "--model sonnet --max-turns 75 --effort high";

for (const [file, job, route, laneSwitch] of [
  ["pr-review-hosted.yml", "pr-review", "review-code", "CLAUDE_REVIEW_DISABLED"],
  ["pr-review-security-hosted.yml", "pr-review-security", "review-security", "CLAUDE_SECURITY_REVIEW_DISABLED"],
]) {
  const { jobs } = workflow(file);
  const resolver = jobs["resolve-model"];
  const steps = resolver?.steps ?? [];
  const checkout = steps.find((step) => step.uses?.startsWith("actions/checkout@"));
  const resolve = steps.find((step) => step.uses?.startsWith(RESOLVE));
  const refusal = steps.find((step) => step.env?.SETTINGS_JSON !== undefined);

  test(`${file}: resolve-model reads the default branch with a read-only token`, () => {
    assert.deepEqual(resolver.permissions, { contents: "read" });
    assert.equal(checkout.with.ref, "refs/heads/main");
    assert.equal(checkout.with.path, ".base");
    assert.equal(checkout.with["persist-credentials"], false);
    assert.equal(resolve.with["model-route"], route);
    assert.equal(resolver.outputs["claude-args"], `\${{ steps.${resolve.id}.outputs.claude-args }}`);
    assertSparseHoldsResolver(checkout);
  });

  test(`${file}: resolve-model fails on a subagent model and passes without one`, () => {
    assert.equal(refusal.env.SETTINGS_JSON, `\${{ steps.${resolve.id}.outputs.settings-json }}`);
    assert.notEqual(runRefusal(refusal, SUBAGENT), 0);
    assert.equal(runRefusal(refusal, ""), 0);
  });

  test(`${file}: the review runs after a failed resolve-model, on the reusable's defaults`, () => {
    const review = jobs[job];
    assert.deepEqual(review.needs, ["resolve-model", "kill-switch"]);
    for (const result of ["success", "failure", "skipped"]) {
      const context = {
        "github.event.pull_request.draft": false,
        "needs.kill-switch.outputs.proceed": "true",
        "needs.resolve-model.result": result,
        "needs.resolve-model.outputs.claude-args": result === "success" ? ARGS : "",
      };
      assert.equal(evaluate(review.if, context), true, `a ready PR is reviewed when resolve-model is ${result}`);
      assert.equal(
        evaluate(review.if, { ...context, "github.event.pull_request.draft": true }),
        false,
        `a draft is not reviewed when resolve-model is ${result}`,
      );
      assert.equal(evaluate(review.with["model-args"], context), result === "success" ? ARGS : "");
    }
    // A failed job's output, if GitHub kept it, never reaches the review.
    const failed = {
      "needs.resolve-model.result": "failure",
      "needs.resolve-model.outputs.claude-args": ARGS,
    };
    assert.equal(evaluate(review.with["model-args"], failed), "");
  });

  test(`${file}: the review runs only when the kill-switch job says proceed`, () => {
    const review = jobs[job];
    const gate = jobs["kill-switch"];
    assertKillSwitchJob(gate);
    for (const proceed of ["true", "false", ""]) {
      const context = {
        "github.event.pull_request.draft": false,
        "needs.kill-switch.outputs.proceed": proceed,
      };
      assert.equal(evaluate(review.if, context), proceed === "true", `proceed=${JSON.stringify(proceed)}`);
    }
    // The org and repository switches fail closed in the action; the lane's
    // own switch stops the review only at `true` (github-iac README).
    const proceeds = (lanes, lane) =>
      evaluate(gate.outputs.proceed, { "steps.kill.outputs.proceed": lanes, [`vars.${laneSwitch}`]: lane });
    assert.equal(proceeds("true", "false"), "true");
    assert.equal(proceeds("true", ""), "true", "an unset lane switch leaves the review running");
    assert.equal(proceeds("true", "true"), "false");
    assert.equal(proceeds("false", "false"), "false");
    assert.equal(proceeds("", "false"), "false", "an unreadable lanes switch stops the review");
  });
}

// The kill-switch job reads the action from the default branch with a
// read-only token and passes it the org and repository switches.
function assertKillSwitchJob(gate) {
  assert.deepEqual(gate.permissions, { contents: "read" });
  const checkout = gate.steps.find((step) => step.uses?.startsWith("actions/checkout@"));
  assert.equal(checkout.with.ref, "refs/heads/main");
  assert.equal(checkout.with["persist-credentials"], false);
  assert.ok(checkout.with["sparse-checkout"].split("\n").includes("/.github/actions/check-kill-switch/"));
  const kill = gate.steps.find((step) => step.uses?.startsWith("./.base/.github/actions/check-kill-switch"));
  assert.equal(kill.id, "kill");
  assert.equal(kill["continue-on-error"], undefined);
  assert.deepEqual(kill.with, {
    value: "${{ vars.CLAUDE_LANES_DISABLED }}",
    "repo-value": "${{ vars.CLAUDE_LANES_REPO_DISABLED }}",
  });
}

test("intake-triage.yml: intake runs only with claude-args resolved from triage-issue", () => {
  const { jobs } = workflow("intake-triage.yml");
  const gate = jobs["born-triaged"];
  const checkout = gate.steps.find((step) => step.uses?.startsWith("actions/checkout@"));
  const resolve = gate.steps.find((step) => step.uses?.startsWith(RESOLVE));
  assert.equal(checkout.with.ref, undefined, "an issues event checks out the default branch");
  assert.equal(resolve.with["model-route"], "triage-issue");
  assertSparseHoldsResolver(checkout);
  assert.equal(
    gate.outputs["claude-args"],
    `\${{ steps.${resolve.id}.outputs.settings-json == '' && steps.${resolve.id}.outputs.claude-args || '' }}`,
  );
  const refusal = gate.steps.find((step) => step.env?.SETTINGS_JSON !== undefined);
  assert.equal(refusal.env.SETTINGS_JSON, `\${{ steps.${resolve.id}.outputs.settings-json }}`);
  assert.notEqual(runRefusal(refusal, SUBAGENT), 0);
  assert.equal(runRefusal(refusal, ""), 0);

  const intake = jobs["intake-triage"];
  assert.match(intake.if, /&& needs\.born-triaged\.outputs\.claude-args != '' \}\}$/);
  const runs = (skip, claudeArgs, event = "issues", proceed = "true") =>
    evaluate(intake.if, {
      "github.event_name": event,
      "needs.born-triaged.outputs.skip": skip,
      "needs.born-triaged.outputs.claude-args": claudeArgs,
      "needs.kill-switch.outputs.proceed": proceed,
    });
  const args = "--model sonnet --max-turns 30 --effort medium";
  assert.equal(runs("", args), true, "a failed or false born-triaged check falls through to the reusable's gate");
  assert.equal(runs("false", args), true);
  assert.equal(runs("true", args), false, "a born-triaged issue skips intake");
  assert.equal(runs("true", args, "workflow_dispatch"), true, "a dispatch triages a born-triaged issue");
  assert.equal(runs("", ""), false, "intake never runs without resolved claude-args");
  assert.equal(runs("false", ""), false);
  assert.equal(runs("true", "", "workflow_dispatch"), false, "a dispatch never runs without resolved claude-args");
  assert.equal(runs("false", args, "issues", "false"), false, "the kill switch stops intake");
  assert.equal(runs("false", args, "workflow_dispatch", ""), false, "a failed kill-switch job stops intake");
  assert.equal(intake.with["claude-args"], "${{ needs.born-triaged.outputs.claude-args }}");
  assert.deepEqual(intake.needs, ["born-triaged", "kill-switch"]);
  const killSwitch = jobs["kill-switch"];
  assertKillSwitchJob(killSwitch);
  assert.equal(killSwitch.if, jobs["born-triaged"].if, "the kill switch runs wherever the gate runs");
  assert.equal(killSwitch.outputs.proceed, "${{ steps.kill.outputs.proceed }}");
});

test("intake-triage.yml: a dispatch runs only from main and passes the gate's ids", () => {
  const { jobs } = workflow("intake-triage.yml");
  const gate = jobs["born-triaged"];
  const runsOn = (event, ref) => evaluate(gate.if, { "github.event_name": event, "github.ref": ref });
  assert.equal(runsOn("issues", "refs/heads/main"), true);
  assert.equal(runsOn("workflow_dispatch", "refs/heads/main"), true);
  assert.equal(runsOn("workflow_dispatch", "refs/heads/feature"), false, "a dispatch from a branch reads no branch's trusted-actor list");

  const intake = jobs["intake-triage"];
  assert.equal(intake.with["allowed-author-ids"], "${{ needs.born-triaged.outputs.human-ids }}");
  assert.equal(intake.with["allowed-bot-sender-ids"], "${{ needs.born-triaged.outputs.bot-ids }}");
  assert.equal(intake.with["issue-number"], "${{ inputs.issue-number }}");

  const bots = gate.steps.find((step) => step.id === "bots");
  assert.equal(gate.outputs["bot-ids"], "${{ steps.bots.outputs.ids }}");
  const dir = mkdtempSync(join(tmpdir(), "bot-ids-"));
  try {
    const ids = (lanesAppId) => {
      const output = join(dir, "output");
      writeFileSync(output, "");
      const result = spawnSync("bash", ["-c", bots.run], {
        env: { ...process.env, LANES_APP_ID: lanesAppId, GITHUB_OUTPUT: output },
      });
      assert.equal(result.status, 0);
      return readFileSync(output, "utf8");
    };
    assert.equal(ids(""), "ids=41898282\n");
    assert.equal(ids("123456"), "ids=41898282,123456\n");
    assert.equal(ids("12a; echo x"), "ids=41898282\n", "a malformed lanes App id is dropped");
    assert.equal(ids("0"), "ids=41898282\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("intake-triage.yml: apply-verdict writes as the lanes App only after a triage that ran, for the issue it triaged", () => {
  const { jobs } = workflow("intake-triage.yml");
  const job = jobs["apply-verdict"];
  assert.deepEqual(job.needs, ["born-triaged", "intake-triage"]);
  assert.deepEqual(job.permissions, { contents: "read", "id-token": "write" });
  const minting = Object.entries(jobs)
    .filter(([, j]) => j.permissions?.["id-token"] !== undefined || j.permissions === "write-all")
    .map(([id]) => id);
  assert.deepEqual(minting, ["apply-verdict", "apply-refinement"], "only the two script writers can request an OIDC token");
  assert.deepEqual(workflow("intake-triage.yml").permissions, {}, "no workflow-level grant");
  assert.equal(job.concurrency["cancel-in-progress"], false);
  assert.notEqual(job.concurrency.group, jobs["intake-triage"].concurrency.group, "its own concurrency group");
  const runs = (result, failed) => evaluate(job.if, { "needs.intake-triage.result": result, "needs.intake-triage.outputs.triage-failed": failed });
  assert.equal(runs("success", "false"), true);
  assert.equal(runs("success", ""), true);
  assert.equal(runs("success", "true"), false, "a triage that did not run writes nothing");
  assert.equal(runs("failure", "false"), false, "a failed apply writes nothing");
  assert.equal(runs("skipped", ""), false);

  const gate = jobs["born-triaged"];
  assert.equal(gate.outputs["started-at"], "${{ steps.started.outputs.at }}");
  assert.equal(gate.steps[0].id, "started", "the start time is taken before the triage runs");

  const step = (id) => job.steps.find((s) => s.id === id);
  const checkout = job.steps.find((s) => s.uses?.startsWith("actions/checkout@"));
  assert.equal(checkout.with.ref, "refs/heads/main");
  assert.equal(step("who").if, "steps.kill.outputs.proceed == 'true'");
  assert.match(step("who").run, /apply-verdict\.mjs --check$/);
  assert.equal(step("config").if, "steps.who.outputs.proceed == 'true'");
  assert.equal(step("config").with.lane, "intake-triage");
  assert.equal(step("config").with.activity, "apply-verdict");
  const token = step("lane-token");
  assert.equal(token.with.lane, "intake-triage");
  assert.equal(token.with.activity, "apply-verdict");
  assert.equal(token.with["issue-number"], "${{ format('{0}', github.event.issue.number || inputs.issue-number) }}");
  assert.equal(token.with["pr-number"], undefined);
  const write = job.steps.find((s) => s.name === "Write the verdict");
  assert.equal(write.env.GH_TOKEN, "${{ steps.lane-token.outputs.token }}");
  assert.equal(write.env.STARTED_AT, "${{ needs.born-triaged.outputs.started-at }}");
  assert.equal(write.env.KILL_SWITCH, "${{ steps.kill.outputs.proceed == 'true' && 'proceed' || '' }}");
  assert.equal(write.run, 'node ".base/$SCRIPT"');
  assert.deepEqual(stepSecrets(job), []);
});

test("intake-triage.yml: a thin issue's refinement runs its model with no write token and writes through the lanes App only", () => {
  const { jobs } = workflow("intake-triage.yml");
  const select = jobs["refine-select"];
  const model = jobs["refine-issue"];
  const apply = jobs["apply-refinement"];
  const again = jobs["redispatch-refined"];
  assert.deepEqual(select.permissions, { contents: "read", issues: "read", "pull-requests": "read" });
  assert.deepEqual(model.permissions, { contents: "read" }, "the model job holds no write grant");
  assert.deepEqual(apply.permissions, { contents: "read", "id-token": "write" });
  assert.deepEqual(again.permissions, { actions: "write" }, "the dispatch grant is not on the job with the App token");
  assert.deepEqual(select.needs, ["born-triaged", "apply-verdict"]);
  assert.deepEqual(model.needs, ["refine-select"]);
  assert.deepEqual(apply.needs, ["born-triaged", "refine-select", "refine-issue"]);
  assert.deepEqual(again.needs, ["apply-refinement"]);

  const groups = Object.values(jobs)
    .map((job) => job.concurrency?.group)
    .filter(Boolean);
  assert.equal(new Set(groups).size, groups.length, "each job has its own concurrency group");
  for (const job of [select, model, apply]) {
    assert.equal(job.concurrency["cancel-in-progress"], false);
  }

  assert.equal(evaluate(select.if, { "needs.apply-verdict.result": "success" }), true);
  assert.equal(evaluate(select.if, { "needs.apply-verdict.result": "failure" }), false);
  assert.equal(evaluate(model.if, { "needs.refine-select.outputs.refine": "true" }), true);
  assert.equal(evaluate(model.if, { "needs.refine-select.outputs.refine": "false" }), false);
  assert.equal(evaluate(apply.if, { "needs.refine-issue.result": "success" }), true);
  assert.equal(evaluate(apply.if, { "needs.refine-issue.result": "skipped" }), false);
  assert.equal(evaluate(again.if, { "needs.apply-refinement.outputs.redispatch": "true" }), true);
  assert.equal(evaluate(again.if, { "needs.apply-refinement.outputs.redispatch": "" }), false);

  // Every checkout is the default branch without credentials.
  for (const job of [select, model, apply]) {
    const checkout = job.steps.find((s) => s.uses?.startsWith("actions/checkout@"));
    assert.equal(checkout.with.ref, "refs/heads/main");
    assert.equal(checkout.with["persist-credentials"], false);
  }

  // The model step: no project settings, an explicit permission mode, and
  // no tool that writes or runs code.
  const run = model.steps.find((s) => s.uses?.startsWith("anthropics/claude-code-action@"));
  const args = run.with.claude_args;
  assert.match(args, /--setting-sources user/);
  assert.match(args, /--permission-mode dontAsk/);
  assert.doesNotMatch(JSON.stringify(model), /bypassPermissions|dangerously/);
  const prompt = model.steps.find((s) => s.id === "prompt").run;
  assert.match(prompt, /denied="Bash,Edit,Write,NotebookEdit,WebSearch,Agent,Skill"/);
  assert.match(prompt, /mcp__github,mcp__github_comment,mcp__github_file_ops,mcp__github_ci,mcp__github_inline_comment/);
  assert.match(prompt, /WebFetch\(domain:\$domain\)/);
  assert.deepEqual(stepSecrets(model), ["INTAKE_CLAUDE_CODE_OAUTH_TOKEN"]);
  for (const job of [select, apply, again]) {
    assert.deepEqual(stepSecrets(job), []);
  }

  const step = (job, id) => job.steps.find((s) => s.id === id);
  assert.match(step(select, "who").run, /apply-verdict\.mjs --check$/);
  assert.match(step(apply, "who").run, /apply-verdict\.mjs --check$/);
  assert.equal(step(apply, "config").with.activity, "apply-refinement");
  const token = step(apply, "lane-token");
  assert.equal(token.with.lane, "intake-triage");
  assert.equal(token.with.activity, "apply-refinement");
  assert.equal(token.with["issue-number"], "${{ format('{0}', github.event.issue.number || inputs.issue-number) }}");
  assert.equal(step(apply, "apply").run, 'node ".base/$SCRIPT" --apply');
  // Select and apply read the admission rules and web hosts the split uses
  // from the default branch, and the model must return the split field.
  assert.equal(step(select, "select").env.BASE_PATH, ".base");
  assert.equal(step(apply, "apply").env.BASE_PATH, ".base");
  assert.match(prompt, /"required":\["exact","outcome","criteria","dependencies","related","questions","sources","split"\]/);
});

test("intake-triage.yml: the model may not apply good first issue or help wanted, and is told the verdict lines", () => {
  const intake = workflow("intake-triage.yml").jobs["intake-triage"];
  const allowed = intake.with["allowed-labels"].trim().split("\n");
  assert.ok(!allowed.includes("good first issue") && !allowed.includes("help wanted"));
  for (const line of ["Size: Small|Medium|Large", "Complexity: Low|Medium|High", "Uncertainty: Known|Knowable|Unknown", "Flags: none|intent|security|cost"]) {
    assert.ok(intake.with.instructions.includes(`\n${line}\n`), line);
  }
});

test("pr-unblock.yml: report-conflict-status runs only for an unresolved-conflict escalation, from the select, push or scan-refusal job, with a gated head", () => {
  const head = "c".repeat(40);
  const { jobs } = workflow("pr-unblock.yml");
  const job = jobs["report-conflict-status"];
  const context = (select, apply, headSha, refused = "") => ({
    "needs.resolve-conflicts-select.outputs.escalation-reason": select,
    "needs.apply-conflict-patch.outputs.escalation-reason": apply,
    "needs.conflict-scan-refusal.outputs.escalation-reason": refused,
    "needs.resolve-conflicts-select.outputs.head-sha": headSha,
  });
  assert.deepEqual(job.needs, ["resolve-conflicts-select", "apply-conflict-patch", "conflict-scan-refusal"]);
  assert.equal(evaluate(job.if, context("unresolved-conflict", "", head)), true, "before any model turn");
  assert.equal(evaluate(job.if, context("", "unresolved-conflict", head)), true, "a conflict the patch left");
  assert.equal(evaluate(job.if, context("", "", head, "unresolved-conflict")), true, "a scan that refused the model's output");
  for (const reason of ["repeat-cap", "protected-path-conflict", "workflow-staged", "conflict-patch-invalid", ""]) {
    assert.equal(evaluate(job.if, context(reason, "", head)), false, reason);
    assert.equal(evaluate(job.if, context("", reason, head)), false, reason);
  }
  assert.equal(evaluate(job.if, context("", "", "", "unresolved-conflict")), false, "no gated head to post on");
  assert.equal(evaluate(job.if, context("unresolved-conflict", "", "")), false, "no gated head to post on");
  // The head is the select job's, never a model call's.
  const post = job.steps.find((step) => step.name === "Post the conflict status");
  assert.equal(post.env.HEAD_SHA, "${{ needs.resolve-conflicts-select.outputs.head-sha }}");
  assert.equal(post.env.ESCALATION_REASON, "unresolved-conflict");
  assert.deepEqual(job.permissions, { contents: "read", statuses: "write" });
  assert.equal(job.uses, undefined, "a script job, never the write runner");
});

// Runs 39184851924 and 39184853452: fix-ci's job group rendered to its own
// run's group, pr-unblock-fix-ci-<pr>, and the job never started.
test("pr-unblock.yml: no job's concurrency group is its own run's group", () => {
  const { on, concurrency, jobs } = workflow("pr-unblock.yml");
  const render = (group, activity) =>
    group.replaceAll("${{ inputs.activity }}", activity).replaceAll("${{ inputs.pr-number }}", "7923");
  for (const activity of on.workflow_dispatch.inputs.activity.options) {
    const runGroup = render(concurrency.group, activity);
    for (const [id, job] of Object.entries(jobs)) {
      if (job.concurrency) assert.notEqual(render(job.concurrency.group, activity), runGroup, `${id} (${activity})`);
    }
  }
  // fix-ci still runs one at a time per PR, a running one never cancelled.
  assert.equal(render(concurrency.group, "fix-ci"), "pr-unblock-fix-ci-7923");
  assert.equal(concurrency["cancel-in-progress"], false);
});

// address-feedback-select's proceed is "true" once its context is uploaded,
// "false" on a skip or an escalation, and empty when it stopped before deciding
// (a kill-switch stop, which also reads no head).
test("pr-unblock.yml: address-feedback and publish-feedback are reported neutral when the select job proceeds with nothing", async () => {
  const head = "c".repeat(40);
  const { jobs } = workflow("pr-unblock.yml");
  const notRun = jobs["address-feedback-not-run"];
  const context = (proceed, headSha, skip = "", activity = "address-feedback") => ({
    "inputs.activity": activity,
    "needs.address-feedback-select.outputs.proceed": proceed,
    "needs.address-feedback-select.outputs.head-sha": headSha,
    "needs.address-feedback-select.outputs.skip-reason": skip,
  });
  assert.deepEqual([notRun.needs].flat(), ["address-feedback-select"]);
  for (const id of ["address-feedback", "publish-feedback"]) {
    assert.equal(evaluate(jobs[id].if, context("true", head)), true, id);
    assert.equal(evaluate(jobs[id].if, context("false", head)), false, id);
    assert.equal(evaluate(jobs[id].if, context("", "")), false, `${id} after a kill-switch stop`);
  }
  assert.equal(evaluate(notRun.if, context("true", head)), false);
  assert.equal(evaluate(notRun.if, context("false", head, "not-applicable")), true);
  assert.equal(evaluate(notRun.if, context("false", "")), false, "a stop before the head read names no head to post on");
  assert.equal(evaluate(notRun.if, context("", "")), false);
  assert.equal(evaluate(notRun.if, context("false", head, "", "resolve-conflicts")), false);

  // Both checks, each neutral with the select job's skip reason; an
  // escalation's skip reason is awaiting-human, and none falls back to it.
  for (const [skip, summary] of [
    ["not-applicable", "Skip reason: not-applicable"],
    ["awaiting-human", "Skip reason: awaiting-human"],
    ["", "Skip reason: awaiting-human"],
  ]) {
    const calls = await postNotRunChecks(notRun, context("false", head, skip));
    assert.deepEqual(
      calls.map((call) => [call.name, call.head_sha, call.conclusion, call.output.summary]),
      [
        ["pr-unblock / address-feedback", head, "neutral", summary],
        ["pr-unblock / publish-feedback", head, "neutral", summary],
      ],
      JSON.stringify(skip),
    );
  }
});

// fix-ci's one retry one model rung up runs inside the same pr-unblock run,
// so whatever it ends in reaches report-escalation: only a clean apply of
// the retry's patch leaves the PR unlabeled.
const ESCALATING = ["resolve-conflicts-select", "apply-conflict-patch", "conflict-scan-refusal", "address-feedback-select", "publish-feedback", "review-dependency-select", "apply-dependency-verdict", "fix-ci-context", "apply-patch"];
const rungUpContext = ({ rungUp = "true", result = "success", escalation = "", skip = "" } = {}) => ({
  ...Object.fromEntries(ESCALATING.map((job) => [`needs.${job}.outputs.escalation-reason`, ""])),
  "needs.apply-patch.outputs.rung-up": rungUp,
  "needs.apply-patch-rung-up.result": result,
  "needs.apply-patch-rung-up.outputs.escalation-reason": escalation,
  "needs.apply-patch-rung-up.outputs.patch-skip-reason": skip,
});

test("pr-unblock.yml: a rung-up stop runs fix-ci and apply-patch again at model-rung 1 in the same run", () => {
  const { jobs } = workflow("pr-unblock.yml");
  const up = jobs["fix-ci-rung-up"];
  const upSubscription = jobs["fix-ci-rung-up-subscription"];
  const apply = jobs["apply-patch-rung-up"];
  const gate = { "needs.apply-patch.outputs.rung-up": "true", "needs.fix-ci-context.outputs.proceed": "true" };
  assert.equal(evaluate(up.if, gate), true);
  assert.equal(evaluate(up.if, { ...gate, "needs.apply-patch.outputs.rung-up": "false" }), false);
  assert.equal(evaluate(up.if, { ...gate, "needs.apply-patch.outputs.rung-up": "" }), false);
  assert.equal(up.with["model-rung"], "1");
  assert.equal(upSubscription.with["model-rung"], "1");
  assert.equal(apply.with["patch-model-rung"], "1");
  // The first pass runs at rung 0: no rung input, so a dispatch cannot skip it.
  assert.equal(jobs["fix-ci"].with["model-rung"], undefined);
  assert.equal(jobs["apply-patch"].with["patch-model-rung"], undefined);
  assert.equal(workflow("pr-unblock.yml").on.workflow_dispatch.inputs["model-rung"], undefined);
});

for (const [why, given, want] of [
  ["the retry ends neutral or cancelled before a patch", { result: "skipped" }, "ci-fix-escalated"],
  ["the retry's apply-patch fails", { result: "failure" }, "ci-fix-escalated"],
  ["the retry's apply-patch is cancelled", { result: "cancelled" }, "ci-fix-escalated"],
  ["the retry escalates", { escalation: "ci-fix-escalated" }, "ci-fix-escalated"],
  ["the retry's patch is invalid", { escalation: "ci-fix-invalid" }, "ci-fix-invalid"],
  ["the retry's apply-patch skips", { skip: "superseded-sha" }, "ci-fix-escalated"],
]) {
  test(`pr-unblock.yml: ${why} hands the PR to a person as ${want}`, () => {
    const job = workflow("pr-unblock.yml").jobs["report-escalation"];
    const context = rungUpContext(given);
    assert.equal(evaluate(job.if, context), true);
    assert.equal(evaluate(job.with["escalation-reason"], context), want);
  });
}

test("pr-unblock.yml: a retry that applies cleanly, or no rung-up stop, escalates nothing", () => {
  const job = workflow("pr-unblock.yml").jobs["report-escalation"];
  assert.equal(evaluate(job.if, rungUpContext()), false);
  assert.equal(evaluate(job.if, rungUpContext({ rungUp: "false", result: "skipped" })), false);
  assert.equal(evaluate(job.if, rungUpContext({ rungUp: "", result: "skipped" })), false);
});

// Both fix-ci passes upload in one workflow run, so the rung-1 pass's
// artifacts carry their own name.
test("pr-run-activity-read.yml: every artifact a model run uploads is named by its rung", () => {
  const text = read("../../workflows/pr-run-activity-read.yml");
  for (const kind of ["skill-reply", "patch", "verdict"]) {
    const names = [...text.matchAll(new RegExp(`name: (${kind}-\\$\\{\\{ inputs\\.lane \\}\\}.*)$`, "gm"))].map((match) => match[1]);
    assert.ok(names.length > 0, kind);
    for (const name of names) {
      assert.match(name, /inputs\.model-rung == '1'/, name);
    }
  }
});

// A fix-ci-context skip with no fix-ci check on the head would let the
// dispatcher send the same head again on every run.
test("pr-unblock.yml: fix-ci is reported neutral when fix-ci-context skips, and the dispatcher counts it", async () => {
  const head = "d".repeat(40);
  const { jobs } = workflow("pr-unblock.yml");
  const fixCi = jobs["fix-ci"];
  const notRun = jobs["fix-ci-not-run"];
  // fix-ci-context.mjs writes proceed "true" or "false"; a kill-switch stop
  // skips its step and leaves every output empty.
  const context = (proceed, escalation, headSha, activity = "fix-ci", skip = "") => ({
    "inputs.activity": activity,
    "needs.fix-ci-context.outputs.proceed": proceed,
    "needs.fix-ci-context.outputs.escalation-reason": escalation,
    "needs.fix-ci-context.outputs.head-sha": headSha,
    "needs.fix-ci-context.outputs.skip-reason": skip,
  });
  assert.equal(evaluate(fixCi.if, context("true", "", head)), true);
  assert.equal(evaluate(notRun.if, context("true", "", head)), false);
  assert.equal(evaluate(notRun.if, context("false", "", head)), true);
  assert.equal(evaluate(notRun.if, context("false", "ci-fix-round-cap", head)), false, "report-escalation owns it");
  assert.equal(evaluate(notRun.if, context("", "", "")), false, "a kill-switch stop names no head");
  assert.equal(evaluate(notRun.if, context("", "", "", "resolve-conflicts")), false);

  const calls = await postNotRunCheck(notRun, context("false", "", head));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "pr-unblock / fix-ci");
  assert.equal(calls[0].head_sha, head);
  assert.equal(calls[0].conclusion, "neutral");
  assert.equal(calls[0].output.summary, "Skip reason: not-applicable");
  // A human-gated hold fix-ci-context read posts awaiting-human instead.
  const held = await postNotRunCheck(notRun, context("false", "", head, "fix-ci", "awaiting-human"));
  assert.equal(held[0].output.title, "Skipped: awaiting-human");

  // fix-ci-dispatch.mjs dispatches a head with no fix-ci check run; the
  // posted one, as the listing returns it, means the head was handled.
  const appSenderId = 7;
  const node = {
    number: 8171,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: head,
    author: { databaseId: appSenderId },
    labels: { nodes: [] },
    commits: {
      nodes: [
        {
          commit: {
            oid: head,
            statusCheckRollup: {
              contexts: {
                nodes: [
                  { name: "ci-status", status: "COMPLETED", conclusion: "FAILURE" },
                  {
                    name: calls[0].name,
                    status: calls[0].status.toUpperCase(),
                    conclusion: calls[0].conclusion.toUpperCase(),
                    title: calls[0].output.title,
                    completedAt: "2026-10-22T10:00:00Z",
                  },
                ]
                  .map((run) => ({ __typename: "CheckRun", checkSuite: { app: { databaseId: 15368 } }, ...run }))
                  .concat({ __typename: "StatusContext", context: "ci-lanes", state: "FAILURE", creator: { __typename: "Bot", login: "github-actions", databaseId: 41898282 } }),
                pageInfo: { hasNextPage: false },
              },
            },
          },
        },
      ],
    },
  };
  const options = { ...CI_FIX_DEFAULTS, appSenderId, restarts: 1 };
  assert.equal(skipReason(node, options), "head's pr-unblock / fix-ci found no failing check on this base");
  // Once the base tip moves past it, the head is dispatched again.
  assert.equal(skipReason(node, { ...options, baseAt: Date.parse("2026-10-22T11:00:00Z") }), "");
});

// Runs a not-run job's report-check-run step, its inputs reaching
// report-check-run.mjs through the action's env map; returns the POST bodies.
async function postNotRunCheck(job, context, step = job.steps.find((s) => s.uses === "./.base/.github/actions/report-check-run")) {
  const action = parse(read("../report-check-run/action.yml"));
  const values = { ...context, "github.token": "test-token" };
  const env = {};
  for (const [name, value] of Object.entries(action.runs.steps[0].env)) {
    const input = value.match(/^\$\{\{ inputs\.([\w-]+) \}\}$/)[1];
    const given = step.with[input] ?? action.inputs[input].default ?? "";
    env[name] = /^\$\{\{/.test(given) ? evaluate(given, values) : String(given);
  }
  const calls = [];
  const code = await reportCheckRun({
    env: {
      ...env,
      BASE_PATH: fileURLToPath(new URL("../../../", import.meta.url)),
      GITHUB_REPOSITORY: "melodic-software/claude-code-plugins",
      GITHUB_API_URL: "https://api.example.test",
    },
    fetchImpl: async (_url, init) => {
      calls.push(JSON.parse(init.body));
      return new Response(JSON.stringify({ id: 1 }), { status: 201 });
    },
    log: () => {},
  });
  assert.equal(code, 0);
  return calls;
}

// Every report-check-run step of a not-run job, in order.
async function postNotRunChecks(job, context) {
  const calls = [];
  for (const step of job.steps.filter((s) => s.uses === "./.base/.github/actions/report-check-run")) {
    calls.push(...(await postNotRunCheck(job, context, step)));
  }
  return calls;
}

// GitHub runs at most one job per concurrency group, and `queue: max` keeps
// the rest waiting instead of cancelling them (workflow-syntax#concurrency),
// so the number of distinct slot groups is the cap: 3.
test("work-resolve-issue.yml: at most 3 resolve-issue runs at once, the rest queued", () => {
  const { concurrency, jobs } = workflow("work-resolve-issue.yml");
  const pick = jobs["pick-slot"];
  const resolve = jobs["resolve-issue"];
  const step = pick.steps.find((s) => s.id === "slot");
  const dir = mkdtempSync(join(tmpdir(), "slot-"));
  after(() => rmSync(dir, { recursive: true, force: true }));
  const output = join(dir, "output");
  const slotOf = (issue) => {
    writeFileSync(output, "");
    const run = spawnSync("bash", ["-c", step.run], {
      env: { ...process.env, SLOTS: String(pick.env.SLOTS), ISSUE_NUMBER: issue, GITHUB_OUTPUT: output },
    });
    return run.status === 0 ? readFileSync(output, "utf8").trim().replace(/^slot=/, "") : null;
  };
  assert.equal(slotOf("7"), "1");
  assert.equal(slotOf("9"), "0");
  assert.equal(slotOf("3001"), "1");
  assert.equal(slotOf("7 + 1"), null, "an issue number that is not digits picks no slot");

  assert.equal(pick.outputs.slot, `\${{ steps.${step.id}.outputs.slot }}`);
  assert.deepEqual(resolve.needs, ["admit", "pick-slot"]);
  assert.equal(resolve.concurrency.queue, "max");
  assert.notEqual(resolve.concurrency["cancel-in-progress"], true, "GitHub rejects queue: max with cancel-in-progress");
  const groups = new Set(
    Array.from({ length: 60 }, (_, i) =>
      resolve.concurrency.group.replace("${{ needs.pick-slot.outputs.slot }}", slotOf(String(i + 1))),
    ),
  );
  assert.deepEqual([...groups].sort(), [0, 1, 2].map((n) => `work-resolve-issue-slot-${n}`));

  // A label other than agent-ready starts neither job, so it holds no runner.
  for (const [label, runs] of [["agent-ready", true], ["bug", false]]) {
    const context = { "github.event.label.name": label, "needs.admit.outputs.proceed": "true", "needs.pick-slot.outputs.capped": "false" };
    assert.equal(evaluate(pick.if, context), runs, label);
    assert.equal(evaluate(resolve.if, context), runs, label);
  }
  // At the WIP cap resolve-issue takes no slot; a cap check that failed or
  // set nothing starts it.
  assert.equal(pick.outputs.capped, "${{ steps.wip.outputs.capped }}");
  for (const [capped, runs] of [["true", false], ["false", true], ["", true]]) {
    const context = { "github.event.label.name": "agent-ready", "needs.admit.outputs.proceed": "true", "needs.pick-slot.outputs.capped": capped };
    assert.equal(evaluate(resolve.if, context), runs, `capped ${JSON.stringify(capped)}`);
  }
  const wip = pick.steps.find((item) => item.id === "wip");
  assert.equal(wip["continue-on-error"], true, "a failed cap check must start the run");
  // The per-issue run group still dedupes: one agent-ready run per issue.
  assert.equal(
    concurrency.group,
    "work-resolve-issue-${{ github.event.issue.number }}-${{ github.event.label.name == 'agent-ready' }}",
  );
  assert.equal(concurrency["cancel-in-progress"], false);
});

// The run job's timeout is the issue size's (models.issue-dimensions), resolved
// from the base config before the job starts; no literal stands in for it.
test("work-resolve-issue.yml: resolve-issue's timeout is the resolved issue dimensions'", () => {
  const { jobs } = workflow("work-resolve-issue.yml");
  const dims = jobs["pick-slot"].steps.find((s) => s.id === "dimensions");
  assert.equal(dims.uses, "./.base/.github/actions/resolve-config");
  assert.deepEqual([dims.with.lane, dims.with.activity], ["work-resolve-issue", "resolve-issue"]);
  assert.notEqual(dims["continue-on-error"], true, "unresolved dimensions must not start a run");
  // The org fields are readable only with issues: read.
  assert.equal(jobs["pick-slot"].permissions.issues, "read");
  assert.equal(jobs["pick-slot"].outputs["timeout-minutes"], "${{ steps.dimensions.outputs.timeout-minutes }}");
  assert.equal(jobs["resolve-issue"].with["timeout-minutes"], "${{ fromJSON(needs.pick-slot.outputs.timeout-minutes || '40') }}");
  // The run takes the dimensions whose timeout it got, not fields set while it waited.
  assert.equal(jobs["pick-slot"].outputs["issue-dimensions"], "${{ steps.dimensions.outputs.issue-dimensions }}");
  assert.equal(jobs["resolve-issue"].with["issue-dimensions"], "${{ needs.pick-slot.outputs.issue-dimensions }}");
  const read = workflow("pr-run-activity-read.yml");
  const config = read.jobs.run.steps.find((s) => s.id === "config");
  assert.equal(config.with["issue-dimensions"], "${{ inputs.issue-dimensions }}");
});

// A queued resolve-issue run starts on the workflow files of its label event,
// and its apply job mints from them. The broker refuses that mint as
// workflow-modified when the caller's or the write runner's blob at the run's
// commit differs from main's tip (azure-iac binding.mjs), so the read runner's run job checks the same
// rule before any model turn and, on a difference, ends green with stale=true,
// which stops the run; work-unblock's sweep re-fires a run that stopped there.
test("pr-run-activity-read.yml: an issue run on stale workflow files stops green before any model turn", () => {
  const { jobs } = workflow("pr-run-activity-read.yml");
  const steps = jobs.run.steps;
  const index = (id) => steps.findIndex((step) => step.id === id);
  const check = steps[index("workflow-current")];
  assert.ok(check, "the run job has a workflow-current step");
  assert.ok(index("base") < index("workflow-current"), "it reads the default branch checkout");
  assert.ok(index("workflow-current") < index("issue-prior"));
  assert.ok(index("workflow-current") < index("go"), "it runs before the run decides to start");
  assert.ok(index("go") < index("act-key"));
  // Every step from the check to the decision runs only while no step failed.
  for (const step of steps.slice(index("workflow-current") + 1, index("go") + 1)) {
    assert.doesNotMatch(String(step.if ?? ""), /always\(\)|failure\(\)|!cancelled\(\)/, step.name);
  }
  // A stale run stops at the stop step: no earlier-work check and no activity.
  const stop = steps.find((step) => step.name === "Stop on stale workflow files");
  assert.ok(index("workflow-current") < steps.indexOf(stop) && steps.indexOf(stop) < index("issue-prior"));
  const prior = steps[index("issue-prior")];
  const issueSkill = { "inputs.issue-number": "7", "steps.config.outputs.applies": "true", "steps.config.outputs.kind": "skill" };
  for (const [stale, stops] of [["true", true], ["", false]]) {
    const context = { ...issueSkill, "steps.workflow-current.outputs.stale": stale };
    assert.equal(evaluate(stop.if, context), stops, `stop step, stale=${stale}`);
    assert.equal(evaluate(prior.if, context), !stops, `issue-prior, stale=${stale}`);
  }
  const go = steps[index("go")];
  assert.equal(go.env.STALE, "${{ steps.workflow-current.outputs.stale }}");
  const decideGo = (env) => {
    const out = join(mkdtempSync(join(tmpdir(), "workflow-go-")), "out");
    writeFileSync(out, "");
    spawnSync("bash", ["-c", go.run], { encoding: "utf8", env: { ...process.env, PRIOR: "", STALE: "", ...env, GITHUB_OUTPUT: out } });
    return readFileSync(out, "utf8").trim();
  };
  assert.equal(decideGo({ STALE: "true" }), "run=false");
  assert.equal(decideGo({ PRIOR: "false" }), "run=false");
  assert.equal(decideGo({}), "run=true");
  // A skill run in issue mode only.
  for (const [issue, kind, runs] of [["7", "skill", true], ["7", "script", false], ["", "skill", false]]) {
    const context = {
      "inputs.issue-number": issue,
      "steps.config.outputs.applies": "true",
      "steps.config.outputs.kind": kind,
    };
    assert.equal(evaluate(check.if, context), runs, `${issue || "no issue"} ${kind}`);
  }

  const dir = mkdtempSync(join(tmpdir(), "workflow-current-"));
  after(() => rmSync(dir, { recursive: true, force: true }));
  const base = join(dir, ".base");
  const git = (...args) => {
    const run = spawnSync("git", ["-C", base, ...args], { encoding: "utf8" });
    assert.equal(run.status, 0, run.stderr);
    return run.stdout.trim();
  };
  const caller = ".github/workflows/work-resolve-issue.yml";
  const reusable = ".github/workflows/pr-run-activity-write.yml";
  const commit = (files) => {
    for (const [path, text] of Object.entries(files)) {
      writeFileSync(join(base, path), text);
    }
    git("add", "-A");
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false", "commit", "-q", "-m", "c");
    return git("rev-parse", "HEAD");
  };
  spawnSync("git", ["init", "-q", "-b", "main", base]);
  spawnSync("mkdir", ["-p", join(base, ".github/workflows")]);
  const run = commit({ [caller]: "caller 1\n", [reusable]: "write 1\n", "README.md": "a\n" });
  const output = join(dir, "github-output");
  // The check's exit status and what it wrote to GITHUB_OUTPUT.
  const runCheck = (sha = run, ref = `melodic-software/claude-code-plugins/${caller}@refs/heads/main`) => {
    writeFileSync(output, "");
    const result = spawnSync("bash", ["-c", check.run], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, WORKFLOW_REF: ref, WORKFLOW_SHA: sha, GITHUB_OUTPUT: output },
    });
    return { ...result, written: readFileSync(output, "utf8") };
  };
  const proceeds = (result, message) => {
    assert.equal(result.status, 0, message);
    assert.equal(result.written, "", message);
  };

  proceeds(runCheck(), "the run's own commit is main's tip");
  commit({ "README.md": "b\n" });
  proceeds(runCheck(), "main moved, but neither workflow file changed");
  commit({ [caller]: "caller 2\n" });
  const callerStale = runCheck();
  assert.equal(callerStale.status, 0, "the caller changed on main: the step ends green");
  assert.equal(callerStale.written, "stale=true\n");
  assert.match(callerStale.stdout, /::warning::workflow-stale: \.github\/workflows\/work-resolve-issue\.yml /);
  const fresh = git("rev-parse", "HEAD");
  proceeds(runCheck(fresh), "a run on main's current files proceeds");
  commit({ [reusable]: "write 2\n" });
  const reusableStale = runCheck(fresh);
  assert.equal(reusableStale.status, 0, "the write runner changed on main: the step ends green");
  assert.equal(reusableStale.written, "stale=true\n");
  assert.match(reusableStale.stdout, /::warning::workflow-stale: \.github\/workflows\/pr-run-activity-write\.yml /);

  // A commit or caller this checkout cannot read is left to the broker.
  proceeds(runCheck("0".repeat(40)));
  proceeds(runCheck(""));
  proceeds(runCheck(run, ""));
});

// The issue lane's model jobs hold no write token. resolve-issue and its
// subscription call run on the read runner, whose run job (the one that runs
// the model) gets only the job's read-only GITHUB_TOKEN; the App token is
// minted only by the apply job that commits the patch. The first call holds
// the issue lane's API key alone, the second its OAuth token alone.
test("work-resolve-issue.yml: the resolve-issue model jobs receive no App token and no write permission", () => {
  const { jobs } = workflow("work-resolve-issue.yml");
  for (const [id, input, secret] of [
    ["resolve-issue", "claude-api-key", "ISSUE_LANE_CLAUDE_API_KEY"],
    ["resolve-issue-subscription", "claude-code-oauth-token", "ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN"],
  ]) {
    const resolve = jobs[id];
    assert.equal(resolve.uses, "./.github/workflows/pr-run-activity-read.yml", id);
    assert.equal(resolve.with.activity, "resolve-issue", id);
    assert.equal(resolve.with["output-mode"], undefined, "patch mode comes from the activity's applied-by");
    assert.deepEqual(Object.keys(resolve.secrets), [input, "scan-carrier-private-key"], `${id}: only one of the issue lane's Claude credentials, and the scan-carrier key by name`);
    assert.equal(resolve.secrets[input], `\${{ secrets.${secret} }}`, id);
  }

  const read = workflow("pr-run-activity-read.yml");
  const run = read.jobs.run;
  assert.deepEqual(run.permissions, { contents: "read", "pull-requests": "read" }, "read-only, no id-token");
  const text = JSON.stringify(run);
  assert.doesNotMatch(text, /request-lane-token|lane-token|id-token|private-key/i, "no App token is minted in the model job");
  assert.doesNotMatch(text, /gh auth|hosts\.yml/, "no cached gh login");
  for (const step of run.steps.filter((s) => String(s.uses ?? "").startsWith("actions/checkout@"))) {
    assert.equal(step.with["persist-credentials"], false, `${step.name} leaves no git credential`);
    assert.equal(step.with.token, undefined, `${step.name} takes no token`);
  }
  // The launcher steps each name one Claude secret, and nothing else is a
  // secret.
  const secrets = [...text.matchAll(/secrets\.([\w-]+)/g)].map((m) => m[1]);
  assert.deepEqual([...new Set(secrets)].sort(), ["claude-api-key", "claude-code-oauth-token"]);
  for (const [id, secret] of [["act-key", "claude-api-key"], ["act-token", "claude-code-oauth-token"]]) {
    assert.deepEqual(stepSecrets(run.steps.find((s) => s.id === id)), [secret], id);
  }
  assert.ok(!run.steps.some((s) => String(s.uses ?? "").startsWith("anthropics/claude-code-action@")), "no claude-code-action step");
  // No job of the read runner holds a write permission but the report job's
  // checks and issues and the broker-check job's id-token, none of which runs
  // the model.
  for (const [name, job] of Object.entries(read.jobs)) {
    for (const [scope, level] of Object.entries(job.permissions ?? {})) {
      if (level === "write") {
        assert.ok((name === "report" && (scope === "checks" || scope === "issues")) || (name === "broker-check" && scope === "id-token"), `${name} ${scope}`);
      }
    }
  }
});

test("work-resolve-issue.yml: apply-issue-patch commits the written patch from the write runner, one per issue at a time", () => {
  const { jobs } = workflow("work-resolve-issue.yml");
  const apply = jobs["apply-issue-patch"];
  assert.equal(apply.uses, "./.github/workflows/pr-run-activity-write.yml");
  assert.deepEqual(apply.needs, ["resolve-issue", "resolve-issue-subscription"]);
  assert.equal(apply.with.activity, "apply-issue-patch");
  assert.equal(apply.with["patch-activity"], "resolve-issue");
  assert.equal(apply.secrets, undefined, "the apply job gets no Claude credential");
  for (const [input, output] of [
    ["patch-state", "scan-patch-state"],
    ["patch-sha256", "scan-patch-sha256"],
    ["patch-attempt", "scan-patch-attempt"],
    ["patch-base-sha", "scan-base-sha"],
    ["patch-resume-tip", "scan-resume-tip"],
    ["reply-attempt", "scan-reply-attempt"],
  ]) {
    // The subscription call's when it ran, else the first call's.
    for (const from of ["resolve-issue", "resolve-issue-subscription"]) {
      const context = {
        "needs.resolve-issue-subscription.result": from === "resolve-issue" ? "skipped" : "success",
        [`needs.resolve-issue-subscription.outputs.${output}`]: from === "resolve-issue" ? "" : "sub",
        [`needs.resolve-issue.outputs.${output}`]: from === "resolve-issue" ? "first" : "",
      };
      assert.equal(evaluate(apply.with[input], context), from === "resolve-issue" ? "first" : "sub", `${input} after ${from}`);
    }
  }
  assert.equal(apply.concurrency.group, "work-resolve-issue-write-${{ github.event.issue.number }}");
  assert.equal(apply.concurrency.queue, "max");
  const runs = (started, state) =>
    evaluate(apply.if, {
      "needs.resolve-issue-subscription.result": "skipped",
      "needs.resolve-issue-subscription.outputs.scan-issue-run-started": "",
      "needs.resolve-issue-subscription.outputs.scan-patch-state": "",
      "needs.resolve-issue.outputs.scan-issue-run-started": started,
      "needs.resolve-issue.outputs.scan-patch-state": state,
    });
  assert.equal(runs("true", "written"), true);
  assert.equal(runs("true", "empty"), false, "an empty patch makes no branch");
  assert.equal(runs("true", ""), false);
  assert.equal(runs("false", "written"), false);
  for (const job of ["run-checks", "report-outcome"]) {
    assert.ok(jobs[job].needs.includes("apply-issue-patch"), `${job} waits for the branch`);
  }
  // A started run whose scan failed or whose run job timed out uploads no
  // outcome, so run-checks skips instead of failing on the missing artifact.
  const checks = (started, uploaded, reuse) =>
    evaluate(jobs["run-checks"].if.replace(/^\$\{\{ |\s*\}\}$/g, "").replace(/!cancelled\(\) && /, ""), {
      "needs.resolve-issue-subscription.result": "skipped",
      "needs.resolve-issue-subscription.outputs.scan-issue-run-started": "",
      "needs.resolve-issue-subscription.outputs.scan-outcome-uploaded": "",
      "needs.resolve-issue-subscription.outputs.scan-reuse-branch": "",
      "needs.resolve-issue.outputs.scan-issue-run-started": started,
      "needs.resolve-issue.outputs.scan-outcome-uploaded": uploaded,
      "needs.resolve-issue.outputs.scan-reuse-branch": reuse,
    });
  assert.equal(checks("true", "true", ""), true);
  assert.equal(checks("true", "", ""), false, "no uploaded outcome runs no checks");
  assert.equal(checks("", "", "work-resolve-issue/issue-7-1-1"), true, "a reuse runs checks without an outcome");
  assert.equal(checks("", "true", ""), false);
});

test("no job using pr-run-activity-write.yml runs the resolve-issue model step, and the write runner refuses an issue skill", () => {
  const dir = new URL("../../workflows/", import.meta.url);
  for (const name of readdirSync(dir).filter((file) => /\.ya?ml$/.test(file))) {
    const { jobs = {} } = parse(readFileSync(new URL(name, dir), "utf8")) ?? {};
    for (const [id, job] of Object.entries(jobs)) {
      if (String(job?.uses ?? "").endsWith("pr-run-activity-write.yml")) {
        assert.notEqual(job.with?.activity, "resolve-issue", `${name} ${id}`);
      }
    }
  }
  const { jobs } = workflow("pr-run-activity-write.yml");
  const refuse = jobs.run.steps.find((s) => s.name === "Assert an issue skill runs in the read runner");
  assert.ok(refuse);
  const context = (issue, kind) => ({ "inputs.issue-number": issue, "steps.config.outcome": "success", "steps.config.outputs.kind": kind });
  assert.equal(evaluate(refuse.if, context("7", "skill")), true);
  assert.equal(evaluate(refuse.if, context("7", "script")), false);
  assert.equal(evaluate(refuse.if, context("", "skill")), false);
  assert.equal(spawnSync("bash", ["-c", refuse.run]).status, 1);
});

// The admission gate: on an issue anyone can open, only a listed human's
// agent-ready label (or the lanes App's own) may start a job that gets the
// issue lane's Claude credential or runs the read runner.
const ISSUE_SECRET = "${{ secrets.ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN }}";
const ADMITTED = "needs.admit.outputs.proceed == 'true'";

function needsOf(jobs, id, seen = new Set()) {
  for (const need of [jobs[id].needs ?? []].flat()) {
    if (!seen.has(need)) {
      seen.add(need);
      needsOf(jobs, need, seen);
    }
  }
  return seen;
}

test("work-resolve-issue.yml: every job that gets the issue lane's credential or runs the read runner needs the admission gate's proceed", () => {
  const { jobs } = workflow("work-resolve-issue.yml");
  const admit = jobs.admit;
  assert.deepEqual(admit.permissions, { contents: "read" }, "the gate holds a read-only token");
  assert.equal(admit.secrets, undefined);
  assert.doesNotMatch(JSON.stringify(admit), /secrets\./, "the gate names no secret");
  assert.equal(admit.outputs.proceed, "${{ steps.gate.outputs.proceed }}");
  const checkout = admit.steps.find((s) => String(s.uses ?? "").startsWith("actions/checkout@"));
  assert.equal(checkout.with.ref, "${{ github.event.repository.default_branch }}");
  assert.equal(checkout.with["persist-credentials"], false);
  const gate = admit.steps.find((s) => s.id === "gate");
  assert.equal(gate.uses, "./.base/.github/actions/check-trusted-trigger");
  assert.deepEqual(
    [gate.with["require-pr"], gate.with["require-kind"], gate.with["app-label"], gate.with["lanes-app-id"]],
    ["false", "human", "agent-ready", "${{ vars.AUTOMATION_LANES_APP_SENDER_ID }}"],
  );
  const guarded = Object.entries(jobs).filter(
    ([, job]) => JSON.stringify(job).includes(ISSUE_SECRET) || job.uses === "./.github/workflows/pr-run-activity-read.yml",
  );
  assert.deepEqual(guarded.map(([id]) => id), ["resolve-issue", "resolve-issue-subscription"]);
  for (const [id, job] of [...guarded, ["pick-slot", jobs["pick-slot"]]]) {
    assert.ok(needsOf(jobs, id).has("admit"), `${id} needs admit`);
    assert.ok(String(job.if).includes(ADMITTED), `${id} requires the gate's proceed`);
    const context = {
      "github.event.label.name": "agent-ready",
      "needs.admit.outputs.proceed": "true",
      "needs.pick-slot.outputs.capped": "false",
      "needs.resolve-issue-handoff.outputs.handed-off": "true",
    };
    assert.equal(evaluate(job.if, context), true, `${id} runs once admitted`);
    for (const proceed of ["false", ""]) {
      assert.equal(evaluate(job.if, { ...context, "needs.admit.outputs.proceed": proceed }), false, `${id} with proceed ${JSON.stringify(proceed)}`);
    }
  }
});

// Drives the gate step's inputs through check-trusted-trigger's own main, as
// the action's env map passes them, on an agent-ready label event. The gate
// reads the run attempt's re-runner by id from the run's own record; the stub
// answers that read alone, with `rerunner` (the labeler by default).
const RUN_ID = "39500000001";
async function admitOn(sender, rerunner = sender) {
  const { jobs } = workflow("work-resolve-issue.yml");
  const gate = jobs.admit.steps.find((s) => s.id === "gate");
  const action = parse(read("../check-trusted-trigger/action.yml"));
  const dir = mkdtempSync(join(tmpdir(), "admit-"));
  try {
    const eventPath = join(dir, "event.json");
    const output = join(dir, "output");
    writeFileSync(eventPath, JSON.stringify({ action: "labeled", label: { name: "agent-ready" }, issue: { number: 7 }, sender, repository: { full_name: "o/r" } }));
    writeFileSync(output, "");
    const values = {
      "vars.AUTOMATION_LANES_APP_SENDER_ID": "337595936",
      "github.triggering_actor": rerunner.login,
    };
    // The event and run the runner would pass through the action's defaults.
    const env = {
      GITHUB_OUTPUT: output,
      REPOSITORY: "o/r",
      EVENT_NAME: "issues",
      EVENT_PATH: eventPath,
      GITHUB_RUN_ID: RUN_ID,
      GITHUB_RUN_ATTEMPT: "1",
    };
    for (const [name, value] of Object.entries(action.runs.steps[0].env)) {
      const input = value.match(/^\$\{\{ inputs\.([\w-]+) \}\}$/)?.[1];
      if (!input || !Object.hasOwn(gate.with, input)) continue;
      const given = String(gate.with[input]);
      env[name] = /^\$\{\{/.test(given) ? evaluate(given, values) : given;
    }
    env.TRUSTED_ACTORS_PATH = fileURLToPath(new URL("../../standards/trusted-actors/trusted-actors.json", import.meta.url));
    const reads = [];
    const github = async (method, path) => {
      reads.push(`${method} ${path}`);
      if (method === "GET" && path === `/repos/o/r/actions/runs/${RUN_ID}`) {
        return { id: Number(RUN_ID), run_attempt: 1, triggering_actor: { login: rerunner.login, id: rerunner.id } };
      }
      throw new Error(`the actor-only gate reads only its own run record, not ${method} ${path}`);
    };
    await checkTrustedTrigger({ env, github: Object.assign(github, { graphql: github }) });
    // GITHUB_OUTPUT's delimited form, as writeOutputs writes it.
    const proceed = /^proceed<<(\S+)\n(.*)\n\1$/m.exec(readFileSync(output, "utf8"))?.[2] ?? "";
    const resolve = jobs["resolve-issue"];
    assert.ok(reads.every((call) => call === `GET /repos/o/r/actions/runs/${RUN_ID}`), reads.join(", "));
    return {
      proceed,
      runs: evaluate(resolve.if, {
        "github.event.label.name": "agent-ready",
        "needs.admit.outputs.proceed": proceed,
        "needs.pick-slot.outputs.capped": "false",
      }),
    };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("work-resolve-issue.yml: an unlisted labeler's agent-ready is refused at the gate and the credentialed job is skipped", async () => {
  const stranger = { login: "stranger", id: 9999001, type: "User" };
  assert.deepEqual(await admitOn(stranger), { proceed: "false", runs: false });
  const listedBot = { login: "claude[bot]", id: 209825114, type: "Bot" };
  assert.deepEqual(await admitOn(listedBot), { proceed: "false", runs: false }, "a listed bot is not a human");
  const human = { login: "kyle-sexton", id: 153232337, type: "User" };
  assert.deepEqual(await admitOn(human), { proceed: "true", runs: true }, "a listed human's label is admitted");
  assert.deepEqual(await admitOn(human, stranger), { proceed: "false", runs: false }, "an unlisted re-runner of a listed human's run is refused");
  const app = { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" };
  assert.deepEqual(await admitOn(app), { proceed: "true", runs: true }, "the lanes App's own agent-ready is admitted");
});

// --- fix-ci on run-claude-cli: one Claude credential per call ---

const READ_RUNNER = "./.github/workflows/pr-run-activity-read.yml";
const workflowFiles = () => readdirSync(new URL("../../workflows/", import.meta.url)).filter((file) => /\.ya?ml$/.test(file));
// The secret a read-runner input takes, by the suffix run-claude-cli names
// it with: <ROLE>_CLAUDE_API_KEY or <ROLE>_CLAUDE_CODE_OAUTH_TOKEN.
const CLAUDE_SECRETS = { "claude-api-key": "CLAUDE_API_KEY", "claude-code-oauth-token": "CLAUDE_CODE_OAUTH_TOKEN" };
const atStep = (expression, context) => evaluate(String(expression).replaceAll("always()", "true"), context);

test("every read-runner caller job passes exactly one Claude secret, named for its role, beside the scan-carrier key", () => {
  const callers = [];
  for (const file of workflowFiles()) {
    for (const [id, job] of Object.entries(workflow(file).jobs ?? {})) {
      if (job?.uses !== READ_RUNNER) continue;
      callers.push(`${file} ${id}`);
      const names = Object.keys(job.secrets ?? {}).filter((name) => name !== "scan-carrier-private-key");
      assert.equal(job.secrets["scan-carrier-private-key"], "${{ secrets.SCAN_CARRIER_PRIVATE_KEY }}", `${file} ${id}`);
      assert.equal(names.length, 1, `${file} ${id} passes ${names.join(", ")}`);
      const [name] = names;
      assert.ok(Object.hasOwn(CLAUDE_SECRETS, name), `${file} ${id} passes ${name}`);
      assert.match(job.with.role, /^[a-z][a-z0-9-]*$/, `${file} ${id} names a role`);
      const role = job.with.role.toUpperCase().replaceAll("-", "_");
      assert.equal(job.secrets[name], `\${{ secrets.${role}_${CLAUDE_SECRETS[name]} }}`, `${file} ${id}`);
      assert.equal(job.with["output-mode"], undefined, `${file} ${id}: patch mode comes from the activity's applied-by`);
    }
  }
  assert.deepEqual(callers.sort(), [
    "pr-refine.yml fix-docs",
    "pr-refine.yml fix-docs-subscription",
    "pr-unblock.yml address-feedback",
    "pr-unblock.yml address-feedback-subscription",
    "pr-unblock.yml fix-ci",
    "pr-unblock.yml fix-ci-rung-up",
    "pr-unblock.yml fix-ci-rung-up-subscription",
    "pr-unblock.yml fix-ci-subscription",
    "pr-unblock.yml resolve-conflicts",
    "pr-unblock.yml resolve-conflicts-subscription",
    "pr-unblock.yml review-dependency",
    "pr-unblock.yml review-dependency-subscription",
    "work-resolve-issue.yml resolve-issue",
    "work-resolve-issue.yml resolve-issue-subscription",
  ]);
});

// --- the lane-funding catalog: .github/lane-funding.json ---

// Read inside each test, so a missing catalog fails every one of them.
const fundingCatalog = () => JSON.parse(read("../../lane-funding.json"));
const catalogLanes = () => fundingCatalog().roles.flatMap((role) => role.lanes.map((lane) => ({ role, lane, key: `${lane.workflow} ${lane.id}` })));
// What a node can read of the secrets context. A reference is a name (secrets.NAME,
// secrets['NAME'], or an ANTHROPIC_* env name) or ALL_SECRETS, a form that
// reaches every secret: toJSON(secrets), secrets[expression], secrets: inherit.
const ALL_SECRETS = "*";
// Expression syntax and secret names are case-insensitive in GitHub Actions.
const CLAUDE_CREDENTIAL = /^(?:(?:[A-Z][A-Z0-9_]*_)?CLAUDE_(?:API_KEY|CODE_OAUTH_TOKEN)|ANTHROPIC_[A-Z0-9_]+)$/i;
const NAMED_ACCESS = String.raw`\s*\.\s*[\w-]|\s*\[\s*['"][\w-]+['"]\s*\]`;
const BARE_SECRETS = new RegExp(String.raw`(?<![\w.-])secrets(?![\w-])(?!${NAMED_ACCESS})`, "i");
function secretRefs(node, key = "", refs = new Set()) {
  if (typeof node === "string") {
    for (const [, dotted, quoted] of node.matchAll(/secrets\.([\w-]+)|secrets\[\s*['"]([\w-]+)['"]\s*\]/gi)) refs.add(dotted ?? quoted);
    // An `if` value is a bare expression; elsewhere only ${{ }} holds one.
    const expressions = key === "if" ? [node] : [...node.matchAll(/\$\{\{([\s\S]*?)\}\}/g)].map((m) => m[1]);
    if (expressions.some((expression) => BARE_SECRETS.test(expression))) refs.add(ALL_SECRETS);
  } else if (Array.isArray(node)) {
    for (const item of node) secretRefs(item, key, refs);
  } else if (node && typeof node === "object") {
    for (const [name, value] of Object.entries(node)) {
      if (name.toLowerCase() === "secrets" && value === "inherit") refs.add(ALL_SECRETS);
      if (key === "env" && /^ANTHROPIC_/i.test(name)) refs.add(name);
      secretRefs(value, name, refs);
    }
  }
  return refs;
}
// The Claude credentials the given nodes can read, sorted.
const claudeReads = (...nodes) => {
  const refs = new Set();
  for (const node of nodes) secretRefs(node, "", refs);
  return [...refs].filter((name) => name === ALL_SECRETS || CLAUDE_CREDENTIAL.test(name)).sort();
};
const isApiKey = (name) => name === ALL_SECRETS || /(^|_)CLAUDE_API_KEY$|^ANTHROPIC_/i.test(name);
// Every job that can read a role's Claude credential, with the names it reads. The
// workflow-level env reaches every job, so it counts toward each.
function claudeSecretJobs(files = workflowFiles(), load = workflow) {
  const jobs = new Map();
  for (const file of files) {
    const doc = load(file);
    for (const [id, job] of Object.entries(doc.jobs ?? {})) {
      const names = claudeReads({ env: doc.env }, job);
      if (names.length) jobs.set(`${file} ${id}`, { doc, job, names });
    }
  }
  return jobs;
}
// The one step that runs Claude: the pinned action, or for claude-cli the run
// step that invokes the `claude` command.
const LAUNCHER_ACTION = {
  "run-claude-cli": "melodic-software/ci-workflows/.github/actions/run-claude-cli@",
  "claude-code-action": "anthropics/claude-code-action@",
};
const isLauncherStep = (step, launcher) =>
  launcher === "claude-cli"
    ? typeof step.run === "string" && step.uses === undefined && /^\s*claude\s+\S/m.test(step.run)
    : String(step.uses ?? "").startsWith(LAUNCHER_ACTION[launcher]);
// A value that is only whether a secret is set, ${{ secrets.NAME != '' }}, carries no credential.
const PRESENCE_ONLY = /^\s*(?:\$\{\{\s*)?secrets\.[\w-]+\s*[!=]=\s*''\s*(?:\}\})?\s*$/;
const withoutPresenceChecks = (node) =>
  typeof node === "string"
    ? PRESENCE_ONLY.test(node) ? "" : node
    : Array.isArray(node)
      ? node.map(withoutPresenceChecks)
      : node && typeof node === "object"
        ? Object.fromEntries(Object.entries(node).map(([name, value]) => [name, withoutPresenceChecks(value)]))
        : node;
// The places a job lets its Claude credentials go beyond the launcher step: the
// workflow or job env (every step), or any other step that reads more than whether
// a secret is set.
function strayClaudeReaders({ doc, job }, launcher) {
  const stray = [];
  if (claudeReads({ env: doc.env }).length) stray.push("workflow env");
  if (claudeReads({ env: job.env }).length) stray.push("job env");
  for (const step of job.steps ?? []) {
    if (claudeReads(withoutPresenceChecks(step)).length && !isLauncherStep(step, launcher)) stray.push(`step ${step.name ?? step.id ?? step.run}`);
  }
  return stray;
}
// Triggers that run a job holding this repository's secrets for an event someone
// outside it can start, so such a job must show a gate.
const GATED_TRIGGERS = ["pull_request_target", "issues", "issue_comment", "workflow_run"];
// The event names under a workflow's on:, in its string, list or map form.
const workflowTriggers = ({ on }) =>
  (typeof on === "string" ? [on] : Array.isArray(on) ? on : Object.keys(on ?? {})).map((name) => name.toLowerCase()).sort();
const hasGatedTrigger = (triggers) => triggers.some((name) => GATED_TRIGGERS.includes(name));
// The top-level && terms of an if:, or none when a top-level || lets a run past them.
function ifTerms(condition) {
  if (typeof condition !== "string") return [];
  const expression = condition.replace(/^\s*\$\{\{([\s\S]*)\}\}\s*$/, "$1").replace(/\s+/g, " ").trim();
  const terms = [];
  let depth = 0;
  let quoted = false;
  let start = 0;
  for (let i = 0; i < expression.length; i++) {
    const c = expression[i];
    if (c === "'") quoted = !quoted;
    else if (quoted) continue;
    else if (c === "(") depth++;
    else if (c === ")") depth--;
    else if (depth === 0 && expression.startsWith("||", i)) return [];
    else if (depth === 0 && expression.startsWith("&&", i)) {
      terms.push(expression.slice(start, i).trim());
      start = i + 2;
      i++;
    }
  }
  return [...terms, expression.slice(start).trim()];
}
// The gate shapes the lanes use. same-repo: pr-verify.yml's if: on the
// workflow_run head repository. author: a needed job's proceed output from
// check-trusted-trigger run from the default branch (work-resolve-issue.yml's
// admit), or the pinned intake reusable, whose claude job starts only for a
// sender in allowed-author-ids (ci-workflows intake-triage.yml, the claude job's
// if:) and whose other Claude job needs it, or a needed job's refine output
// from refine.mjs --select run from the default branch, which refines only an
// issue a listed human or the lanes App opened, in a run apply-verdict --check
// admitted (intake-triage.yml's refine-issue).
const SAME_REPO = "github.event.workflow_run.head_repository.full_name == github.repository";
const TRUSTED_TRIGGER = "./.base/.github/actions/check-trusted-trigger";
const REFINE_SELECT = "node .base/.github/scripts/intake-triage/refine.mjs --select";
const INTAKE_REUSABLE = /^melodic-software\/ci-workflows\/\.github\/workflows\/intake-triage\.yml@[0-9a-f]{40}$/;
function jobGates(doc, job) {
  const gates = new Set();
  const needs = [job.needs ?? []].flat();
  for (const term of ifTerms(job.if)) {
    if (term === SAME_REPO) gates.add("same-repo");
    const [, need, output] = term.match(/^needs\.([\w-]+)\.outputs\.([\w-]+) == 'true'$/) ?? [];
    if (!needs.includes(need)) continue;
    const gateJob = doc.jobs?.[need] ?? {};
    const [, stepId] = String(gateJob.outputs?.[output] ?? "").match(/^\$\{\{\s*steps\.([\w-]+)\.outputs\.proceed\s*\}\}$/) ?? [];
    if (stepId && (gateJob.steps ?? []).some((step) => step.id === stepId && step.uses === TRUSTED_TRIGGER)) gates.add("author");
    const [, selectId] = String(gateJob.outputs?.[output] ?? "").match(/^\$\{\{\s*steps\.([\w-]+)\.outputs\.refine\s*\}\}$/) ?? [];
    if (selectId && (gateJob.steps ?? []).some((step) => step.id === selectId && String(step.run ?? "").split("\n").some((line) => line.trim() === REFINE_SELECT))) gates.add("author");
  }
  if (INTAKE_REUSABLE.test(String(job.uses ?? "")) && String(job.with?.["allowed-author-ids"] ?? "").trim() !== "") gates.add("author");
  return [...gates].sort();
}
// Each job that holds a Claude credential under a gated trigger, with the gates it shows.
function gatedTriggerJobs(files = workflowFiles(), load = workflow) {
  const jobs = new Map();
  for (const [key, { doc, job }] of claudeSecretJobs(files, load)) {
    if (hasGatedTrigger(workflowTriggers(doc))) jobs.set(key, jobGates(doc, job));
  }
  return jobs;
}

test("lane-funding.json validates against its schema", () => {
  const validate = new Ajv2020({ allErrors: true, strict: true }).compile(JSON.parse(read("../../lane-funding.schema.json")));
  assert.ok(validate(fundingCatalog()), JSON.stringify(validate.errors));
});

test("every job that reads a Claude secret is a catalog lane, and every catalog lane is a job that reads the secrets it lists", () => {
  const jobs = claudeSecretJobs();
  const lanes = catalogLanes();
  assert.equal(new Set(lanes.map(({ key }) => key)).size, lanes.length, "a job is one lane");
  assert.deepEqual(lanes.map(({ key }) => key).sort(), [...jobs.keys()].sort());
  for (const { lane, key } of lanes) {
    const { job, names } = jobs.get(key);
    assert.deepEqual([...lane.currentSecrets].sort(), names, key);
    // Where the job itself names its launcher, the catalog names the same one.
    const steps = (job.steps ?? []).map((step) => String(step.uses ?? ""));
    if (steps.some((uses) => uses.includes("/run-claude-cli@"))) assert.equal(lane.launcher, "run-claude-cli", key);
    if (steps.some((uses) => uses.startsWith("anthropics/claude-code-action@"))) assert.equal(lane.launcher, "claude-code-action", key);
  }
});

// run-claude-cli names the lane record's credential from `role:`, never from
// the secret passed, so the role and the secret are checked together.
test("every catalog lane reads only its role's secrets, and every role: it passes is its role", () => {
  const jobs = claudeSecretJobs();
  for (const { role, lane, key } of catalogLanes()) {
    for (const name of lane.currentSecrets) assert.ok([role.keySecret, role.tokenSecret].includes(name), `${key} reads ${name}`);
    const { job } = jobs.get(key);
    const roles = [job.with?.role, ...(job.steps ?? []).map((step) => step.with?.role)].filter((value) => value !== undefined);
    for (const value of roles) assert.equal(value, role.id, key);
  }
  // A runner caller that reads no Claude secret still names the credential
  // the lane record reports, so it passes its workflow's role.
  const workflowRoles = new Map();
  for (const { role, lane } of catalogLanes()) workflowRoles.set(lane.workflow, [...new Set([...(workflowRoles.get(lane.workflow) ?? []), role.id])]);
  for (const [file, ids] of workflowRoles) {
    if (ids.length !== 1) continue;
    for (const [id, job] of Object.entries(workflow(file).jobs ?? {})) {
      if (job?.uses === READ_RUNNER || job?.uses === "./.github/workflows/pr-run-activity-write.yml") assert.equal(job.with?.role, ids[0], `${file} ${id}`);
    }
  }
});

test("a job reads a Claude API key only when its catalog lane runs on run-claude-cli", () => {
  const lanes = new Map(catalogLanes().map(({ lane, key }) => [key, lane]));
  const keyed = [...claudeSecretJobs()].filter(([, { names }]) => names.some(isApiKey));
  assert.ok(keyed.length > 0);
  for (const [key] of keyed) assert.equal(lanes.get(key)?.launcher, "run-claude-cli", key);
});

test("a Claude credential reaches only the launcher step of its catalog lane", () => {
  const jobs = claudeSecretJobs();
  for (const { lane, key } of catalogLanes()) {
    assert.deepEqual(strayClaudeReaders(jobs.get(key), lane.launcher), [], key);
  }
});

test("the Claude credential scan sees every form a secret can be read in", () => {
  const KEY = "REVIEWS_CLAUDE_API_KEY";
  const step = (env) => ({ jobs: { j: { steps: [{ name: "s", run: "true", env }] } } });
  const forms = {
    "secrets.NAME": [step({ K: `\${{ secrets.${KEY} }}` }), [KEY]],
    "secrets['NAME']": [step({ K: `\${{ secrets['${KEY}'] }}` }), [KEY]],
    'secrets["NAME"]': [step({ K: `\${{ secrets["${KEY}"] }}` }), [KEY]],
    "toJSON(secrets)": [step({ K: "${{ toJSON(secrets) }}" }), [ALL_SECRETS]],
    "secrets[expression]": [step({ K: "${{ secrets[matrix.name] }}" }), [ALL_SECRETS]],
    "if: toJSON(secrets)": [{ jobs: { j: { if: "toJSON(secrets) != ''", steps: [] } } }, [ALL_SECRETS]],
    "secrets: inherit": [{ jobs: { j: { uses: "./.github/workflows/x.yml", secrets: "inherit" } } }, [ALL_SECRETS]],
    "reusable secrets mapping": [{ jobs: { j: { uses: "./.github/workflows/x.yml", secrets: { k: `\${{ secrets.${KEY} }}` } } } }, [KEY]],
    "workflow env": [{ env: { K: `\${{ secrets.${KEY} }}` }, jobs: { j: { steps: [{ run: "true" }] } } }, [KEY]],
    "ANTHROPIC_ secret name": [step({ K: "${{ secrets.ANTHROPIC_API_KEY }}" }), ["ANTHROPIC_API_KEY"]],
    "mixed-case context": [step({ K: `\${{ Secrets.${KEY} }}` }), [KEY]],
    "lowercase secret name": [step({ K: "${{ secrets.reviews_claude_api_key }}" }), ["reviews_claude_api_key"]],
    "lowercase bracket name": [step({ K: "${{ secrets['anthropic_api_key'] }}" }), ["anthropic_api_key"]],
    "mixed-case toJSON(Secrets)": [step({ K: "${{ toJSON(SECRETS) }}" }), [ALL_SECRETS]],
    "mixed-case secrets: inherit": [{ jobs: { j: { uses: "./.github/workflows/x.yml", Secrets: "inherit" } } }, [ALL_SECRETS]],
    "job env ANTHROPIC_ name": [{ jobs: { j: { env: { ANTHROPIC_API_KEY: "x" }, steps: [{ run: "true" }] } } }, ["ANTHROPIC_API_KEY"]],
    "lowercase anthropic_ env name": [step({ anthropic_api_key: "x" }), ["anthropic_api_key"]],
    "ANTHROPIC_ env name": [step({ ANTHROPIC_API_KEY: "${{ secrets.OTHER }}" }), ["ANTHROPIC_API_KEY"]],
    "workflow env ANTHROPIC_ name": [{ env: { ANTHROPIC_AUTH_TOKEN: "x" }, jobs: { j: { steps: [{ run: "true" }] } } }, ["ANTHROPIC_AUTH_TOKEN"]],
  };
  for (const [form, [doc, expected]] of Object.entries(forms)) {
    assert.deepEqual([...claudeSecretJobs(["f.yml"], () => doc).values()].flatMap(({ names }) => names), expected, form);
  }
  // A named secret that is not a Claude credential and a literal mention stay quiet.
  const quiet = { jobs: { j: { steps: [{ run: "echo secrets", env: { T: "${{ secrets.SCAN_CARRIER_PRIVATE_KEY }}" } }] } } };
  assert.equal(claudeSecretJobs(["f.yml"], () => quiet).size, 0);
});

test("the stray-reader check names an extra step and an env that reaches every step", () => {
  const launcher = { uses: "melodic-software/ci-workflows/.github/actions/run-claude-cli@abc", with: { "api-key": "${{ secrets.REVIEWS_CLAUDE_API_KEY }}" } };
  const extra = { name: "extra", run: "true", env: { K: "${{ secrets.REVIEWS_CLAUDE_API_KEY }}" } };
  const check = (doc, job) => strayClaudeReaders({ doc, job }, "run-claude-cli");
  assert.deepEqual(check({}, { steps: [launcher] }), []);
  assert.deepEqual(check({}, { steps: [launcher, extra] }), ["step extra"]);
  const other = { ...launcher, name: "other-owner", uses: "someone-else/ci-workflows/.github/actions/run-claude-cli@abc" };
  assert.deepEqual(check({}, { steps: [other] }), ["step other-owner"], "the launcher is pinned to its owner");
  assert.deepEqual(check({ env: { ANTHROPIC_AUTH_TOKEN: "x" } }, { steps: [launcher] }), ["workflow env"]);
  assert.deepEqual(check({}, { env: { ANTHROPIC_API_KEY: "x" }, steps: [launcher] }), ["job env"]);
  const cli = { name: "eval", run: "set -e\nclaude plugin eval x", env: { CLAUDE_CODE_OAUTH_TOKEN: "${{ secrets.AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN }}" } };
  const sibling = { name: "sibling", run: "echo hi", env: cli.env };
  assert.deepEqual(strayClaudeReaders({ doc: {}, job: { steps: [cli] } }, "claude-cli"), []);
  assert.deepEqual(strayClaudeReaders({ doc: {}, job: { steps: [cli, sibling] } }, "claude-cli"), ["step sibling"], "a run step that does not invoke claude is no launcher");
  assert.deepEqual(check({}, { env: extra.env, steps: [launcher] }), ["job env"]);
  assert.deepEqual(check({ env: extra.env }, { steps: [launcher] }), ["workflow env"]);
  assert.deepEqual(check({}, { steps: [{ ...launcher, name: "wrong", uses: "actions/checkout@abc" }] }), ["step wrong"]);
  const presence = { name: "presence", run: "true", if: "secrets.REVIEWS_CLAUDE_API_KEY != ''", env: { P: "${{ secrets.REVIEWS_CLAUDE_API_KEY != '' }}" } };
  assert.deepEqual(check({}, { steps: [presence, launcher] }), [], "whether a secret is set is not the secret");
  const value = { ...presence, env: { P: "${{ secrets.REVIEWS_CLAUDE_API_KEY != '' && secrets.REVIEWS_CLAUDE_API_KEY }}" } };
  assert.deepEqual(check({}, { steps: [value, launcher] }), ["step presence"]);
});

test("each catalog lane names its workflow's triggers, and the gate its job shows", () => {
  const jobs = claudeSecretJobs();
  for (const { lane, key } of catalogLanes()) {
    const { doc, job } = jobs.get(key);
    assert.deepEqual([...lane.triggers].sort(), workflowTriggers(doc), key);
    if (lane.gate !== undefined) assert.ok(jobGates(doc, job).includes(lane.gate), `${key} shows no ${lane.gate} gate`);
  }
});

test("a pull_request_target, issues, issue_comment or workflow_run job that holds a Claude credential shows an author or same-repo gate", () => {
  const jobs = gatedTriggerJobs();
  for (const [key, gates] of jobs) assert.notDeepEqual(gates, [], `${key} holds a Claude credential with no author or same-repo gate`);
  const gatedLanes = catalogLanes().filter(({ lane }) => hasGatedTrigger(lane.triggers));
  assert.deepEqual([...jobs.keys()].sort(), gatedLanes.map(({ key }) => key).sort());
});

test("the trigger-gate check names an ungated job and accepts only the lanes' gate shapes", () => {
  const launcher = { uses: "anthropics/claude-code-action@abc", with: { claude_code_oauth_token: "${{ secrets.ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN }}" } };
  const admit = (step = { id: "gate", uses: TRUSTED_TRIGGER }) => ({ outputs: { proceed: "${{ steps.gate.outputs.proceed }}" }, steps: [step] });
  const gates = (on, jobs) => Object.fromEntries(gatedTriggerJobs(["f.yml"], () => ({ on, jobs })));
  const intake = (uses, ids) => ({ uses, with: { "allowed-author-ids": ids }, secrets: { CLAUDE_CODE_OAUTH_TOKEN: "${{ secrets.AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN }}" } });
  const PINNED = "melodic-software/ci-workflows/.github/workflows/intake-triage.yml@d02b8697e092705153f0996549b05f95a446bb52";
  const cases = {
    "ungated issues job": [{ issues: { types: ["labeled"] } }, { run: { steps: [launcher] } }, { "f.yml run": [] }],
    "ungated issue_comment job": [{ issue_comment: { types: ["created"] } }, { run: { steps: [launcher] } }, { "f.yml run": [] }],
    "ungated pull_request_target job": [{ pull_request_target: {} }, { run: { steps: [launcher] } }, { "f.yml run": [] }],
    "ungated workflow_run job": [{ workflow_run: {} }, { run: { steps: [launcher] } }, { "f.yml run": [] }],
    "on: as a string": ["issues", { run: { steps: [launcher] } }, { "f.yml run": [] }],
    "on: as a list": [["push", "workflow_run"], { run: { steps: [launcher] } }, { "f.yml run": [] }],
    "same-repo if:": [{ workflow_run: {} }, { run: { if: `github.ref == 'refs/heads/main' && ${SAME_REPO}`, steps: [launcher] } }, { "f.yml run": ["same-repo"] }],
    "same-repo inside an ||": [{ workflow_run: {} }, { run: { if: `github.event_name == 'push' || ${SAME_REPO}`, steps: [launcher] } }, { "f.yml run": [] }],
    "same-repo beside a top-level ||": [{ workflow_run: {} }, { run: { if: `${SAME_REPO} && a || b`, steps: [launcher] } }, { "f.yml run": [] }],
    "check-trusted-trigger in a needed job": [{ issues: {} }, { admit: admit(), run: { needs: ["admit"], if: "needs.admit.outputs.proceed == 'true'", steps: [launcher] } }, { "f.yml run": ["author"] }],
    "a gate job outside needs": [{ issues: {} }, { admit: admit(), run: { if: "needs.admit.outputs.proceed == 'true'", steps: [launcher] } }, { "f.yml run": [] }],
    "another action's proceed": [{ issues: {} }, { admit: admit({ id: "gate", uses: "./.base/.github/actions/check-kill-switch" }), run: { needs: "admit", if: "needs.admit.outputs.proceed == 'true'", steps: [launcher] } }, { "f.yml run": [] }],
    "a gate output compared to false": [{ issues: {} }, { admit: admit(), run: { needs: "admit", if: "needs.admit.outputs.proceed != 'true'", steps: [launcher] } }, { "f.yml run": [] }],
    "the pinned intake reusable with author ids": [{ issues: {} }, { triage: intake(PINNED, "${{ needs.x.outputs.human-ids }}") }, { "f.yml triage": ["author"] }],
    "the intake reusable with no author ids": [{ issues: {} }, { triage: intake(PINNED, "") }, { "f.yml triage": [] }],
    "an intake reusable from another owner": [{ issues: {} }, { triage: intake(PINNED.replace("melodic-software", "someone-else"), "1") }, { "f.yml triage": [] }],
    "an unpinned intake reusable": [{ issues: {} }, { triage: intake(PINNED.replace(/@.*/, "@main"), "1") }, { "f.yml triage": [] }],
    "a pull_request job": [{ pull_request: {} }, { run: { steps: [launcher] } }, {}],
    "a gated trigger with no Claude credential": [{ issues: {} }, { run: { steps: [{ run: "true" }] } }, {}],
  };
  for (const [name, [on, jobs, expected]] of Object.entries(cases)) assert.deepEqual(gates(on, jobs), expected, name);
});

test("each catalog role names its secrets from its prefix, and is keyed only with a run-claude-cli lane", () => {
  for (const role of fundingCatalog().roles) {
    assert.equal(role.secretPrefix, role.id.toUpperCase().replaceAll("-", "_"), role.id);
    assert.equal(role.keySecret, `${role.secretPrefix}_CLAUDE_API_KEY`, role.id);
    assert.equal(role.tokenSecret, `${role.secretPrefix}_CLAUDE_CODE_OAUTH_TOKEN`, role.id);
    if (role.keyed) assert.ok(role.lanes.some((lane) => lane.launcher === "run-claude-cli"), role.id);
  }
});

test("no workflow step references both Claude secrets or sets CLAUDE_CODE_ENTRYPOINT, and claude-code-action gets no API key", () => {
  for (const file of workflowFiles()) {
    const doc = workflow(file);
    assert.ok(!Object.hasOwn(doc.env ?? {}, "CLAUDE_CODE_ENTRYPOINT"), file);
    for (const [id, job] of Object.entries(doc.jobs ?? {})) {
      assert.ok(!Object.hasOwn(job.env ?? {}, "CLAUDE_CODE_ENTRYPOINT"), `${file} ${id}`);
      for (const step of job.steps ?? []) {
        const names = stepSecrets(step);
        const both = names.some((name) => /api[-_]key/i.test(name)) && names.some((name) => /oauth[-_]token/i.test(name));
        assert.ok(!both, `${file} ${id} ${step.name}: ${names.join(", ")}`);
        assert.ok(!Object.hasOwn(step.env ?? {}, "CLAUDE_CODE_ENTRYPOINT"), `${file} ${id} ${step.name}`);
        if (String(step.uses ?? "").startsWith("anthropics/claude-code-action@")) {
          assert.doesNotMatch(JSON.stringify(step.with ?? {}), /api[-_]key/i, `${file} ${id} ${step.name}`);
        }
      }
    }
  }
});

test("pr-run-activity-read.yml: the run job can only read, and each launcher step holds one Claude secret", () => {
  const { jobs } = workflow("pr-run-activity-read.yml");
  assert.deepEqual(jobs.run.permissions, { contents: "read", "pull-requests": "read" }, "read-only, no id-token");
  const step = (id) => jobs.run.steps.find((s) => s.id === id);
  const launcher = "melodic-software/ci-workflows/.github/actions/run-claude-cli@d02b8697e092705153f0996549b05f95a446bb52";
  for (const [id, input, secret] of [
    ["act-key", "api-key", "claude-api-key"],
    ["act-token", "subscription-token", "claude-code-oauth-token"],
  ]) {
    const launch = step(id);
    assert.equal(launch.uses, launcher, id);
    assert.deepEqual(stepSecrets(launch), [secret], id);
    assert.equal(launch.with[input], `\${{ secrets.${secret} }}`, id);
    assert.equal(launch.with[input === "api-key" ? "subscription-token" : "api-key"], undefined, id);
    assert.equal(launch.with["permission-mode"], "${{ steps.config.outputs.permission-mode }}", id);
    assert.equal(launch["continue-on-error"], true, id);
    assert.equal(launch["timeout-minutes"], "${{ fromJSON(steps.launch.outputs.step-minutes || '50') }}", id);
    assert.equal(launch.with["leg-timeout-minutes"], "${{ steps.launch.outputs.leg-minutes }}", id);
    for (const list of ["tools", "allowed-tools", "disallowed-tools", "plugin-dirs", "preamble"]) {
      assert.equal(launch.with[list], `\${{ steps.stage.outputs.${list} }}`, `${id} ${list}`);
    }
    for (const value of ["model", "effort", "max-turns"]) {
      assert.equal(launch.with[value], `\${{ steps.config.outputs.${value} }}`, `${id} ${value}`);
    }
  }
  // The key leg runs on a set key and the token leg only on a fallback call.
  assert.equal(step("act-key").if, "steps.key-present.outputs.present == 'true'");
  assert.equal(step("act-token").if, "steps.token-present.outputs.present == 'true'");
  assert.match(step("key-present").if, /&& inputs\.fallback == ''$/);
  assert.match(step("token-present").if, /&& inputs\.fallback != ''$/);
  // The managed settings need sudo, so they come before the isolation; the
  // head checkout comes after both.
  const index = (name) => jobs.run.steps.findIndex((s) => s.name === name);
  assert.ok(index("Apply the Claude managed settings") < index("Isolate the runner"));
  assert.ok(index("Isolate the runner") < index("Check out the PR head"));
  assert.ok(index("Stage the skill's files in the checkout") < index("Run the skill on the API key"));
  // The staged trusted context is read-only, as the plugin and the CI context are.
  assert.match(jobs.run.steps[index("Stage the skill's files in the checkout")].run, /chmod a-w \.lane\/trusted-context\.json/);
  // The prompt and .lane/ itself too, so a script's --out lands only in .lane/scratch.
  assert.match(jobs.run.steps[index("Stage the skill's files in the checkout")].run, /chmod a-w \.lane\/prompt\.md \.lane\n/);
});

test("no run-claude-cli plugin-dirs or add-dirs value names runner.temp, RUNNER_TEMP or /proc", () => {
  const launchers = [];
  for (const file of workflowFiles()) {
    for (const [id, job] of Object.entries(workflow(file).jobs ?? {})) {
      for (const step of job.steps ?? []) {
        if (!String(step.uses ?? "").includes("/run-claude-cli@")) continue;
        launchers.push(`${file} ${id} ${step.id}`);
        for (const input of ["plugin-dirs", "add-dirs"]) {
          assert.doesNotMatch(String(step.with?.[input] ?? ""), /runner\.temp|RUNNER_TEMP|\/proc/, `${file} ${id} ${input}`);
        }
      }
    }
  }
  assert.ok(launchers.includes("pr-run-activity-read.yml run act-key") && launchers.includes("pr-run-activity-read.yml run act-token"), launchers.join(", "));
});

// Launcher SHAs checked to pass `--permission-prompts none` unconditionally,
// under which the default mode denies every call no rule allows, as dontAsk
// does; check-permission-mode.sh accepts default for dontAsk on that basis.
// 7b362428: lane.cjs:311-312; 164c2809: lane.cjs:355-358; d02b8697: lane.cjs:357-358; in cliArgs. A pin
// bump fails here until its lane.cjs is read and its SHA added.
const PERMISSION_PROMPTS_NONE_LAUNCHERS = new Set([
  "7b362428c76085a160e28656cd2c75c3147a69ff",
  "164c2809f6150429b6f24d4a2777bb377af953d9",
  "d02b8697e092705153f0996549b05f95a446bb52",
]);

test("pr-run-activity-read.yml: every run-claude-cli pin is a launcher checked to pass --permission-prompts none", () => {
  const pins = [];
  for (const [id, job] of Object.entries(workflow("pr-run-activity-read.yml").jobs ?? {})) {
    for (const step of job.steps ?? []) {
      const uses = String(step.uses ?? "");
      if (!uses.includes("/run-claude-cli@")) continue;
      const sha = uses.slice(uses.indexOf("@") + 1);
      pins.push(sha);
      assert.match(sha, /^[0-9a-f]{40}$/, `${id} ${step.id} pins a full SHA`);
      assert.ok(PERMISSION_PROMPTS_NONE_LAUNCHERS.has(sha), `${id} ${step.id}: ${sha} is not checked to pass --permission-prompts none`);
    }
  }
  assert.ok(pins.length >= 2, pins.join(", "));
});

// Each launcher leg is followed by a check that the CLI's init message
// reports the permission mode the base config asked for, or default for
// dontAsk; any other mismatch, a missing init message or an empty mode fails
// it. The key leg's credit stop hands off unchecked. The check runs from the
// base copy in RUNNER_TEMP; check-permission-mode.test.sh holds its cases.
test("pr-run-activity-read.yml: each launcher leg is followed by a check of the CLI's reported permission mode", (t) => {
  const steps = workflow("pr-run-activity-read.yml").jobs.run.steps;
  const at = (id) => steps.findIndex((s) => s.id === id);
  const dir = mkdtempSync(join(tmpdir(), "mode-check-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const copy = steps.find((s) => s.name === "Copy the patch collector and the output sealer from the base");
  assert.match(copy.run, /cp [^\n]*\.base\/\.github\/scripts\/read-patch\/check-permission-mode\.sh [^\n]*"\$DEST\/"/);
  assert.ok(steps.indexOf(copy) < at("act-key"));
  mkdirSync(join(dir, "read-patch"));
  writeFileSync(join(dir, "read-patch", "check-permission-mode.sh"), read("../../scripts/read-patch/check-permission-mode.sh"));
  const file = (name, messages) => {
    const path = join(dir, name);
    writeFileSync(path, typeof messages === "string" ? messages : JSON.stringify(messages));
    return path;
  };
  const init = (mode) => [{ type: "system", subtype: "init", permissionMode: mode }, { type: "result", subtype: "success" }];
  for (const [leg, check] of [["act-key", "mode-key"], ["act-token", "mode-token"]]) {
    const step = steps[at(check)];
    assert.equal(at(check), at(leg) + 1, `${check} follows ${leg}`);
    assert.equal(step.env.EXECUTION_FILE, `\${{ steps.${leg}.outputs.execution-file }}`);
    assert.equal(step.env.MODE, "${{ steps.config.outputs.permission-mode }}");
    assert.ok(!writesSummary(step), `${check} writes no summary`);
    const runs = (mode, execution) =>
      spawnSync("bash", ["-e", "-c", step.run], { env: { PATH: process.env.PATH, RUNNER_TEMP: dir, MODE: mode, EXECUTION_FILE: execution } }).status;
    assert.equal(runs("auto", file(`${check}-auto.json`, init("auto"))), 0);
    assert.equal(runs("dontAsk", file(`${check}-dontask.json`, init("dontAsk"))), 0);
    assert.equal(runs("dontAsk", file(`${check}-default.json`, init("default"))), 0, "default for dontAsk");
    assert.equal(runs("auto", file(`${check}-auto-default.json`, init("default"))), 1, "default for auto");
    assert.equal(runs("auto", file(`${check}-other.json`, init("dontAsk"))), 1, "another mode");
    assert.equal(runs("auto", file(`${check}-none.json`, [{ type: "result", subtype: "success" }])), 1, "no init message");
    assert.equal(runs("auto", join(dir, "missing.json")), 1, "no execution file");
    assert.equal(runs("auto", file(`${check}-bad.json`, "{not json")), 1, "an unreadable file");
    assert.equal(runs("", file(`${check}-empty.json`, init(""))), 1, "an empty mode");
  }
  const ran = { "steps.act-key.outcome": "failure", "steps.act-key.outputs.handoff": "false" };
  assert.equal(atStep(steps[at("mode-key")].if, ran), true);
  assert.equal(atStep(steps[at("mode-key")].if, { ...ran, "steps.act-key.outputs.handoff": "true" }), false, "a handoff (a credit stop, or a 401 or 402)");
  assert.equal(atStep(steps[at("mode-key")].if, { "steps.act-key.outcome": "skipped", "steps.act-key.outputs.handoff": "" }), false);
  // A failed check fails the job before the patch is collected.
  assert.ok(at("mode-token") < at("patch"));
  assert.match(steps[at("patch")].if, /job\.status == 'success'/);
});

// A call that handed off (its key empty, or a credit stop on its key leg)
// uploads nothing, records no lane outcome and posts no check: the fallback
// call's artifacts take the same names, and fix-ci-dispatch.mjs counts the
// fix-ci checks on a head.
test("pr-run-activity-read.yml: a handoff skips every upload, the lane record, the patch and the report", () => {
  const { jobs } = workflow("pr-run-activity-read.yml");
  const run = jobs.run;
  const base = {
    "inputs.issue-number": "",
    "inputs.fallback": "",
    "job.status": "success",
    "steps.go.outputs.run": "true",
    "steps.config.outputs.kind": "skill",
    "steps.config.outputs.applied-by-patch": "apply-patch",
    "steps.launch.outcome": "success",
    "steps.act-token.outcome": "skipped",
    "steps.mode-token.outcome": "skipped",
    "steps.token-present.outcome": "skipped",
    "steps.token-present.outputs.present": "",
    "steps.key-present.outcome": "success",
    "steps.patch.outputs.state": "written",
  };
  // run-claude-cli's handoff output: a credit stop, or class auth with a 401
  // or 402; the mode check skips a handoff.
  const handoffs = {
    "an empty key": { ...base, "steps.key-present.outputs.present": "false", "steps.act-key.outcome": "skipped", "steps.act-key.outputs.handoff": "", "steps.mode-key.outcome": "skipped" },
    "a credit stop": { ...base, "steps.key-present.outputs.present": "true", "steps.act-key.outcome": "failure", "steps.act-key.outputs.handoff": "true", "steps.mode-key.outcome": "skipped" },
  };
  const ran = { ...base, "steps.key-present.outputs.present": "true", "steps.act-key.outcome": "success", "steps.act-key.outputs.handoff": "false", "steps.mode-key.outcome": "success" };
  const guarded = run.steps.filter((s) => /^actions\/upload-artifact@|\/report-lane-outcome@/.test(String(s.uses ?? "")) || s.id === "patch");
  assert.deepEqual(
    guarded.map((s) => s.id ?? s.name),
    ["lane-record", "patch"],
  );
  const outcome = run.steps.find((s) => s.name === "Collect the issue outcome");
  for (const step of guarded) {
    for (const [name, context] of Object.entries(handoffs)) {
      assert.equal(atStep(step.if, context), false, `${step.id ?? step.name} after ${name}`);
      // An issue run's handoff too: the fallback call's outcome and patch are the run's.
      assert.equal(atStep(step.if, { ...context, "inputs.issue-number": "7" }), false, `${step.id ?? step.name} after ${name} in issue mode`);
    }
  }
  for (const [name, context] of Object.entries(handoffs)) {
    assert.equal(atStep(outcome.if, { ...context, "inputs.issue-number": "7" }), false, `the issue outcome after ${name}`);
  }
  assert.equal(atStep(outcome.if, { ...ran, "inputs.issue-number": "7" }), true, "an issue run that ran collects its outcome");
  // A call that ran collects its patch and records its outcome; its uploads are the scan job's.
  for (const step of guarded) {
    assert.equal(atStep(step.if, ran), true, step.id ?? step.name);
  }
  // An issue run keeps a failed leg's partial patch only when its permission
  // mode checked out.
  const failed = { ...ran, "inputs.issue-number": "7", "job.status": "failure", "steps.act-key.outcome": "failure" };
  const patch = run.steps.find((s) => s.id === "patch");
  assert.equal(atStep(patch.if, failed), true, "a failed leg in the asked mode");
  assert.equal(atStep(patch.if, { ...failed, "steps.mode-key.outcome": "failure" }), false, "a leg in another mode");
  assert.equal(atStep(patch.if, { ...failed, "inputs.issue-number": "" }), false, "a failed PR-mode leg collects nothing");
  // The scan job, which uploads the reply, patch and verdict, is skipped on a handoff.
  const scanRuns = (handedOffOutput, result = "success") =>
    atStep(jobs.scan.if, { "needs.run.outputs.handed-off": handedOffOutput, "needs.run.result": result });
  assert.equal(scanRuns("true"), false);
  assert.equal(scanRuns("false"), true);
  assert.equal(scanRuns("false", "failure"), true, "a failed run still posts its verdict");
  assert.equal(scanRuns("false", "skipped"), false, "a run job the broker check skipped");
  assert.equal(scanRuns("false", "cancelled"), false);
  const handedOff = (context) => atStep(run.outputs["handed-off"], context);
  assert.equal(handedOff(handoffs["an empty key"]), true);
  assert.equal(handedOff(handoffs["a credit stop"]), true);
  assert.equal(handedOff(ran), false);
  assert.equal(handedOff({ "steps.key-present.outputs.present": "", "steps.act-key.outputs.handoff": "" }), false, "the fallback call never hands off");
  assert.equal(handedOff({ ...ran, "steps.act-key.outcome": "failure", "steps.act-key.outputs.handoff": "false" }), false, "a rate limit or a 403 is no handoff");

  const report = (handedOffOutput) =>
    atStep(jobs.report.if, {
      "inputs.issue-number": "",
      "needs.run.outputs.handed-off": handedOffOutput,
      "github.event_name": "workflow_dispatch",
      "github.event.pull_request.head.repo.full_name": "",
      "github.repository": "o/r",
      "format('{0}', github.event.sender.id)": "1",
      "vars.AUTOMATION_LANES_APP_SENDER_ID": "2",
    });
  assert.equal(report("true"), false);
  assert.equal(report("false"), true);

  // The handoff ends green; a call left with no launcher success fails.
  const fail = run.steps.find((s) => s.name === "Fail without a result");
  assert.equal(run.steps.at(-1), fail, "the run job's last step");
  for (const [name, context] of Object.entries(handoffs)) assert.equal(atStep(fail.if, context), false, name);
  assert.equal(atStep(fail.if, ran), false);
  assert.equal(atStep(fail.if, { ...ran, "steps.act-key.outcome": "failure", "steps.act-key.outputs.handoff": "false" }), true);
  const noToken = {
    ...base,
    "inputs.fallback": "handoff",
    "steps.key-present.outcome": "skipped",
    "steps.key-present.outputs.present": "",
    "steps.act-key.outcome": "skipped",
    "steps.act-key.outputs.handoff": "",
    "steps.token-present.outcome": "success",
    "steps.token-present.outputs.present": "false",
  };
  assert.equal(atStep(fail.if, noToken), true, "an empty token on the fallback call fails red");
  assert.equal(spawnSync("bash", ["-c", fail.run]).status, 1);
});

// The lane record's name, with each format() call filled from `values`.
function laneRecordName(record, context, values) {
  const filled = record.with.lane.replace(/format\('([^']*)'((?:, [\w.-]+)+)\)/g, (_, text, args) =>
    JSON.stringify(args.split(", ").slice(1).reduce((out, arg, i) => out.replace(`{${i}}`, values[arg]), text)),
  );
  return atStep(filled, { ...context, "inputs.lane": values["inputs.lane"] });
}

test("pr-run-activity-read.yml: the fallback call's lane record names why it ran", () => {
  const { jobs } = workflow("pr-run-activity-read.yml");
  const record = jobs.run.steps.find((s) => s.name === "Record the launcher's lane outcome");
  const pr = { "inputs.lane": "pr-unblock", "inputs.activity": "fix-ci", "steps.launch.outputs.key-name": "PR_UNBLOCK_CLAUDE_API_KEY" };
  const lane = (fallback) => laneRecordName(record, { "inputs.issue-number": "", "inputs.fallback": fallback }, pr);
  assert.equal(lane(""), "pr-unblock/fix-ci");
  assert.equal(lane("credit-stop"), "pr-unblock/fix-ci (key PR_UNBLOCK_CLAUDE_API_KEY hit a credit stop)");
  assert.equal(lane("no-key"), "pr-unblock/fix-ci (key PR_UNBLOCK_CLAUDE_API_KEY is empty)");
  assert.equal(lane("handoff"), "pr-unblock/fix-ci (key PR_UNBLOCK_CLAUDE_API_KEY posted no check)");
  // An issue run keeps the lane's own name, which the issue lane's records
  // carried on claude-code-action.
  const issue = { "inputs.lane": "work-resolve-issue", "inputs.activity": "resolve-issue", "steps.launch.outputs.key-name": "ISSUE_LANE_CLAUDE_API_KEY" };
  const issueLane = (fallback) => laneRecordName(record, { "inputs.issue-number": "7", "inputs.fallback": fallback }, issue);
  assert.equal(issueLane(""), "work-resolve-issue");
  assert.equal(issueLane("handoff"), "work-resolve-issue (key ISSUE_LANE_CLAUDE_API_KEY handed off)");
  assert.equal(record.with["step-timeout-minutes"], "${{ steps.launch.outputs.step-minutes }}", "the launcher step's timeout");
  assert.equal(record.with.credential, "${{ steps.act-key.outputs.credential || steps.act-token.outputs.credential }}", "the credential the leg ran on");
});

// A caller whose handoff job read only that the first call posted no check
// passes fallback handoff; the run job's input check must let it through.
test("pr-run-activity-read.yml: the fallback input takes empty, credit-stop, no-key or handoff, and nothing else", () => {
  const step = workflow("pr-run-activity-read.yml").jobs.run.steps.find((s) => s.env?.FALLBACK === "${{ inputs.fallback }}");
  const check = /^ *case "\$FALLBACK" in\n[\s\S]*?^ *esac$/m.exec(step.run)[0];
  const status = (fallback) => spawnSync("bash", ["-c", check], { env: { FALLBACK: fallback }, encoding: "utf8" }).status;
  for (const fallback of ["", "credit-stop", "no-key", "handoff"]) assert.equal(status(fallback), 0, fallback);
  for (const fallback of ["handoff ", "posted", "credit-stop\nno-key"]) assert.equal(status(fallback), 1, JSON.stringify(fallback));
});

// Each patch producer run on run-claude-cli, as [file, first job,
// subscription job, the subscription job's other needs, the outputs of those
// needs it must also see, the push job]. Each call holds one Claude secret
// beside the scan-carrier key; the subscription job holds only the OAuth
// token and reads the first job's outputs only through two exact compares;
// the push job holds no Claude credential and takes the patch from whichever
// call ran the activity.
const PATCH_LANES = [
  ["pr-unblock.yml", "fix-ci", "fix-ci-subscription", ["fix-ci-context"], { "needs.fix-ci-context.outputs.proceed": "true" }, "apply-patch"],
  ["pr-refine.yml", "fix-docs", "fix-docs-subscription", ["fix-docs-head"], {}, "apply-docs-patch"],
  // apply-feedback-patch stays out of report-escalation: every refusal leaves
  // no fix commit, and publish-feedback escalates feedback-not-landed
  // (publish-feedback.test.mjs).
  [
    "pr-unblock.yml",
    "address-feedback",
    "address-feedback-subscription",
    ["address-feedback-select"],
    { "needs.address-feedback-select.outputs.proceed": "true" },
    "apply-feedback-patch",
  ],
  // apply-dependency-patch stays out of report-escalation too: a refused
  // patch leaves no fix commit, and the verdict job escalates
  // dependency-fix-not-landed (apply-dependency-verdict.test.mjs).
  [
    "pr-unblock.yml",
    "review-dependency",
    "review-dependency-subscription",
    ["review-dependency-select"],
    { "needs.review-dependency-select.outputs.proceed": "true" },
    "apply-dependency-patch",
  ],
  // apply-conflict-patch reaches report-escalation: an empty or refused
  // patch leaves the conflicts to a person.
  [
    "pr-unblock.yml",
    "resolve-conflicts",
    "resolve-conflicts-subscription",
    ["resolve-conflicts-select"],
    { "needs.resolve-conflicts-select.outputs.proceed": "true" },
    "apply-conflict-patch",
  ],
];
// The activity each push job runs in the write runner.
const APPLY_ACTIVITY = {
  "fix-ci": "apply-patch",
  "fix-docs": "apply-patch",
  "address-feedback": "apply-feedback-patch",
  "review-dependency": "apply-dependency-patch",
  "resolve-conflicts": "apply-conflict-patch",
};
const CARRIER_SECRETS = { "scan-carrier-private-key": "${{ secrets.SCAN_CARRIER_PRIVATE_KEY }}" };
// The head apply-patch holds the patch to, per producer. fix-ci's push job
// takes the head fix-ci-context gated, and fix-docs's the head fix-docs-head
// read, each from a job that ran no head code; apply-patch applies onto the
// head its own gate reads either way.
const PATCH_HEAD = {
  "fix-ci": { needs: ["fix-ci-context"], value: "${{ needs.fix-ci-context.outputs.head-sha }}" },
  "fix-docs": { needs: ["fix-docs-head"], value: "${{ needs.fix-docs-head.outputs.head-sha }}" },
  "address-feedback": { needs: ["address-feedback-select"], value: "${{ needs.address-feedback-select.outputs.head-sha }}" },
  "review-dependency": { needs: ["review-dependency-select"], value: "${{ needs.review-dependency-select.outputs.head-sha }}" },
  "resolve-conflicts": { needs: ["resolve-conflicts-select"], value: "${{ needs.resolve-conflicts-select.outputs.head-sha }}" },
};
// What else a push job's gate reads, set so a conflicted round's patch decides it.
const APPLY_GATE = {
  "resolve-conflicts": { "needs.resolve-conflicts-select.outputs.merge-state": "conflicted", "needs.resolve-conflicts-select.outputs.proceed": "true" },
};
// Whether an empty patch still runs the push job, and its escalation reaches
// report-escalation, which hands the PR to a person: fix-ci's does; no change
// is fix-docs's common case, and its refused patch posts its check neutral and
// labels nothing (report-escalation takes no patch-* reason).
// address-feedback's empty patch is a round whose every reply needs no fix,
// and review-dependency's one whose verdict needs none.
// resolve-conflicts's empty patch leaves the conflicts unresolved.
const EMPTY_RUNS_APPLY = { "fix-ci": true, "fix-docs": false, "address-feedback": false, "review-dependency": false, "resolve-conflicts": true };
const PATCH_OUTPUTS = { "patch-state": "patch-state", "patch-sha256": "patch-sha256", "patch-attempt": "patch-attempt", "reply-attempt": "reply-attempt" };
// The read runner output each push job reads per input: the scan job's alone,
// never the run job's, which head code can forge.
const SCAN_ONLY = new Set(["fix-ci", "fix-docs", "address-feedback", "review-dependency", "resolve-conflicts"]);
// The base-code job whose jobs-API read starts a lane's fallback call, in
// place of the first call's own handoff outputs.
const HANDOFF = {
  "fix-ci": "fix-ci-handoff",
  "fix-docs": "fix-docs-handoff",
  "address-feedback": "address-feedback-handoff",
  "review-dependency": "review-dependency-handoff",
  "resolve-conflicts": "resolve-conflicts-handoff",
};
const PATCH_OUTPUTS_OF = (firstId) =>
  SCAN_ONLY.has(firstId) ? Object.fromEntries(Object.entries(PATCH_OUTPUTS).map(([input, output]) => [input, `scan-${output}`])) : PATCH_OUTPUTS;
const WRITE_RUNNER = "./.github/workflows/pr-run-activity-write.yml";

for (const [file, firstId, subId, extraNeeds, extraProceed, applyId] of PATCH_LANES) {
  test(`${file}: ${subId} runs only after ${firstId} handed off, read ${HANDOFF[firstId] ? `by ${HANDOFF[firstId]}` : "from its credit stop or empty key alone"}`, () => {
    const { jobs } = workflow(file);
    const first = jobs[firstId];
    const sub = jobs[subId];
    assert.equal(first.uses, READ_RUNNER);
    assert.equal(sub.uses, READ_RUNNER);
    assert.deepEqual([sub.needs].flat(), [...extraNeeds, firstId, ...(HANDOFF[firstId] ? [HANDOFF[firstId]] : [])]);
    assert.deepEqual(first.secrets, { "claude-api-key": "${{ secrets.PR_UNBLOCK_CLAUDE_API_KEY }}", ...CARRIER_SECRETS });
    assert.deepEqual(sub.secrets, { "claude-code-oauth-token": "${{ secrets.PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN }}", ...CARRIER_SECRETS });
    // The report job posts and labels through the caller's grant.
    for (const job of [first, sub]) assert.equal(job.permissions.issues, "write");
    assert.equal(first.with.role, "pr-unblock");
    assert.equal(first.with.fallback, undefined);
    const { fallback, ...same } = sub.with;
    assert.deepEqual(same, first.with, "the fallback call runs the same activity on the same inputs");
    // The first call's outputs reach the fallback call only through two exact
    // compares, and a lane with a handoff job not at all: its fallback is the
    // one fact the handoff job's read attests, that the first call posted no check.
    const outputsOf = new RegExp(`needs\\.${firstId}\\.outputs\\.`);
    const text = JSON.stringify(sub);
    const compares = [...text.matchAll(new RegExp(`needs\\.${firstId}\\.outputs\\.([\\w-]+) == '([^']*)'`, "g"))].map((m) => `${m[1]} == ${m[2]}`);
    assert.deepEqual([...new Set(compares)].sort(), HANDOFF[firstId] ? [] : ["credential-present == false", "lane-class == credit-stop"]);
    assert.doesNotMatch(
      text.replace(new RegExp(`needs\\.${firstId}\\.outputs\\.(lane-class == 'credit-stop'|credential-present == 'false')`, "g"), ""),
      outputsOf,
    );
    if (!HANDOFF[firstId]) {
      const runs = (laneClass, present, proceed = extraProceed) =>
        evaluate(sub.if, {
          ...proceed,
          [`needs.${firstId}.outputs.lane-class`]: laneClass,
          [`needs.${firstId}.outputs.credential-present`]: present,
        });
      assert.equal(runs("credit-stop", "true"), true);
      assert.equal(runs("", "false"), true);
      for (const laneClass of ["", "rate-limit", "max-turns", "timeout", "other", "credit-stop "]) {
        assert.equal(runs(laneClass, "true"), false, JSON.stringify(laneClass));
      }
      assert.equal(runs("", ""), false, `a ${firstId} that stopped before its credential step`);
      for (const name of Object.keys(extraProceed)) {
        assert.equal(runs("credit-stop", "true", { ...extraProceed, [name]: "false" }), false, `${name} false`);
      }
    }
    if (HANDOFF[firstId]) {
      assert.equal(fallback, "handoff");
    } else {
      assert.equal(evaluate(fallback, { [`needs.${firstId}.outputs.lane-class`]: "credit-stop" }), "credit-stop");
      assert.equal(evaluate(fallback, { [`needs.${firstId}.outputs.lane-class`]: "" }), "no-key");
    }
    // No run: script in the lane reads the first call's outputs.
    for (const [id, job] of Object.entries(jobs)) {
      for (const step of job.steps ?? []) {
        assert.doesNotMatch(String(step.run ?? ""), outputsOf, `${id} ${step.name}`);
      }
    }
    // Both calls and the push job queue in one per-PR write group, never cancelled.
    assert.match(first.concurrency.group, /^pr-pipeline-write-\$\{\{ (github\.event\.pull_request\.number \|\| )?inputs\.pr-number \}\}$/);
    for (const id of [firstId, subId, applyId]) {
      assert.deepEqual(jobs[id].concurrency, { group: first.concurrency.group, queue: "max" }, id);
    }
    assert.equal(first.with["timeout-minutes"], 60, "the run job holds the 50-minute launcher step");
  });

  test(`${file}: ${applyId} takes the patch from whichever ${firstId} call ran the activity, under ${firstId}'s prepare-mode row`, () => {
    const { jobs } = workflow(file);
    const apply = jobs[applyId];
    assert.deepEqual(apply.needs, [...PATCH_HEAD[firstId].needs, firstId, subId]);
    assert.equal(apply.permissions.issues, "write");
    assert.equal(apply.uses, WRITE_RUNNER);
    assert.equal(apply.with.activity, APPLY_ACTIVITY[firstId]);
    assert.equal(apply.with["patch-activity"], firstId);
    assert.equal(apply.with["trusted-base"], jobs[firstId].with["trusted-base"]);
    assert.equal(apply.secrets, undefined, "the push job gets no Claude credential");
    const config = parse(read("../../../docs/conventions/pr-pipeline.yaml"));
    assert.equal(apply.with["patch-prepare"] ?? "", config.activities[firstId].prepare ?? "", "the row of the producer's prepare mode");
    const context = (from) => {
      const values = { [`needs.${subId}.result`]: from === subId ? "success" : "skipped" };
      for (const job of [subId, firstId]) {
        for (const output of Object.values(PATCH_OUTPUTS_OF(firstId))) {
          values[`needs.${job}.outputs.${output}`] = job === from ? `${job}:${output}` : "";
        }
      }
      return values;
    };
    for (const from of [firstId, subId]) {
      for (const [input, output] of Object.entries(PATCH_OUTPUTS_OF(firstId))) {
        assert.equal(evaluate(apply.with[input], context(from)), `${from}:${output}`, `${input} after ${from}`);
      }
    }
    const head = PATCH_HEAD[firstId].value;
    if (head) {
      assert.equal(apply.with["patch-head-sha"], head);
    } else {
      for (const from of [firstId, subId]) {
        const values = { [`needs.${subId}.outputs.head-sha`]: "", [`needs.${firstId}.outputs.head-sha`]: "", [`needs.${from}.outputs.head-sha`]: `${from}:head-sha` };
        assert.equal(evaluate(apply.with["patch-head-sha"], values), `${from}:head-sha`, `patch-head-sha after ${from}`);
      }
    }
    const state = PATCH_OUTPUTS_OF(firstId)["patch-state"];
    const runs = (firstState, subState) =>
      evaluate(apply.if, {
        ...APPLY_GATE[firstId],
        [`needs.${subId}.result`]: subState === "" ? "skipped" : "success",
        [`needs.${subId}.outputs.${state}`]: subState,
        [`needs.${firstId}.outputs.${state}`]: firstState,
        [`needs.${subId}.outputs.feedback-attempt`]: "1",
        [`needs.${firstId}.outputs.feedback-attempt`]: "1",
        [`needs.${subId}.outputs.dependency-verdict`]: "fix",
        [`needs.${firstId}.outputs.dependency-verdict`]: "fix",
        [`needs.${subId}.outputs.scan-collect-refused`]: "",
        [`needs.${firstId}.outputs.scan-collect-refused`]: "",
      });
    assert.equal(runs("written", ""), true);
    assert.equal(runs("", "written"), true);
    assert.equal(runs("", "empty"), EMPTY_RUNS_APPLY[firstId], "an empty patch");
    assert.equal(runs("empty", ""), EMPTY_RUNS_APPLY[firstId], "an empty patch");
    assert.equal(runs("", ""), false, "a handoff whose fallback call left no patch");
    const escalation = jobs["report-escalation"];
    if (escalation === undefined) {
      // A lane with no escalation job hands no PR to a person.
      assert.equal(EMPTY_RUNS_APPLY[firstId], false, `${file} has no report-escalation for ${applyId}`);
      return;
    }
    for (const need of escalation.needs) assert.ok(Object.hasOwn(jobs, need), `report-escalation needs ${need}, a job of the file`);
    if (EMPTY_RUNS_APPLY[firstId]) {
      assert.ok(escalation.needs.includes(applyId));
    } else {
      for (const id of [firstId, subId, applyId]) {
        assert.ok(!escalation.needs.includes(id), `report-escalation does not need ${id}`);
        assert.doesNotMatch(JSON.stringify(escalation), new RegExp(`needs\\.${id}\\.`), `report-escalation reads no ${id} output`);
      }
    }
  });
}

test("pr-run-activity-write.yml passes the producer's prepare mode to both apply-patch steps", () => {
  const { jobs } = workflow("pr-run-activity-write.yml");
  const steps = Object.values(jobs).flatMap((job) => job.steps ?? []);
  for (const name of ["Select the patch", "Run the script activity"]) {
    const step = steps.find((candidate) => candidate.name === name);
    assert.ok(step, name);
    assert.equal(step.env.PATCH_PREPARE, "${{ inputs.patch-prepare }}", `${name} sets PATCH_PREPARE, or apply-patch.mjs uses the default row`);
  }
});

// fix-docs starts only from a pr-refine.yml dispatch naming it: the
// dispatcher, or a listed person. Every fix-docs job trusts the default
// branch tip, and the lanes App's own dispatch starts none.
test("pr-refine.yml: fix-docs runs only on a fix-docs dispatch with a PR number, never the lanes App's, trusting the default branch tip", () => {
  const { on, jobs, "run-name": runName } = workflow("pr-refine.yml");
  assert.deepEqual(Object.keys(on), ["workflow_dispatch"], "dispatch only, no pull_request trigger");
  assert.deepEqual(on.workflow_dispatch.inputs.activity.options, ["fix-docs"]);
  // fix-docs-dispatch.mjs matches this title to skip a PR whose run is not done.
  assert.equal(runName, "pr-refine ${{ inputs.activity }} #${{ inputs.pr-number }}");
  for (const id of ["fix-docs", "fix-docs-subscription", "apply-docs-patch"]) {
    assert.equal(jobs[id].with["trusted-base"], "default-tip", id);
    assert.equal(jobs[id].with["dispatcher-run-id"], "${{ inputs.dispatcher-run-id }}", id);
    assert.equal(jobs[id].with.lane, "pr-refine", id);
    assert.deepEqual(jobs[id].permissions, { contents: "read", "pull-requests": "read", checks: "write", issues: "write", "id-token": "write" }, id);
  }
  const starts = ({ activity = "fix-docs", pr = "7", sender = "1", held = "false" } = {}) =>
    evaluate(jobs["fix-docs"].if, {
      "inputs.pr-number": pr,
      "inputs.activity": activity,
      "format('{0}', github.event.sender.id)": sender,
      "vars.AUTOMATION_LANES_APP_SENDER_ID": "2",
      "needs.fix-docs-head.outputs.held": held,
    });
  assert.equal(starts(), true);
  // fix-docs-head's lane-hold.mjs step: a human-gated hold, or no answer, runs nothing.
  assert.equal(starts({ held: "true" }), false);
  assert.equal(starts({ held: "" }), false);
  const hold = jobs["fix-docs-head"].steps.find((step) => step.id === "hold");
  assert.equal(hold.run, "node .base/.github/scripts/pr-unblock/lane-hold.mjs");
  assert.equal(hold.env.ACTIVITY, "fix-docs");
  assert.equal(jobs["apply-docs-patch"].with["patch-fix-requested"], "${{ needs.fix-docs-head.outputs.lane-escalated }}");
  assert.equal(starts({ activity: "fix-ci" }), false);
  assert.equal(starts({ activity: "resolve-conflicts" }), false);
  assert.equal(starts({ pr: "" }), false);
  assert.equal(starts({ sender: "2" }), false, "the lanes App's own dispatch");
  const unblock = workflow("pr-unblock.yml");
  assert.ok(!unblock.on.workflow_dispatch.inputs.activity.options.includes("fix-docs"), "pr-unblock.yml no longer takes fix-docs");
  assert.deepEqual(Object.keys(unblock.jobs).filter((id) => /docs/.test(id)), []);
});

// The read report job posts on the run's head only when it equals a head the
// caller or event gated; with neither it trusts the PR head read at report
// time, so a push mid-run made a finished run look forged and posted failure
// on the new head (#9207). Runs the report job's head step with the head-sha
// each pr-unblock and pr-refine call passes.
test("pr-unblock.yml and pr-refine.yml: a read activity whose PR head moved mid-run posts on its own head, never on the new one", () => {
  const old = "1".repeat(40);
  const moved = "2".repeat(40);
  const jobs = { ...workflow("pr-unblock.yml").jobs, ...workflow("pr-refine.yml").jobs };
  const read = workflow("pr-run-activity-read.yml");
  const step = read.jobs.report.steps.find((s) => s.name === "Choose the head the check is posted on");
  const choose = (callerHead, runHead, postDecline = true) => {
    const dir = mkdtempSync(join(tmpdir(), "w9207-"));
    try {
      const output = join(dir, "output");
      writeFileSync(output, "");
      spawnSync("bash", ["-c", step.run], {
        env: {
          PATH: process.env.PATH,
          GITHUB_OUTPUT: output,
          RUN_HEAD: runHead,
          CALLER_HEAD: callerHead,
          EVENT_HEAD: "",
          API_HEAD: moved,
          PR_MISMATCH: "",
          TRUSTED_SKIP: "false",
          POST_DECLINE: String(postDecline),
        },
      });
      return Object.fromEntries(readFileSync(output, "utf8").trim().split("\n").map((line) => line.split("=")));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };
  const callers = Object.entries(jobs).filter(([, job]) => job.uses === "./.github/workflows/pr-run-activity-read.yml");
  assert.ok(callers.some(([id]) => id === "fix-docs"));
  for (const [id, job] of callers) {
    const given = job.with["head-sha"] ?? "";
    const callerHead = given === "" ? "" : evaluate(given, Object.fromEntries([...given.matchAll(/needs\.[\w-]+\.outputs\.head-sha/g)].map(([ref]) => [ref, old])));
    assert.equal(callerHead, old, `${id} passes the head a base job read`);
    assert.deepEqual(choose(callerHead, old), { post: "true", sha: old, forged: "false" }, id);
    assert.deepEqual(choose(callerHead, "3".repeat(40)), { post: "true", sha: old, forged: "true" }, `${id}: a foreign run head still fails`);
    // A run that declines before its trigger gate leaves an empty head:
    // fix-ci posts neutral not-assessed so fix-ci-dispatch moves on; fix-docs,
    // dispatched once per PR, posts nothing so it is dispatched again.
    const postDecline = job.with["post-decline"] ?? true;
    assert.equal(postDecline, !id.startsWith("fix-docs"), `${id} post-decline`);
    assert.deepEqual(
      choose(callerHead, "", postDecline),
      postDecline ? { post: "true", sha: old, forged: "false", "not-run-reason": "not-assessed" } : { post: "true", sha: "", forged: "false" },
      `${id}: a declined run`,
    );
  }
  assert.equal(read.on.workflow_call.inputs["post-decline"].default, true);
});

test("pr-run-activity-read.yml: with output-mode gone, issue mode still refuses an activity that hands on no patch", () => {
  const read = workflow("pr-run-activity-read.yml");
  assert.equal(read.on.workflow_call.inputs["output-mode"], undefined);
  const steps = read.jobs.run.steps;
  const guard = steps.find((s) => s.name === "Assert an issue activity is in patch mode");
  const refuses = (issue, patch) =>
    evaluate(guard.if, { "steps.config.outcome": "success", "inputs.issue-number": issue, "steps.config.outputs.applied-by-patch": patch });
  assert.equal(refuses("7", ""), true, "an issue activity with no applied-by patch");
  assert.equal(spawnSync("bash", ["-c", guard.run]).status, 1);
  assert.equal(refuses("7", "apply-issue-patch"), false);
  assert.equal(refuses("", ""), false, "a PR-mode read activity may leave a clean tree");
  const index = (predicate) => steps.findIndex(predicate);
  assert.ok(index((s) => s === guard) > index((s) => s.id === "config"));
  assert.ok(index((s) => s === guard) < index((s) => s.name === "Check out the PR head"), "before any head code");
  assert.ok(index((s) => s === guard) < index((s) => s.id === "act-key"));
});

// --- the PR-mode leak scan, before any upload or summary ---

const runSteps = () => workflow("pr-run-activity-read.yml").jobs.run.steps;
const scanSteps = () => workflow("pr-run-activity-read.yml").jobs.scan.steps;
const writesSummary = (step) => /GITHUB_STEP_SUMMARY|core\.summary/.test(`${step.run ?? ""}${step.with?.script ?? ""}`);
const isUpload = (step) => String(step.uses ?? "").startsWith("actions/upload-artifact@");

test("pr-run-activity-read.yml: the model job uploads nothing and writes no step summary in either mode", () => {
  const steps = runSteps();
  assert.deepEqual(steps.filter(isUpload).map((s) => s.name), [], "every upload is the scan job's");
  assert.deepEqual(steps.filter(writesSummary).map((s) => s.name), [], "the scan job shows the run after its leak scan");
  // The leak scan and the verdict are the scan job's alone; a
  // dependency-review skill's dependency-verdict.json is a payload it carries.
  for (const step of steps) {
    assert.notEqual(step.id, "leak-scan");
    assert.doesNotMatch(String(step.with?.name ?? ""), /^verdict-/, step.name);
    assert.doesNotMatch(String(step.run ?? ""), /(?<![\w-])verdict\.json/, step.name);
  }
});

test("pr-run-activity-read.yml: the scan job holds only the scan-carrier key, in its decode step, under its environment, with no id-token, no cache and no artifact from the run job", () => {
  const { jobs } = workflow("pr-run-activity-read.yml");
  const scan = jobs.scan;
  assert.equal(scan["runs-on"], "ubuntu-24.04");
  assert.deepEqual(scan.needs, ["run", "issue-fields"]);
  assert.deepEqual(scan.permissions, { contents: "read" });
  assert.equal(scan.environment, "pr-pipeline-scan-carrier");
  assert.deepEqual(stepSecrets(scan), ["scan-carrier-private-key"], "the one secret in the job");
  assert.deepEqual(scan.steps.filter((step) => stepSecrets(step).length > 0).map((step) => step.id), ["open"], "read in the decode step alone");
  assert.doesNotMatch(JSON.stringify(scan), /id-token|ACTIONS_ID_TOKEN/);
  // The one action from a checkout is the opener, from the default branch tip
  // the event names: no run job output chooses the code that holds the key.
  const base = scan.steps.find((step) => step.id === "base");
  assert.deepEqual([base.with.ref, base.with.path, base.with["persist-credentials"]], ["${{ github.event.repository.default_branch }}", ".base", false]);
  for (const id of ["base", "key", "open"]) {
    const step = scan.steps.find((s) => s.id === id);
    assert.doesNotMatch(JSON.stringify({ with: step.with, run: step.run, uses: step.uses }), /base-sha|head-sha|default-tip/, `${id}: no run job output names a commit or path`);
  }
  // The AAD's job id is a literal on both sides, and the run id is each job's own.
  const seal = jobs.run.steps.find((step) => step.id === "seal");
  assert.equal(seal.with["job-id"], "run");
  assert.equal(scan.steps.find((step) => step.id === "open").with["job-id"], "run");
  for (const action of ["seal-lane-output/seal.mjs", "open-lane-output/open.mjs"]) assert.match(read(`../${action}`), /env\.GITHUB_RUN_ID/, action);
  for (const step of scan.steps) {
    assert.doesNotMatch(String(step.uses ?? ""), /^actions\/(cache|download-artifact)@/, step.name);
    if (step.id !== "open") assert.doesNotMatch(String(step.uses ?? ""), /^\.\//, `${step.name}: no other action from a checkout`);
  }
  // Payloads reach a script only through env, never inlined.
  for (const step of scan.steps) {
    assert.doesNotMatch(`${step.run ?? ""}${step.with?.script ?? ""}`, /\$\{\{/, step.name);
  }
  // It is the only job that uploads the reply, patch and verdict in PR mode, each once per name.
  const uploads = Object.entries(jobs).flatMap(([id, job]) => (job.steps ?? []).filter(isUpload).map((step) => [id, step]));
  for (const prefix of ["skill-reply-", "patch-", "verdict-"]) {
    const named = uploads.filter(([, step]) => String(step.with.name).startsWith(prefix));
    const scanUploads = named.filter(([id]) => id === "scan");
    assert.equal(scanUploads.length, 1, prefix);
    assert.equal(scanUploads[0][1].with.overwrite, false, prefix);
    for (const [id, step] of named.filter(([id]) => id !== "scan")) assert.match(String(step.if), /inputs\.issue-number != ''/, `${id} ${prefix}`);
  }
});

test("pr-run-activity-read.yml: the leak scan runs after the decode and gates every later upload and summary", () => {
  const steps = scanSteps();
  const at = (id) => steps.findIndex((step) => step.id === id);
  const scan = at("leak-scan");
  assert.deepEqual(steps.slice(0, 2).map((step) => step.id ?? step.name), ["Require the checked issue fields", "Assert the default branch is set"]);
  assert.deepEqual(["base", "key", "open", "decode"].map(at), [2, 3, 4, 5]);
  assert.ok(at("decode") < scan);
  const outputs = steps.filter((step) => (isUpload(step) && !String(step.with.name).startsWith("verdict-")) || writesSummary(step));
  assert.equal(outputs.length, 6);
  const context = (clean) => ({
    "inputs.issue-number": "7",
    "steps.decode.outputs.outcome": "true",
    "steps.leak-scan.outputs.clean": clean,
    "steps.decode.outputs.reply": "true",
    "steps.decode.outputs.patch": "true",
    "steps.decode.outputs.replies": "true",
    "steps.decode.outputs.dependency-verdict": "true",
  });
  for (const step of outputs) {
    assert.ok(steps.indexOf(step) > scan, `${step.name} comes after the scan`);
    assert.equal(atStep(step.if, context("true")), true, `${step.name} runs on a clean scan`);
    assert.equal(atStep(step.if, context("false")), false, `${step.name} is dropped on a hit`);
    assert.equal(atStep(step.if, context("")), false, `${step.name} is dropped when no scan ran`);
  }
  // A hit skips the patch upload, so the scan job's patch-state is never `written`.
  assert.match(workflow("pr-run-activity-read.yml").jobs.scan.outputs["patch-state"], /^\$\{\{ steps\.patch-upload\.outcome == 'success' && 'written'/);
});

// Every context reference in an expression, empty unless the PR-mode skill
// run below or the overrides set it.
const PR_RUN = {
  "inputs.issue-number": "",
  "steps.go.outputs.run": "true",
  "steps.key-present.outcome": "success",
  "steps.key-present.outputs.present": "true",
  "steps.act-skill.outcome": "skipped",
  "steps.act-key.outcome": "success",
  "steps.act-token.outcome": "skipped",
  "steps.patch.outputs.state": "written",
};
function prRun(expression, overrides = {}, base = PR_RUN) {
  const context = {};
  for (const [name] of String(expression).matchAll(/\b(?:steps|inputs|job)\.[\w.-]*[\w]/g)) context[name] = "";
  // Longer names first, so no name is replaced inside another.
  return Object.fromEntries(Object.entries({ ...context, ...base, ...overrides }).sort(([a], [b]) => b.length - a.length));
}

test("pr-run-activity-read.yml: a PR run that stops before head code still uploads its verdict, and nothing else", () => {
  const steps = scanSteps();
  const step = (name) => steps.find((s) => s.name === name);
  // A trigger decline, the kill switch, applies false or an issue-prior stop: go never ran, so no scan.
  const stopped = { "inputs.issue-number": "", "needs.run.outputs.go": "", "steps.decode.outputs.reply": "false", "steps.decode.outputs.patch": "false", "steps.leak-scan.outputs.clean": "" };
  const scan = step("Scan the outputs for credentials");
  assert.equal(atStep(scan.if, stopped), false);
  assert.equal(atStep(scan.if, { ...stopped, "needs.run.outputs.go": "true" }), true);
  // The verdict steps keep the default success(): they run when no step before
  // them failed, so a skipped scan still posts the skip and a hit posts nothing.
  for (const name of ["Write the verdict", "Upload the verdict"]) assert.equal(step(name).if, undefined, name);
  for (const name of ["Upload the skill's final reply", "Upload the patch", "Show the skill's run in the step summary"]) {
    assert.equal(atStep(step(name).if, stopped), false, `${name} has nothing to upload`);
  }
  assert.equal(step("Check out the gated head").if, "steps.decode.outputs.patch == 'true' && inputs.merge-conflict-tree == ''");
  // Nothing sealed: no base checkout, no key read and no open.
  const base = steps.find((s) => s.id === "base");
  assert.equal(atStep(base.if, { ...stopped, "needs.run.outputs.carry-sealed-length": "" }), false);
  assert.equal(atStep(base.if, { ...stopped, "needs.run.outputs.go": "true", "needs.run.outputs.carry-sealed-length": "" }), false);
  assert.equal(atStep(base.if, { ...stopped, "needs.run.outputs.go": "true", "needs.run.outputs.carry-sealed-length": "100" }), true);
  for (const id of ["key", "open"]) assert.equal(steps.find((s) => s.id === id).if, "steps.base.outcome == 'success'", id);
});

// In issue mode the run job's head-sha is forgeable, so an empty checked
// start commit leaves the scan no commit rather than falling back to it.
test("pr-run-activity-read.yml: the scan's commit is the checked start commit in issue mode and the run head only in PR mode", () => {
  const steps = scanSteps();
  const head = "a".repeat(40);
  const start = "b".repeat(40);
  for (const value of [steps.find((s) => s.name === "Check out the gated head").with.ref, steps.find((s) => s.id === "leak-scan").env.HEAD_SHA]) {
    const at = (issue, startSha) => evaluate(value, { "inputs.issue-number": issue, "needs.run.outputs.head-sha": head, "needs.issue-fields.outputs.start-sha": startSha });
    assert.equal(at("", ""), head, "PR mode");
    assert.equal(at("7", start), start, "issue mode");
    assert.equal(at("7", ""), "", "issue mode with no checked start commit");
  }
});

test("pr-run-activity-read.yml: the leak scan resolves the default branch tip itself and loads the publish gate there, never from a run job output, the base SHA or a checkout", () => {
  const step = scanSteps().find((s) => s.id === "leak-scan");
  const script = step.with.script;
  const { jobs } = workflow("pr-run-activity-read.yml");
  // Nothing the run job sets names the gate's commit.
  assert.equal(jobs.run.outputs["default-tip-sha"], undefined);
  for (const value of Object.values(step.env)) assert.doesNotMatch(String(value), /base-sha|default-tip|steps\.base/, "no run job output names the gate's commit");
  assert.match(script, /github\.rest\.repos\.getBranch\(\{ \.\.\.context\.repo, branch \}\)/);
  assert.match(script, /const branch = context\.payload\.repository\?\.default_branch;/);
  assert.match(script, /getContent\(\{ \.\.\.context\.repo, path: 'lib\/publish-gate\.mjs', ref: tip \}\)/);
  assert.doesNotMatch(script, /BASE_SHA|GATE_SHA/);
  assert.doesNotMatch(script, /require\(['"]\.|import\(['"]\.|GITHUB_WORKSPACE[^)]*publish-gate|\.base\/|RUNNER_TEMP/);
  assert.match(script, /mkdtempSync/);
  assert.equal(step.env.GITHUB_TOKEN, undefined);
  assert.equal(Object.keys(step.with).toSorted().join(","), "retries,script", "no token input beyond the job's default");
  for (const value of Object.values(step.env)) assert.doesNotMatch(String(value), /secrets\./);
});

const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;
const KEY = ["sk", "ant", "api03", "x".repeat(40)].join("-");

const COLLECT = fileURLToPath(new URL("../../scripts/read-patch/collect-patch.sh", import.meta.url));

// The plant stands in for the model's run, then the real collector writes the
// patch from the checkout, then afterCollect stands in for a process the run
// left behind, then the scan job's scan. headRepo, given the checkout and a
// scratch directory, returns the repository the scan reads the head's
// objects from (the scan job's own checkout); by default the run's checkout.
// The scan job's own API, as the leak scan reads it: getBranch on the
// default branch answers the tip (d…), and getContent serves the gate only at
// that tip. calls records what was asked.
const GATE_TIP = "d".repeat(40);
const SCAN_CONTEXT = { repo: { owner: "o", repo: "r" }, payload: { repository: { default_branch: "main" } } };
function gateApi(gate, { tip = async () => ({ data: { commit: { sha: GATE_TIP } } }), calls = [] } = {}) {
  return {
    calls,
    rest: {
      repos: {
        getBranch: async ({ owner, repo, branch }) => {
          calls.push(["getBranch", branch]);
          assert.deepEqual({ owner, repo, branch }, { owner: "o", repo: "r", branch: "main" }, "the event's default branch");
          return tip();
        },
        getContent: async ({ owner, repo, path: file, ref }) => {
          calls.push(["getContent", ref]);
          assert.deepEqual({ owner, repo, file, ref }, { owner: "o", repo: "r", file: "lib/publish-gate.mjs", ref: GATE_TIP }, "the gate at the tip getBranch answered only");
          return { data: { content: Buffer.from(gate).toString("base64") } };
        },
      },
    },
  };
}

// source, given the run's temp directory once the patch is collected, returns
// the directory the scan reads the reply, run fields and patch from (the scan
// job's opened payloads); by default the run's own.
async function scanWith(t, plant, gate = read("../../../lib/publish-gate.mjs"), { afterCollect = () => {}, headRepo = (work) => work, source = (temp) => ({ reply: join(temp, "skill-reply"), patch: join(temp, "patch", "patch.diff") }), env: extraEnv = {} } = {}) {
  const root = mkdtempSync(join(tmpdir(), "leak-scan-test-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const work = join(root, "work");
  const temp = join(root, "temp");
  mkdirSync(join(temp, "skill-reply"), { recursive: true });
  mkdirSync(join(temp, "patch"), { recursive: true });
  const git = (...args) => spawnSync("git", args, { cwd: work, encoding: "utf8" });
  mkdirSync(work);
  git("init", "-q", "-b", "main");
  git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "head");
  writeFileSync(join(work, "tracked.txt"), "unchanged\n");
  git("add", "tracked.txt");
  git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "-m", "tracked");
  const head = git("rev-parse", "HEAD").stdout.trim();
  writeFileSync(join(temp, "skill-reply", "reply.txt"), "lint-shell: fixed\n");
  writeFileSync(join(temp, "skill-reply", "act-turns.json"), '{"num_turns": 3}\n');
  plant({ work, temp });
  const collected = spawnSync("bash", [COLLECT, head, join(temp, "patch", "patch.diff")], { cwd: work, encoding: "utf8" });
  assert.equal(collected.status, 0, collected.stderr);
  afterCollect({ work, temp, head });
  const { reply: replyDir, patch: patchFile } = source(temp);
  const outputs = {};
  let failed = null;
  const warnings = [];
  const core = { setOutput: (name, value) => (outputs[name] = value), setFailed: (message) => (failed = message), warning: (message) => warnings.push(message) };
  const github = gateApi(gate);
  const env = {
    // Hostile run job outputs beside the tip: the gate must come from getBranch.
    BASE_SHA: "b".repeat(40),
    GATE_SHA: "e".repeat(40),
    DEFAULT_TIP_SHA: "e".repeat(40),
    HEAD_SHA: head,
    REPLY_DIR: replyDir,
    PATCH_FILE: patchFile,
    GITHUB_WORKSPACE: headRepo(work, root),
    HOME: process.env.HOME,
    ...extraEnv,
  };
  const script = scanSteps().find((s) => s.id === "leak-scan").with.script;
  const { createRequire } = await import("node:module");
  await new AsyncFunction("require", "core", "github", "context", "process", script)(
    createRequire(import.meta.url),
    core,
    github,
    SCAN_CONTEXT,
    { env },
  );
  return { clean: outputs.clean, failed, work, temp, warnings, outputs };
}

// dependency-review: the verdict file is scanned like the reply, hashed from
// the scanned bytes, and only its verdict field, held to review-dependency.mjs
// VERDICTS, leaves as an output.
test("leak scan: a dependency verdict is scanned and hashed, and only a known verdict field leaves", async (t) => {
  const plantVerdict = (text) => ({ temp }) => writeFileSync(join(temp, "skill-reply", "dependency-verdict.json"), text);
  const fix = '{"verdict":"fix","reasons":["a"],"evidence":[]}\n';
  const scanned = await scanWith(t, plantVerdict(fix));
  assert.equal(scanned.clean, "true");
  assert.equal(scanned.outputs["dependency-verdict"], "fix");
  assert.equal(scanned.outputs["verdict-sha256"], createHash("sha256").update(fix).digest("hex"));
  assert.equal(readFileSync(join(scanned.outputs.dir, "dependency-verdict.json"), "utf8"), fix);
  for (const verdict of VERDICTS) {
    assert.equal((await scanWith(t, plantVerdict(JSON.stringify({ verdict })))).outputs["dependency-verdict"], verdict);
  }
  for (const text of ['{"verdict":"approve"}', '{"verdict":["fix"]}', "fix", '"fix"', "null"]) {
    const other = await scanWith(t, plantVerdict(text));
    assert.equal(other.outputs["dependency-verdict"], "", text);
    assert.match(other.outputs["verdict-sha256"], /^[0-9a-f]{64}$/, `${text}: still uploaded for the verdict job to refuse`);
  }
  assert.equal((await scanWith(t, () => {})).outputs["dependency-verdict"], undefined, "no file, no output");
  const leaked = await scanWith(t, plantVerdict(`{"verdict":"fix","reasons":["${KEY}"],"evidence":[]}`));
  assert.equal(leaked.clean, "false");
  assert.doesNotMatch(String(leaked.failed), new RegExp(KEY));
  // The scan's list is review-dependency.mjs's.
  const script = scanSteps().find((s) => s.id === "leak-scan").with.script;
  assert.match(script, new RegExp(`\\[${VERDICTS.map((v) => `'${v}'`).join(", ")}\\]\\.includes\\(value\\)`));
});

// Plan Q5: a lockfile fix over the patch cap is refused with the rest of the
// run's payloads; the scan names the patch so the verdict job escalates
// dependency-fix-not-landed instead of reading a round with no model turn.
test("scan job: a refusal names an oversize patch, and every other refusal `output`", async (t) => {
  const over = await scanIn(t, runOutputsAfterCarry(t, { "patch/patch.diff": Buffer.alloc(262145, 0x61) }));
  assert.match(over.failed, /^too-large: the patch /);
  assert.equal(over.outputs.refused, "patch");
  const reply = await scanIn(t, runOutputsAfterCarry(t, { "skill-reply/reply.txt": Buffer.alloc(16385, 0x61), "patch/patch.diff": "diff\n" }));
  assert.match(reply.failed, /^too-large: the reply /);
  assert.equal(reply.outputs.refused, undefined, "the reply is refused first");
  const ok = await scanIn(t, runOutputsAfterCarry(t, { "patch/patch.diff": Buffer.alloc(262144, 0x61) }));
  assert.equal(ok.outputs.refused, undefined);
  // The job output: the decode step's patch, else any failed step of this job is `output`.
  const refused = workflow("pr-run-activity-read.yml").jobs.scan.outputs.refused;
  const at = (decodeRefused, outcomes = {}) =>
    evaluate(refused, {
      "steps.decode.outputs.refused": decodeRefused,
      "steps.open.outcome": "success",
      "steps.decode.outcome": "success",
      "steps.leak-scan.outcome": "success",
      ...outcomes,
    });
  assert.equal(at("patch", { "steps.decode.outcome": "failure" }), "patch");
  assert.equal(at("", { "steps.decode.outcome": "failure" }), "output");
  assert.equal(at("", { "steps.open.outcome": "failure", "steps.decode.outcome": "skipped" }), "output");
  assert.equal(at("", { "steps.leak-scan.outcome": "failure" }), "output");
  assert.equal(at(""), "");
  assert.equal(at("", { "steps.open.outcome": "skipped", "steps.decode.outcome": "success", "steps.leak-scan.outcome": "skipped" }), "", "a run with nothing to open");
});

// A failed scan fails the caller's job for the whole read workflow, and a
// failed job's outputs are not documented to reach a workflow_call caller
// (#9340). So the scan-refusal job, which needs the scan job alone, uploads a
// marker artifact, and the reply and verdict jobs download it by name: the
// marker alone decides the refusal, with every leg output empty.
const read_ = read;
test("scan refusal: a failed or cancelled scan's marker reaches the reply and verdict jobs by name, never by a job output", () => {
  const read = workflow("pr-run-activity-read.yml");
  const relay = read.jobs["scan-refusal"];
  assert.ok(relay, "the read runner has a scan-refusal job");
  assert.equal(relay.needs, "scan");
  assert.doesNotMatch(JSON.stringify(relay), /needs\.run\./);
  const write = relay.steps.find((step) => step.name === "Write the scan refusal marker");
  const upload = relay.steps.find((step) => step.uses?.startsWith("actions/upload-artifact@"));
  const ctx = (result, refused = "", issue = "") => ({
    "needs.scan.result": result,
    "needs.scan.outputs.refused": refused,
    "inputs.issue-number": issue,
    "inputs.model-rung": "",
    "inputs.lane": "pr-unblock",
    "github.run_attempt": "2",
  });
  // cancelled() as the runner reads it: true once the scan was cancelled,
  // which evaluate's !cancelled() shortcut would hide.
  const runs = (values, cancelled = false) =>
    evaluate(relay.if.replaceAll("cancelled()", String(cancelled)).replaceAll("always()", "true"), values) === true;
  assert.equal(runs(ctx("failure")), true);
  assert.equal(runs(ctx("cancelled"), true), true, "a cancelled scan");
  assert.equal(runs(ctx("success")), false);
  assert.equal(runs(ctx("skipped")), false);
  assert.equal(runs(ctx("failure", "", "7")), false, "issue mode has no reply or verdict job");
  assert.equal(evaluate(write.env.REFUSED, ctx("failure")), "output", "a failed scan whose outputs did not arrive");
  assert.equal(evaluate(write.env.REFUSED, ctx("failure", "patch")), "patch");
  const sub = (text, values) => text.replace(/\$\{\{([^}]*)\}\}/g, (_, expr) => String(evaluate(`\${{${expr}}}`, values)));
  // The marker's file name is one scanRefusal reads.
  assert.match(sub(write.env.MARKER, { ...ctx("failure"), "runner.temp": "/t" }).split("/").at(-1), /^scan-refused-[1-9][0-9]{0,4}(-rung-up)?\.txt$/);
  assert.equal(upload.with.overwrite, false);
  // The write runner downloads every attempt's marker for the model call's activity.
  const steps = workflow("pr-run-activity-write.yml").jobs.run.steps;
  const download = steps.find((step) => step.id === "scan-refused");
  const script = steps.find((step) => step.id === "act-script");
  for (const [mode, activity] of [["inputs.review-replies", "address-feedback"], ["inputs.dependency-verdict", "review-dependency"]]) {
    const values = { "inputs.review-replies": mode === "inputs.review-replies", "inputs.dependency-verdict": mode === "inputs.dependency-verdict", "inputs.lane": "pr-unblock", "runner.temp": "/t" };
    const name = sub(upload.with.name, { ...ctx("failure"), "inputs.activity": activity });
    const pattern = sub(download.with.pattern, values);
    assert.ok(pattern.endsWith("-*") && name.startsWith(pattern.slice(0, -1)), `${activity}: ${pattern} matches ${name}`);
    assert.equal(sub(download.with.path, values), "/t/scan-refused", activity);
  }
  assert.equal(script.env.SCAN_REFUSED_DIR, "${{ (inputs.review-replies || inputs.dependency-verdict) && format('{0}/scan-refused', runner.temp) || '' }}");
  assert.equal(download["continue-on-error"], true);
  assert.equal(download.with["merge-multiple"], true);
  assert.equal(script.env.SCAN_REFUSED_READ, "${{ steps.scan-refused.outcome }}");
  // No decision reads a refusal from a job output.
  assert.equal(read.on.workflow_call.outputs["scan-refused"], undefined);
  assert.doesNotMatch(read_("../../workflows/pr-unblock.yml"), /outputs\.scan-refused/);
  assert.equal(script.env.REVIEW_SCAN_REFUSED, undefined);
  assert.equal(script.env.DEPENDENCY_SCAN_REFUSED, undefined);
});

test("leak scan: a clean run is clean", async (t) => {
  const { clean, failed } = await scanWith(t, () => {});
  assert.deepEqual({ clean, failed }, { clean: "true", failed: null });
});

test("leak scan: a key in the reply, in a binary changed file or in an untracked file fails it, naming the pattern and never the key", async (t) => {
  const plants = {
    reply: ({ temp }) => writeFileSync(join(temp, "skill-reply", "reply.txt"), `done ${KEY}\n`),
    "binary changed file": ({ work }) => writeFileSync(join(work, "tracked.txt"), Buffer.concat([Buffer.from([0, 255, 0]), Buffer.from(KEY)])),
    "binary file the index marks assume-unchanged": ({ work }) => {
      writeFileSync(join(work, "tracked.txt"), Buffer.concat([Buffer.from([0, 255, 0]), Buffer.from(KEY)]));
      spawnSync("git", ["update-index", "--assume-unchanged", "tracked.txt"], { cwd: work });
      assert.equal(spawnSync("git", ["diff", "--name-only"], { cwd: work, encoding: "utf8" }).stdout, "", "the real index hides it");
    },
    "untracked file": ({ work }) => writeFileSync(join(work, "new.bin"), Buffer.concat([Buffer.from([0, 1]), Buffer.from(KEY)])),
  };
  for (const [where, plant] of Object.entries(plants)) {
    const { clean, failed, work } = await scanWith(t, plant);
    assert.equal(clean, "false", where);
    // The scan stages in a scratch index and leaves the checkout's own as the run left it.
    assert.match(spawnSync("git", ["ls-files", "-v", "tracked.txt"], { cwd: work, encoding: "utf8" }).stdout, where.includes("assume-unchanged") ? /^h / : /^H /, where);
    assert.match(failed, /^leak-scan: Anthropic key; .*\nrotate this credential$/, where);
    assert.ok(!failed.includes(KEY), where);
  }
});

test("leak scan: a missing default branch tip or head, or a gate that imports beyond node builtins, fails closed", async (t) => {
  const outputs = {};
  let failed = null;
  const { createRequire } = await import("node:module");
  const script = scanSteps().find((s) => s.id === "leak-scan").with.script;
  await new AsyncFunction("require", "core", "github", "context", "process", script)(
    createRequire(import.meta.url),
    { setOutput: (name, value) => (outputs[name] = value), setFailed: (message) => (failed = message), warning: () => {} },
    {},
    { repo: {} },
    { env: {} },
  );
  assert.equal(outputs.clean, "false");
  assert.match(failed, /no finished scan/);
  assert.doesNotMatch(failed, /rotate/, "no credential was found");
  // A gate that loads and passes everything, but imports beyond node builtins, is refused.
  const evil = 'import "data:text/javascript,export default 1";\nexport const findSecret = () => null;\n';
  const refused = await scanWith(t, ({ temp }) => writeFileSync(join(temp, "skill-reply", "reply.txt"), "clean\n"), evil);
  assert.equal(refused.clean, "false");
  assert.match(refused.failed, /^leak-scan: no finished scan \(Error\)/);
});

test("leak scan: a failed getBranch, a malformed tip or no default branch fails closed and fetches no gate", async () => {
  const script = scanSteps().find((s) => s.id === "leak-scan").with.script;
  const { createRequire } = await import("node:module");
  const answers = {
    "a failed call": async () => {
      throw Object.assign(new Error("Not Found"), { status: 404 });
    },
    "no commit": async () => ({ data: {} }),
    "a short sha": async () => ({ data: { commit: { sha: "d".repeat(39) } } }),
    "an upper-case sha": async () => ({ data: { commit: { sha: "D".repeat(40) } } }),
    "a branch name": async () => ({ data: { commit: { sha: "main" } } }),
    "a number": async () => ({ data: { commit: { sha: 7 } } }),
  };
  const run = async (github, context) => {
    const outputs = {};
    let failed = null;
    await new AsyncFunction("require", "core", "github", "context", "process", script)(
      createRequire(import.meta.url),
      { setOutput: (name, value) => (outputs[name] = value), setFailed: (message) => (failed = message), warning: () => {} },
      github,
      context,
      { env: { HEAD_SHA: "c".repeat(40), GATE_SHA: GATE_TIP, DEFAULT_TIP_SHA: GATE_TIP } },
    );
    return { outputs, failed };
  };
  for (const [name, tip] of Object.entries(answers)) {
    const github = gateApi("", { tip });
    const { outputs, failed } = await run(github, SCAN_CONTEXT);
    assert.equal(outputs.clean, "false", name);
    assert.equal(failed, "leak-scan: no finished scan (Error); nothing is uploaded or summarized", name);
    assert.deepEqual(github.calls.map(([call]) => call), ["getBranch"], `${name}: no gate fetched`);
  }
  // An event that names no default branch asks for nothing.
  const github = gateApi("");
  const { failed } = await run(github, { repo: { owner: "o", repo: "r" }, payload: {} });
  assert.match(failed, /^leak-scan: no finished scan/);
  assert.deepEqual(github.calls, []);
});

test("leak scan: a hostile run job output, any value or another commit's SHA, never moves the commit the gate is read at", async (t) => {
  for (const forged of ["e".repeat(40), "b".repeat(40), "", "main", "../../x"]) {
    const outputs = runOutputsAfterCarry(t, { "skill-reply/reply.txt": "fixed\n" });
    const hostile = Object.fromEntries(Object.keys({ ...outputs, "base-sha": "", "default-tip-sha": "" }).map((name) => [name, forged]));
    const step = scanSteps().find((s) => s.id === "leak-scan");
    // Every run job output the step's env could carry, forged.
    const env = {};
    for (const [name, expression] of Object.entries(step.env)) {
      const output = OUTPUT_EXPRESSION.exec(expression);
      env[name] = output ? hostile[output[1]] ?? forged : "";
    }
    env.HEAD_SHA = "c".repeat(40);
    const github = gateApi("export const findSecret = () => null;\nexport const SECRET_PATTERNS = [];\n");
    const script = step.with.script;
    const { createRequire } = await import("node:module");
    await new AsyncFunction("require", "core", "github", "context", "process", script)(
      createRequire(import.meta.url),
      { setOutput: () => {}, setFailed: () => {}, warning: () => {} },
      github,
      SCAN_CONTEXT,
      { env },
    );
    assert.deepEqual(github.calls.slice(0, 2), [["getBranch", "main"], ["getContent", GATE_TIP]], JSON.stringify(forged));
  }
});

// One sample per credential format the gate names, built at run time.
const CREDENTIALS = {
  "private key": ["-----BEGIN", "RSA PRIVATE KEY-----"].join(" "),
  "AWS access key": `AKIA${"ABCDEFGHIJKLMNOP"}`,
  "GitHub token": `${"ghp"}_${"a1".repeat(18)}`,
  "Anthropic key": KEY,
  "OpenAI key": `${"sk"}-proj-${"A".repeat(24)}`,
  "Slack token": `${"xox"}b-${"1234567890ab"}`,
  "Stripe key": `${"sk"}_live_${"0123456789ab"}`,
  "R2 key pair": `${"0".repeat(32)} ${"f".repeat(64)}`,
  "Azure client secret": ` abc1Q~${"x".repeat(32)}`,
  "Cloudflare API token": `${"cfut"}_${"A".repeat(40)}`,
  "upload token": `${"pgup"}_${"A".repeat(20)}`,
};
const ASSIGNMENT = `password = '${["hunter2", "zz9"].join("-")}'`;
test("leak scan: every credential format the gate names blocks and asks for rotation", async (t) => {
  const { SECRET_PATTERNS } = await import("../../../lib/publish-gate.mjs");
  const blocking = SECRET_PATTERNS.map(([label]) => label).filter((label) => label !== "password or secret assignment");
  assert.deepEqual(Object.keys(CREDENTIALS).toSorted(), blocking.toSorted(), "one sample per blocking label");
  for (const [label, sample] of Object.entries(CREDENTIALS)) {
    const { clean, failed } = await scanWith(t, ({ temp }) => writeFileSync(join(temp, "skill-reply", "reply.txt"), `x ${sample} y\n`));
    assert.equal(clean, "false", label);
    assert.equal(failed, `leak-scan: ${label}; nothing is uploaded or summarized\nrotate this credential`, label);
  }
  // A credential inside an assignment still blocks: the broad label never hides it.
  const wrapped = await scanWith(t, ({ work }) => writeFileSync(join(work, "tracked.txt"), `token: "${CREDENTIALS["Cloudflare API token"]}"\n`));
  assert.equal(wrapped.clean, "false");
  assert.match(wrapped.failed, /^leak-scan: Cloudflare API token; .*\nrotate this credential$/);
});

test("leak scan: a plain password or secret assignment warns, naming the kind of source only, and does not block", async (t) => {
  const plants = {
    "a changed file": ({ work }) => writeFileSync(join(work, "tracked.txt"), `${ASSIGNMENT}\n`),
    "an untracked file": ({ work }) => writeFileSync(join(work, "new-notes.txt"), `${ASSIGNMENT}\n`),
    "the reply": ({ temp }) => writeFileSync(join(temp, "skill-reply", "reply.txt"), `${ASSIGNMENT}\n`),
  };
  for (const [kind, plant] of Object.entries(plants)) {
    const { clean, failed, warnings } = await scanWith(t, plant);
    assert.deepEqual({ clean, failed }, { clean: "true", failed: null }, kind);
    // A changed or untracked file leaves only in the patch.
    const source = kind === "the reply" ? kind : "the patch";
    assert.deepEqual(warnings, [`leak-scan: password or secret assignment in ${source}; not blocking, check it is no real credential`], kind);
    assert.ok(!/hunter2|tracked\.txt|new-notes/.test(warnings[0]), kind);
  }
});

const HIDDEN = "assignment hidden by markup or escapes";
const R2_TAIL = "A".repeat(20);
test("leak scan: an assignment never hides a credential the gate finds only in its normalized copy", async (t) => {
  const A40 = "A".repeat(40);
  const cases = {
    // An early assignment line, then a key split by an HTML tag.
    "a tag-split key after an assignment line": [`${ASSIGNMENT}\nnotes ${KEY.slice(0, 7)}<i></i>${KEY.slice(7)}\n`, "Anthropic key"],
    // One line: an assignment, then an entity-escaped token later in the gate's order.
    "an entity-escaped token on the assignment's line": [`${ASSIGNMENT} &#x63;${CREDENTIALS["Cloudflare API token"].slice(1)}\n`, "Cloudflare API token"],
    // The escaped token is the assignment's own value.
    "an entity-escaped token as the assignment's value": [`token = '&#x63;${CREDENTIALS["Cloudflare API token"].slice(1)}'\n`, "Cloudflare API token"],
    // The harness's cases 11-13: an R2 pair the folded copy shows, overlapping an assignment.
    "an R2 assignment form across the assignment's edge": [`token = 'x.secret_access_key'=&#65;${R2_TAIL}\n`, HIDDEN],
    "an R2 assignment form inside the assignment's value": [`token = 'secret_access_key=&#65;${R2_TAIL}'\n`, HIDDEN],
    "an R2 hex pair split by a tag around the assignment": [`token = '${"a".repeat(32)}' ${"b".repeat(32)}<b></b>${"b".repeat(32)}\n`, HIDDEN],
    // Case 14: an assignment only the folded copy shows.
    "an entity-escaped assignment": ["password = &quot;hunter2-zz9&quot;\n", HIDDEN],
    "a tag-split second assignment": [`${ASSIGNMENT} secret=<b></b>'abcdefgh1'\n`, HIDDEN],
    "a tag-split Cloudflare token": [`x cf<b></b>ut_${A40} y\n`, "Cloudflare API token"],
    // A raw R2 assignment form inside an assignment: blanking = and : would erase it, so the raw check names it.
    "a raw R2 assignment form inside the assignment's value": [`token = 'secret_access_key=${R2_TAIL}'\n`, "R2 key pair"],
  };
  for (const [name, [text, label]] of Object.entries(cases)) {
    const { clean, failed } = await scanWith(t, ({ work }) => writeFileSync(join(work, "tracked.txt"), text));
    assert.equal(clean, "false", name);
    const rotate = label === HIDDEN ? "" : "\nrotate this credential";
    assert.equal(failed, `leak-scan: ${label}; nothing is uploaded or summarized${rotate}`, name);
  }
  // Case 15: a plain assignment still only warns.
  const plain = await scanWith(t, ({ work }) => writeFileSync(join(work, "tracked.txt"), `${ASSIGNMENT}\n`));
  assert.deepEqual({ clean: plain.clean, failed: plain.failed, warnings: plain.warnings.length }, { clean: "true", failed: null, warnings: 1 });
});

test("leak scan: a credential-format file name blocks, and a PEM header alone blocks as a private key", async (t) => {
  // Case 17: the file holds only an assignment; its name is the credential.
  const named = await scanWith(t, ({ work }) => writeFileSync(join(work, `${CREDENTIALS["Cloudflare API token"]}.txt`), `${ASSIGNMENT}\n`));
  assert.equal(named.clean, "false");
  assert.equal(named.failed, "leak-scan: Cloudflare API token; nothing is uploaded or summarized\nrotate this credential");
  assert.deepEqual(named.warnings, []);
  const pem = await scanWith(t, ({ work }) => writeFileSync(join(work, "key.pem"), `${CREDENTIALS["private key"]}\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASC\n-----END RSA PRIVATE KEY-----\n`));
  assert.equal(pem.clean, "false");
  assert.match(pem.failed, /^leak-scan: private key; .*\nrotate this credential$/);
});

test("leak scan: a gate whose labels lack the warning label still blocks its credentials", async (t) => {
  const gate = [
    'export const SECRET_PATTERNS = Object.freeze([["Anthropic key", /\\bsk-ant-[A-Za-z0-9_-]{20,}/]]);',
    "export const findSecret = (text) => (SECRET_PATTERNS[0][1].test(text) ? [SECRET_PATTERNS[0][0], 1] : null);",
  ].join("\n");
  assert.deepEqual((await scanWith(t, () => {}, gate)).clean, "true");
  const hit = await scanWith(t, ({ temp }) => writeFileSync(join(temp, "skill-reply", "reply.txt"), `${KEY}\n`), gate);
  assert.equal(hit.clean, "false");
  assert.match(hit.failed, /^leak-scan: Anthropic key; .*\nrotate this credential$/);
});

// A key the working tree no longer shows: the patch carries it as a binary
// literal, compressed, so only the file the patch makes holds its bytes.
const KEY_BLOB = Buffer.concat([Buffer.from([0, 1, 0]), Buffer.from(KEY), Buffer.from([0])]);
const restore = ({ work }) => writeFileSync(join(work, "tracked.txt"), "unchanged\n");

test("leak scan: a key only the patch's binary hunk carries blocks, and a patch that does not apply blocks without rotation", async (t) => {
  const { clean, failed, temp } = await scanWith(t, ({ work }) => writeFileSync(join(work, "tracked.txt"), KEY_BLOB), undefined, { afterCollect: restore });
  const patch = readFileSync(join(temp, "patch", "patch.diff"));
  assert.ok(patch.includes("GIT binary patch") && !patch.includes(KEY), "the key is compressed in the patch");
  assert.equal(clean, "false");
  assert.equal(failed, "leak-scan: Anthropic key; nothing is uploaded or summarized\nrotate this credential");
  const stale = await scanWith(t, () => {}, undefined, {
    afterCollect: ({ temp }) => writeFileSync(join(temp, "patch", "patch.diff"), "diff --git a/gone.txt b/gone.txt\n--- a/gone.txt\n+++ b/gone.txt\n@@ -1 +1 @@\n-a\n+b\n"),
  });
  assert.equal(stale.failed, "leak-scan: the patch does not apply to the head; nothing is uploaded or summarized");
});

test("leak scan: an object planted under the name of the patch's blob never stands in for the hunk's bytes", async (t) => {
  const { inflateSync, deflateSync } = await import("node:zlib");
  const { createHash } = await import("node:crypto");
  const { clean, failed } = await scanWith(t, ({ work }) => writeFileSync(join(work, "tracked.txt"), KEY_BLOB), undefined, {
    afterCollect: (state) => {
      restore(state);
      // The blob the patch makes, planted under its name with benign bytes.
      const sha = createHash("sha1").update(`blob ${KEY_BLOB.length}\0`).update(KEY_BLOB).digest("hex");
      const dir = join(state.work, ".git", "objects", sha.slice(0, 2));
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, sha.slice(2)), deflateSync(Buffer.from("blob 7\0benign\n")));
      assert.equal(inflateSync(readFileSync(join(dir, sha.slice(2)))).toString().endsWith("benign\n"), true);
    },
  });
  assert.equal(clean, "false");
  assert.equal(failed, "leak-scan: Anthropic key; nothing is uploaded or summarized\nrotate this credential");
});

test("leak scan: no filter, include, hook or fsmonitor planted in the checkout's .git runs while the patch is collected or scanned", async (t) => {
  const marks = mkdtempSync(join(tmpdir(), "leak-scan-marks-"));
  t.after(() => rmSync(marks, { recursive: true, force: true }));
  const mark = (name) => join(marks, name);
  const hook = (file, name) => {
    mkdirSync(join(file, ".."), { recursive: true });
    writeFileSync(file, `#!/bin/sh\ntouch '${mark(name)}'\ncat\n`, { mode: 0o755 });
  };
  const { clean, failed, temp } = await scanWith(t, ({ work }) => {
    const git = (...args) => spawnSync("git", args, { cwd: work, encoding: "utf8" });
    // Set through git config, as Bash in the run could.
    git("config", "filter.x.clean", `touch '${mark("filter")}'; printf '\\000${KEY}\\n'`);
    mkdirSync(join(work, ".git", "info"), { recursive: true });
    writeFileSync(join(work, ".git", "info", "attributes"), "tracked.txt filter=x\n");
    writeFileSync(join(work, "included"), `[filter "y"]\n\tclean = touch '${mark("include")}'; cat\n`);
    git("config", "include.path", join(work, "included"));
    git("config", `includeIf.gitdir:${work}/.path`, join(work, "included"));
    writeFileSync(join(work, ".gitattributes"), "doc.txt filter=y\n");
    writeFileSync(join(work, "doc.txt"), "doc\n");
    hook(join(work, ".git", "hooks", "post-index-change"), "hook");
    hook(join(work, "hooks", "post-index-change"), "hooks-path");
    git("config", "core.hooksPath", join(work, "hooks"));
    hook(join(work, ".git", "monitor"), "fsmonitor");
    git("config", "core.fsmonitor", join(work, ".git", "monitor"));
    writeFileSync(join(work, "tracked.txt"), "benign\n");
  });
  assert.deepEqual(readdirSync(marks), [], "nothing planted ran");
  assert.deepEqual({ clean, failed }, { clean: "true", failed: null });
  assert.match(readFileSync(join(temp, "patch", "patch.diff"), "latin1"), /^\+benign$/m, "the patch holds the bytes on disk");
});

test("leak scan: the uploads and the summary read the scanned copies, and the patch SHA-256 the apply job checks is the copy's", async (t) => {
  const steps = scanSteps();
  const step = (id) => steps.find((s) => s.id === id);
  const scan = step("leak-scan");
  assert.equal(typeof scan["timeout-minutes"], "number", "a slow scan ends, failing closed");
  assert.equal(scan.with.script.match(/setOutput\('clean'/g).length, 1, "clean is set only once the scan finished");
  const copy = "${{ steps.leak-scan.outputs.dir }}";
  assert.ok(String(step("reply-upload").with.path).split("\n").filter(Boolean).every((line) => line.startsWith(`${copy}/`)));
  assert.ok(step("patch-upload").with.path.startsWith(`${copy}/`));
  assert.equal(steps.find((s) => s.name === "Show the skill's run in the step summary").env.REPLY_DIR, copy);
  assert.equal(workflow("pr-run-activity-read.yml").jobs.scan.outputs["patch-sha256"], "${{ steps.patch-upload.outcome == 'success' && steps.leak-scan.outputs.patch-sha256 || '' }}");
  const { outputs, temp } = await scanWith(t, ({ work }) => writeFileSync(join(work, "tracked.txt"), "changed\n"));
  const original = readFileSync(join(temp, "patch", "patch.diff"));
  // A process left behind rewrites what it knows; the copies keep the scanned bytes.
  writeFileSync(join(temp, "patch", "patch.diff"), `${KEY}\n`);
  writeFileSync(join(temp, "skill-reply", "reply.txt"), `${KEY}\n`);
  assert.deepEqual(readFileSync(join(outputs.dir, "patch.diff")), original);
  assert.equal(readFileSync(join(outputs.dir, "reply.txt"), "utf8"), "lint-shell: fixed\n");
  const { createHash } = await import("node:crypto");
  assert.equal(outputs["patch-sha256"], createHash("sha256").update(original).digest("hex"));
  rmSync(outputs.dir, { recursive: true, force: true });
});

// --- post-leg git in the head workspace ---

// A checkout as the run left it, with git config the model could plant: a
// filter its .gitattributes names, an fsmonitor and a hook, each touching a
// marker if git runs it.
function plantedCheckout(t) {
  const root = mkdtempSync(join(tmpdir(), "post-leg-git-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const work = join(root, "work");
  const temp = join(root, "temp");
  const marks = join(root, "marks");
  for (const dir of [work, join(temp, "read-patch"), marks]) mkdirSync(dir, { recursive: true });
  writeFileSync(join(temp, "read-patch", "collect-patch.sh"), readFileSync(COLLECT));
  const git = (...args) => spawnSync("git", args, { cwd: work, encoding: "utf8" });
  git("init", "-q", "-b", "main");
  writeFileSync(join(work, "tracked.txt"), "unchanged\n");
  git("add", "tracked.txt");
  git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "-m", "head");
  const head = git("rev-parse", "HEAD").stdout.trim();
  const plant = () => {
    const script = (name) => {
      const file = join(root, `${name}.sh`);
      writeFileSync(file, `#!/bin/sh\ntouch '${join(marks, name)}'\ncat\n`, { mode: 0o755 });
      return file;
    };
    git("config", "filter.x.clean", script("filter"));
    mkdirSync(join(work, ".git", "info"), { recursive: true });
    writeFileSync(join(work, ".git", "info", "attributes"), "* filter=x\n");
    git("config", "core.fsmonitor", script("fsmonitor"));
    mkdirSync(join(work, ".git", "hooks"), { recursive: true });
    writeFileSync(join(work, ".git", "hooks", "post-index-change"), readFileSync(script("hook")), { mode: 0o755 });
  };
  return { root, work, temp, marks, head, git, plant };
}

const runStep = (step, cwd, env) =>
  spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", step.run], { cwd, env: { PATH: process.env.PATH, ...env }, encoding: "utf8" });

test("pr-run-activity-read.yml: the dirty-tree check runs no git config the model planted and prints no path", (t) => {
  const steps = runSteps();
  const tree = steps.find((s) => s.id === "tree");
  const copy = steps.find((s) => s.name === "Copy the patch collector and the output sealer from the base");
  // The collector is copied for every activity that runs, not only patch mode.
  assert.equal(evaluate(copy.if, { "steps.go.outputs.run": "true" }), true);
  assert.ok(steps.indexOf(copy) < steps.findIndex((s) => s.name === "Check out the PR head"), "copied before head code");
  // setup runs before the plant, so its own git runs nothing planted.
  const check = (setup) => {
    const state = plantedCheckout(t);
    setup(state);
    state.plant();
    const output = join(state.root, "github-output");
    writeFileSync(output, "");
    const result = runStep(tree, state.work, {
      HEAD_SHA: state.head,
      TREE_DIFF: join(state.temp, "tree-check", "tree.diff"),
      RUNNER_TEMP: state.temp,
      GITHUB_OUTPUT: output,
    });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(readdirSync(state.marks), [], "nothing planted ran");
    assert.equal(result.stdout, "", "no path reaches the log");
    assert.equal(existsSync(join(state.temp, "tree-check", "tree.diff")), false, "the diff is not kept");
    return readFileSync(output, "utf8");
  };
  assert.equal(check(() => {}), "dirty-tree=false\n", "config, attributes and hooks in .git are no change");
  assert.equal(check(({ work }) => writeFileSync(join(work, "tracked.txt"), "changed\n")), "dirty-tree=true\n");
  assert.equal(check(({ work }) => writeFileSync(join(work, "made.txt"), "new\n")), "dirty-tree=true\n", "an untracked file");
  assert.equal(
    check(({ work, git }) => {
      writeFileSync(join(work, "made.txt"), "new\n");
      git("add", "made.txt");
      git("-c", "user.email=t@example.com", "-c", "user.name=t", "commit", "-q", "-m", "made");
    }),
    "dirty-tree=true\n",
    "a commit the activity made is a change against the gated head",
  );
  assert.equal(
    check(({ work }) => {
      mkdirSync(join(work, ".lane"));
      writeFileSync(join(work, ".lane", "prompt.md"), "staged\n");
    }),
    "dirty-tree=false\n",
    "the staged .lane/ is no change",
  );
  assert.equal(check(({ work }) => writeFileSync(join(work, ".npmrc"), "")), "dirty-tree=false\n", "an empty CLI scrub stub is no change");
  assert.equal(check(({ work }) => writeFileSync(join(work, ".env"), "TOKEN=x\n")), "dirty-tree=true\n", "a scrub stub name with content, the collector's exit 3");
  // A collector that fails fails the step.
  const broken = plantedCheckout(t);
  writeFileSync(join(broken.temp, "read-patch", "collect-patch.sh"), "exit 1\n");
  assert.notEqual(runStep(tree, broken.work, { HEAD_SHA: broken.head, TREE_DIFF: join(broken.temp, "x", "d"), RUNNER_TEMP: broken.temp, GITHUB_OUTPUT: join(broken.root, "o") }).status, 0);
});

test("pr-run-activity-read.yml: after the collector, no checkout's post step finds a .git/config to run git in", (t) => {
  const steps = runSteps();
  const remove = steps.find((s) => s.name === "Remove the checkouts' .git directories");
  const at = (predicate) => steps.findIndex(predicate);
  assert.ok(at((s) => s === remove) > at((s) => s.id === "patch"), "after the collector");
  assert.ok(at((s) => s === remove) > at((s) => s.id === "tree"), "after the tree check");
  // Every git step in the job runs before it.
  const gitAfter = steps.slice(at((s) => s === remove) + 1).filter((s) => /\bgit\b/.test(String(s.run ?? "")) || String(s.uses ?? "").startsWith("actions/checkout@"));
  assert.deepEqual(gitAfter.map((s) => s.name), []);
  // It runs after a failed or skipped collector, and whenever the head checkout ran in PR mode.
  const runs = (overrides) => atStep(remove.if, prRun(remove.if, overrides));
  assert.equal(runs({}), true);
  assert.equal(runs({ "steps.patch.outcome": "failure", "job.status": "failure" }), true);
  assert.equal(runs({ "steps.go.outputs.run": "" }), false, "no head checkout");
  assert.doesNotMatch(remove.if, /issue-number/, "issue mode too, now on the launcher");
  // actions/checkout@3d3c42e5 cleanup() returns when <path>/.git/config is
  // missing (src/git-source-provider.ts:331-336), and each post step passes
  // its own checkout's path (src/main.ts:34): the workspace and .base.
  const state = plantedCheckout(t);
  state.plant();
  mkdirSync(join(state.work, ".base", ".git"), { recursive: true });
  writeFileSync(join(state.work, ".base", ".git", "config"), "[core]\n\tfsmonitor = /bin/false\n");
  const result = runStep(remove, state.temp, { GITHUB_WORKSPACE: state.work });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(existsSync(join(state.work, ".git", "config")), false);
  assert.equal(existsSync(join(state.work, ".base", ".git", "config")), false);
  assert.equal(readFileSync(join(state.work, "tracked.txt"), "utf8"), "unchanged\n", "the work tree stays");
  assert.equal(runStep(remove, state.temp, {}).status, 1, "an unset workspace removes nothing");
});

// --- the model job's payloads to the scan job, sealed ---

// name=value lines from a GITHUB_OUTPUT file; the carry and seal steps write no heredoc.
const outputLines = (file) => Object.fromEntries(readFileSync(file, "utf8").split("\n").filter(Boolean).map((line) => [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1)]));
// The kernel refuses one environment string over 131072 bytes (MAX_ARG_STRLEN).
const ENV_STRING_MAX = 131072;
const CARRY_RUN_ID = "77";
const CARRIER_SECRET = "${{ secrets.scan-carrier-private-key }}";
const CARRIER_PASS = "${{ secrets.SCAN_CARRIER_PRIVATE_KEY }}";
// A test key pair, generated in-process; the committed key file is a placeholder.
const CARRIER = (() => {
  const { publicLine, privateText } = generateCarrierKey();
  return { publicLine, privateText, keyId: publicLine.split(" ")[1] };
})();
const ACTIONS = new URL("../", import.meta.url);

// A composite action's one step env, each `NAME: ${{ inputs.x }}` given input x
// (or its default), as the runner builds it.
function compositeEnv(action, inputs) {
  const text = readFileSync(new URL(`${action}/action.yml`, ACTIONS), "utf8");
  const { inputs: declared, runs } = parse(text);
  const env = {};
  for (const [name, expression] of Object.entries(runs.steps[0].env)) {
    const input = /^\$\{\{ inputs\.([\w-]+) \}\}$/.exec(expression)[1];
    env[name] = inputs[input] ?? declared[input].default ?? "";
  }
  return env;
}

// A step's `with:` values, each `${{ ... }}` replaced from the given values.
function withInputs(step, values) {
  return Object.fromEntries(
    Object.entries(step.with).map(([name, value]) => [
      name,
      String(value).replace(/\$\{\{ ([^}]+) \}\}/g, (_, expression) => {
        assert.ok(Object.hasOwn(values, expression), `${name}: ${expression}`);
        return values[expression];
      }),
    ]),
  );
}

// Runs the carry step, then the seal step as the composite runs it, on the
// given files; returns the two steps' outputs and their log.
function carry(t, files, { publicLine = CARRIER.publicLine, issue = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), "carry-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const temp = join(root, "temp");
  const workspace = join(root, "workspace");
  for (const dir of ["skill-reply", "patch", "seal-lane-output", "work-outcome"]) mkdirSync(join(temp, dir), { recursive: true });
  mkdirSync(workspace);
  // The copy step's sealer and key, from the base.
  for (const file of ["action.yml", "seal.mjs"]) writeFileSync(join(temp, "seal-lane-output", file), readFileSync(new URL(`seal-lane-output/${file}`, ACTIONS)));
  writeFileSync(join(temp, "seal-lane-output", "scan-carrier.pub"), publicLine);
  for (const [name, bytes] of Object.entries(files)) {
    const file = join(temp, name);
    if (bytes === "symlink") symlinkSync("/etc/hostname", file);
    else writeFileSync(file, bytes);
  }
  const output = join(root, "carry-output");
  writeFileSync(output, "");
  const steps = runSteps();
  const step = steps.find((s) => s.id === "carry");
  const result = runStep(step, workspace, {
    REPLY_DIR: join(temp, "skill-reply"),
    PATCH_FILE: join(temp, "patch", "patch.diff"),
    CARRY_DIR: join(temp, "carry"),
    SEAL_DIR: join(temp, "seal-lane-output"),
    // The step's issue-mode expression, as the runner would expand it.
    OUTCOME_DIR: issue ? join(temp, "work-outcome") : "",
    GITHUB_WORKSPACE: workspace,
    GITHUB_OUTPUT: output,
  });
  assert.equal(result.status, 0, result.stderr);
  const seal = steps.find((s) => s.id === "seal");
  assert.equal(seal.uses.split(" ")[0], "./.lane-seal");
  const sealOutput = join(root, "seal-output");
  writeFileSync(sealOutput, "");
  const sealed = spawnSync(process.execPath, [join(workspace, ".lane-seal", "seal.mjs")], {
    cwd: workspace,
    env: { PATH: process.env.PATH, GITHUB_WORKSPACE: workspace, GITHUB_RUN_ID: CARRY_RUN_ID, GITHUB_OUTPUT: sealOutput, ...compositeEnv("seal-lane-output", withInputs(seal, { "runner.temp": temp })) },
    encoding: "utf8",
  });
  return { outputs: outputLines(output), seal: { status: sealed.status, outputs: outputLines(sealOutput) }, log: result.stdout + sealed.stdout + sealed.stderr };
}

test("pr-run-activity-read.yml: the carry step stages each payload within its cap, and the seal step seals them in chunks one environment variable holds", async (t) => {
  const { randomBytes } = await import("node:crypto");
  const patch = randomBytes(262144);
  const reply = Buffer.from("lint-shell: fixed\n");
  const { outputs, seal, log } = carry(t, { "skill-reply/reply.txt": reply, "skill-reply/act-turns.json": "", "patch/patch.diff": patch });
  assert.deepEqual(outputs, { "reply-bytes": String(reply.length), "act-turns-bytes": "0", "patch-bytes": "262144" });
  assert.equal(seal.status, 0, log);
  // All three at their caps fit the five chunks the run job maps.
  const all = carry(t, { "skill-reply/reply.txt": randomBytes(16384), "skill-reply/act-turns.json": randomBytes(32768), "patch/patch.diff": patch });
  assert.equal(all.seal.status, 0, all.log);
  assert.ok(Number(all.seal.outputs["sealed-length"]) <= 5 * 98304);
  for (const [name, value] of Object.entries({ ...seal.outputs, ...all.seal.outputs })) assert.ok(`CARRY_${name}=${value}`.length < ENV_STRING_MAX, name);
  // Ciphertext only: no payload's bytes, and nothing at all, reach an output in the clear or the log.
  assert.doesNotMatch(Object.values(seal.outputs).join(""), new RegExp(reply.toString("base64").slice(0, 16).replace(/[+/]/g, "\\$&")));
  assert.equal(log, "", "no payload reaches the log");
  // Every output the two steps set is a run job output; none is a workflow_call output.
  const { jobs, on } = workflow("pr-run-activity-read.yml");
  for (const name of Object.keys(outputs)) assert.equal(jobs.run.outputs[`carry-${name}`], `\${{ steps.carry.outputs.${name} }}`, name);
  for (const name of Object.keys(all.seal.outputs)) assert.equal(jobs.run.outputs[`carry-${name}`], `\${{ steps.seal.outputs.${name} }}`, name);
  assert.doesNotMatch(JSON.stringify(on.workflow_call.outputs), /carry-/);
});

test("pr-run-activity-read.yml: a payload over its cap carries only its byte count, an absent one nothing, and the placeholder key seals nothing", (t) => {
  const over = carry(t, { "patch/patch.diff": Buffer.alloc(262145, 0x61), "skill-reply/reply.txt": Buffer.alloc(16385, 0x61) });
  assert.deepEqual(over.outputs, { "reply-bytes": "16385", "patch-bytes": "262145" });
  assert.deepEqual(over.seal.outputs, {}, "nothing over a cap is sealed");
  assert.match(over.log, /^::error::too-large: the reply is 16385 bytes, over its 16384-byte cap/m);
  assert.match(over.log, /^::error::too-large: the patch is 262145 bytes, over its 262144-byte cap/m);
  assert.deepEqual(carry(t, {}).outputs, {});
  assert.deepEqual(carry(t, {}).seal.outputs, {});
  assert.deepEqual(carry(t, { "patch/patch.diff": "symlink" }).outputs, {}, "a link is no payload");
  // A placeholder key file, as the repository held before keygen: the seal step fails and carries nothing.
  const placeholder = carry(t, { "skill-reply/reply.txt": "x\n" }, { publicLine: "PLACEHOLDER: owner runs keygen; see .github/actions/open-lane-output/README.md\n" });
  assert.equal(placeholder.seal.status, 1);
  assert.match(placeholder.log, /^::error::seal-lane-output: the public key file holds no x25519 key line/m);
  assert.deepEqual(placeholder.seal.outputs, {});
  // The committed key file seals.
  const committed = carry(t, { "skill-reply/reply.txt": "x\n" }, { publicLine: read("../../lane-keys/scan-carrier.pub") });
  assert.equal(committed.seal.status, 0, committed.log);
  assert.match(committed.seal.outputs["sealed-length"], /^[1-9][0-9]*$/);
});

test("pr-run-activity-read.yml: the run fields keep at most four local-command stderr entries", async (t) => {
  const root = mkdtempSync(join(tmpdir(), "act-turns-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const stderr = (n) => ({ type: "user", message: { content: `<local-command-stderr>failure ${n}</local-command-stderr>` } });
  const messages = [1, 2, 3, 4, 5, 6].map(stderr).concat({ type: "result", subtype: "success", num_turns: 2, modelUsage: { m: {} } });
  writeFileSync(join(root, "execution.json"), JSON.stringify(messages));
  const script = runSteps().find((s) => s.id === "act-turns").with.script;
  const { createRequire } = await import("node:module");
  const core = { setFailed: (message) => assert.fail(message), info: () => {} };
  await new AsyncFunction("require", "core", "process", script)(createRequire(import.meta.url), core, { env: { EXECUTION_FILE: join(root, "execution.json"), REPLY_DIR: root } });
  const { local_command_stderr: kept } = JSON.parse(readFileSync(join(root, "act-turns.json"), "utf8"));
  assert.deepEqual(kept, [1, 2, 3, 4].map((n) => `<local-command-stderr>failure ${n}</local-command-stderr>`));
});

// --- the scan job's open and check, from the run job's outputs ---

const OUTPUT_EXPRESSION = /^\$\{\{ needs\.run\.outputs\.([\w-]+) \}\}$/;

// Runs the open step, as the scan job runs it, on the run job's outputs:
// skipped (no file, no failure) when its if is false. Returns its exit, log,
// output and env files, and the directory the check step then reads.
function openStep(t, runOutputs, { privateText = CARRIER.privateText, runId = CARRY_RUN_ID, runAttempt = "1" } = {}) {
  const steps = scanSteps();
  const step = steps.find((s) => s.id === "open");
  const context = { "inputs.issue-number": "", "needs.run.outputs.go": "", "needs.run.outputs.carry-sealed-length": "" };
  for (const [name, value] of Object.entries(runOutputs)) context[`needs.run.outputs.${name}`] = value;
  const base = steps.find((s) => s.id === "base");
  const ran = atStep(base.if, prRun(base.if, context, {}));
  if (!ran) return { ran, status: 0, log: "", output: "", env: "", dir: "" };
  const temp = mkdtempSync(join(tmpdir(), "open-"));
  t.after(() => rmSync(temp, { recursive: true, force: true }));
  const values = { "runner.temp": temp, "steps.key.outputs.id": CARRIER.keyId, "secrets.scan-carrier-private-key": privateText };
  for (const [name, expression] of Object.entries(step.with)) {
    const output = OUTPUT_EXPRESSION.exec(String(expression));
    if (output) values[`needs.run.outputs.${output[1]}`] = runOutputs[output[1]] ?? "";
  }
  const output = join(temp, "github-output");
  const envFile = join(temp, "github-env");
  writeFileSync(output, "");
  writeFileSync(envFile, "");
  const result = spawnSync(process.execPath, [fileURLToPath(new URL("open-lane-output/open.mjs", ACTIONS))], {
    env: { PATH: process.env.PATH, GITHUB_RUN_ID: runId, GITHUB_RUN_ATTEMPT: runAttempt, GITHUB_OUTPUT: output, GITHUB_ENV: envFile, ...compositeEnv("open-lane-output", withInputs(step, values)) },
    encoding: "utf8",
  });
  return { ran, status: result.status, log: result.stdout + result.stderr, output: readFileSync(output, "utf8"), env: readFileSync(envFile, "utf8"), dir: result.status === 0 ? join(temp, "scan-in") : "" };
}

// The env the check step reads, built from the run job's outputs as the
// runner would pass them, and OPEN_DIR from the open step's outcome.
function decodeEnv(runOutputs, inputs = { "issue-number": "" }, open = { status: 1, ran: false }, issueFields = {}) {
  const step = scanSteps().find((s) => s.id === "decode");
  const env = {};
  for (const [name, expression] of Object.entries(step.env)) {
    const output = OUTPUT_EXPRESSION.exec(expression);
    const input = /^\$\{\{ inputs\.([\w-]+) \}\}$/.exec(expression);
    const checked = /^\$\{\{ needs\.issue-fields\.outputs\.([\w-]+) \}\}$/.exec(expression);
    if (checked) {
      env[name] = issueFields[checked[1]] ?? "";
      continue;
    }
    if (name === "OPEN_DIR") {
      const temp = open.dir ? open.dir.slice(0, -"/scan-in".length) : "/unused";
      env[name] = evaluate(expression.replace("format('{0}/scan-in', runner.temp)", JSON.stringify(`${temp}/scan-in`)), { "steps.open.outcome": open.ran ? (open.status === 0 ? "success" : "failure") : "skipped" });
      continue;
    }
    assert.ok(output || input, `${name}: ${expression}`);
    env[name] = output ? (runOutputs[output[1]] ?? "") : (inputs[input[1]] ?? "");
  }
  return env;
}

// Runs the check step; returns its outputs and failure.
async function decode(t, env) {
  const outputs = {};
  let failed = null;
  const core = { setOutput: (name, value) => (outputs[name] = value), setFailed: (message) => (failed = message) };
  const { createRequire } = await import("node:module");
  const script = scanSteps().find((s) => s.id === "decode").with.script;
  await new AsyncFunction("require", "core", "process", script)(createRequire(import.meta.url), core, { env });
  const files = outputs.dir ? Object.fromEntries(readdirSync(outputs.dir).map((name) => [name, readFileSync(join(outputs.dir, name))])) : {};
  return { outputs, failed, files };
}

// The open step, then the check step, on the run job's outputs.
async function scanIn(t, runOutputs, options) {
  const open = openStep(t, runOutputs, options);
  if (open.status !== 0) return { open, failed: null, outputs: {}, files: {} };
  return { open, ...(await decode(t, decodeEnv(runOutputs, undefined, open))) };
}

// The run job's outputs after a PR-mode skill run, from the real carry and
// seal steps and the run job's output map.
function runOutputsAfterCarry(t, files, options) {
  const { outputs, seal } = carry(t, files, options);
  const { jobs } = workflow("pr-run-activity-read.yml");
  const mapped = {};
  for (const [name, expression] of Object.entries(jobs.run.outputs)) {
    const step = /^\$\{\{ steps\.(carry|seal)\.outputs\.([\w-]+) \}\}$/.exec(expression);
    if (step) mapped[name] = (step[1] === "carry" ? outputs : seal.outputs)[step[2]] ?? "";
  }
  return {
    ...mapped,
    go: "true",
    "base-sha": "b".repeat(40),
    "head-sha": "c".repeat(40),
    "kill-proceed": "true",
    "trigger-proceed": "true",
    "config-outcome": "success",
    "act-outcome": "success",
    "patch-collected": files["patch/patch.diff"] ? "written" : "empty",
  };
}

test("scan job: the reply, run fields and patch round-trip sealed from the run job through its outputs to the open and check steps", async (t) => {
  const { randomBytes } = await import("node:crypto");
  const files = {
    "skill-reply/reply.txt": Buffer.from("lint-shell: fixed\nnon-ASCII: é中\n"),
    "skill-reply/act-turns.json": Buffer.from('{"num_turns": 3}\n'),
    "patch/patch.diff": randomBytes(262144),
  };
  const runOutputs = runOutputsAfterCarry(t, files);
  const { open, outputs, failed, files: decoded } = await scanIn(t, runOutputs);
  assert.equal(open.status, 0, open.log);
  assert.equal(failed, null);
  assert.deepEqual(decoded, { "act-turns.json": files["skill-reply/act-turns.json"], "patch.diff": files["patch/patch.diff"], "reply.txt": files["skill-reply/reply.txt"] });
  assert.deepEqual({ reply: outputs.reply, patch: outputs.patch, state: outputs["patch-state"] }, { reply: "true", patch: "true", state: "" });
  // The plaintext reaches neither the open step's log, its outputs nor GITHUB_ENV.
  for (const text of [open.log, open.output, open.env]) assert.doesNotMatch(text, /lint-shell|num_turns/);
  assert.equal(open.output, "opened=reply.txt act-turns.json patch.diff\n");
  // Each env value fits one environment string.
  for (const [name, value] of Object.entries(decodeEnv(runOutputs, undefined, open))) assert.ok(`${name}=${value}`.length < ENV_STRING_MAX, name);
  // No patch collected: no patch file, and the state the apply job reads is `empty`.
  const empty = await scanIn(t, runOutputsAfterCarry(t, { "skill-reply/reply.txt": "ok\n" }));
  assert.equal(empty.failed, null);
  assert.deepEqual(Object.keys(empty.files), ["reply.txt"]);
  assert.deepEqual([empty.outputs.patch, empty.outputs["patch-state"]], ["false", "empty"]);
  // A run that stopped before head code hands on nothing, and the open step never runs.
  const stopped = await scanIn(t, { go: "false", "kill-proceed": "true", "trigger-proceed": "false", "trigger-reason": "untrusted-actor" });
  assert.equal(stopped.open.ran, false);
  assert.deepEqual([stopped.failed, stopped.outputs.reply, stopped.outputs.patch], [null, "false", "false"]);
});

// Issue mode seals its outcome files with the reply, run fields and patch.
// The cap on all of them is five chunks: GitHub caps a job's outputs at 1 MB,
// counted as UTF-16, and five 98304-character chunks are about 0.94 MB
// (https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax,
// jobs.<job_id>.outputs). So every payload at its cap still seals.
test("scan job: an issue run's outcome files round-trip sealed with every payload at its cap, within five chunks", async (t) => {
  const { randomBytes } = await import("node:crypto");
  const at = (bytes) => Buffer.alloc(bytes, "a");
  const files = {
    "skill-reply/reply.txt": at(16384),
    "skill-reply/act-turns.json": at(32768),
    "patch/patch.diff": randomBytes(262144),
    "work-outcome/work-outcome.json": randomBytes(49152),
    "work-outcome/lane.json": at(4096),
  };
  const { seal } = carry(t, files, { issue: true });
  assert.equal(seal.status, 0, JSON.stringify(seal.outputs));
  assert.ok(Number(seal.outputs["sealed-length"]) <= 5 * 98304, seal.outputs["sealed-length"]);
  const runOutputs = runOutputsAfterCarry(t, files, { issue: true });
  const open = openStep(t, runOutputs);
  assert.equal(open.status, 0, open.log);
  const { outputs, failed, files: decoded } = await decode(t, decodeEnv(runOutputs, { "issue-number": "7" }, open));
  assert.equal(failed, null);
  assert.deepEqual(Object.keys(decoded).sort(), ["act-turns.json", "lane.json", "patch.diff", "reply.txt", "work-outcome.json"]);
  assert.deepEqual(decoded["work-outcome.json"], files["work-outcome/work-outcome.json"]);
  assert.deepEqual([outputs.outcome, outputs.patch], ["true", "true"]);
  // One byte over the outcome's cap publishes nothing.
  const over = runOutputsAfterCarry(t, { ...files, "patch/patch.diff": "", "work-outcome/work-outcome.json": at(49153) }, { issue: true });
  assert.equal(over["carry-work-outcome-bytes"], "49153");
  const overOpen = openStep(t, over);
  const refused = await decode(t, decodeEnv({ ...over, "patch-collected": "empty" }, { "issue-number": "7" }, overOpen));
  assert.match(refused.failed, /^too-large: the work-outcome is 49153 bytes/);
  // A PR-mode run carries no outcome: one that does publishes nothing.
  const pr = runOutputsAfterCarry(t, { "skill-reply/reply.txt": "ok\n", "work-outcome/lane.json": "{}" }, { issue: true });
  const prOpen = openStep(t, pr);
  assert.equal(prOpen.status, 0, prOpen.log);
  const prDecoded = await decode(t, decodeEnv(pr, { "issue-number": "" }, prOpen));
  assert.match(prDecoded.failed, /^payload-mismatch: a PR-mode run carried an issue outcome/);
  // The collect step cuts the model's outcome file at that same cap.
  const collect = runSteps().find((s) => s.name === "Collect the issue outcome");
  assert.match(collect.run, /head -c 49152 "\$SCRATCH_OUTCOME"/);
  assert.ok(runSteps().indexOf(collect) < runSteps().findIndex((s) => s.id === "carry"), "collected before it is carried");
});

test("scan job: a credential in the issue outcome blocks every upload", async (t) => {
  const { clean, failed } = await scanWith(t, ({ temp }) => writeFileSync(join(temp, "skill-reply", "work-outcome.json"), `{"summary": "${KEY}"}\n`));
  assert.equal(clean, "false");
  assert.match(failed, /rotate this credential/);
  const upload = scanSteps().find((s) => s.id === "outcome-upload");
  const runs = (clean) => evaluate(upload.if, { "inputs.issue-number": "7", "steps.leak-scan.outputs.clean": clean, "steps.decode.outputs.outcome": "true" });
  assert.deepEqual([runs("true"), runs("false"), runs("")], [true, false, false]);
  assert.equal(upload.with.name, "work-outcome-${{ inputs.issue-number }}");
});

// The issue-fields job: the run job's issue fields reach the caller only
// through it, held to their closed sets and the combinations the run job's
// steps make, with any branch claim re-derived by the earlier-work check
// ([h16]: nothing that picks the commit a patch applies to takes a run job
// output unchecked).
const issueFieldsJob = () => workflow("pr-run-activity-read.yml").jobs["issue-fields"];
async function issueStep(env) {
  const step = issueFieldsJob().steps.find((s) => s.id === "issue");
  const outputs = {};
  let failed = null;
  const core = { setOutput: (name, value) => (outputs[name] = value), setFailed: (message) => (failed = message) };
  const { createRequire } = await import("node:module");
  const full = { LANE: "work-resolve-issue", ISSUE_NUMBER: "7", STARTED: "true", REUSE_BRANCH: "", RESUME_BRANCH: "", RESUME_TIP: "", BASE_SHA: "b".repeat(40), ...env };
  await new AsyncFunction("require", "core", "github", "context", "process", step.with.script)(createRequire(import.meta.url), core, {}, SCAN_CONTEXT, { env: full });
  return { outputs, failed };
}

// Liveness: the job that hands issue-run-started to the caller runs whatever
// the run job's result but skipped, in issue mode only, and holds no
// environment, so a cancelled or timed-out run job, or a scan job the
// environment never admits, still leaves the report job its gate.
test("pr-run-activity-read.yml: issue-fields runs after any run job result but skipped, with no environment, and every issue output is its", () => {
  const read = workflow("pr-run-activity-read.yml");
  const job = read.jobs["issue-fields"];
  assert.equal(job.needs, "run");
  assert.equal(job.environment, undefined);
  assert.deepEqual(job.permissions, { contents: "read", "pull-requests": "read" });
  assert.match(job.if, /^always\(\)/);
  for (const result of ["success", "failure", "cancelled"]) {
    assert.equal(evaluate(job.if.replace(/^always\(\) && /, ""), { "inputs.issue-number": "7", "needs.run.result": result }), true, result);
  }
  assert.equal(evaluate(job.if.replace(/^always\(\) && /, ""), { "inputs.issue-number": "7", "needs.run.result": "skipped" }), false);
  assert.equal(evaluate(job.if.replace(/^always\(\) && /, ""), { "inputs.issue-number": "", "needs.run.result": "success" }), false);
  // A refusal ends the job green, so its outputs reach the caller.
  for (const step of job.steps) assert.equal(step["continue-on-error"], true, step.name);
  const outputs = read.on.workflow_call.outputs;
  for (const name of ["issue-run-started", "reuse-branch", "resume-branch", "resume-tip", "base-sha"]) {
    assert.equal(outputs[`scan-${name}`].value, `\${{ jobs.issue-fields.outputs.${name} }}`, name);
  }
  assert.equal(job.outputs["issue-run-started"], "${{ steps.issue.outputs.issue-run-started }}");
  for (const name of ["checked", "reuse-branch", "resume-branch", "resume-tip", "base-sha", "start-sha"]) {
    assert.equal(job.outputs[name], `\${{ steps.checked.outputs.${name} }}`, name);
  }
  // The scan job publishes nothing in issue mode unless the fields were checked.
  const require = read.jobs.scan.steps[0];
  assert.equal(require.name, "Require the checked issue fields");
  assert.equal(spawnSync("bash", ["-c", require.run], { env: { PATH: process.env.PATH, CHECKED: "" } }).status, 1);
  assert.equal(spawnSync("bash", ["-c", require.run], { env: { PATH: process.env.PATH, CHECKED: "true" } }).status, 0);
});

test("issue-fields: the issue step holds each field to its closed set and to the combinations the run job makes", async () => {
  const base = "b".repeat(40);
  const tip = "c".repeat(40);
  const branch = "work-resolve-issue/issue-7-123-1";
  const fresh = await issueStep({});
  assert.equal(fresh.failed, null);
  assert.deepEqual(fresh.outputs, { "issue-run-started": "true", claimed: "false", "reuse-branch": "", "resume-branch": "", "resume-tip": "", "base-sha": base });
  const resumed = await issueStep({ RESUME_BRANCH: branch, RESUME_TIP: tip });
  assert.deepEqual([resumed.failed, resumed.outputs.claimed, resumed.outputs["resume-tip"]], [null, "true", tip]);
  const reused = await issueStep({ STARTED: "false", REUSE_BRANCH: branch });
  assert.deepEqual([reused.failed, reused.outputs.claimed, reused.outputs["reuse-branch"]], [null, "true", branch]);
  // A refused field sets only issue-run-started.
  for (const [name, env] of [
    ["another issue's branch", { RESUME_BRANCH: "work-resolve-issue/issue-8-123-1", RESUME_TIP: tip }],
    ["another lane's branch", { STARTED: "false", REUSE_BRANCH: "pr-unblock/issue-7-123-1" }],
    ["a base that is no commit id", { BASE_SHA: "main" }],
    ["a reuse that started the skill", { REUSE_BRANCH: branch }],
    ["a reuse beside a resume", { STARTED: "false", REUSE_BRANCH: branch, RESUME_BRANCH: branch, RESUME_TIP: tip }],
    ["a resume tip with no branch", { RESUME_TIP: tip }],
    ["a resume branch with no tip", { RESUME_BRANCH: branch }],
    ["a resume that started no skill", { STARTED: "false", RESUME_BRANCH: branch, RESUME_TIP: tip }],
    ["a started run with no base", { BASE_SHA: "" }],
  ]) {
    const result = await issueStep(env);
    assert.match(String(result.failed), /^bad-output: /, name);
    assert.deepEqual(result.outputs, { "issue-run-started": env.STARTED ?? "true" }, name);
  }
  const unset = await issueStep({ STARTED: "" });
  assert.match(String(unset.failed), /^bad-output: the run job's issue-run-started/);
  assert.deepEqual(unset.outputs, {});
});

// Branch eligibility: a branch claim is published only when the default-tip
// earlier-work check, run again, chooses the same reuse branch, resume branch
// and tip; the check's own rules (App commits, not rejected) then hold for
// the branch the caller gets. The run job chose before the model ran, so a
// resume branch the default branch moved past since still resumes.
test("issue-fields: a branch claim is published only when the re-derived earlier-work check chooses the same branch and tip", (t) => {
  const job = issueFieldsJob();
  const prior = job.steps.find((s) => s.id === "prior");
  assert.match(prior.run, /node \.base\/\.github\/scripts\/work-resolve-issue\/report-outcome\.mjs --find-prior$/m);
  assert.equal(prior.env.FIND_PRIOR_KEEP_BEHIND, "true");
  assert.equal(job.steps.find((s) => s.id === "base").with.ref, "${{ github.event.repository.default_branch }}");
  const checked = job.steps.find((s) => s.id === "checked");
  assert.equal(evaluate(checked.if, { "steps.issue.outcome": "success", "steps.issue.outputs.claimed": "true", "steps.prior.outcome": "failure" }), false, "a claim whose re-derive failed");
  assert.equal(evaluate(checked.if, { "steps.issue.outcome": "success", "steps.issue.outputs.claimed": "false", "steps.prior.outcome": "skipped" }), true, "no claim needs no re-derive");
  const root = mkdtempSync(join(tmpdir(), "issue-fields-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const branch = "work-resolve-issue/issue-7-123-1";
  const tip = "c".repeat(40);
  const base = "b".repeat(40);
  const publish = (claim, priorLines) => {
    const priorOut = join(root, "prior");
    const output = join(root, "output");
    writeFileSync(priorOut, priorLines);
    writeFileSync(output, "");
    const result = runStep(checked, root, { CLAIMED: "true", REUSE_BRANCH: "", RESUME_BRANCH: "", RESUME_TIP: "", BASE_SHA: base, ...claim, PRIOR_OUT: priorOut, GITHUB_OUTPUT: output });
    return { status: result.status, stdout: result.stdout, outputs: outputLines(output) };
  };
  const resume = { RESUME_BRANCH: branch, RESUME_TIP: tip };
  const same = publish(resume, `proceed=true\nreuse-branch=\nresume-branch=${branch}\nresume-tip=${tip}\nresume-cause=turn-cap\n`);
  assert.equal(same.status, 0, same.stdout);
  assert.deepEqual(same.outputs, { checked: "true", "reuse-branch": "", "resume-branch": branch, "resume-tip": tip, "base-sha": base, "start-sha": tip });
  for (const [name, lines] of [
    ["another tip", `proceed=true\nreuse-branch=\nresume-branch=${branch}\nresume-tip=${"e".repeat(40)}\n`],
    ["no resume now (the branch is rejected or not the App's)", "proceed=true\nreuse-branch=\n"],
    ["another branch", `proceed=true\nreuse-branch=\nresume-branch=work-resolve-issue/issue-7-124-1\nresume-tip=${tip}\n`],
  ]) {
    const result = publish(resume, lines);
    assert.equal(result.status, 1, name);
    assert.match(result.stdout, /^::error::bad-output: /m, name);
    assert.deepEqual(result.outputs, {}, name);
  }
  const reuse = publish({ REUSE_BRANCH: branch }, "proceed=false\nskip-reason=not-applicable\nreuse-branch=\n");
  assert.equal(reuse.status, 1, "a reuse the check does not choose");
  const fresh = publish({ CLAIMED: "false" }, "");
  assert.deepEqual([fresh.status, fresh.outputs["start-sha"]], [0, base]);
});

// lane.json is the runner's record: an issue run that started carries it,
// naming no branch yet and exactly the branch the run resumed
// (report-outcome.mjs reads branch and resume from it).
test("scan job: an issue run that started must carry lane.json, with no branch and the checked resume", async (t) => {
  const lane = (fields) => JSON.stringify({ branch: "", class: "", resets: "", "max-turns": "50", resume: "", failed: "false", "api-error-status": "", "error-text": "", ...fields });
  const branch = "work-resolve-issue/issue-7-123-1";
  const decodeIssue = async (files, issueFields) => {
    const outputs = runOutputsAfterCarry(t, files, { issue: true });
    const open = openStep(t, outputs);
    return decode(t, decodeEnv({ ...outputs, "patch-collected": "" }, { "issue-number": "7" }, open, issueFields));
  };
  const started = { "issue-run-started": "true", "resume-branch": "" };
  assert.equal((await decodeIssue({ "work-outcome/lane.json": lane({}) }, started)).failed, null);
  assert.equal((await decodeIssue({ "work-outcome/lane.json": lane({ resume: branch }) }, { ...started, "resume-branch": branch })).failed, null);
  for (const [name, files, fields] of [
    ["no lane.json", { "skill-reply/reply.txt": "ok\n" }, started],
    ["a branch already named", { "work-outcome/lane.json": lane({ branch }) }, started],
    ["a resume the run did not make", { "work-outcome/lane.json": lane({ resume: branch }) }, started],
    ["no resume on a resumed run", { "work-outcome/lane.json": lane({}) }, { ...started, "resume-branch": branch }],
    ["lane.json that does not parse", { "work-outcome/lane.json": "{" }, started],
  ]) {
    const { failed } = await decodeIssue(files, fields);
    assert.match(String(failed), /^payload-mismatch: /, name);
  }
  // A run that did not start (a reuse or a stale stop) carries nothing.
  assert.equal((await decodeIssue({ "skill-reply/reply.txt": "ok\n" }, { "issue-run-started": "false" })).failed, null);
});

// The reuse summary job runs code from the default branch tip only, and
// takes its branch and base from the issue-fields job's checked outputs.
test("pr-run-activity-read.yml: the reuse summary job takes code from the default branch tip and its branch and base from issue-fields", () => {
  const job = workflow("pr-run-activity-read.yml").jobs.summary;
  assert.deepEqual(job.needs, ["run", "issue-fields"]);
  assert.equal(job.steps.find((s) => s.id === "base").with.ref, "${{ github.event.repository.default_branch }}");
  const text = JSON.stringify(job);
  assert.doesNotMatch(text, /needs\.run\.outputs/);
  const ctx = (checked, reuse) => ({ "needs.issue-fields.outputs.checked": checked, "needs.issue-fields.outputs.reuse-branch": reuse, "github.event.repository.default_branch": "main" });
  const runs = (c) => evaluate(job.if.replace(/^\$\{\{ |\s*\}\}$/g, "").replace(/!cancelled\(\) && /, ""), c);
  assert.equal(runs(ctx("true", "work-resolve-issue/issue-7-1-1")), true);
  assert.equal(runs(ctx("", "work-resolve-issue/issue-7-1-1")), false, "an unchecked reuse branch runs no summary");
});

test("work-resolve-issue.yml: every resolve-issue output a job reads is the read runner's scan or issue-fields job's", () => {
  const { jobs } = workflow("work-resolve-issue.yml");
  const outputs = workflow("pr-run-activity-read.yml").on.workflow_call.outputs;
  const read = (call) => [...new Set([...JSON.stringify(jobs).matchAll(new RegExp(`needs\\.${call}\\.outputs\\.([\\w-]+)`, "g"))].map((m) => m[1]))].sort();
  const names = read("resolve-issue");
  assert.deepEqual(names, ["scan-base-sha", "scan-issue-run-started", "scan-outcome-uploaded", "scan-patch-attempt", "scan-patch-sha256", "scan-patch-state", "scan-reply-attempt", "scan-resume-branch", "scan-resume-tip", "scan-reuse-branch"]);
  // The subscription call's are the same outputs, read in the same picks.
  assert.deepEqual(read("resolve-issue-subscription"), names);
  for (const name of names) assert.match(outputs[name].value, /^\$\{\{ jobs\.(scan|issue-fields)\.outputs\.[\w-]+ \}\}$/, name);
});

test("scan job: a re-run at another attempt of the same run opens; a bundle from another run, or opened with another key, fails closed without rotation", async (t) => {
  const outputs = runOutputsAfterCarry(t, { "skill-reply/reply.txt": "done\n" });
  const rerun = await scanIn(t, outputs, { runAttempt: "2" });
  assert.equal(rerun.open.status, 0, rerun.open.log);
  assert.deepEqual(rerun.files, { "reply.txt": Buffer.from("done\n") });
  for (const [name, options] of Object.entries({ "another run": { runId: "78" }, "another key": { privateText: generateCarrierKey().privateText } })) {
    const { open } = await scanIn(t, outputs, options);
    assert.equal(open.status, 1, name);
    assert.match(open.log, /^::error::sealed-mismatch: /m, name);
    assert.doesNotMatch(open.log, /rotate/, name);
    assert.equal(open.dir, "", name);
  }
  // A caller that passed nothing, or an environment whose secret is unset or malformed: one fixed
  // message with no key material, no rotation line, nothing opened, and the check step never runs.
  for (const privateText of ["", "  ", "bm90IGEga2V5", CARRIER.privateText.slice(0, 30)]) {
    const result = await scanIn(t, outputs, { privateText });
    assert.equal(result.open.status, 1, JSON.stringify(privateText));
    assert.equal(result.open.log, "::error::no-key: the private key is missing or malformed; no payload opened\n");
    assert.equal(result.open.dir, "");
    assert.deepEqual(result.files, {});
  }
});

test("scan job: an output the runner withheld fails closed with the rotation signal, and nothing is opened", async (t) => {
  const { randomBytes } = await import("node:crypto");
  const outputs = runOutputsAfterCarry(t, { "skill-reply/reply.txt": "done\n", "patch/patch.diff": randomBytes(200000) });
  // The runner skips an output it judges may hold a secret: the chunk goes, the length stays.
  for (const withheld of ["carry-sealed-1", "carry-sealed-3"]) {
    const { open } = await scanIn(t, { ...outputs, [withheld]: "" });
    assert.equal(open.status, 1, withheld);
    assert.match(open.log, /^::error::output-withheld: .*%0Arotate this credential$/m, withheld);
    assert.equal(open.dir, "", withheld);
  }
  // A bundle of three chunks leaves the fourth and fifth empty by design, not withheld.
  assert.deepEqual([outputs["carry-sealed-4"], outputs["carry-sealed-5"]], ["", ""]);
  assert.equal((await scanIn(t, outputs)).failed, null);
});

test("scan job: a payload over its cap, or one that does not match its byte count, fails closed without rotation", async (t) => {
  const over = await scanIn(t, runOutputsAfterCarry(t, { "patch/patch.diff": Buffer.alloc(262145, 0x61) }));
  assert.equal(over.failed, "too-large: the patch is 262145 bytes, over its 262144-byte cap; nothing is published");
  const at = await scanIn(t, runOutputsAfterCarry(t, { "patch/patch.diff": Buffer.alloc(262144, 0x61) }));
  assert.equal(at.failed, null, "the cap itself passes");
  // A forged byte count over the cap is refused.
  const forged = await scanIn(t, { ...runOutputsAfterCarry(t, { "patch/patch.diff": "x\n" }), "carry-patch-bytes": "999999" });
  assert.match(forged.failed, /^too-large: /);
  const good = runOutputsAfterCarry(t, { "skill-reply/reply.txt": "fixed\n", "patch/patch.diff": "diff\n" });
  const tampered = {
    "a wrong byte count": { "carry-reply-bytes": "7" },
    "a byte count one short": { "carry-reply-bytes": "5" },
    "a byte count that is no number": { "carry-reply-bytes": "6 " },
    "an opened payload with no byte count": { "carry-reply-bytes": "" },
    "a byte count with no sealed bundle": { "carry-sealed-length": "", "carry-sealed-1": "" },
    "a patch the collector never reported": { "patch-collected": "empty" },
  };
  for (const [name, change] of Object.entries(tampered)) {
    const { failed } = await scanIn(t, { ...good, ...change });
    assert.match(failed ?? "", /^payload-mismatch: .*nothing is published$/, name);
    assert.doesNotMatch(failed, /rotate/, name);
  }
  // A collected patch that never arrived.
  const noPatch = runOutputsAfterCarry(t, { "skill-reply/reply.txt": "fixed\n" });
  assert.match((await scanIn(t, { ...noPatch, "patch-collected": "written" })).failed ?? "", /^payload-mismatch: the patch does not match the state its collector reported/);
});

test("scan job: every run job output set after head code must be in its closed set", async (t) => {
  const good = runOutputsAfterCarry(t, { "skill-reply/reply.txt": "fixed\n" });
  assert.equal((await scanIn(t, { ...good, "dirty-tree": "false", "skip-reason": "no-ci-failure", "lane-class": "max-turns" })).failed, null);
  const forged = {
    "dirty-tree": "maybe",
    "act-outcome": "passed",
    "skip-reason": "Skip\nreason",
    "patch-collected": "written ",
    "lane-class": "credit stop",
    "head-sha": "c".repeat(39),
    go: "yes",
  };
  for (const [name, value] of Object.entries(forged)) {
    const { failed } = await decode(t, decodeEnv({ ...good, [name]: value }));
    assert.match(failed ?? "", new RegExp(`^bad-output: the run job's ${name} output is not one the runner sets`), name);
  }
});

test("pr-run-activity-read.yml: the scan-carrier key is passed by name by each read-runner caller, read by the scan job's decode step alone, and its environment is on that job alone", () => {
  const files = workflowFiles();
  const read = workflow("pr-run-activity-read.yml");
  assert.deepEqual(read.on.workflow_call.secrets["scan-carrier-private-key"].required, true);
  // Every job that calls the read runner passes it by name in its secrets map, and nothing else names it.
  let callers = 0;
  for (const file of files) {
    for (const [id, job] of Object.entries(workflow(file).jobs ?? {})) {
      if (job.uses === READ_RUNNER) {
        callers += 1;
        assert.notEqual(job.secrets, "inherit", `${file} ${id}`);
        assert.equal(job.secrets["scan-carrier-private-key"], CARRIER_PASS, `${file} ${id}`);
        const rest = { ...job, secrets: { ...job.secrets, "scan-carrier-private-key": undefined } };
        assert.doesNotMatch(JSON.stringify(rest), /SCAN_CARRIER_PRIVATE_KEY|scan-carrier-private-key/i, `${file} ${id}`);
      } else if (file !== "pr-run-activity-read.yml") {
        assert.doesNotMatch(JSON.stringify(job), /SCAN_CARRIER_PRIVATE_KEY|scan-carrier-private-key/i, `${file} ${id}`);
      }
    }
  }
  assert.equal(callers, 14, "resolve-conflicts, address-feedback, review-dependency, fix-ci, fix-docs, resolve-issue and their subscription calls, and fix-ci's rung-up pair");
  // In the read runner, one step of one job.
  for (const [id, job] of Object.entries(read.jobs)) {
    const steps = (job.steps ?? []).filter((step) => /scan-carrier-private-key|SCAN_CARRIER_PRIVATE_KEY/i.test(JSON.stringify(step)));
    assert.deepEqual(steps.map((step) => step.id), id === "scan" ? ["open"] : [], id);
  }
  const open = read.jobs.scan.steps.find((s) => s.id === "open");
  assert.deepEqual(stepSecrets(open), ["scan-carrier-private-key"]);
  assert.equal(open.with["private-key"], CARRIER_SECRET);
  assert.equal(open.env, undefined);
  assert.equal(open.uses, "./.base/.github/actions/open-lane-output");
  for (const file of files) {
    for (const [id, job] of Object.entries(workflow(file).jobs ?? {})) {
      if (file === "pr-run-activity-read.yml" && id === "scan") assert.equal(job.environment, "pr-pipeline-scan-carrier");
      else assert.doesNotMatch(JSON.stringify(job.environment ?? ""), /pr-pipeline-scan-carrier/, `${file} ${id}`);
    }
  }
});

test("scan job: the verdict is built from the run job's checked outputs, never from a file a model job wrote", (t) => {
  const steps = scanSteps();
  const write = steps.find((s) => s.name === "Write the verdict");
  for (const [name, expression] of Object.entries(write.env)) {
    assert.match(expression, /^\$\{\{ (needs\.run\.outputs\.[\w-]+|inputs\.(lane|activity)|runner\.temp|steps\.(patch-upload|decode)\.[\w.-]+.*) \}\}/, name);
  }
  // Every needs.run output it reads, the decode step checks.
  const decoded = new Set(Object.values(steps.find((s) => s.id === "decode").env));
  for (const expression of Object.values(write.env).filter((value) => value.includes("needs.run.outputs."))) {
    assert.ok(decoded.has(expression), `${expression} is checked by the decode step`);
  }
  const root = mkdtempSync(join(tmpdir(), "verdict-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const env = {
    LANE: "pr-unblock",
    ACTIVITY: "fix-ci",
    KILL_PROCEED: "true",
    KILL_REASON: "",
    TRIGGER_PROCEED: "true",
    TRIGGER_REASON: "",
    HEAD_SHA: "c".repeat(40),
    CONFIG_OUTCOME: "success",
    SKIP_REASON: "",
    ACT_OUTCOME: "success",
    DIRTY_TREE: "",
    PATCH_STATE: "written",
    VERDICT_DIR: root,
    GITHUB_SERVER_URL: "https://github.com",
    GITHUB_REPOSITORY: "o/r",
    GITHUB_RUN_ID: "7",
  };
  assert.equal(runStep(write, root, env).status, 0);
  assert.deepEqual(JSON.parse(readFileSync(join(root, "verdict.json"), "utf8")), {
    version: 1,
    lane: "pr-unblock",
    activity: "fix-ci",
    "run-url": "https://github.com/o/r/actions/runs/7",
    "head-sha": "c".repeat(40),
    gates: { "kill-switch": { proceed: "true", reason: "" }, trigger: { proceed: "true", reason: "" } },
    config: "valid",
    "skip-reason": null,
    outcome: "success",
    "dirty-tree": null,
    patch: "written",
  });
  // The run job writes no verdict.
  assert.ok(!runSteps().some((s) => /verdict/i.test(s.name ?? "") && s.name !== "Check the gate skill's verdict"));
});

test("pr-run-activity-read.yml: the patch and reply outputs come from the scan job alone, and every caller's reads resolve", () => {
  const read = workflow("pr-run-activity-read.yml");
  const outputs = read.on.workflow_call.outputs;
  for (const name of ["patch-state", "patch-sha256", "patch-attempt", "reply-attempt"]) {
    for (const exposed of [name, `scan-${name}`]) assert.equal(outputs[exposed].value, `\${{ jobs.scan.outputs.${name} }}`, exposed);
    assert.ok(Object.hasOwn(read.jobs.scan.outputs, name) && !Object.hasOwn(read.jobs.run.outputs, name), name);
  }
  // Every output a caller of the read runner reads is one the read runner declares.
  for (const file of ["pr-unblock.yml", "work-resolve-issue.yml"]) {
    const { jobs } = workflow(file);
    const callers = Object.entries(jobs).filter(([, job]) => job.uses === READ_RUNNER).map(([id]) => id);
    for (const [, name] of JSON.stringify(jobs).matchAll(new RegExp(`needs\\.(?:${callers.join("|")})\\.outputs\\.([\\w-]+)`, "g"))) {
      assert.ok(Object.hasOwn(outputs, name), `${file} reads ${name}`);
    }
  }
});

test("pr-run-activity-read.yml: the report needs the scan job, and a failed scan fails the check after a green run job", () => {
  const { report } = workflow("pr-run-activity-read.yml").jobs;
  assert.deepEqual(report.needs, ["broker-check", "run", "scan"]);
  const post = report.steps.find((s) => s.name === "Post the check run");
  const result = (broker, run, scan) =>
    evaluate(post.with["run-result"], { "steps.head.outputs.forged": "false", "steps.head.outputs.not-run-reason": "", "needs.broker-check.result": broker, "needs.run.result": run, "needs.scan.result": scan });
  assert.equal(result("success", "success", "success"), "success");
  assert.equal(result("success", "success", "failure"), "failure", "a credential, a withheld or an oversize payload");
  assert.equal(result("success", "failure", "success"), "failure");
  assert.equal(result("success", "cancelled", "skipped"), "cancelled");
  assert.equal(result("failure", "skipped", "skipped"), "failure");
  assert.equal(result("success", "skipped", "skipped"), "skipped");
});

test("leak scan: a fresh shallow checkout of the head, as the scan job makes, still applies and scans the patch", async (t) => {
  const shallow = (work, root) => {
    const dir = join(root, "fresh");
    const cloned = spawnSync("git", ["clone", "-q", "--depth", "1", `file://${work}`, dir], { encoding: "utf8" });
    assert.equal(cloned.status, 0, cloned.stderr);
    assert.equal(spawnSync("git", ["rev-parse", "--is-shallow-repository"], { cwd: dir, encoding: "utf8" }).stdout.trim(), "true");
    return dir;
  };
  const hit = await scanWith(t, ({ work }) => writeFileSync(join(work, "tracked.txt"), KEY_BLOB), undefined, { afterCollect: restore, headRepo: shallow });
  assert.equal(hit.failed, "leak-scan: Anthropic key; nothing is uploaded or summarized\nrotate this credential");
  const clean = await scanWith(t, ({ work }) => writeFileSync(join(work, "tracked.txt"), "changed\n"), undefined, { headRepo: shallow });
  assert.deepEqual({ clean: clean.clean, failed: clean.failed }, { clean: "true", failed: null });
});

test("scan job: every gate, skip and launcher class value the runner sets passes the decode step's closed sets", async (t) => {
  const good = runOutputsAfterCarry(t, {});
  const schema = JSON.parse(read("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json"));
  const gateReasons = Object.keys(JSON.parse(read("../report-check-run/gate-skip-reasons.json")));
  // run-claude-cli's failure classes, the keys of SUMMARY_NOTES in lane.cjs at
  // the pinned d02b8697. cant-fail-ok: an external contract's value list.
  const laneClasses = ["credit-stop", "rate-limit", "auth", "overloaded", "max-turns", "timeout", "other"];
  const cases = [
    ...schema.$defs["skip-reason"].enum.map((value) => ["skip-reason", value]),
    ...gateReasons.flatMap((value) => [["kill-reason", value], ["trigger-reason", value], ["gate-reason", value]]),
    ...laneClasses.map((value) => ["lane-class", value]),
  ];
  assert.ok(cases.length > 20);
  for (const [name, value] of cases) {
    const { failed } = await decode(t, decodeEnv({ ...good, [name]: value }));
    assert.equal(failed, null, `${name}=${value}`);
  }
});

test("scan job: patch-sha256 is the SHA-256 of exactly the bytes opened, scanned and uploaded", async (t) => {
  const { createHash } = await import("node:crypto");
  const steps = scanSteps();
  const step = (id) => steps.find((s) => s.id === id);
  // The wiring: the scan reads the check step's dir, which is the open step's
  // directory; the patch upload reads the scan's copy; the job output is the scan's hash.
  assert.equal(step("leak-scan").env.PATCH_FILE, "${{ steps.decode.outputs.dir }}/patch.diff");
  assert.equal(step("leak-scan").env.REPLY_DIR, "${{ steps.decode.outputs.dir }}");
  assert.match(step("decode").with.script, /core\.setOutput\('dir', env\.OPEN_DIR\)/);
  assert.equal(step("patch-upload").with.path, "${{ steps.leak-scan.outputs.dir }}/patch.diff");
  assert.equal(workflow("pr-run-activity-read.yml").jobs.scan.outputs["patch-sha256"], "${{ steps.patch-upload.outcome == 'success' && steps.leak-scan.outputs.patch-sha256 || '' }}");
  // The run: the collected patch, sealed by the run job, opened by the scan job, then scanned.
  let opened = null;
  const viaCarrier = (temp) => {
    const files = { "patch/patch.diff": readFileSync(join(temp, "patch", "patch.diff")), "skill-reply/reply.txt": readFileSync(join(temp, "skill-reply", "reply.txt")) };
    const open = openStep(t, runOutputsAfterCarry(t, files));
    assert.equal(open.status, 0, open.log);
    opened = open.dir;
    return { reply: open.dir, patch: join(open.dir, "patch.diff") };
  };
  const clean = await scanWith(t, ({ work }) => writeFileSync(join(work, "tracked.txt"), "changed\n"), undefined, { source: viaCarrier });
  assert.equal(clean.clean, "true", clean.failed);
  const scannedFrom = readFileSync(join(opened, "patch.diff"));
  const uploaded = readFileSync(join(clean.outputs.dir, "patch.diff"));
  assert.deepEqual(uploaded, scannedFrom, "the upload holds the opened bytes");
  assert.equal(clean.outputs["patch-sha256"], createHash("sha256").update(uploaded).digest("hex"));
  // The scan reads those same bytes: a key in them, through the carrier, blocks.
  const hit = await scanWith(t, ({ work }) => writeFileSync(join(work, "tracked.txt"), `${KEY}\n`), undefined, { source: viaCarrier });
  assert.equal(hit.clean, "false");
  assert.match(hit.failed, /^leak-scan: Anthropic key; nothing is uploaded or summarized/);
  for (const dir of [clean.outputs.dir, hit.outputs.dir]) if (dir) rmSync(dir, { recursive: true, force: true });
});

// --- the report job: where the check is posted ---

const reportSteps = () => workflow("pr-run-activity-read.yml").jobs.report.steps;
const TRUSTED = "a".repeat(40);
const OTHER = "f".repeat(40);

// Runs the head step with the given env; returns its exit and outputs.
function chooseHead(t, env) {
  const root = mkdtempSync(join(tmpdir(), "report-head-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const output = join(root, "github-output");
  writeFileSync(output, "");
  const step = reportSteps().find((s) => s.id === "head");
  const result = runStep(step, root, { RUN_HEAD: "", CALLER_HEAD: "", EVENT_HEAD: "", API_HEAD: "", PR_MISMATCH: "", TRUSTED_SKIP: "false", ...env, GITHUB_OUTPUT: output });
  return { status: result.status, log: result.stdout, outputs: outputLines(output) };
}

// The post step's inputs as the runner evaluates them, then decide().
function posted(head, { verdictHead = head.outputs.sha, runResult = "success", gateReason = "", event = "workflow_dispatch" } = {}) {
  const post = reportSteps().find((s) => s.name === "Post the check run");
  const context = {
    "steps.head.outputs.post": head.outputs.post ?? "",
    "steps.head.outputs.sha": head.outputs.sha ?? "",
    "steps.head.outputs.forged": head.outputs.forged ?? "",
    "steps.head.outputs.not-run-reason": head.outputs["not-run-reason"] ?? "",
    "github.event_name": event,
    "needs.broker-check.result": "success",
    "needs.run.result": runResult,
    "needs.scan.result": "success",
    "needs.run.outputs.gate-reason": gateReason,
  };
  if (!evaluate(post.if.replaceAll("always()", "true"), context)) return null;
  const verdict = {
    version: 1, lane: "pr-unblock", activity: "fix-ci", "run-url": "u", "head-sha": verdictHead,
    gates: { "kill-switch": { proceed: "true", reason: "" }, trigger: { proceed: "true", reason: "" } },
    config: "valid", "skip-reason": null, outcome: "success", "dirty-tree": null, patch: "written",
  };
  const decision = decide(verdict, {
    lane: "pr-unblock",
    activity: "fix-ci",
    runResult: evaluate(post.with["run-result"], context),
    notRunReason: evaluate(post.with["not-run-reason"], context),
    actOutcome: "success",
    signedCommits: null,
    gateReason: evaluate(post.with["gate-reason"], context),
    headSha: evaluate(post.with["head-sha"], context),
    headShaFallback: "",
    prHeadSha: TRUSTED,
    gateSkipReasons: {},
    skipReasons: JSON.parse(read("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json")).$defs["skip-reason"].enum,
  });
  return decision.report;
}

test("report job: a run head that is the gated head posts normally on it", (t) => {
  for (const env of [{ CALLER_HEAD: TRUSTED }, { CALLER_HEAD: TRUSTED, API_HEAD: OTHER }, { EVENT_HEAD: TRUSTED }]) {
    const head = chooseHead(t, { RUN_HEAD: TRUSTED, ...env });
    assert.equal(head.status, 0, head.log);
    assert.deepEqual(head.outputs, { post: "true", sha: TRUSTED, forged: "false" }, JSON.stringify(env));
    const report = posted(head);
    assert.deepEqual([report.head_sha, report.conclusion], [TRUSTED, "success"], JSON.stringify(env));
  }
});

// #8945: the PR head read at report time may have moved during the run, so
// with no caller or event head nothing was gated and no run head can match.
test("report job: with no caller or event head, any run head is forged, and the PR head read is only where failure is posted", (t) => {
  for (const runHead of [TRUSTED, OTHER]) {
    const head = chooseHead(t, { RUN_HEAD: runHead, API_HEAD: TRUSTED });
    assert.equal(head.status, 0, head.log);
    assert.deepEqual(head.outputs, { post: "true", sha: TRUSTED, forged: "true" }, runHead);
    assert.match(head.log, /^::error::the run job's head-sha or pr-number is not the gated PR's/m);
    // Even a verdict that agrees with the run's head.
    const report = posted(head, { verdictHead: runHead });
    assert.deepEqual([report.head_sha, report.conclusion], [TRUSTED, "failure"], runHead);
  }
});

test("report job: a run head equal to a PR head that moved mid-run, never gated, posts failure on the gated head, not success there", (t) => {
  const gated = TRUSTED;
  const moved = "b".repeat(40);
  for (const env of [{ CALLER_HEAD: gated, API_HEAD: moved }, { EVENT_HEAD: gated, API_HEAD: moved }]) {
    const head = chooseHead(t, { RUN_HEAD: moved, ...env });
    assert.deepEqual(head.outputs, { post: "true", sha: gated, forged: "true" }, JSON.stringify(env));
    const report = posted(head, { verdictHead: moved });
    assert.deepEqual([report.head_sha, report.conclusion], [gated, "failure"], JSON.stringify(env));
  }
  // The signed-commit check never runs from the moved head either.
  const signed = reportSteps().find((s) => s.id === "signed");
  assert.match(signed.if, /steps\.head\.outputs\.forged == 'false'/);
  assert.equal(signed.with["since-sha"], "${{ steps.head.outputs.sha }}");
});

test("report job: the signed-commit check runs only when the lane can commit and a head SHA was gated", () => {
  const signed = reportSteps().find((s) => s.id === "signed");
  const ctx = { "needs.run.outputs.can-commit": "true", "steps.pr-head.outputs.number": "7", "steps.head.outputs.sha": TRUSTED, "steps.head.outputs.forged": "false" };
  const runs = (over) => Boolean(evaluate(signed.if.replaceAll("always()", "true"), { ...ctx, ...over }));
  assert.equal(runs({}), true);
  // A read activity cannot commit, and a run that gated no head leaves can-commit empty.
  for (const canCommit of ["false", ""]) assert.equal(runs({ "needs.run.outputs.can-commit": canCommit }), false, `can-commit '${canCommit}'`);
  assert.equal(runs({ "steps.head.outputs.sha": "" }), false);
  assert.equal(runs({ "steps.pr-head.outputs.number": "" }), false);
  assert.equal(runs({ "steps.head.outputs.forged": "true" }), false);
});

test("report job: an empty run head after the kill switch or a broker refusal posts nothing, so the owner's switch is never a merge blocker", (t) => {
  const steps = reportSteps();
  // The broker-check job's allow alone, which already holds its kill switch
  // read: never a run job output, and never a second read a switch flipped
  // mid-run could change.
  assert.equal(steps.find((s) => s.id === "kill"), undefined);
  const head = steps.find((s) => s.id === "head");
  assert.equal(head.env.TRUSTED_SKIP, "${{ needs.broker-check.outputs.allowed != 'true' }}");
  for (const allowed of ["false", ""]) {
    const trusted = evaluate(head.env.TRUSTED_SKIP, { "needs.broker-check.outputs.allowed": allowed });
    assert.equal(String(trusted), "true", allowed);
    const chosen = chooseHead(t, { RUN_HEAD: "", CALLER_HEAD: TRUSTED, TRUSTED_SKIP: String(trusted) });
    assert.deepEqual(chosen.outputs, { post: "true", sha: "", forged: "false" });
    // Off pull_request, nothing is posted, so no failing check can block a merge.
    assert.equal(posted(chosen), null);
  }
  assert.equal(String(evaluate(head.env.TRUSTED_SKIP, { "needs.broker-check.outputs.allowed": "true" })), "false");
});

test("report job: an empty run head with no trusted skip posts neutral not-assessed on the gated head, never failure or success", (t) => {
  for (const env of [{ CALLER_HEAD: TRUSTED, API_HEAD: OTHER }, { EVENT_HEAD: TRUSTED }]) {
    const head = chooseHead(t, { RUN_HEAD: "", ...env });
    assert.deepEqual(head.outputs, { post: "true", sha: TRUSTED, forged: "false", "not-run-reason": "not-assessed" }, JSON.stringify(env));
    // Whatever verdict, gate skip or outcome the run claims.
    for (const options of [{ verdictHead: null }, { verdictHead: null, gateReason: "untrusted-actor" }, { verdictHead: TRUSTED, runResult: "success" }]) {
      const report = posted(head, options);
      assert.deepEqual([report.head_sha, report.conclusion, report.output.title], [TRUSTED, "neutral", "Skipped: not-assessed"], JSON.stringify(options));
    }
  }
  // No gated head: nothing.
  assert.deepEqual(chooseHead(t, { RUN_HEAD: "", API_HEAD: TRUSTED }).outputs, { post: "true", sha: "", forged: "false" });
  // A handoff never reaches the report job: the fallback call posts that check.
  assert.match(workflow("pr-run-activity-read.yml").jobs.report.if, /needs\.run\.outputs\.handed-off != 'true'/);
});

test("report job: a forged run head-sha naming another commit posts failure on the trusted head, never on the forged SHA", (t) => {
  const head = chooseHead(t, { RUN_HEAD: OTHER, CALLER_HEAD: TRUSTED, API_HEAD: TRUSTED });
  assert.equal(head.status, 0);
  assert.deepEqual(head.outputs, { post: "true", sha: TRUSTED, forged: "true" });
  assert.match(head.log, /^::error::the run job's head-sha or pr-number is not the gated PR's/m);
  // A verdict the hostile run made to agree with its own head, a forged gate skip
  // or success: still failure, on the trusted head.
  for (const options of [{ verdictHead: OTHER }, { verdictHead: OTHER, gateReason: "untrusted-actor" }, { verdictHead: TRUSTED }]) {
    const report = posted(head, options);
    assert.deepEqual([report.head_sha, report.conclusion], [TRUSTED, "failure"], JSON.stringify(options));
  }
  // A pr-number naming another PR fails the same way, even with a matching head.
  const pr = chooseHead(t, { RUN_HEAD: TRUSTED, CALLER_HEAD: TRUSTED, PR_MISMATCH: "true" });
  assert.deepEqual(pr.outputs, { post: "true", sha: TRUSTED, forged: "true" });
  assert.deepEqual([posted(pr).head_sha, posted(pr).conclusion], [TRUSTED, "failure"]);
});

test("report job: with no trusted head, nothing is posted and the job fails", (t) => {
  for (const env of [{}, { CALLER_HEAD: "x", EVENT_HEAD: "A".repeat(40), API_HEAD: "a".repeat(39) }]) {
    const head = chooseHead(t, { RUN_HEAD: OTHER, ...env });
    assert.equal(head.status, 1, JSON.stringify(env));
    assert.deepEqual(head.outputs, { post: "false" });
    assert.equal(posted(head), null, "the post step does not run");
  }
  // An empty run head (a run that stopped before its gate) keeps the old rule:
  // off pull_request nothing is posted; on pull_request the event's head.
  const empty = chooseHead(t, {});
  assert.deepEqual(empty.outputs, { post: "true", sha: "", forged: "false" });
  assert.equal(posted(empty), null);
  const post = reportSteps().find((s) => s.name === "Post the check run");
  assert.equal(post.with["head-sha-fallback"], "${{ github.event.pull_request.head.sha || github.sha }}");
});

test("report job: the PR number comes from the caller or the event, a run job pr-number naming another PR fails closed, and the posting code comes from the default branch tip", (t) => {
  const steps = reportSteps();
  const read = steps.find((s) => s.id === "pr-head");
  assert.equal(read.env.PR_NUMBER, "${{ inputs.pr-number || github.event.pull_request.number }}");
  assert.equal(read.env.RUN_PR_NUMBER, "${{ needs.run.outputs.pr-number }}");
  const signed = steps.find((s) => s.id === "signed");
  assert.equal(signed.with["pr-number"], "${{ steps.pr-head.outputs.number }}");
  // Stub gh: the PR's head.
  const root = mkdtempSync(join(tmpdir(), "report-pr-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, "bin"));
  writeFileSync(join(root, "bin", "gh"), `#!/bin/sh\necho ${TRUSTED}\n`, { mode: 0o755 });
  const run = (env) => {
    const output = join(root, "out");
    writeFileSync(output, "");
    const result = spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", read.run], { cwd: root, env: { PATH: `${join(root, "bin")}:/usr/bin:/bin`, GITHUB_REPOSITORY: "o/r", GH_TOKEN: "x", GITHUB_OUTPUT: output, ...env }, encoding: "utf8" });
    return { status: result.status, outputs: outputLines(output), log: result.stdout };
  };
  assert.deepEqual(run({ PR_NUMBER: "5", RUN_PR_NUMBER: "5" }).outputs, { sha: TRUSTED, number: "5" });
  assert.deepEqual(run({ PR_NUMBER: "5", RUN_PR_NUMBER: "" }).outputs, { sha: TRUSTED, number: "5" });
  const other = run({ PR_NUMBER: "5", RUN_PR_NUMBER: "6" });
  assert.deepEqual(other.outputs, { sha: TRUSTED, number: "5", "pr-mismatch": "true" });
  assert.match(other.log, /^::error::the run job's pr-number is not the PR the caller or event names/m);
  // The posting code: the default branch tip, never a run job output.
  const checkout = steps.find((s) => String(s.uses ?? "").startsWith("actions/checkout@"));
  assert.equal(checkout.with.ref, "${{ github.event.repository.default_branch }}");
  assert.equal(steps.filter((s) => String(s.uses ?? "").startsWith("actions/checkout@")).length, 1);
  assert.doesNotMatch(JSON.stringify(steps), /base-sha/, "no step reads the run job's base-sha");
  assert.equal(steps.findIndex((s) => s.name === "Assert the default branch is set"), 0);
  // pr-unblock and pr-refine pass the head a job that ran no head code read
  // to both calls of each activity.
  const { jobs } = workflow("pr-unblock.yml");
  for (const id of ["fix-ci", "fix-ci-subscription"]) assert.equal(jobs[id].with["head-sha"], "${{ needs.fix-ci-context.outputs.head-sha }}", id);
  const refine = workflow("pr-refine.yml").jobs;
  for (const id of ["fix-docs", "fix-docs-subscription"]) assert.equal(refine[id].with["head-sha"], "${{ needs.fix-docs-head.outputs.head-sha }}", id);
});

test("scan job: an empty default branch fails closed before the opener is checked out", (t) => {
  const steps = scanSteps();
  const assertStep = steps.find((s) => s.name === "Assert the default branch is set");
  const base = steps.find((s) => s.id === "base");
  assert.equal(assertStep.name, "Assert the default branch is set");
  assert.equal(assertStep.if, base.if, "runs whenever the checkout would");
  assert.equal(assertStep.env.DEFAULT_BRANCH, "${{ github.event.repository.default_branch }}");
  const root = mkdtempSync(join(tmpdir(), "scan-branch-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const empty = runStep(assertStep, root, { DEFAULT_BRANCH: "" });
  assert.equal(empty.status, 1);
  assert.match(empty.stdout, /^::error::the event names no default branch/m);
  assert.equal(runStep(assertStep, root, { DEFAULT_BRANCH: "main" }).status, 0);
});

// --- leak scan: UTF-16LE and split-line passes ---

// A stateless installation token, ghs_<app id>_<JWT>, about 520 characters,
// built at run time so no credential-shaped literal sits in the file.
const B64URL = (n) => "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_".repeat(Math.ceil(n / 38)).slice(0, n);
const GHS = ["ghs", `1234567_eyJ${B64URL(100)}.eyJ${B64URL(300)}.${B64URL(108)}`].join("_");
const SK = KEY;
const utf16 = (text) => Buffer.from(text, "utf16le");
// Split so neither line holds the prefix and enough of the token to match.
const split = (token) => `the token is ${token.slice(0, 2)}\n${token.slice(2)} and that is all\n`;
// The main gate as it was before #8857 added the stateless ghs_ form.
const MAIN_GATE = read("../../../lib/publish-gate.mjs");
const PRE_8857_GATE = (() => {
  const old = MAIN_GATE.replace("ghs_[A-Za-z0-9._-]{36,}|gh[pousr]_", "gh[pousr]_");
  assert.notEqual(old, MAIN_GATE, "the main gate carries #8857's ghs_ form");
  return old;
})();
const inReply = (bytes) => ({ temp }) => writeFileSync(join(temp, "skill-reply", "reply.txt"), bytes);
const inPatch = (bytes) => ({ work }) => writeFileSync(join(work, "tracked.txt"), bytes);

test("leak scan: a UTF-16LE or line-split credential blocks in the reply and in the patch, with its label and the rotation line", async (t) => {
  assert.ok(GHS.length > 500 && GHS.length < 540, String(GHS.length));
  const cases = [
    // #8857's ghs_ form needs a gate that has it: main's.
    ["GitHub token", GHS, MAIN_GATE],
    // The same shapes on the gate before #8857, with an Anthropic key.
    ["Anthropic key", SK, PRE_8857_GATE],
    ["Anthropic key", SK, MAIN_GATE],
  ];
  for (const [label, token, gate] of cases) {
    const shapes = { "UTF-16LE": utf16(`done: ${token}\r\n`), "split across two lines": Buffer.from(split(token)) };
    for (const [shape, bytes] of Object.entries(shapes)) {
      for (const [where, plant] of [["reply", inReply(bytes)], ["patch", inPatch(bytes)]]) {
        const name = `${label} ${shape} in the ${where}${gate === PRE_8857_GATE ? " (pre-#8857 gate)" : ""}`;
        const { clean, failed, outputs } = await scanWith(t, plant, gate);
        assert.equal(clean, "false", name);
        assert.equal(failed, `leak-scan: ${label}; nothing is uploaded or summarized\nrotate this credential`, name);
        if (outputs.dir) rmSync(outputs.dir, { recursive: true, force: true });
      }
    }
  }
  // Without #8857's form, the stateless token itself passes: the passes add no format.
  const old = await scanWith(t, inReply(utf16(`done: ${GHS}\n`)), PRE_8857_GATE);
  assert.equal(old.clean, "true", old.failed);
  if (old.outputs.dir) rmSync(old.outputs.dir, { recursive: true, force: true });
});

test("leak scan: clean multi-line and clean UTF-16LE text stay clean in the reply and the patch", async (t) => {
  const prose = "The fix renames the helper.\nIt keeps the old name as an alias\nsk-\nfor one release, then drops it.\n";
  for (const bytes of [Buffer.from(prose), utf16(prose), utf16("ghs_ is the installation token prefix.\n")]) {
    for (const plant of [inReply(bytes), inPatch(bytes)]) {
      for (const gate of [MAIN_GATE, PRE_8857_GATE]) {
        const { clean, failed, outputs } = await scanWith(t, plant, gate);
        assert.deepEqual({ clean, failed }, { clean: "true", failed: null });
        if (outputs.dir) rmSync(outputs.dir, { recursive: true, force: true });
      }
    }
  }
});

test("leak scan: the split-line pass joins patch hunk lines without their prefixes, and counts only a match across the join", async () => {
  const script = scanSteps().find((s) => s.id === "leak-scan").with.script;
  const body = script.slice(script.indexOf("const straddles"), script.indexOf("// Each source has a kind"));
  const { findSecret, SECRET_PATTERNS } = await import(new URL("../../../lib/publish-gate.mjs", import.meta.url));
  const WARN_ONLY = "password or secret assignment";
  const blocking = SECRET_PATTERNS.filter(([label]) => label !== WARN_ONLY);
  const deeper = new Function("blocking", "findSecret", "WARN_ONLY", `${body}; return deeper;`)(blocking, findSecret, WARN_ONLY);
  const hunk = `diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1 +1,2 @@\n+the token is ${GHS.slice(0, 2)}\n+${GHS.slice(2)}\n`;
  assert.equal(deeper(hunk, true), "GitHub token", "an added-hunk split joins without the + prefixes");
  assert.equal(deeper(hunk, false), null, "kept, the + prefix breaks the token");
  assert.equal(deeper(` ${GHS.slice(0, 2)}\n+${GHS.slice(2)}\n`, true), "GitHub token", "a context line joins an added line");
  // A match wholly inside one line is the per-line scan's, never this pass's.
  assert.equal(deeper(`${GHS}\nnext line\n`, false), null);
  assert.equal(deeper(utf16(`x ${GHS}`).toString("latin1"), false), "GitHub token");
});

test("report job: fix-ci-dispatch reads the neutral not-assessed post as the head's run, and no post as none, so neither counts toward the restart cap", () => {
  const head = TRUSTED;
  const node = (runs) => ({
    number: 9001,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: head,
    author: { databaseId: 7 },
    labels: { nodes: [] },
    commits: {
      nodes: [
        {
          commit: {
            oid: head,
            statusCheckRollup: {
              contexts: {
                nodes: [{ name: "ci-status", status: "COMPLETED", conclusion: "FAILURE" }, ...runs]
                  .map((run) => ({ __typename: "CheckRun", checkSuite: { app: { databaseId: 15368 } }, ...run }))
                  .concat({ __typename: "StatusContext", context: "ci-lanes", state: "FAILURE", creator: { __typename: "Bot", login: "github-actions", databaseId: 41898282 } }),
                pageInfo: { hasNextPage: false },
              },
            },
          },
        },
      ],
    },
  });
  const options = { ...CI_FIX_DEFAULTS, appSenderId: 7, restarts: 1 };
  const neutral = { name: "pr-unblock / fix-ci", status: "COMPLETED", conclusion: "NEUTRAL", title: "Skipped: not-assessed" };
  assert.equal(skipReason(node([neutral]), options), "head already has a pr-unblock / fix-ci check run", "not re-dispatched on that head");
  assert.equal(skipReason(node([]), options), "", "after the kill switch, nothing posted: dispatchable again once it is off");
});

test("leak scan: the split-line pass leaves out the OpenAI pattern, so an sk- word ending a line stays clean, and a split Anthropic key still blocks", async (t) => {
  // The test-scan.test.sh:503-504 shape: an identifier that ends a line, then a word.
  const shape = 'run Write "$DEF_TMP/def.test.ts" stskip "" sk-def-control\nassert_contains "control: a /tmp copy records" "$(rec stskip sk-def-control)" sk-def-control\n';
  for (const plant of [inReply(Buffer.from(shape)), inPatch(Buffer.from(shape))]) {
    const { clean, failed, outputs } = await scanWith(t, plant);
    assert.deepEqual({ clean, failed }, { clean: "true", failed: null });
    if (outputs.dir) rmSync(outputs.dir, { recursive: true, force: true });
  }
  for (const plant of [inReply(Buffer.from(split(SK))), inPatch(Buffer.from(split(SK)))]) {
    const { failed, outputs } = await scanWith(t, plant);
    assert.equal(failed, "leak-scan: Anthropic key; nothing is uploaded or summarized\nrotate this credential");
    if (outputs.dir) rmSync(outputs.dir, { recursive: true, force: true });
  }
  // The OpenAI pattern stays in the per-line and UTF-16LE passes.
  const openai = ["sk", "proj", "x".repeat(30)].join("-");
  for (const bytes of [Buffer.from(`key ${openai}\n`), utf16(`key ${openai}\n`)]) {
    const { failed, outputs } = await scanWith(t, inReply(bytes));
    assert.equal(failed, "leak-scan: OpenAI key; nothing is uploaded or summarized\nrotate this credential");
    if (outputs.dir) rmSync(outputs.dir, { recursive: true, force: true });
  }
});

test("leak scan: the split-line pass leaves out the R2 key pair pattern, so adjacent md5 and sha256 lines stay clean, and a pair on one line still blocks", async (t) => {
  const checksums = `  md5: ${"a".repeat(32)}\n  sha256: ${"b".repeat(64)}\n`;
  for (const plant of [inReply(Buffer.from(checksums)), inPatch(Buffer.from(checksums))]) {
    const { clean, failed, outputs } = await scanWith(t, plant);
    assert.deepEqual({ clean, failed }, { clean: "true", failed: null });
    if (outputs.dir) rmSync(outputs.dir, { recursive: true, force: true });
  }
  const { failed, outputs } = await scanWith(t, inReply(Buffer.from(`${"a".repeat(32)} ${"b".repeat(64)}\n`)));
  assert.equal(failed, "leak-scan: R2 key pair; nothing is uploaded or summarized\nrotate this credential");
  if (outputs.dir) rmSync(outputs.dir, { recursive: true, force: true });
});


// --- address-feedback on run-claude-cli: a select job, two model calls, a push job, a reply job ---

// The outputs of a model call (the read runner) each address-feedback job may
// read: the push job the patch the scan job uploaded, the reply job the
// replies it uploaded. No job takes a gate, a head or a reply input from
// anything else a model call reports; the subscription call starts on
// address-feedback-handoff's read and reads none.
const MODEL_CALL_READS = {
  "apply-feedback-patch": ["feedback-attempt", "scan-patch-attempt", "scan-patch-sha256", "scan-patch-state", "scan-reply-attempt"],
  "publish-feedback": ["feedback-attempt", "feedback-sha256", "scan-patch-state"],
};

// One leg answers the round: the fallback call when it ran, else the first.
// Every model-call input is that leg's, so a forged leg cannot pair its
// replies with the other's patch, and an empty field never falls through.
test("pr-unblock.yml: the apply and reply jobs take every model-call input from one leg", () => {
  const { jobs } = workflow("pr-unblock.yml");
  const apply = jobs["apply-feedback-patch"];
  const publish = jobs["publish-feedback"].with;
  const OUT = ["scan-patch-state", "scan-patch-sha256", "scan-patch-attempt", "scan-reply-attempt", "feedback-attempt", "feedback-sha256"];
  const legs = (subResult, sub, first) => {
    const values = { "needs.address-feedback-subscription.result": subResult };
    for (const output of OUT) {
      values[`needs.address-feedback-subscription.outputs.${output}`] = sub[output] ?? "";
      values[`needs.address-feedback.outputs.${output}`] = first[output] ?? "";
    }
    return values;
  };
  const full = (leg) => Object.fromEntries(OUT.map((o) => [o, `${leg}:${o}`]).concat([["scan-patch-state", "written"]]));
  const inputs = {
    "patch-state": [apply.with, "scan-patch-state"],
    "patch-sha256": [apply.with, "scan-patch-sha256"],
    "patch-attempt": [apply.with, "scan-patch-attempt"],
    "reply-attempt": [apply.with, "scan-reply-attempt"],
    "review-replies-attempt": [publish, "feedback-attempt"],
    "review-replies-sha256": [publish, "feedback-sha256"],
    "review-patch-state": [publish, "scan-patch-state"],
  };
  for (const [subResult, from] of [["skipped", "first"], ["success", "sub"], ["failure", "sub"]]) {
    const context = legs(subResult, from === "sub" ? full("sub") : {}, from === "first" ? full("first") : {});
    for (const [input, [block, output]] of Object.entries(inputs)) {
      const want = output === "scan-patch-state" ? "written" : `${from}:${output}`;
      assert.equal(evaluate(block[input], context), want, `${input} when the fallback call is ${subResult}`);
    }
    assert.equal(evaluate(apply.if, context), true, `a written patch with replies when the fallback call is ${subResult}`);
  }
  // The fallback call ran and left a field empty: nothing comes from the first call.
  const mixed = legs("success", { "feedback-attempt": "2", "feedback-sha256": "s" }, full("first"));
  for (const [input, [block]] of Object.entries(inputs)) {
    if (!["review-replies-attempt", "review-replies-sha256"].includes(input)) {
      assert.equal(evaluate(block[input], mixed), "", `${input} never falls through to the first call`);
    }
  }
  assert.equal(evaluate(apply.if, mixed), false, "the first call's patch never pairs with the fallback call's replies");
  // No replies from the chosen leg, no push.
  for (const subResult of ["skipped", "success"]) {
    const leg = { ...full(subResult === "skipped" ? "first" : "sub"), "feedback-attempt": "" };
    const context = legs(subResult, subResult === "skipped" ? {} : leg, subResult === "skipped" ? leg : {});
    assert.equal(evaluate(apply.if, context), false, `a written patch with no replies when the fallback call is ${subResult}`);
  }
  // The scan job alone sets the replies' SHA-256, from the bytes it uploads.
  const read = workflow("pr-run-activity-read.yml");
  assert.equal(read.on.workflow_call.outputs["feedback-sha256"].value, "${{ jobs.scan.outputs.feedback-sha256 }}");
  assert.equal(read.jobs.scan.outputs["feedback-sha256"], "${{ steps.feedback-upload.outcome == 'success' && steps.leak-scan.outputs.replies-sha256 || '' }}");
  assert.equal(read.jobs.run.outputs["feedback-sha256"], undefined);
  const scan = read.jobs.scan.steps.find((step) => step.id === "leak-scan").with.script;
  assert.match(scan, /if \(replies\) core\.setOutput\('replies-sha256', crypto\.createHash\('sha256'\)\.update\(replies\)\.digest\('hex'\)\)/);
  // The write runner hands both to the reply script.
  const write = workflow("pr-run-activity-write.yml");
  const script = write.jobs.run.steps.find((step) => step.id === "act-script");
  assert.equal(script.env.REPLIES_SHA256, "${{ inputs.review-replies-sha256 }}");
  assert.equal(script.env.REVIEW_PATCH_STATE, "${{ inputs.review-replies && inputs.review-patch-state || '' }}");
});

// --- review-dependency on run-claude-cli: a select job, two model calls, a push job, a verdict job ---

// The outputs of a model call each review-dependency job may read: the push
// job the patch, its report and the verdict the scan job uploaded; the
// verdict job the verdict, the patch state and the scan's refusal. No job
// takes a gate or a head from a model call; the subscription call starts on
// review-dependency-handoff's read and reads none.
const DEPENDENCY_CALL_READS = {
  "apply-dependency-patch": ["dependency-attempt", "dependency-sha256", "dependency-verdict", "scan-patch-attempt", "scan-patch-sha256", "scan-patch-state", "scan-reply-attempt"],
  "apply-dependency-verdict": ["dependency-attempt", "dependency-sha256", "scan-patch-state"],
};

test("pr-unblock.yml: no job takes a gate, head or verdict input from a review-dependency model call but the outputs it needs", () => {
  const { jobs } = workflow("pr-unblock.yml");
  for (const [id, job] of Object.entries(jobs)) {
    const read = [...JSON.stringify(job).matchAll(/needs\.review-dependency(?:-subscription)?\.outputs\.([\w-]+)/g)].map((m) => m[1]);
    assert.deepEqual([...new Set(read)].sort(), DEPENDENCY_CALL_READS[id] ?? [], id);
  }
  const SELECT = (output) => `\${{ needs.review-dependency-select.outputs.${output} }}`;
  for (const id of ["review-dependency", "review-dependency-subscription"]) {
    assert.equal(jobs[id].with["head-sha"], SELECT("head-sha"), id);
    assert.equal(jobs[id].with["dependency-context-attempt"], SELECT("context-attempt"), id);
    assert.equal(jobs[id].with["dependency-context-sha256"], SELECT("context-sha256"), id);
  }
  const apply = jobs["apply-dependency-patch"].with;
  assert.equal(apply["patch-head-sha"], SELECT("head-sha"));
  assert.equal(apply["patch-prepare"], "dependency-review");
  const verdict = jobs["apply-dependency-verdict"];
  assert.equal(verdict.with["dependency-verdict"], true);
  assert.equal(verdict.with["dependency-context-attempt"], SELECT("context-attempt"));
  assert.equal(verdict.with["dependency-run-sha256"], SELECT("run-sha256"));
  assert.equal(verdict.with["dependency-head-sha"], SELECT("head-sha"));
  assert.equal(verdict.with["expected-upstream-head"], undefined, "the dispatcher run vouches for the PR; the head the push moved is checked by the script");
  // The verdict job counts every round the select job proceeded on, whatever a model call reports.
  assert.deepEqual(verdict.needs, ["review-dependency-select", "review-dependency", "review-dependency-subscription", "apply-dependency-patch"]);
  for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(verdict.if, { "needs.review-dependency-select.outputs.proceed": proceed }), runs, JSON.stringify(proceed));
  }
  // The read runner's dependency and refusal outputs come from its scan job alone.
  const read = workflow("pr-run-activity-read.yml");
  for (const [output, value] of [
    ["dependency-attempt", "dependency-attempt"],
    ["dependency-sha256", "dependency-sha256"],
    ["dependency-verdict", "dependency-verdict"],
  ]) {
    assert.equal(read.on.workflow_call.outputs[output].value, `\${{ jobs.scan.outputs.${value} }}`, output);
    assert.equal(read.jobs.run.outputs[output], undefined, output);
  }
  assert.equal(read.jobs.run.outputs["scan-refused"], undefined);
  assert.equal(read.jobs.scan.outputs["dependency-sha256"], "${{ steps.dependency-upload.outcome == 'success' && steps.leak-scan.outputs.verdict-sha256 || '' }}");
  assert.equal(read.jobs.scan.outputs["dependency-verdict"], "${{ steps.dependency-upload.outcome == 'success' && steps.leak-scan.outputs.dependency-verdict || '' }}");
  // report-escalation reads the select job's escalation, never a model call's.
  const escalation = jobs["report-escalation"];
  assert.ok(escalation.needs.includes("review-dependency-select") && escalation.needs.includes("apply-dependency-verdict"));
  assert.match(escalation.with["escalation-reason"], /needs\.review-dependency-select\.outputs\.escalation-reason/);
});

// One leg answers the round: the fallback call when it ran, else the first;
// the push needs a written patch beside a fix verdict from that same leg, and
// an empty field never falls through to the other.
test("pr-unblock.yml: apply-dependency-patch and the verdict job take every model-call input from one leg", () => {
  const { jobs } = workflow("pr-unblock.yml");
  const apply = jobs["apply-dependency-patch"];
  const verdict = jobs["apply-dependency-verdict"].with;
  const OUT = ["scan-patch-state", "scan-patch-sha256", "scan-patch-attempt", "scan-reply-attempt", "dependency-attempt", "dependency-sha256", "dependency-verdict"];
  const legs = (subResult, sub, first) => {
    const values = { "needs.review-dependency-subscription.result": subResult };
    for (const output of OUT) {
      values[`needs.review-dependency-subscription.outputs.${output}`] = sub[output] ?? "";
      values[`needs.review-dependency.outputs.${output}`] = first[output] ?? "";
    }
    return values;
  };
  const full = (leg) => ({ ...Object.fromEntries(OUT.map((o) => [o, `${leg}:${o}`])), "scan-patch-state": "written", "dependency-verdict": "fix" });
  const inputs = {
    "patch-state": [apply.with, "scan-patch-state"],
    "patch-sha256": [apply.with, "scan-patch-sha256"],
    "patch-attempt": [apply.with, "scan-patch-attempt"],
    "reply-attempt": [apply.with, "scan-reply-attempt"],
    "patch-verdict-attempt": [apply.with, "dependency-attempt"],
    "patch-verdict-sha256": [apply.with, "dependency-sha256"],
    "dependency-run-attempt": [verdict, "dependency-attempt"],
    "dependency-verdict-sha256": [verdict, "dependency-sha256"],
    "dependency-patch-state": [verdict, "scan-patch-state"],
  };
  for (const [subResult, from] of [["skipped", "first"], ["success", "sub"], ["failure", "sub"]]) {
    const context = legs(subResult, from === "sub" ? full("sub") : {}, from === "first" ? full("first") : {});
    for (const [input, [block, output]] of Object.entries(inputs)) {
      const want = output === "scan-patch-state" ? "written" : `${from}:${output}`;
      assert.equal(evaluate(block[input], context), want, `${input} when the fallback call is ${subResult}`);
    }
    assert.equal(evaluate(apply.if, context), true, `a written patch beside a fix verdict when the fallback call is ${subResult}`);
  }
  // The fallback call ran and left its verdict empty: the first call's fix never pairs with it.
  const mixed = legs("success", { "scan-patch-state": "written" }, full("first"));
  assert.equal(evaluate(apply.if, mixed), false);
  for (const [input, [block]] of Object.entries(inputs)) {
    if (input !== "patch-state" && input !== "dependency-patch-state") assert.equal(evaluate(block[input], mixed), "", `${input} never falls through to the first call`);
  }
  // Any verdict but fix, or no patch, pushes nothing.
  for (const [state, value] of [["written", "merge"], ["written", "close"], ["written", "escalate"], ["written", ""], ["empty", "fix"], ["", "fix"]]) {
    const leg = { ...full("first"), "scan-patch-state": state, "dependency-verdict": value };
    assert.equal(evaluate(apply.if, legs("skipped", {}, leg)), false, `${state} patch beside a ${JSON.stringify(value)} verdict`);
  }
});

// A select that skips or escalates runs no model job: a neutral check on the
// head it read keeps dependency-dispatch.mjs from sending the head again, and
// countCheckRounds counts no round for it.
test("pr-unblock.yml: review-dependency is reported neutral when the select job does not proceed", async () => {
  const head = "d".repeat(40);
  const { jobs } = workflow("pr-unblock.yml");
  const notRun = jobs["review-dependency-not-run"];
  const context = (proceed, headSha, skip = "", activity = "review-dependency") => ({
    "inputs.activity": activity,
    "needs.review-dependency-select.outputs.proceed": proceed,
    "needs.review-dependency-select.outputs.head-sha": headSha,
    "needs.review-dependency-select.outputs.skip-reason": skip,
  });
  assert.deepEqual([notRun.needs].flat(), ["review-dependency-select"]);
  assert.deepEqual(notRun.permissions, { checks: "write", contents: "read" });
  for (const id of ["review-dependency", "apply-dependency-verdict"]) {
    assert.equal(evaluate(jobs[id].if, context("true", head)), true, id);
    assert.equal(evaluate(jobs[id].if, context("false", head)), false, id);
    assert.equal(evaluate(jobs[id].if, context("", "")), false, `${id} after a kill-switch stop`);
  }
  assert.equal(evaluate(notRun.if, context("true", head)), false);
  assert.equal(evaluate(notRun.if, context("false", head, "not-applicable")), true);
  assert.equal(evaluate(notRun.if, context("false", "")), false, "a stop before the head read names no head to post on");
  assert.equal(evaluate(notRun.if, context("false", head, "", "fix-ci")), false);
  for (const [skip, summary] of [
    ["not-applicable", "Skip reason: not-applicable"],
    ["superseded-sha", "Skip reason: superseded-sha"],
    ["", "Skip reason: awaiting-human"],
  ]) {
    const calls = await postNotRunChecks(notRun, context("false", head, skip));
    assert.deepEqual(
      calls.map((call) => [call.name, call.head_sha, call.conclusion, call.output.summary]),
      [["pr-unblock / review-dependency", head, "neutral", summary]],
      JSON.stringify(skip),
    );
  }
});

test("pr-unblock.yml: review-dependency-select reads the slot with the read runner's applied-by keys and uploads both files under its attempt", () => {
  const select = workflow("pr-unblock.yml").jobs["review-dependency-select"];
  assert.deepEqual(select.permissions, { contents: "read", "pull-requests": "read", checks: "read", issues: "read" });
  assert.equal(select.uses, undefined, "a base job, never a runner that checks out the head");
  const step = (id) => select.steps.find((s) => s.id === id);
  assert.equal(step("slot").with["applied-by-supported"], "patch dependency-verdict");
  assert.equal(step("slot").with.activity, "review-dependency");
  assert.match(step("select").run, /CONTEXT_RUN_FILE="\$DEPENDENCY_DIR\/context\.json"/);
  assert.equal(step("upload").with.name, "dependency-context-${{ github.run_attempt }}");
  assert.deepEqual(stepSecrets(select), []);
});

// The pr-feedback-dispatch.yml trust reaches the read gate only for a
// review-threads call, which alone passes the select job's feedback context,
// and a feedback context with any other prepare mode fails red.
test("pr-run-activity-read.yml: the gate admits a feedback dispatch only for a review-threads call", () => {
  const read = workflow("pr-run-activity-read.yml");
  const steps = read.jobs.run.steps;
  const gate = steps.find((step) => step.id === "gate").with;
  // evaluate() refuses a dotted path literal, so the expressions are matched whole.
  assert.equal(gate["run-dispatcher-workflow"], "${{ inputs.feedback-context-sha256 != '' && '.github/workflows/pr-feedback-dispatch.yml' || '' }}");
  assert.equal(
    gate["run-dispatcher-upstreams"],
    "${{ inputs.feedback-context-sha256 != '' && '.github/workflows/pr-review-hosted.yml .github/workflows/pr-review-security-hosted.yml' || '' }}",
  );
  const assertStep = steps.find((step) => step.name === "Assert a feedback context goes with review-threads");
  const config = steps.findIndex((step) => step.id === "config");
  assert.ok(steps.indexOf(assertStep) > config);
  const fails = (sha, prepare) =>
    evaluate(assertStep.if, { "steps.config.outcome": "success", "inputs.feedback-context-sha256": sha, "steps.config.outputs.prepare": prepare });
  assert.equal(fails("e".repeat(64), "ci-context"), true);
  assert.equal(fails("e".repeat(64), ""), true);
  assert.equal(fails("e".repeat(64), "review-threads"), false);
  assert.equal(fails("", "ci-context"), false);
  assert.match(assertStep.run, /exit 1/);
});

test("pr-unblock.yml: no job takes a gate, head or reply input from an address-feedback model call but the outputs it needs", () => {
  const { jobs } = workflow("pr-unblock.yml");
  for (const [id, job] of Object.entries(jobs)) {
    const read = [...JSON.stringify(job).matchAll(/needs\.address-feedback(?:-subscription)?\.outputs\.([\w-]+)/g)].map((m) => m[1]);
    assert.deepEqual([...new Set(read)].sort(), MODEL_CALL_READS[id] ?? [], id);
  }
  // Every head the address-feedback jobs pass or check against is the select job's.
  const SELECT_HEAD = "${{ needs.address-feedback-select.outputs.head-sha }}";
  for (const id of ["address-feedback", "address-feedback-subscription"]) {
    assert.equal(jobs[id].with["head-sha"], SELECT_HEAD, id);
    assert.equal(jobs[id].with["feedback-context-attempt"], "${{ needs.address-feedback-select.outputs.context-attempt }}", id);
    assert.equal(jobs[id].with["feedback-context-sha256"], "${{ needs.address-feedback-select.outputs.threads-sha256 }}", id);
  }
  const apply = jobs["apply-feedback-patch"].with;
  assert.equal(apply["patch-head-sha"], SELECT_HEAD);
  assert.equal(apply["patch-prepare"], "review-threads");
  assert.equal(apply["patch-threads-attempt"], "${{ needs.address-feedback-select.outputs.context-attempt }}");
  assert.equal(apply["patch-threads-sha256"], "${{ needs.address-feedback-select.outputs.threads-sha256 }}");
  assert.equal(apply["patch-fix-requested"], "${{ needs.address-feedback-select.outputs.fix-requested }}");
  const publish = jobs["publish-feedback"].with;
  assert.equal(publish["review-run-sha256"], "${{ needs.address-feedback-select.outputs.run-sha256 }}");
  assert.equal(publish["review-run-attempt"], "${{ needs.address-feedback-select.outputs.context-attempt }}");
  const upstream = (dispatcher) =>
    evaluate(publish["expected-upstream-head"], { "inputs.dispatcher-run-id": dispatcher, "needs.address-feedback-select.outputs.head-sha": "e".repeat(40) });
  assert.equal(upstream("39000000001"), "e".repeat(40));
  assert.equal(upstream(""), "", "a human dispatch passes none");
  // The read runner's feedback-attempt and scan-* outputs come from its scan job alone.
  const read = workflow("pr-run-activity-read.yml");
  assert.equal(read.on.workflow_call.outputs["feedback-attempt"].value, "${{ jobs.scan.outputs.feedback-attempt }}");
  for (const output of ["patch-state", "patch-sha256", "patch-attempt", "reply-attempt"]) {
    assert.equal(read.on.workflow_call.outputs[`scan-${output}`].value, `\${{ jobs.scan.outputs.${output} }}`, output);
  }
  assert.equal(read.jobs.run.outputs["feedback-attempt"], undefined);
  assert.equal(read.jobs.scan.outputs["feedback-attempt"], "${{ steps.feedback-upload.outcome == 'success' && github.run_attempt || '' }}");
  // report-escalation takes the select job's escalation and head, never a model call's.
  const escalation = jobs["report-escalation"];
  assert.ok(escalation.needs.includes("address-feedback-select"));
  assert.ok(!escalation.needs.includes("address-feedback") && !escalation.needs.includes("apply-feedback-patch"));
  const head = (dispatcher) =>
    evaluate(escalation.with["expected-upstream-head"], {
      "inputs.activity": "address-feedback",
      "inputs.dispatcher-run-id": dispatcher,
      "needs.address-feedback-select.outputs.head-sha": "e".repeat(40),
    });
  assert.equal(head("39000000001"), "e".repeat(40));
  assert.equal(head(""), "");
});

test("pr-unblock.yml: the select job runs only base code with a read-only token and uploads the context only on proceed", () => {
  const { jobs } = workflow("pr-unblock.yml");
  const select = jobs["address-feedback-select"];
  assert.equal(select.uses, undefined, "a script job, never a runner that runs a model");
  assert.deepEqual(select.permissions, { contents: "read", "pull-requests": "read", checks: "read" });
  assert.doesNotMatch(JSON.stringify(select), /secrets\./);
  for (const step of select.steps.filter((s) => String(s.uses ?? "").startsWith("actions/checkout@"))) {
    assert.equal(step.with.ref, "${{ github.event.repository.default_branch }}");
    assert.equal(step.with["persist-credentials"], false);
  }
  const slot = select.steps.find((s) => s.id === "slot");
  assert.deepEqual([slot.with.lane, slot.with.activity, slot.with["prepare-supported"], slot.with["applied-by-supported"]], ["pr-unblock", "address-feedback", "true", "patch feedback-replies"]);
  const starts = (activity, sender = "1") =>
    evaluate(select.if, {
      "inputs.pr-number": "7",
      "inputs.activity": activity,
      "format('{0}', github.event.sender.id)": sender,
      "vars.AUTOMATION_LANES_APP_SENDER_ID": "2",
    });
  assert.equal(starts("address-feedback"), true);
  assert.equal(starts("fix-ci"), false);
  assert.equal(starts("address-feedback", "2"), false, "the lanes App's own dispatch");
  const proceed = (upload, applies, decided) =>
    evaluate(select.outputs.proceed, { "steps.upload.outcome": upload, "steps.slot.outputs.applies": applies, "steps.select.outputs.proceed": decided });
  assert.equal(proceed("success", "true", "true"), "true");
  assert.equal(proceed("failure", "true", "true"), "", "a context that did not upload proceeds to nothing");
  assert.equal(proceed("skipped", "true", "false"), "false");
  assert.equal(proceed("skipped", "false", ""), "false", "a slot that does not apply");
  assert.equal(proceed("skipped", "", ""), "", "a kill-switch stop");
  const upload = select.steps.find((s) => s.id === "upload");
  assert.equal(upload.if, "steps.select.outputs.proceed == 'true'");
  assert.equal(upload.with.name, "feedback-context-${{ github.run_attempt }}");
});

test("pr-run-activity-read.yml: a pr-feedback-dispatch.yml dispatch passes the trigger gate on the same terms as the write runner's", () => {
  const gateOf = (file) => workflow(file).jobs.run.steps.find((s) => s.id === "gate").with;
  const read = gateOf("pr-run-activity-read.yml");
  const write = gateOf("pr-run-activity-write.yml");
  for (const input of ["dispatcher-run-id", "dispatcher-workflow", "dispatched-workflow"]) {
    assert.equal(read[input], write[input], input);
  }
  // The feedback dispatcher's two inputs are the write runner's, passed only
  // for a review-threads call (the next test).
  for (const input of ["run-dispatcher-workflow", "run-dispatcher-upstreams"]) {
    const value = String(write[input]).trim().split(/\s+/).join(" ");
    assert.equal(read[input], `\${{ inputs.feedback-context-sha256 != '' && '${value}' || '' }}`, input);
  }
  // The App id reaches the gate on a dispatched run and in issue mode only, as before for every other read run.
  const appId = (issue, dispatcher) =>
    evaluate(read["lanes-app-id"], { "inputs.issue-number": issue, "inputs.dispatcher-run-id": dispatcher, "vars.AUTOMATION_LANES_APP_SENDER_ID": "337595936" });
  assert.equal(appId("", "39000000001"), "337595936");
  assert.equal(appId("7", ""), "337595936");
  assert.equal(appId("", ""), "", "a PR run with no dispatcher passes none");
  assert.equal(read["expected-upstream-head"], undefined, "the model calls run on the reviewed head");
});

test("pr-run-activity-read.yml: review-threads, ci-context, dependency-review and merge-base are its prepare modes, PR mode only, each handing on a patch", () => {
  const steps = workflow("pr-run-activity-read.yml").jobs.run.steps;
  const guard = steps.find((s) => s.name === "Assert the prepare mode is ci-context, review-threads, dependency-review or merge-base in patch mode");
  const refuses = (prepare, patch, issue = "") =>
    evaluate(guard.if, {
      "steps.config.outcome": "success",
      "steps.config.outputs.prepare": prepare,
      "steps.config.outputs.applied-by-patch": patch,
      "inputs.issue-number": issue,
    });
  assert.equal(refuses("review-threads", "apply-feedback-patch"), false);
  assert.equal(refuses("ci-context", "apply-patch"), false);
  assert.equal(refuses("", ""), false);
  assert.equal(refuses("review-threads", ""), true);
  assert.equal(refuses("merge-base", "apply-conflict-patch"), false);
  assert.equal(refuses("merge-base", ""), true);
  assert.equal(refuses("merge-base", "apply-conflict-patch", "7"), true, "issue mode");
  assert.equal(refuses("apply-patch", "apply-patch"), true);
  assert.equal(refuses("dependency-review", "apply-dependency-patch"), false);
  assert.equal(refuses("dependency-review", ""), true);
  assert.equal(refuses("dependency-review", "apply-dependency-patch", "7"), true, "issue mode");
  assert.equal(refuses("review-threads", "apply-feedback-patch", "7"), true, "issue mode");
  assert.equal(spawnSync("bash", ["-c", guard.run]).status, 1);
  const config = steps.find((s) => s.id === "config");
  assert.equal(evaluate(config.with["applied-by-supported"], { "inputs.issue-number": "" }), "patch feedback-replies dependency-verdict");
  assert.equal(evaluate(config.with["applied-by-supported"], { "inputs.issue-number": "7" }), "patch work-outcome");
});

// The check step of the feedback context, run as the runner runs it: exactly
// threads.json and run.json, regular, within 1 MiB, the select job's SHA-256,
// for the gated PR and head.
test("pr-run-activity-read.yml: the feedback context reaches the skill only as the select job's thread file for the gated PR and head", (t) => {
  const steps = workflow("pr-run-activity-read.yml").jobs.run.steps;
  const at = (name) => steps.findIndex((s) => s.name === name);
  const check = steps[at("Check the feedback context")];
  const download = steps[at("Download the feedback context")];
  assert.equal(download.with.name, "feedback-context-${{ inputs.feedback-context-attempt }}");
  assert.equal(download.with.path, "${{ runner.temp }}/lane-feedback");
  assert.equal(check.env.THREADS_SHA256, "${{ inputs.feedback-context-sha256 }}");
  assert.equal(check.env.HEAD_SHA, "${{ steps.gate.outputs.head-sha }}");
  assert.equal(check.env.PR_NUMBER, "${{ steps.gate.outputs.pr-number }}");
  assert.ok(at("Download the feedback context") < at("Check the feedback context"));
  assert.ok(at("Check the feedback context") < at("Stage the activity from the base"));
  assert.ok(at("Stage the activity from the base") < at("Check out the PR head"));
  for (const step of [download, check]) {
    assert.equal(evaluate(step.if, { "steps.go.outputs.run": "true", "steps.config.outputs.prepare": "review-threads" }), true);
    assert.equal(evaluate(step.if, { "steps.go.outputs.run": "true", "steps.config.outputs.prepare": "ci-context" }), false);
  }
  const head = "a".repeat(40);
  const runCheck = ({ threads = { pr: 42, head_sha: head }, run = '{"version":1}\n', extra = false, link = false, sha } = {}) => {
    const dir = mkdtempSync(join(tmpdir(), "feedback-context-"));
    t.after(() => rmSync(dir, { recursive: true, force: true }));
    const text = `${JSON.stringify(threads)}\n`;
    if (link) {
      writeFileSync(join(dir, "elsewhere.json"), text);
      symlinkSync(join(dir, "elsewhere.json"), join(dir, "threads.json"));
    } else {
      writeFileSync(join(dir, "threads.json"), text);
    }
    if (run !== null) writeFileSync(join(dir, "run.json"), run);
    if (extra) writeFileSync(join(dir, "extra.json"), "{}");
    const digest = createHash("sha256").update(text).digest("hex");
    return spawnSync("bash", ["-e", "-c", check.run], {
      encoding: "utf8",
      env: { PATH: process.env.PATH, FEEDBACK_DIR: dir, THREADS_SHA256: sha ?? digest, HEAD_SHA: head, PR_NUMBER: "42" },
    });
  };
  assert.equal(runCheck().status, 0, runCheck().stdout);
  for (const [why, options, message] of [
    ["no run.json", { run: null }, /exactly one threads\.json and one run\.json/],
    ["a third file", { extra: true }, /exactly one threads\.json and one run\.json/],
    ["a linked thread file", { link: true }, /exactly one threads\.json and one run\.json/],
    ["another SHA-256", { sha: "0".repeat(64) }, /does not match the SHA-256/],
    ["no SHA-256", { sha: "" }, /does not match the SHA-256/],
    ["another head", { threads: { pr: 42, head_sha: "b".repeat(40) } }, /another head or PR/],
    ["another PR", { threads: { pr: 43, head_sha: head } }, /another head or PR/],
  ]) {
    const result = runCheck(options);
    assert.equal(result.status, 1, why);
    assert.match(result.stdout, message, why);
  }
});

// The stage step, run in a fresh repository: the thread files and the
// tool are read-only, and the review-thread tool can still write its replies
// file in state/, which the collect-base-activity stage made before the copy.
test("pr-run-activity-read.yml: the staged review-thread files are read-only and only state/ takes the replies file", (t) => {
  const step = workflow("pr-run-activity-read.yml").jobs.run.steps.find((s) => s.name === "Stage the skill's files in the checkout");
  const dir = mkdtempSync(join(tmpdir(), "stage-feedback-"));
  t.after(() => {
    spawnSync("chmod", ["-R", "u+w", dir]);
    rmSync(dir, { recursive: true, force: true });
  });
  const ws = join(dir, "ws");
  const stage = join(dir, "lane-stage");
  mkdirSync(ws);
  spawnSync("git", ["init", "-q", ws]);
  for (const sub of ["plugins/source-control", "scratch", "feedback/bin", "feedback/state"]) mkdirSync(join(stage, sub), { recursive: true });
  for (const file of ["prompt.md", "feedback/threads.json", "feedback/run.json", "feedback/feedback-thread.sh", "feedback/bin/feedback-thread"]) {
    writeFileSync(join(stage, file), "x\n");
  }
  const run = spawnSync("bash", ["-e", "-c", step.run], { cwd: ws, encoding: "utf8", env: { PATH: process.env.PATH, STAGE: stage, TRUSTED_CONTEXT: join(dir, "absent.json") } });
  assert.equal(run.status, 0, run.stderr);
  const writes = (relative) => spawnSync("bash", ["-c", 'echo y >>"$1"', "_", join(ws, ".lane", relative)]).status === 0;
  assert.equal(writes("feedback/state/replies.jsonl"), true, "the tool writes its replies file");
  for (const relative of ["feedback/threads.json", "feedback/run.json", "feedback/feedback-thread.sh", "feedback/bin/feedback-thread", "feedback/new.json", "feedback/bin/new"]) {
    assert.equal(writes(relative), false, relative);
  }
  assert.equal(writes("scratch/notes.txt"), true);
  assert.match(readFileSync(join(ws, ".git", "info", "exclude"), "utf8"), /^\/\.lane\/$/m);
});

// replies.jsonl's cap, in each place it is held to: the carry, the open, the
// decode and the reply script, all at publish-feedback.mjs's limit.
test("pr-run-activity-read.yml: the replies leave the model job only for a review-threads skill, within the reply script's 49152-byte limit", async (t) => {
  const { LIMITS } = await import("../../scripts/pr-unblock/publish-feedback.mjs");
  assert.equal(LIMITS.bytes, 49152);
  const read = workflow("pr-run-activity-read.yml");
  const carry = read.jobs.run.steps.find((s) => s.id === "carry");
  assert.match(carry.run, /carry replies "\$REPLIES_FILE" replies\.jsonl 49152\n/);
  assert.match(read.jobs.scan.steps.find((s) => s.id === "open").with["max-bytes"], /^replies\.jsonl=49152$/m);
  assert.match(read.jobs.scan.steps.find((s) => s.id === "decode").with.script, /\['replies', 'replies\.jsonl', 49152\]/);
  assert.match(read.jobs.run.steps.find((s) => s.id === "seal").with.payloads, /^replies\.jsonl=\$\{\{ runner\.temp \}\}\/carry\/replies\.jsonl$/m);
  // The workspace path, a format() the evaluator does not run, stands in as one word.
  const path = "format('{0}/.lane/feedback/state/replies.jsonl', github.workspace)";
  assert.ok(carry.env.REPLIES_FILE.includes(path));
  const repliesFile = (prepare) => evaluate(carry.env.REPLIES_FILE.replace(path, '"REPLIES_PATH"'), { "steps.config.outputs.prepare": prepare });
  assert.equal(repliesFile("ci-context"), "");
  assert.equal(repliesFile(""), "");
  assert.equal(repliesFile("review-threads"), "REPLIES_PATH");
  const dir = mkdtempSync(join(tmpdir(), "carry-replies-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const carryWith = (bytes) => {
    const out = join(dir, `out-${bytes}`);
    const ws = join(dir, `ws-${bytes}`);
    mkdirSync(ws);
    mkdirSync(join(dir, "seal"), { recursive: true });
    writeFileSync(out, "");
    const replies = join(dir, `replies-${bytes}.jsonl`);
    writeFileSync(replies, "x".repeat(bytes));
    const result = spawnSync("bash", ["-e", "-c", carry.run], {
      encoding: "utf8",
      env: {
        PATH: process.env.PATH,
        GITHUB_OUTPUT: out,
        GITHUB_WORKSPACE: ws,
        REPLY_DIR: join(dir, "no-reply"),
        PATCH_FILE: join(dir, "no-patch"),
        REPLIES_FILE: replies,
        CARRY_DIR: join(dir, `carry-${bytes}`),
        SEAL_DIR: join(dir, "seal"),
      },
    });
    return { result, output: readFileSync(out, "utf8"), copied: existsSync(join(dir, `carry-${bytes}`, "replies.jsonl")) };
  };
  const fits = carryWith(49152);
  assert.equal(fits.result.status, 0, fits.result.stdout);
  assert.equal(fits.output, "replies-bytes=49152\n");
  assert.equal(fits.copied, true);
  const over = carryWith(49153);
  assert.equal(over.output, "replies-bytes=49153\n");
  assert.equal(over.copied, false, "an oversized replies file is not sealed");
  assert.match(over.result.stdout, /too-large: the replies is 49153 bytes, over its 49152-byte cap/);
});

test("pr-run-activity-read.yml: the scan job uploads the replies from its scanned copy, only on a clean scan", () => {
  const steps = workflow("pr-run-activity-read.yml").jobs.scan.steps;
  const upload = steps.find((s) => s.id === "feedback-upload");
  assert.equal(upload.with.name, "feedback-replies-${{ inputs.lane }}-${{ inputs.activity }}-${{ github.run_attempt }}");
  assert.equal(upload.with.path, "${{ steps.leak-scan.outputs.dir }}/replies.jsonl");
  assert.equal(upload.with.overwrite, false);
  assert.ok(steps.indexOf(upload) > steps.findIndex((s) => s.id === "leak-scan"));
  const scan = steps.find((s) => s.id === "leak-scan").with.script;
  assert.match(scan, /const replies = keep\(`\$\{REPLY_DIR\}\/replies\.jsonl`, 'replies\.jsonl'\);/);
  assert.match(scan, /judge\('the replies', replies\);/);
});

test("pr-run-activity-write.yml: apply-patch under the review-threads row reads the select job's thread file, checked against its SHA-256 before the mint", (t) => {
  const steps = workflow("pr-run-activity-write.yml").jobs.run.steps;
  const at = (name) => steps.findIndex((s) => s.name === name);
  const download = steps[at("Download the kept threads")];
  const check = steps[at("Check the kept threads")];
  assert.equal(download.with.name, "feedback-context-${{ inputs.patch-threads-attempt }}");
  assert.ok(at("Check the kept threads") < at("Request the lane token"));
  const context = (prepare) => ({ "steps.config.outputs.applies": "true", "steps.config.outputs.prepare": "apply-patch", "inputs.patch-prepare": prepare });
  for (const step of [download, check]) {
    assert.equal(evaluate(step.if, context("review-threads")), true);
    assert.equal(evaluate(step.if, context("ci-context")), false);
    assert.equal(evaluate(step.if, context("")), false);
  }
  const script = steps.find((s) => s.id === "act-script");
  assert.equal(script.env.KEPT_THREADS_FILE, "${{ steps.patch-threads.outputs.file }}");
  const dir = mkdtempSync(join(tmpdir(), "kept-threads-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const file = join(dir, "threads.json");
  writeFileSync(file, '{"threads":[]}\n');
  const digest = createHash("sha256").update('{"threads":[]}\n').digest("hex");
  const runCheck = (sha) => {
    const out = join(dir, "out");
    writeFileSync(out, "");
    const result = spawnSync("bash", ["-e", "-c", check.run], { encoding: "utf8", env: { PATH: process.env.PATH, GITHUB_OUTPUT: out, THREADS_FILE: file, THREADS_SHA256: sha } });
    return { status: result.status, output: readFileSync(out, "utf8") };
  };
  assert.deepEqual(runCheck(digest), { status: 0, output: `file=${file}\n` });
  assert.deepEqual(runCheck("0".repeat(64)), { status: 1, output: "" });
  assert.deepEqual(runCheck(""), { status: 1, output: "" });
});

// S&C 7.2 finding 2, carried into review-dependency: no patch applies
// without a scanned verdict. The push reads the scan job's verdict, checked
// against its SHA-256 before the mint, and only its closed-set verdict field
// reaches the row's dependency-verdict requirement.
test("pr-run-activity-write.yml: apply-patch under the dependency-review row reads the scanned verdict, checked against its SHA-256 before the mint", (t) => {
  const steps = workflow("pr-run-activity-write.yml").jobs.run.steps;
  const at = (name) => steps.findIndex((s) => s.name === name);
  const download = steps[at("Download the dependency verdict for the patch")];
  const check = steps[at("Check the dependency verdict for the patch")];
  assert.equal(download.with.name, "dependency-verdict-${{ inputs.lane }}-${{ inputs.patch-activity }}-${{ inputs.patch-verdict-attempt }}");
  assert.ok(at("Check the dependency verdict for the patch") < at("Request the lane token"));
  const context = (prepare) => ({ "steps.config.outputs.applies": "true", "steps.config.outputs.prepare": "apply-patch", "inputs.patch-prepare": prepare });
  for (const step of [download, check]) {
    assert.equal(evaluate(step.if, context("dependency-review")), true);
    assert.equal(evaluate(step.if, context("review-threads")), false);
    assert.equal(evaluate(step.if, context("")), false);
  }
  assert.equal(steps.find((s) => s.id === "act-script").env.DEPENDENCY_VERDICT, "${{ steps.patch-verdict.outputs.verdict }}");
  const dir = mkdtempSync(join(tmpdir(), "patch-verdict-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const file = join(dir, "dependency-verdict.json");
  const runCheck = (text, sha = createHash("sha256").update(text).digest("hex")) => {
    writeFileSync(file, text);
    const out = join(dir, "out");
    writeFileSync(out, "");
    const result = spawnSync("bash", ["-e", "-c", check.run], { encoding: "utf8", env: { PATH: process.env.PATH, GITHUB_OUTPUT: out, VERDICT_FILE: file, VERDICT_SHA256: sha } });
    return { status: result.status, output: readFileSync(out, "utf8") };
  };
  assert.deepEqual(runCheck('{"verdict":"fix","reasons":["r"],"evidence":[]}'), { status: 0, output: "verdict=fix\n" });
  assert.deepEqual(runCheck('{"verdict":"merge"}'), { status: 0, output: "verdict=merge\n" });
  assert.deepEqual(runCheck('{"verdict":"fix\\nverdict=fix"}'), { status: 0, output: "verdict=\n" }, "a value outside the set");
  assert.deepEqual(runCheck("not json"), { status: 0, output: "verdict=\n" });
  assert.deepEqual(runCheck('{"verdict":"fix"}', "0".repeat(64)), { status: 1, output: "" });
  assert.deepEqual(runCheck('{"verdict":"fix"}', ""), { status: 1, output: "" });
  rmSync(file);
  const missing = spawnSync("bash", ["-e", "-c", check.run], { encoding: "utf8", env: { PATH: process.env.PATH, GITHUB_OUTPUT: join(dir, "out"), VERDICT_FILE: file, VERDICT_SHA256: "0".repeat(64) } });
  assert.equal(missing.status, 1, "no verdict, no patch");
  // The base dependabot.yml, whose pairs the dependency-manifests rule reads, is copied beside the rules.
  assert.match(steps.find((s) => s.id === "apply-base").run, /cp \.base\/\.github\/dependabot\.yml "\$DEST\/\.github\/dependabot\.yml"/);
});

test("pr-run-activity-write.yml: the verdict job reads context.json from the select job's artifact and the verdict from the scan job's", () => {
  const steps = workflow("pr-run-activity-write.yml").jobs.run.steps;
  const context = steps.find((s) => s.name === "Download the dependency context");
  const verdict = steps.find((s) => s.name === "Download the dependency verdict");
  assert.equal(context.with.name, "dependency-context-${{ inputs.dependency-context-attempt }}");
  assert.equal(verdict.with.name, "dependency-verdict-${{ inputs.lane }}-review-dependency-${{ inputs.dependency-run-attempt }}");
  assert.equal(context.with.path, verdict.with.path);
  const env = steps.find((s) => s.id === "act-script").env;
  assert.equal(env.DEPENDENCY_VERDICT_DIR, "${{ inputs.dependency-verdict && format('{0}/dependency-verdict', runner.temp) || '' }}");
  assert.equal(env.DEPENDENCY_RUN_SHA256, "${{ inputs.dependency-run-sha256 }}");
  assert.equal(env.DEPENDENCY_VERDICT_SHA256, "${{ inputs.dependency-verdict-sha256 }}");
  assert.equal(env.DEPENDENCY_PATCH_STATE, "${{ inputs.dependency-verdict && inputs.dependency-patch-state || '' }}");
  // A dependency-review skill on this runner fails red before the mint.
  const at = (name) => steps.findIndex((s) => s.name === name);
  const refuse = steps[at("Assert dependency-review runs in the read runner")];
  assert.ok(at("Assert dependency-review runs in the read runner") < at("Request the lane token"));
  assert.equal(evaluate(refuse.if, { "steps.config.outcome": "success", "steps.config.outputs.prepare": "dependency-review" }), true);
  assert.equal(evaluate(refuse.if, { "steps.config.outcome": "success", "steps.config.outputs.prepare": "apply-patch" }), false);
  assert.equal(spawnSync("bash", ["-c", refuse.run]).status, 1);
});

// A needs-human PR's fix request, or another lane's escalation, reaches the
// push: the caller's base-code job's output leaves the human-gated label out
// of the holds.
test("pr-run-activity-write.yml: apply-patch drops the human-gated hold only on its caller's base-code verdict", () => {
  const step = workflow("pr-run-activity-write.yml").jobs.run.steps.find((s) => s.id === "hold-label");
  const requested = (prepare, fixRequested) =>
    evaluate(step.env.FIX_REQUESTED, { "steps.config.outputs.prepare": prepare, "inputs.patch-fix-requested": fixRequested });
  assert.equal(requested("apply-patch", "true"), "true");
  assert.equal(requested("apply-patch", "false"), "false");
  assert.equal(requested("apply-patch", ""), "", "a caller that passes nothing keeps every hold");
  assert.equal(requested("ci-context", "true"), "", "a skill run never drops it");
  // scripts/write-runner-promote-holds.test.sh runs the step's jq on these values.
});

test("pr-run-activity-write.yml: the reply job reads run.json from the select job's artifact and the replies from the scan job's", () => {
  const steps = workflow("pr-run-activity-write.yml").jobs.run.steps;
  const record = steps.find((s) => s.name === "Download the review-thread run record");
  const replies = steps.find((s) => s.name === "Download the review-thread replies");
  assert.equal(record.with.name, "feedback-context-${{ inputs.review-run-attempt }}");
  assert.equal(replies.with.name, "feedback-replies-${{ inputs.lane }}-address-feedback-${{ inputs.review-replies-attempt }}");
  assert.equal(record.with.path, replies.with.path);
  assert.equal(steps.find((s) => s.id === "act-script").env.FEEDBACK_REPLIES_DIR, "${{ inputs.review-replies && format('{0}/feedback-replies', runner.temp) || '' }}");
  // The longer name first, so "inputs.review-replies" is not replaced inside it.
  const base = (attempt) => ({ "inputs.review-replies-attempt": attempt, "steps.lane-token.outputs.token": "t", "inputs.review-replies": true, "steps.config.outputs.kind": "script" });
  assert.equal(evaluate(record.if, { ...base(""), "inputs.review-run-attempt": "1" }), true);
  assert.equal(evaluate(replies.if, base("")), false, "no replies uploaded: none is downloaded");
  assert.equal(evaluate(replies.if, base("2")), true);
});

// work-resolve-issue.yml: report-outcome gets apply-issue-patch's escalation
// reason, so a refused patch is handed back with its reason; the write
// runner takes a patch-* reason in issue mode only, so pr-unblock's
// report-escalation still takes none.
test("work-resolve-issue.yml: report-outcome passes apply-issue-patch's escalation reason", () => {
  const job = workflow("work-resolve-issue.yml").jobs["report-outcome"];
  assert.ok(job.needs.includes("apply-issue-patch"));
  const context = (reason) => ({ "needs.apply-issue-patch.outputs.escalation-reason": reason });
  assert.equal(evaluate(job.with["escalation-reason"], context("patch-protected-path")), "patch-protected-path");
  assert.equal(evaluate(job.with["escalation-reason"], context("")), "");
});

test("pr-run-activity-write.yml: a patch-* escalation reason passes the input check in issue mode only", () => {
  const step = workflow("pr-run-activity-write.yml").jobs.run.steps.find((s) => s.name?.startsWith("Assert the lanes App sender id"));
  const status = (reason, issueMode) =>
    spawnSync("bash", ["-c", step.run], {
      env: {
        PATH: process.env.PATH,
        APP_SENDER_ID: "1",
        DEFAULT_BRANCH: "main",
        ESCALATION_REASON: reason,
        ...(issueMode
          ? { ISSUE_NUMBER: "7", EVENT_NAME: "issues", EVENT_ISSUE: "7", TRUSTED_BASE: "default-tip" }
          : { EVENT_NAME: "workflow_dispatch", PR_NUMBER: "42", TRUSTED_BASE: "pr-base" }),
      },
    }).status;
  for (const reason of ["patch-empty", "patch-invalid", "patch-not-applied", "patch-protected-path"]) {
    assert.equal(status(reason, true), 0, `${reason} in issue mode`);
    assert.equal(status(reason, false), 1, `${reason} in PR mode`);
  }
  assert.equal(status("", false), 0, "the PR-mode control passes with no reason");
  assert.equal(status("patch-unknown", true), 1);
});

// --- resolve-conflicts on run-claude-cli: a select job, two model calls, a push job ---

// The outputs of a model call each resolve-conflicts job may read: the
// subscription call its fallback compares; the push job the patch and its
// report from the scan job. No job takes a gate, head, base or conflict tree
// from a model call.
const CONFLICT_CALL_READS = {
  "apply-conflict-patch": ["scan-patch-attempt", "scan-patch-sha256", "scan-patch-state", "scan-reply-attempt"],
  "conflict-scan-refusal": ["scan-patch-state"],
};

test("pr-unblock.yml: no job takes a gate, head, base or conflict tree from a resolve-conflicts model call", () => {
  const { jobs } = workflow("pr-unblock.yml");
  for (const [id, job] of Object.entries(jobs)) {
    const read = [...JSON.stringify(job).matchAll(/needs\.resolve-conflicts(?:-subscription)?\.outputs\.([\w-]+)/g)].map((m) => m[1]);
    assert.deepEqual([...new Set(read)].sort(), CONFLICT_CALL_READS[id] ?? [], id);
  }
  const SELECT = (output) => `\${{ needs.resolve-conflicts-select.outputs.${output} }}`;
  for (const id of ["resolve-conflicts", "resolve-conflicts-subscription"]) {
    assert.equal(jobs[id].with["head-sha"], SELECT("head-sha"), id);
    assert.equal(jobs[id].with["merge-base-sha"], SELECT("base-sha"), id);
    assert.equal(jobs[id].with["merge-conflict-tree"], SELECT("conflict-tree"), id);
  }
  const apply = jobs["apply-conflict-patch"].with;
  assert.equal(apply["patch-head-sha"], SELECT("head-sha"));
  assert.equal(apply["patch-merge-base-sha"], SELECT("base-sha"));
  assert.equal(apply["patch-merge-state"], SELECT("merge-state"));
  assert.equal(apply["patch-conflict-tree"], SELECT("conflict-tree"));
  assert.equal(apply["patch-prepare"], "merge-base");
  // report-escalation reads the select and push jobs' escalations, never a model call's.
  const escalation = jobs["report-escalation"];
  assert.ok(escalation.needs.includes("resolve-conflicts-select") && escalation.needs.includes("apply-conflict-patch"));
  assert.ok(!escalation.needs.includes("resolve-conflicts"));
  assert.match(escalation.with["escalation-reason"], /needs\.resolve-conflicts-select\.outputs\.escalation-reason\s+\|\| needs\.apply-conflict-patch\.outputs\.escalation-reason/);
});

// A clean merge commits with no model call; a conflicted one only beside a
// patch the answering leg's scan job handed on; anything else pushes nothing.
test("pr-unblock.yml: apply-conflict-patch runs on a clean merge, or on a conflicted one beside the answering leg's scanned patch", () => {
  const { jobs } = workflow("pr-unblock.yml");
  const apply = jobs["apply-conflict-patch"];
  const runs = (mergeState, proceed, subResult, sub, first) =>
    evaluate(apply.if, {
      "needs.resolve-conflicts-select.outputs.merge-state": mergeState,
      "needs.resolve-conflicts-select.outputs.proceed": proceed,
      "needs.resolve-conflicts-subscription.result": subResult,
      "needs.resolve-conflicts-subscription.outputs.scan-patch-state": sub,
      "needs.resolve-conflicts.outputs.scan-patch-state": first,
    });
  assert.equal(runs("clean", "false", "skipped", "", ""), true, "a clean merge, no model call");
  assert.equal(runs("conflicted", "true", "skipped", "", "written"), true);
  assert.equal(runs("conflicted", "true", "skipped", "", "empty"), true, "an empty patch escalates unresolved-conflict");
  assert.equal(runs("conflicted", "true", "success", "written", ""), true);
  assert.equal(runs("conflicted", "true", "success", "", "written"), false, "the key call's patch is not taken once the subscription call ran");
  assert.equal(runs("conflicted", "true", "skipped", "", ""), false, "a leg that handed on nothing");
  for (const state of ["escalate", ""]) {
    assert.equal(runs(state, "false", "skipped", "", "written"), false, `${state || "no"} merge state`);
  }
  // A forged run job output cannot make a clean merge take a patch: the
  // select job's merge-state is clean only when no model call ran.
  assert.equal(evaluate(jobs["resolve-conflicts"].if, { "needs.resolve-conflicts-select.outputs.proceed": "false" }), false);
});

// A refused scan hands no patch state on, so apply-conflict-patch skips; the
// scan-refusal marker alone, read by a script job, escalates the round.
test("pr-unblock.yml: conflict-scan-refusal escalates a refused resolve-conflicts scan from its marker, with every leg output empty", () => {
  const { jobs } = workflow("pr-unblock.yml");
  const job = jobs["conflict-scan-refusal"];
  assert.ok(job, "pr-unblock.yml has a conflict-scan-refusal job");
  assert.equal(job.uses, undefined, "a script job, never a runner call");
  assert.deepEqual(job.permissions, { contents: "read" });
  assert.deepEqual(job.needs, ["resolve-conflicts-select", "resolve-conflicts", "resolve-conflicts-subscription"]);
  const runs = (proceed, subResult, sub, first) =>
    evaluate(job.if, {
      "needs.resolve-conflicts-select.outputs.proceed": proceed,
      "needs.resolve-conflicts-subscription.result": subResult,
      "needs.resolve-conflicts-subscription.outputs.scan-patch-state": sub,
      "needs.resolve-conflicts.outputs.scan-patch-state": first,
    });
  assert.equal(runs("true", "skipped", "", ""), true, "the first leg handed on nothing");
  assert.equal(runs("true", "failure", "", ""), true, "the fallback leg handed on nothing");
  assert.equal(runs("true", "success", "", "written"), true, "the key call's patch is not the answering leg's");
  // Exactly where apply-conflict-patch does not run on a conflicted round.
  for (const state of ["written", "empty"]) {
    assert.equal(runs("true", "skipped", "", state), false, state);
    assert.equal(runs("true", "success", state, ""), false, state);
  }
  // On every conflicted round exactly one of the two jobs runs.
  const states = ["", "written", "empty", "other"];
  for (const subResult of ["skipped", "success", "failure"]) {
    for (const sub of states) {
      for (const first of states) {
        const values = {
          "needs.resolve-conflicts-select.outputs.merge-state": "conflicted",
          "needs.resolve-conflicts-select.outputs.proceed": "true",
          "needs.resolve-conflicts-subscription.result": subResult,
          "needs.resolve-conflicts-subscription.outputs.scan-patch-state": sub,
          "needs.resolve-conflicts.outputs.scan-patch-state": first,
        };
        const apply = evaluate(jobs["apply-conflict-patch"].if, values) === true;
        const refusal = evaluate(job.if, values) === true;
        assert.notEqual(apply, refusal, JSON.stringify([subResult, sub, first]));
      }
    }
  }
  assert.equal(runs("false", "skipped", "", ""), false, "a clean merge or a select-job skip");
  assert.equal(runs("", "skipped", "", ""), false);
  // The marker comes by name from the scan-refusal job's upload, never a job output.
  const download = job.steps.find((step) => step.uses?.startsWith("actions/download-artifact@"));
  const writeDownload = workflow("pr-run-activity-write.yml").jobs.run.steps.find((step) => step.id === "scan-refused");
  assert.equal(download.uses, writeDownload.uses, "the write runner's pinned download action");
  assert.equal(download["continue-on-error"], true);
  assert.equal(download.with["merge-multiple"], true);
  const upload = workflow("pr-run-activity-read.yml").jobs["scan-refusal"].steps.find((step) => step.uses?.startsWith("actions/upload-artifact@"));
  const sub = (text, values) => text.replace(/\$\{\{([^}]*)\}\}/g, (_, expr) => String(evaluate(`\${{${expr}}}`, values)));
  const values = { "inputs.lane": "pr-unblock", "inputs.activity": "resolve-conflicts", "github.run_attempt": "2", "runner.temp": "/t" };
  for (const rung of ["", "1"]) {
    const name = sub(upload.with.name, { ...values, "inputs.model-rung": rung });
    assert.ok(download.with.pattern.endsWith("-*") && name.startsWith(download.with.pattern.slice(0, -1)), `${download.with.pattern} matches ${name}`);
  }
  const script = job.steps.find((step) => step.id === "refusal");
  assert.equal(script.run, "node .base/.github/scripts/pr-unblock/conflict-scan-refusal.mjs");
  assert.equal(sub(script.env.SCAN_REFUSED_DIR, values), sub(download.with.path, values));
  assert.equal(script.env.SCAN_REFUSED_READ, `\${{ steps.${download.id}.outcome }}`);
  assert.equal(job.outputs["escalation-reason"], "${{ steps.refusal.outputs.escalation-reason }}");
  assert.doesNotMatch(JSON.stringify(job.steps), /needs\./, "no step reads a leg output");
  // Its escalation reaches report-escalation and the conflict status.
  const escalation = jobs["report-escalation"];
  assert.ok(escalation.needs.includes("conflict-scan-refusal"));
  assert.match(escalation.with["escalation-reason"], /needs\.apply-conflict-patch\.outputs\.escalation-reason\s+\|\| needs\.conflict-scan-refusal\.outputs\.escalation-reason/);
  const quiet = rungUpContext({ rungUp: "false" });
  const refused = { ...quiet, "needs.conflict-scan-refusal.outputs.escalation-reason": "unresolved-conflict" };
  assert.equal(evaluate(escalation.if, refused), true);
  assert.equal(evaluate(escalation.with["escalation-reason"], refused).trim(), "unresolved-conflict");
  assert.equal(evaluate(escalation.if, quiet), false);
});

test("pr-unblock.yml: resolve-conflicts is reported neutral when the select job does not proceed: its skip, a clean merge, or a person's", async () => {
  const head = "d".repeat(40);
  const { jobs } = workflow("pr-unblock.yml");
  const notRun = jobs["resolve-conflicts-not-run"];
  const context = (proceed, headSha, { skip = "", state = "", activity = "resolve-conflicts" } = {}) => ({
    "inputs.activity": activity,
    "needs.resolve-conflicts-select.outputs.proceed": proceed,
    "needs.resolve-conflicts-select.outputs.head-sha": headSha,
    "needs.resolve-conflicts-select.outputs.skip-reason": skip,
    "needs.resolve-conflicts-select.outputs.merge-state": state,
  });
  assert.deepEqual([notRun.needs].flat(), ["resolve-conflicts-select"]);
  assert.deepEqual(notRun.permissions, { checks: "write", contents: "read" });
  assert.equal(evaluate(notRun.if, context("true", head)), false);
  assert.equal(evaluate(notRun.if, context("false", head, { state: "clean" })), true);
  assert.equal(evaluate(notRun.if, context("false", "")), false, "a stop before the head read names no head to post on");
  assert.equal(evaluate(notRun.if, context("false", head, { activity: "fix-ci" })), false);
  for (const [given, summary] of [
    [{ skip: "not-applicable" }, "Skip reason: not-applicable"],
    [{ skip: "awaiting-human" }, "Skip reason: awaiting-human"],
    [{ state: "clean" }, "Skip reason: clean-merge"],
    [{ state: "escalate" }, "Skip reason: awaiting-human"],
  ]) {
    const calls = await postNotRunChecks(notRun, context("false", head, given));
    assert.deepEqual(
      calls.map((call) => [call.name, call.head_sha, call.conclusion, call.output.summary]),
      [["pr-unblock / resolve-conflicts", head, "neutral", summary]],
      JSON.stringify(given),
    );
  }
});

test("pr-unblock.yml: resolve-conflicts-select merges with the base's scripts, pinned to the tip it read, in a head checkout that keeps no credential", () => {
  const select = workflow("pr-unblock.yml").jobs["resolve-conflicts-select"];
  assert.deepEqual(select.permissions, { contents: "read", "pull-requests": "read" });
  assert.equal(select.uses, undefined, "a base job, never a runner");
  assert.deepEqual(stepSecrets(select), []);
  const step = (id) => select.steps.find((s) => s.id === id);
  assert.equal(step("slot").with["applied-by-supported"], "patch");
  assert.equal(step("slot").with.activity, "resolve-conflicts");
  const head = select.steps.find((s) => s.name === "Check out the PR head");
  assert.deepEqual(
    [head.with.ref, head.with.path, head.with["fetch-depth"], head.with["persist-credentials"]],
    ["${{ steps.head.outputs.sha }}", "head", 0, false],
  );
  assert.equal(step("prepare")["working-directory"], "head");
  assert.equal(step("prepare").env.BASE_SHA, "${{ steps.base-sha.outputs.sha }}");
  assert.match(step("prepare").run, /\.base\/\.github\/scripts\/merge-base\/run-prepare\.sh/);
  assert.match(step("merge-bin").run, /\.base\/\.github\/scripts\/merge-base\/prepare\.sh/);
  assert.match(step("base-sha").run, /git -C \.base rev-parse HEAD/);
  // proceed: true only for a conflicted merge, false for a skip, a clean merge
  // or an escalation, empty for a stop before the merge.
  const proceed = (applies, state, held = applies === "true" ? "false" : "") =>
    evaluate(select.outputs.proceed, { "steps.slot.outputs.applies": applies, "steps.hold.outputs.held": held, "steps.prepare.outputs.merge-state": state });
  assert.equal(proceed("true", "conflicted"), "true");
  assert.equal(proceed("true", "clean"), "false");
  assert.equal(proceed("true", "escalate"), "false");
  assert.equal(proceed("false", ""), "false");
  assert.equal(proceed("", ""), "");
  assert.equal(proceed("true", ""), "", "a merge step that failed");
  // The human-gated hold (lane-hold.mjs) runs after the slot and before any
  // merge: held skips awaiting-human; a failed read stops it.
  assert.equal(proceed("true", "", "true"), "false");
  assert.equal(proceed("true", "", ""), "", "a hold read that failed");
  const skip = evaluate(select.outputs["skip-reason"], { "steps.slot.outputs.applies": "true", "steps.slot.outputs.skip-reason": "", "steps.hold.outputs.held": "true" });
  assert.equal(skip, "awaiting-human");
  assert.equal(step("hold").if, "steps.slot.outputs.applies == 'true'");
  assert.equal(step("hold").env.ACTIVITY, "resolve-conflicts");
  assert.equal(step("hold").run, "node .base/.github/scripts/pr-unblock/lane-hold.mjs");
  for (const id of ["base-sha", "merge-bin", "prepare"]) {
    assert.equal(step(id).if, "steps.hold.outputs.held == 'false'", id);
  }
  const apply = workflow("pr-unblock.yml").jobs["apply-conflict-patch"];
  assert.equal(apply.with["patch-fix-requested"], "${{ needs.resolve-conflicts-select.outputs.lane-escalated }}");
});

// merge-base: the patch is measured from a conflict tree GitHub does not
// hold, so the scan reads it as text and never applies it to the head; a
// binary hunk, whose bytes the text does not show, blocks.
const CONFLICT_PATCH = [
  "diff --git a/a.txt b/a.txt",
  "index 1111111111111111111111111111111111111111..2222222222222222222222222222222222222222 100644",
  "--- a/a.txt",
  "+++ b/a.txt",
  "@@ -1,5 +1 @@",
  "-<<<<<<< HEAD",
  "-pr",
  "-=======",
  "-main",
  "->>>>>>> main",
  "+pr and main",
  "",
].join("\n");
test("leak scan: a merge-base patch is scanned as text, never applied to the head, and a binary hunk blocks", async (t) => {
  const plantPatch = (text) => ({ afterCollect: ({ temp }) => writeFileSync(join(temp, "patch", "patch.diff"), text) });
  const text = await scanWith(t, () => {}, undefined, { ...plantPatch(CONFLICT_PATCH), env: { TEXT_PATCH: "true" } });
  assert.deepEqual([text.clean, text.failed], ["true", null]);
  // The same patch as any other activity's must apply to the head.
  const applied = await scanWith(t, () => {}, undefined, { ...plantPatch(CONFLICT_PATCH), env: { TEXT_PATCH: "false" } });
  assert.equal(applied.clean, "false");
  assert.match(applied.failed, /the patch does not apply to the head/);
  const binary = `${CONFLICT_PATCH}diff --git a/b.bin b/b.bin\nnew file mode 100644\nindex 0000000000000000000000000000000000000000..3333333333333333333333333333333333333333\nGIT binary patch\nliteral 4\nLcmZ?wbYcJl00RI3\n\nliteral 0\nHcmV?d00001\n\n`;
  const blocked = await scanWith(t, () => {}, undefined, { ...plantPatch(binary), env: { TEXT_PATCH: "true" } });
  assert.equal(blocked.clean, "false");
  assert.match(blocked.failed, /a merge-base patch holds a binary hunk/);
  assert.doesNotMatch(blocked.failed, /rotate/);
  const leaked = await scanWith(t, () => {}, undefined, { ...plantPatch(CONFLICT_PATCH.replace("+pr and main", `+${KEY}`)), env: { TEXT_PATCH: "true" } });
  assert.equal(leaked.clean, "false");
  assert.match(leaked.failed, /rotate this credential/);
  // TEXT_PATCH is the caller's input, never a run job output.
  const step = scanSteps().find((s) => s.id === "leak-scan");
  assert.equal(step.env.TEXT_PATCH, "${{ inputs.merge-conflict-tree != '' }}");
});

// The read runner merges the select job's pinned base again before the model
// and refuses any other conflict tree; the merge inputs go with merge-base
// alone, and the patch is measured from the conflict tree.
test("pr-run-activity-read.yml: merge-base merges the select job's base again, must reach its conflict tree, and measures the patch from it", () => {
  const steps = workflow("pr-run-activity-read.yml").jobs.run.steps;
  const at = (name) => steps.findIndex((s) => s.name === name);
  const step = (name) => steps[at(name)];
  const inputs = step("Check the merge inputs");
  const checks = (prepare, base, tree) =>
    evaluate(inputs.if, { "steps.config.outcome": "success", "steps.config.outputs.prepare": prepare, "inputs.merge-base-sha": base, "inputs.merge-conflict-tree": tree });
  assert.equal(checks("merge-base", "", ""), true);
  assert.equal(checks("ci-context", "a".repeat(40), ""), true, "a merge input on another mode is refused");
  assert.equal(checks("ci-context", "", "b".repeat(40)), true);
  assert.equal(checks("ci-context", "", ""), false);
  assert.ok(at("Check the merge inputs") < at("Check out the PR head"), "before any head code");
  assert.ok(at("Copy the merge scripts from the base") < at("Check out the PR head"));
  const merge = steps.find((s) => s.id === "merge");
  assert.ok(at("Assert the head is the gated SHA") < steps.indexOf(merge) && steps.indexOf(merge) < at("Stage the skill's files in the checkout"));
  assert.equal(merge.env.BASE_SHA, "${{ inputs.merge-base-sha }}");
  assert.equal(merge.env.EXPECT_STATE, "conflicted");
  assert.equal(merge.env.EXPECT_TREE, "${{ inputs.merge-conflict-tree }}");
  assert.match(merge.run, /bash "\$BIN\/run-prepare\.sh"/);
  assert.match(merge.run, /bash "\$BIN\/context\.sh" "\$HEAD_SHA" "\$BASE_SHA" "\$STAGE\/merge"/);
  assert.equal(merge.env.GIT_NO_REPLACE_OBJECTS, "1");
  assert.match(step("Stage the skill's files in the checkout").run, /chmod -R a-w \.lane\/merge/);
  const checkout = step("Check out the PR head");
  assert.equal(evaluate(checkout.with["fetch-depth"], { "steps.config.outputs.prepare": "merge-base" }), 0);
  assert.equal(evaluate(checkout.with["fetch-depth"], { "steps.config.outputs.prepare": "ci-context" }), 1);
  assert.equal(checkout.with["persist-credentials"], false);
  const collect = steps.find((s) => s.id === "patch");
  assert.equal(collect.env.FROM_TREE, "${{ steps.config.outputs.prepare == 'merge-base' && steps.merge.outputs.conflict-tree || '' }}");
  assert.match(collect.run, /collect-patch\.sh" "\$HEAD_SHA" "\$PATCH_DIR\/patch\.diff" \$\{FROM_TREE:\+"\$FROM_TREE"\}/);
});

// The write runner's apply-patch under the merge-base row merges the pinned
// base again, refuses any other state or tree, and hands apply-patch.mjs the
// merge, the base copy of tree-entries.sh and only the merge row's reasons.
test("pr-run-activity-write.yml: apply-patch under the merge-base row merges the pinned base again and must reach the select job's tree", () => {
  const steps = workflow("pr-run-activity-write.yml").jobs.run.steps;
  const at = (name) => steps.findIndex((s) => s.name === name);
  const prepare = steps.find((s) => s.id === "prepare");
  const applyMode = { "steps.lane-token.outputs.token": "t", "steps.config.outputs.prepare": "apply-patch", "inputs.patch-prepare": "merge-base" };
  assert.equal(evaluate(prepare.if, applyMode), true);
  assert.equal(evaluate(prepare.if, { ...applyMode, "inputs.patch-prepare": "ci-context" }), false);
  const values = { ...applyMode, "inputs.patch-merge-base-sha": "p".repeat(40), "inputs.patch-merge-state": "conflicted", "inputs.patch-conflict-tree": "t".repeat(40), "steps.trusted-base.outputs.commit": "d".repeat(40) };
  assert.equal(evaluate(prepare.env.BASE_SHA, values), "p".repeat(40), "the pinned base, never the tip now");
  assert.equal(evaluate(prepare.env.EXPECT_STATE, values), "conflicted");
  assert.equal(evaluate(prepare.env.EXPECT_TREE, values), "t".repeat(40));
  assert.ok(at("Check the merge patch's pinned base") < at("Request the lane token"));
  const checkout = steps[at("Check out the PR head")];
  assert.equal(evaluate(checkout.with["fetch-depth"], { "steps.config.outputs.prepare": "apply-patch", "inputs.issue-number": "", "inputs.patch-prepare": "merge-base" }), 0);
  assert.equal(evaluate(checkout.with["fetch-depth"], { "steps.config.outputs.prepare": "apply-patch", "inputs.issue-number": "", "inputs.patch-prepare": "ci-context" }), 1);
  const script = steps.find((s) => s.id === "act-script");
  assert.equal(script.env.MERGE_STATE, "${{ inputs.patch-prepare == 'merge-base' && steps.prepare.outputs.merge-state || '' }}");
  assert.equal(script.env.CONFLICT_TREE, "${{ inputs.patch-prepare == 'merge-base' && steps.prepare.outputs.conflict-tree || '' }}");
  assert.equal(script.env.TREE_ENTRIES_SHA256, "${{ inputs.patch-prepare == 'merge-base' && steps.merge-bin.outputs.tree-entries-sha256 || '' }}");
  assert.equal(steps.find((s) => s.id === "patch-select").env.MERGE_STATE, "${{ inputs.patch-merge-state }}");
});

// report-escalation passes the select and push jobs' merge reasons to the
// write runner as its escalation-reason input, which the first step holds to
// the runner's reasons: each must pass it, and a reason outside the set fails.
test("pr-run-activity-write.yml: the first step admits every resolve-conflicts escalation reason as the escalation-reason input", () => {
  const step = workflow("pr-run-activity-write.yml").jobs.run.steps[0];
  const run = (reason, extra = {}) =>
    spawnSync("bash", ["-c", step.run], {
      encoding: "utf8",
      env: { PATH: process.env.PATH, APP_SENDER_ID: "1", DEFAULT_BRANCH: "main", ESCALATION_REASON: reason, ...extra },
    }).status;
  for (const reason of [
    "repeat-cap",
    "protected-path-conflict",
    "unresolved-conflict",
    "workflow-staged",
    "unexpected-path-staged",
    "conflict-patch-invalid",
    "conflict-patch-not-applied",
    "conflict-patch-protected-path",
  ]) {
    assert.equal(run(reason), 0, reason);
  }
  assert.equal(run("conflict-patch-bogus"), 1);
  // The merge inputs go with patch-prepare merge-base alone, in PR mode.
  const merge = { PATCH_PREPARE: "merge-base", PATCH_MERGE_BASE_SHA: "a".repeat(40), PATCH_MERGE_STATE: "conflicted", PATCH_CONFLICT_TREE: "b".repeat(40) };
  assert.equal(run("", merge), 0);
  assert.equal(run("", { ...merge, PATCH_MERGE_STATE: "escalate" }), 1);
  assert.equal(run("", { ...merge, PATCH_CONFLICT_TREE: "" }), 1);
  assert.equal(run("", { ...merge, PATCH_PREPARE: "ci-context" }), 1, "merge inputs beside another row");
  assert.equal(run("", { PATCH_PREPARE: "merge-base" }), 1, "the merge row with no inputs");
});

// --- pr-unblock fix-ci: trusted handoff, unreported rounds, refused collections ---

const FIX_CI_CALLS = ["fix-ci", "fix-ci-subscription", "fix-ci-rung-up", "fix-ci-rung-up-subscription"];

// A job listing in the shape GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs
// returns: a reusable call's jobs are named "<caller job> / <called job>", as
// run 39911047185's listing names "fix-docs / report" with its "Post the check
// run" step and "fix-docs / broker-check" with its "Ask the broker whether
// the lane may run" step. `posted` names the calls whose report posted;
// `reportSkipped` the calls whose report job was skipped, as a handoff, forged
// or not, leaves it; `unallowed` the calls whose broker step did not succeed
// (skipped on a kill switch, failed on a refusal).
function jobListing(posted, { reportSkipped = [], unallowed = [], calls = FIX_CI_CALLS } = {}) {
  const jobs = [{ name: "fix-ci-context", conclusion: "success", steps: [] }];
  for (const call of calls) {
    jobs.push({
      name: `${call} / broker-check`,
      conclusion: "success",
      steps: [{ name: "Ask the broker whether the lane may run", conclusion: unallowed.includes(call) ? "skipped" : "success" }],
    });
    // A run job's own step of that name, which no read may count.
    jobs.push({ name: `${call} / run`, conclusion: "success", steps: [{ name: "Post the check run", conclusion: "success" }] });
    const ran = !reportSkipped.includes(call);
    jobs.push({
      name: `${call} / report`,
      conclusion: ran ? "success" : "skipped",
      steps: ran ? [{ name: "Post the check run", conclusion: posted.includes(call) ? "success" : "skipped" }] : [],
    });
  }
  jobs.push({ name: "fix-docs / report", conclusion: "success", steps: [{ name: "Post the check run", conclusion: "success" }] });
  return { total_count: jobs.length, jobs };
}

// Runs a "Read whether ... posted" step, with the default branch tip's
// handoff-evidence.sh where the step's checkout puts it, against a gh stub
// that answers the jobs listing through the script's own --jq filter. A list
// of listings answers one per read, the last repeating; the retry delays are
// zero. Returns its exit, outputs, stdout and the arguments of each read.
const HANDOFF_EVIDENCE = new URL("../../scripts/lib/handoff-evidence.sh", import.meta.url);
function readPosted(t, step, listing, { fail = false, delays = "0 0 0 0 0" } = {}) {
  const root = mkdtempSync(join(tmpdir(), "fix-ci-posted-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, "bin"));
  mkdirSync(join(root, ".base", ".github", "scripts", "lib"), { recursive: true });
  writeFileSync(join(root, ".base", ".github", "scripts", "lib", "handoff-evidence.sh"), readFileSync(HANDOFF_EVIDENCE));
  const listings = Array.isArray(listing) ? listing : [listing];
  listings.forEach((one, index) => writeFileSync(join(root, `listing-${index}.json`), JSON.stringify(one)));
  const calls = join(root, "calls");
  writeFileSync(
    join(root, "bin", "gh"),
    `#!/bin/bash\nprintf '%s\\n' "$*" >>"${calls}"\n${fail ? "exit 1\n" : ""}` +
      `n=$(($(wc -l <"${calls}") - 1)); [ "$n" -lt ${listings.length} ] || n=${listings.length - 1}\n` +
      `while [ $# -gt 0 ]; do if [ "$1" = --jq ]; then filter=$2; fi; shift; done\njq -r "$filter" "${root}/listing-$n.json"\n`,
    { mode: 0o755 },
  );
  const output = join(root, "out");
  writeFileSync(output, "");
  const result = runStep(step, root, {
    PATH: `${join(root, "bin")}:${process.env.PATH}`,
    GITHUB_REPOSITORY: "o/r",
    GITHUB_RUN_ID: "99",
    GH_TOKEN: "x",
    GITHUB_OUTPUT: output,
    CALLS: step.env.CALLS,
    HANDOFF_EVIDENCE_DELAYS: delays,
  });
  return { status: result.status, outputs: outputLines(output), stdout: result.stdout, calls: existsSync(calls) ? readFileSync(calls, "utf8") : "" };
}

// A job that reads handoff evidence: the default branch tip's
// handoff-evidence.sh, sparse-checked out without credentials, then one step
// that runs it, on read-only tokens and no secret.
function assertHandoffEvidenceJob(job) {
  assert.deepEqual(job.permissions, { actions: "read", contents: "read" });
  const checkout = job.steps[0];
  assert.match(String(checkout.uses), /^actions\/checkout@[0-9a-f]{40}$/);
  assert.equal(checkout.with.ref, "${{ github.event.repository.default_branch }}");
  assert.equal(checkout.with.path, ".base");
  assert.equal(checkout.with["persist-credentials"], false);
  assert.equal(checkout.with["sparse-checkout"], ".github/scripts/lib/handoff-evidence.sh");
  // A file path, not a cone directory: cone mode would check out no file.
  assert.equal(checkout.with["sparse-checkout-cone-mode"], false);
  const read = job.steps.find((step) => step.id === "posted");
  assert.equal(read.uses, undefined);
  assert.match(read.run, /^bash \.base\/\.github\/scripts\/lib\/handoff-evidence\.sh( posted| allowed)+$/);
  assert.deepEqual(Object.keys(read.env).sort(), ["CALLS", "GH_TOKEN"]);
  assert.deepEqual(stepSecrets(job), []);
}

// The jobs listing as GitHub can return it while it lags: every step list
// empty, or a step's conclusion null, though each job has concluded.
const lagging = (listing, conclusion = undefined) => ({
  ...listing,
  jobs: listing.jobs.map((job) => ({
    ...job,
    steps: conclusion === undefined ? [] : job.steps.map((step) => ({ ...step, conclusion })),
  })),
});
// The listing with each call's broker-allowed job, which pr-run-activity-read.yml
// runs only on broker-check's allow.
const withMarkers = (listing, allowedCalls) => ({
  ...listing,
  jobs: listing.jobs.flatMap((job) => {
    const call = job.name.endsWith(" / broker-check") ? job.name.slice(0, -" / broker-check".length) : null;
    return call === null ? [job] : [job, { name: `${call} / broker-allowed`, conclusion: allowedCalls.includes(call) ? "success" : "skipped", steps: [] }];
  }),
});

// The broker-allowed job: needs broker-check alone, runs only on its allowed
// output, holds no permission and runs no action or head code.
test("pr-run-activity-read.yml: broker-allowed succeeds only on broker-check's allow, and no run job output reaches it", () => {
  const { jobs } = workflow("pr-run-activity-read.yml");
  const marker = jobs["broker-allowed"];
  assert.equal(marker.needs, "broker-check");
  assert.deepEqual(marker.permissions, {});
  assert.deepEqual(marker.steps.map((step) => step.uses ?? null), [null]);
  assert.doesNotMatch(JSON.stringify(marker), /needs\.(run|scan|report)\b/);
  for (const [allowed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(marker.if, { "needs.broker-check.outputs.allowed": allowed }), runs, JSON.stringify(allowed));
  }
  // broker-check's allowed is its broker step's outcome, a step that runs no
  // head code and cannot continue on error.
  assert.equal(jobs["broker-check"].outputs.allowed, "${{ steps.broker.outcome == 'success' }}");
  const broker = jobs["broker-check"].steps.find((step) => step.id === "broker");
  assert.equal(broker.name, "Ask the broker whether the lane may run");
  assert.equal(broker["continue-on-error"], undefined);
});

// GitHub's jobs listing has returned every step list empty, and a broker
// step's conclusion null for five minutes after its job ended (sandbox run
// 40118275531): the job-level evidence decides at once, a fact only a step can
// settle is read again with backoff, and one that never settles fails closed.
test("handoff-evidence.sh: job-level evidence decides through a lagging listing, a step fact retries, and an unsettled one fails closed", (t) => {
  const read = workflow("pr-unblock.yml").jobs["fix-ci-unreported"].steps.find((s) => s.id === "posted");
  // Empty steps, a handoff (report skipped) after the broker's allow: one read.
  const handoff = withMarkers(jobListing([], { reportSkipped: FIX_CI_CALLS }), FIX_CI_CALLS);
  const empty = readPosted(t, read, lagging(handoff));
  assert.equal(empty.status, 0);
  assert.deepEqual(empty.outputs, { posted: "false", allowed: "true" });
  assert.equal(empty.calls.trim().split("\n").length, 1, "job-level evidence needs one read");
  // A kill switch or refusal: broker-allowed skipped, steps empty.
  const killed = readPosted(t, read, lagging(withMarkers(jobListing([], { reportSkipped: FIX_CI_CALLS }), [])));
  assert.deepEqual(killed.outputs, { posted: "false", allowed: "false" });
  assert.equal(killed.calls.trim().split("\n").length, 1);
  // A report that ran, its step conclusion null, then success on the next read.
  const ran = withMarkers(jobListing(["fix-ci"]), FIX_CI_CALLS);
  const retried = readPosted(t, read, [lagging(ran, null), lagging(ran, null), ran]);
  assert.equal(retried.status, 0);
  assert.deepEqual(retried.outputs, { posted: "true", allowed: "true" });
  assert.equal(retried.calls.trim().split("\n").length, 3);
  assert.match(retried.stdout, /Read 1: missing: fix-ci \/ report step "Post the check run" has no conclusion/);
  // No broker-allowed job (a listing from before it): the broker step decides,
  // retried while null, then the handoff the subscription leg starts on.
  const legacy = jobListing([], { reportSkipped: FIX_CI_CALLS });
  const stepRetry = readPosted(t, read, [lagging(legacy, null), legacy]);
  assert.deepEqual(stepRetry.outputs, { posted: "false", allowed: "true" });
  // A report job that ended before its post step (a setup failure) lists its
  // steps without it: settled as no post on one read, not waited on.
  const setupFailed = withMarkers(jobListing([]), FIX_CI_CALLS);
  for (const job of setupFailed.jobs.filter((j) => j.name.endsWith(" / report"))) {
    job.conclusion = "failure";
    job.steps = [{ name: "Set up job", conclusion: "failure" }];
  }
  const ended = readPosted(t, read, setupFailed);
  assert.equal(ended.status, 0);
  assert.deepEqual(ended.outputs, { posted: "false", allowed: "true" });
  assert.equal(ended.calls.trim().split("\n").length, 1);
  // Never filled: fails closed after every read, one error line, no output.
  const never = readPosted(t, read, lagging(ran));
  assert.notEqual(never.status, 0);
  assert.deepEqual(never.outputs, {});
  assert.equal(never.calls.trim().split("\n").length, 6, "one read and five retries");
  assert.equal(never.stdout.split("\n").filter((line) => line.startsWith("::error::")).length, 1);
  assert.match(never.stdout, /::error::handoff evidence for fix-ci fix-ci-subscription fix-ci-rung-up fix-ci-rung-up-subscription still missing after 6 reads: missing: fix-ci \/ report has no steps listed/);
  // A failed read is retried the same way, then fails closed.
  const failed = readPosted(t, read, ran, { fail: true });
  assert.notEqual(failed.status, 0);
  assert.deepEqual(failed.outputs, {});
  assert.match(failed.stdout, /::error::.*the jobs read failed/);
});

// The run job runs head code but cannot name a job: a run job step called
// "Post the check run" or "Ask the broker whether the lane may run", or a
// forged handed-off that skips the report, never reads as an allow or a post.
test("handoff-evidence.sh: a run job's forged steps and outputs are never evidence", (t) => {
  const read = workflow("pr-unblock.yml").jobs["fix-ci-unreported"].steps.find((s) => s.id === "posted");
  const listing = withMarkers(jobListing([], { reportSkipped: FIX_CI_CALLS }), []);
  for (const job of listing.jobs.filter((j) => j.name.endsWith(" / run"))) {
    job.steps = [
      { name: "Post the check run", conclusion: "success" },
      { name: "Ask the broker whether the lane may run", conclusion: "success" },
    ];
  }
  const forged = readPosted(t, read, listing);
  assert.equal(forged.status, 0);
  assert.deepEqual(forged.outputs, { posted: "false", allowed: "false" });
  // With no broker-allowed job the broker step decides, and only
  // broker-check's: a run job's successful step of that name is not read.
  const legacy = jobListing([], { reportSkipped: FIX_CI_CALLS, unallowed: FIX_CI_CALLS });
  for (const job of legacy.jobs.filter((j) => j.name.endsWith(" / run"))) {
    job.steps = [{ name: "Ask the broker whether the lane may run", conclusion: "success" }];
  }
  const legacyRead = readPosted(t, read, legacy);
  assert.equal(legacyRead.calls.trim().split("\n").length, 1);
  assert.deepEqual(legacyRead.outputs, { posted: "false", allowed: "false" });
});

// The retry delays are the script's own: no workflow shortens or stretches them.
test("handoff-evidence.sh: no workflow sets HANDOFF_EVIDENCE_DELAYS, and every handoff read runs the script", () => {
  for (const file of readdirSync(new URL("../../workflows/", import.meta.url)).filter((name) => name.endsWith(".yml"))) {
    const text = read(`../../workflows/${file}`);
    assert.doesNotMatch(text, /HANDOFF_EVIDENCE_DELAYS/, file);
    assert.doesNotMatch(text, /\.steps\[\]\?; \.name == "(Post the check run|Ask the broker whether the lane may run)"/, `${file} reads a handoff step inline`);
  }
});

// #8890: a hostile run job can forge handed-off, lane-class and
// credential-present, so no fix-ci fallback call may start on them.
test("pr-unblock.yml: each fix-ci fallback call starts on a base job's jobs-API read of the first call's report, never on a fix-ci output", (t) => {
  const { jobs } = workflow("pr-unblock.yml");
  for (const [subId, firstId, handoffId, extra] of [
    ["fix-ci-subscription", "fix-ci", "fix-ci-handoff", {}],
    ["fix-ci-rung-up-subscription", "fix-ci-rung-up", "fix-ci-rung-up-handoff", { "needs.fix-ci-rung-up.result": "success" }],
  ]) {
    const sub = jobs[subId];
    const handoff = jobs[handoffId];
    assert.doesNotMatch(sub.if, /needs\.fix-ci(-rung-up)?\.outputs\./, `${subId}'s start reads no fix-ci output`);
    // The evaluator refuses any reference left unset: the start reads only these.
    const starts = (posted, overrides = {}) =>
      evaluate(sub.if, { "needs.fix-ci-context.outputs.proceed": "true", ...extra, [`needs.${handoffId}.outputs.posted`]: posted, ...overrides });
    assert.equal(starts("false"), true, `${subId} after a call that posted no check`);
    assert.equal(starts(""), true, `${subId} after a failed read: a second leg, never a lost check`);
    assert.equal(starts("true"), false, `${subId} after a call that posted its check`);
    assert.equal(starts("false", { "needs.fix-ci-context.outputs.proceed": "false" }), false);
    if (extra["needs.fix-ci-rung-up.result"]) assert.equal(starts("", { "needs.fix-ci-rung-up.result": "skipped" }), false, "no rung-up, no rung-up fallback");
    // The handoff job checks out the default branch tip's handoff-evidence.sh
    // and runs it on read-only tokens.
    assert.deepEqual(handoff.needs, ["fix-ci-context", firstId]);
    assertHandoffEvidenceJob(handoff);
    assert.doesNotMatch(JSON.stringify(handoff), /needs\.fix-ci(-rung-up)?\.outputs\./);
    assert.equal(handoff.outputs.posted, "${{ steps.posted.outputs.posted }}");
    const step = handoff.steps[1];
    assert.equal(step.env.CALLS, firstId);
    assert.equal(step.run, "bash .base/.github/scripts/lib/handoff-evidence.sh posted");
    // The first call's report posted: no fallback.
    const posted = readPosted(t, step, jobListing([firstId]));
    assert.equal(posted.status, 0);
    assert.deepEqual(posted.outputs, { posted: "true" });
    assert.match(posted.calls, /^api --paginate repos\/o\/r\/actions\/runs\/99\/jobs\?filter=latest&per_page=100 --jq /);
    // A handoff, forged or not, skips the report job; a report that ran and
    // posted nothing, or another call's posted check, is no post either.
    for (const [name, listing] of Object.entries({
      "a skipped report job": jobListing([], { reportSkipped: [firstId] }),
      "a report that posted nothing": jobListing([]),
      "only other calls posted": jobListing(FIX_CI_CALLS.filter((call) => call !== firstId)),
    })) {
      const read = readPosted(t, step, listing);
      assert.equal(read.status, 0, name);
      assert.equal(read.outputs.posted, "false", `${handoffId}: ${name}`);
    }
    // A failed read fails the job and leaves posted empty.
    const failed = readPosted(t, step, jobListing([firstId]), { fail: true });
    assert.notEqual(failed.status, 0);
    assert.deepEqual(failed.outputs, {});
  }
});

// #8890 for fix-docs: fix-docs's run job is as hostile as fix-ci's, so its
// fallback call starts on fix-docs-handoff's jobs-API read, the same step
// fix-ci-handoff runs, never on a fix-docs output. fix-docs posts nothing on a
// decline (post-decline: false), so the fallback also needs the broker's allow:
// a kill switch or a refusal starts no second leg, and a failed read leaves
// no check, so fix-docs-dispatch.mjs dispatches the PR again.
test("pr-refine.yml: fix-docs-subscription starts on a base job's jobs-API read of fix-docs's report, never on a fix-docs output", (t) => {
  const { jobs } = workflow("pr-refine.yml");
  const sub = jobs["fix-docs-subscription"];
  const handoff = jobs["fix-docs-handoff"];
  assert.ok(handoff, "pr-refine.yml has a fix-docs-handoff job");
  assert.doesNotMatch(sub.if, /needs\.fix-docs\.outputs\./, "the start reads no fix-docs output");
  // The evaluator refuses any reference left unset: the start reads only these.
  const starts = (posted, allowed, result = "success") =>
    evaluate(sub.if, {
      "needs.fix-docs.result": result,
      "needs.fix-docs-handoff.outputs.posted": posted,
      "needs.fix-docs-handoff.outputs.allowed": allowed,
    });
  assert.equal(starts("false", "true"), true, "a handoff after the broker's allow");
  assert.equal(starts("true", "true"), false, "fix-docs posted its check");
  assert.equal(starts("false", "false"), false, "a kill switch or broker refusal");
  assert.equal(starts("", ""), false, "a failed read: no check, so the dispatcher sends the PR again");
  assert.equal(starts("", "", "skipped"), false, "no fix-docs call, no fallback");
  assert.deepEqual(handoff.needs, ["fix-docs-head", "fix-docs"]);
  for (const [result, runs] of [["success", true], ["failure", true], ["skipped", false]]) {
    assert.equal(evaluate(handoff.if, { "needs.fix-docs.result": result }), runs, result);
  }
  assertHandoffEvidenceJob(handoff);
  assert.doesNotMatch(JSON.stringify(handoff), /needs\.fix-docs\.outputs\./);
  assert.deepEqual(handoff.outputs, { posted: "${{ steps.posted.outputs.posted }}", allowed: "${{ steps.posted.outputs.allowed }}" });
  const step = handoff.steps[1];
  assert.equal(step.env.CALLS, "fix-docs");
  // The one read fix-ci-unreported runs, byte for byte.
  assert.equal(step.run, workflow("pr-unblock.yml").jobs["fix-ci-unreported"].steps.find((s) => s.id === "posted").run);
  const listing = ({ posted = false, reportRan = true, allowed = true } = {}) => ({
    jobs: [
      { name: "fix-docs-head", conclusion: "success", steps: [] },
      { name: "fix-docs / broker-check", conclusion: "success", steps: [{ name: "Ask the broker whether the lane may run", conclusion: allowed ? "success" : "skipped" }] },
      { name: "fix-docs / run", conclusion: "success", steps: [{ name: "Post the check run", conclusion: "success" }] },
      {
        name: "fix-docs / report",
        conclusion: reportRan ? "success" : "skipped",
        steps: reportRan ? [{ name: "Post the check run", conclusion: posted ? "success" : "skipped" }] : [],
      },
    ],
  });
  for (const [name, list, outputs] of [
    ["fix-docs posted its check", listing({ posted: true }), { posted: "true", allowed: "true" }],
    ["a handoff skipped the report job", listing({ reportRan: false }), { posted: "false", allowed: "true" }],
    ["the broker allowed nothing", listing({ allowed: false }), { posted: "false", allowed: "false" }],
  ]) {
    const read = readPosted(t, step, list);
    assert.equal(read.status, 0, name);
    assert.deepEqual(read.outputs, outputs, name);
  }
  const failed = readPosted(t, step, listing({ posted: true }), { fail: true });
  assert.notEqual(failed.status, 0);
  assert.deepEqual(failed.outputs, {});
});

// #8890 for fix-docs's push job: patch-state, patch-sha256, patch-attempt,
// reply-attempt and the head came from the run job, which head code can
// forge. Now each comes from the answering leg's scan job, or the head from
// fix-docs-head, as #9363 did for fix-ci's apply-patch.
test("pr-refine.yml: apply-docs-patch reads no read-runner run-job output and takes only the leg that answered", () => {
  const apply = workflow("pr-refine.yml").jobs["apply-docs-patch"];
  const runOutputs = Object.entries(workflow("pr-run-activity-read.yml").on.workflow_call.outputs)
    .filter(([, output]) => /\bjobs\.run\.outputs\./.test(output.value))
    .map(([name]) => name);
  assert.ok(runOutputs.includes("head-sha"), runOutputs.join(" "));
  const read = [...JSON.stringify(apply).matchAll(/needs\.(fix-docs(?:-subscription)?)\.outputs\.([\w-]+)/g)]
    .filter(([, , output]) => runOutputs.includes(output))
    .map(([ref]) => ref);
  assert.deepEqual(read, [], "apply-docs-patch reads no run-job output");
  assert.equal(apply.with["patch-head-sha"], "${{ needs.fix-docs-head.outputs.head-sha }}");
  const runs = (subResult, sub, first) =>
    evaluate(apply.if, {
      "needs.fix-docs-subscription.result": subResult,
      "needs.fix-docs-subscription.outputs.scan-patch-state": sub,
      "needs.fix-docs.outputs.scan-patch-state": first,
    });
  assert.equal(runs("skipped", "", "written"), true, "the key call's patch, its subscription call skipped");
  assert.equal(runs("success", "written", ""), true, "the subscription call's patch after a handoff");
  assert.equal(runs("success", "", "written"), false, "the key call's patch is not taken once the subscription call ran");
  assert.equal(runs("skipped", "", "empty"), false, "no change runs no push job");
  assert.equal(runs("skipped", "", ""), false, "a call that left no patch");
});

// #8890: a round in which no call posted left fix-ci-dispatch.mjs nothing to
// count, so it dispatched the head again with no end.
test("pr-unblock.yml: a fix-ci round with no posted check posts fix-ci failure on the gated head, which fix-ci-dispatch counts toward fix-ci-restarts", (t) => {
  const { jobs } = workflow("pr-unblock.yml");
  const job = jobs["fix-ci-unreported"];
  assert.deepEqual(job.needs, ["fix-ci-context", ...FIX_CI_CALLS]);
  assert.deepEqual(job.permissions, { actions: "read", checks: "write", contents: "read" });
  assert.deepEqual(stepSecrets(job), []);
  for (const [proceed, runs] of [["true", true], ["false", false], ["", false]]) {
    assert.equal(evaluate(job.if, { "needs.fix-ci-context.outputs.proceed": proceed }), runs, JSON.stringify(proceed));
  }
  const checkout = job.steps.find((step) => String(step.uses ?? "").startsWith("actions/checkout@"));
  assert.equal(checkout.with.ref, "${{ github.event.repository.default_branch }}");
  const read = job.steps.find((step) => step.id === "posted");
  const post = job.steps.find((step) => step.name === "Post the check run");
  // The handoff jobs' read, over every call of the round, of both facts.
  assert.equal(read.run, "bash .base/.github/scripts/lib/handoff-evidence.sh posted allowed");
  assert.equal(read.env.CALLS, FIX_CI_CALLS.join(" "));
  // As the report job, it trusts the broker-check job's allow alone: a kill
  // switch (with its repository shadow) or a refusal posts nothing.
  assert.equal(job.steps.find((step) => step.id === "kill"), undefined);
  for (const [name, listing, outputs, posts] of [
    ["every report job skipped after an allow", jobListing([], { reportSkipped: FIX_CI_CALLS }), { posted: "false", allowed: "true" }, true],
    ["the fallback call posted", jobListing(["fix-ci-subscription"]), { posted: "true", allowed: "true" }, false],
    ["the rung-up call posted", jobListing(["fix-ci-rung-up"]), { posted: "true", allowed: "true" }, false],
    ["the broker allowed no call", jobListing([], { unallowed: FIX_CI_CALLS }), { posted: "false", allowed: "false" }, false],
    ["the broker allowed only the fallback call", jobListing([], { unallowed: ["fix-ci", "fix-ci-rung-up", "fix-ci-rung-up-subscription"] }), { posted: "false", allowed: "true" }, true],
  ]) {
    assert.deepEqual(readPosted(t, read, listing).outputs, outputs, name);
    assert.equal(evaluate(post.if, { "steps.posted.outputs.posted": outputs.posted, "steps.posted.outputs.allowed": outputs.allowed }), posts, name);
  }
  assert.equal(evaluate(post.if, { "steps.posted.outputs.posted": "", "steps.posted.outputs.allowed": "" }), false, "a failed read posts nothing");
  // The check it posts, as report-check-run decides it with no verdict.
  assert.equal(post.with["head-sha"], "${{ needs.fix-ci-context.outputs.head-sha }}");
  assert.equal(post.with["verdict-path"], undefined);
  const decision = decide(null, {
    lane: post.with.lane,
    activity: post.with.activity,
    runResult: post.with["run-result"],
    notRunReason: post.with["not-run-reason"] ?? "",
    actOutcome: "",
    signedCommits: null,
    gateReason: "",
    headSha: TRUSTED,
    headShaFallback: TRUSTED,
    prHeadSha: TRUSTED,
    gateSkipReasons: {},
    skipReasons: [],
  });
  assert.deepEqual([decision.report.name, decision.report.head_sha, decision.report.conclusion], ["pr-unblock / fix-ci", TRUSTED, "failure"]);
  // fix-ci-dispatch reads each such post as one failed fix-ci run: with one
  // restart, the third unreported round is never dispatched.
  const node = (rounds) => ({
    number: 9002,
    isDraft: false,
    isCrossRepository: false,
    baseRefName: "main",
    headRefOid: TRUSTED,
    author: { databaseId: 7 },
    labels: { nodes: [] },
    commits: {
      nodes: [
        {
          commit: {
            oid: TRUSTED,
            statusCheckRollup: {
              contexts: {
                nodes: [
                  { name: "ci-status", status: "COMPLETED", conclusion: "FAILURE" },
                  ...Array.from({ length: rounds }, () => ({
                    name: decision.report.name,
                    status: decision.report.status.toUpperCase(),
                    conclusion: decision.report.conclusion.toUpperCase(),
                    title: decision.report.output.title,
                  })),
                ]
                  .map((run) => ({ __typename: "CheckRun", checkSuite: { app: { databaseId: 15368 } }, ...run }))
                  .concat({ __typename: "StatusContext", context: "ci-lanes", state: "FAILURE", creator: { __typename: "Bot", login: "github-actions", databaseId: 41898282 } }),
                pageInfo: { hasNextPage: false },
              },
            },
          },
        },
      ],
    },
  });
  const options = { ...CI_FIX_DEFAULTS, appSenderId: 7, restarts: 1 };
  assert.equal(skipReason(node(0), options), "", "the first dispatch");
  assert.equal(skipReason(node(1), options), "", "one restart");
  assert.equal(skipReason(node(2), options), "head's pr-unblock / fix-ci failed 2 time(s) on this base, past 1 restart(s)");
});

// #8912: a refused collection left patch-state empty, so apply-patch was
// skipped and no person was told.
test("pr-run-activity-read.yml: a collector refusal sets state refused, which the scan job hands on as collect-refused", async (t) => {
  const collect = runSteps().find((step) => step.id === "patch");
  const collectIn = (setup) => {
    const state = plantedCheckout(t);
    setup(state);
    const output = join(state.root, "github-output");
    writeFileSync(output, "");
    const result = runStep(collect, state.work, { HEAD_SHA: state.head, PATCH_DIR: join(state.temp, "patch"), RUNNER_TEMP: state.temp, GITHUB_OUTPUT: output });
    return { status: result.status, outputs: outputLines(output) };
  };
  // A scrub stub name with content is the collector's exit 3; the step still fails.
  assert.deepEqual(collectIn(({ work }) => writeFileSync(join(work, ".env"), "TOKEN=x\n")), { status: 3, outputs: { state: "refused" } });
  assert.deepEqual(collectIn(() => {}), { status: 0, outputs: { state: "empty", sha256: "" } });
  // Any other collector failure is no refusal.
  assert.deepEqual(
    collectIn(({ temp }) => writeFileSync(join(temp, "read-patch", "collect-patch.sh"), "exit 1\n")),
    { status: 1, outputs: {} },
  );
  // The scan job: refused passes the closed set with no patch, and becomes collect-refused.
  const refused = await scanIn(t, { ...runOutputsAfterCarry(t, { "skill-reply/reply.txt": "ok\n" }), "patch-collected": "refused" });
  assert.equal(refused.failed, null);
  assert.deepEqual([refused.outputs["collect-refused"], refused.outputs["patch-state"], refused.outputs.patch], ["true", "", "false"]);
  const empty = await scanIn(t, runOutputsAfterCarry(t, { "skill-reply/reply.txt": "ok\n" }));
  assert.deepEqual([empty.outputs["collect-refused"], empty.outputs["patch-state"]], ["false", "empty"]);
  const { jobs, on } = workflow("pr-run-activity-read.yml");
  for (const value of ["true", "false", ""]) {
    assert.equal(evaluate(jobs.scan.outputs["collect-refused"], { "steps.decode.outputs.collect-refused": value }), value === "true" ? "true" : "");
  }
  assert.equal(on.workflow_call.outputs["scan-collect-refused"].value, "${{ jobs.scan.outputs.collect-refused }}");
});

test("pr-unblock.yml: a refused fix-ci collection runs apply-patch, whose select escalates ci-fix-invalid through report-escalation", () => {
  const { jobs } = workflow("pr-unblock.yml");
  for (const [applyId, firstId, subId] of [
    ["apply-patch", "fix-ci", "fix-ci-subscription"],
    ["apply-patch-rung-up", "fix-ci-rung-up", "fix-ci-rung-up-subscription"],
  ]) {
    const apply = jobs[applyId];
    // Every model-call input is one leg's scan output, never a run job's.
    const outputs = [...JSON.stringify(apply).matchAll(/needs\.fix-ci(?:-rung-up)?(?:-subscription)?\.outputs\.([\w-]+)/g)].map((m) => m[1]);
    assert.deepEqual([...new Set(outputs)].sort(), ["scan-collect-refused", "scan-patch-attempt", "scan-patch-sha256", "scan-patch-state", "scan-reply-attempt"], applyId);
    const leg = (from, values) => {
      const context = { [`needs.${subId}.result`]: from === subId ? "success" : "skipped" };
      for (const job of [subId, firstId]) {
        for (const output of ["scan-patch-state", "scan-collect-refused"]) context[`needs.${job}.outputs.${output}`] = job === from ? (values[output] ?? "") : "";
      }
      return context;
    };
    for (const from of [firstId, subId]) {
      const refused = leg(from, { "scan-collect-refused": "true" });
      assert.equal(evaluate(apply.if, refused), true, `${applyId} after ${from}'s refused collection`);
      assert.equal(evaluate(apply.with["patch-state"], refused), "", "select gets no patch-state");
      // The paired control: a leg that left no patch and refused nothing (a failed model turn) runs no push.
      assert.equal(evaluate(apply.if, leg(from, {})), false, `${applyId} after ${from} left no patch`);
    }
    // The first call's refusal is never taken once the fallback call ran.
    assert.equal(evaluate(apply.if, { ...leg(subId, {}), [`needs.${firstId}.outputs.scan-collect-refused`]: "true" }), false);
  }
  // select, with the empty patch-state a refused collection passes, escalates.
  const row = rowFor(loadRules(fileURLToPath(new URL("../../../", import.meta.url))), { prepare: "ci-context" });
  const decision = selectPatch({ row, patchState: "", patchSha256: "", patchHeadSha: TRUSTED, headSha: TRUSTED, patchDir: "/nonexistent", reportDir: "/nonexistent" });
  assert.deepEqual(decision, { proceed: false, skipReason: "awaiting-human", escalationReason: "ci-fix-invalid" });
  // report-escalation runs on that reason, and on nothing else here.
  const escalation = jobs["report-escalation"];
  const quiet = Object.fromEntries([...escalation.if.matchAll(/needs\.[\w-]+\.(?:outputs\.[\w-]+|result)/g)].map(([ref]) => [ref, ""]));
  assert.equal(evaluate(escalation.if, quiet), false, "nothing to escalate");
  assert.equal(evaluate(escalation.if, { ...quiet, "needs.apply-patch.outputs.escalation-reason": decision.escalationReason }), true);
  assert.match(escalation.with["escalation-reason"], /needs\.apply-patch\.outputs\.escalation-reason/);
});

// #8954, fix-ci's half: the run job binds the head it works on to the head
// the caller gated, before any head code.
test("pr-run-activity-read.yml: a trigger gate that read another head than the caller's fails the run before the head checkout", (t) => {
  const steps = runSteps();
  const check = steps.find((step) => step.name === "Assert the gated head is the caller's");
  assert.ok(steps.indexOf(check) > steps.findIndex((step) => step.id === "gate"));
  assert.ok(steps.indexOf(check) < steps.findIndex((step) => step.name === "Check out the PR head"));
  assert.deepEqual(check.env, { CALLER_HEAD: "${{ inputs.head-sha }}", HEAD_SHA: "${{ steps.gate.outputs.head-sha }}" });
  const runs = (proceed, caller) => atStep(check.if, { "steps.gate.outputs.proceed": proceed, "inputs.head-sha": caller });
  assert.equal(runs("true", TRUSTED), true);
  assert.equal(runs("true", ""), false, "a caller that gated no head, issue mode among them");
  assert.equal(runs("false", TRUSTED), false);
  const root = mkdtempSync(join(tmpdir(), "gated-head-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const moved = runStep(check, root, { CALLER_HEAD: TRUSTED, HEAD_SHA: OTHER });
  assert.equal(moved.status, 1);
  assert.match(moved.stdout, /^::error::the PR head the trigger gate read is not the head the caller gated/m);
  assert.equal(runStep(check, root, { CALLER_HEAD: TRUSTED, HEAD_SHA: TRUSTED }).status, 0);
  // Every fix-ci call passes the head fix-ci-context gated.
  const { jobs } = workflow("pr-unblock.yml");
  for (const id of FIX_CI_CALLS) assert.equal(jobs[id].with["head-sha"], "${{ needs.fix-ci-context.outputs.head-sha }}", id);
});

// --- pr-unblock subscription legs: every start from a trusted value ---

// The read runner's outputs its run job sets. The run job runs head code
// (rule h16), so a caller's start may read none of them.
const RUN_JOB_OUTPUTS = () =>
  Object.entries(workflow("pr-run-activity-read.yml").on.workflow_call.outputs)
    .filter(([, output]) => /\bjobs\.run\.outputs\./.test(output.value))
    .map(([name]) => name);
// #9365: a forged run job could start or suppress a subscription leg.
test("no subscription leg's if: reads a read runner run-job output", () => {
  const runOutputs = RUN_JOB_OUTPUTS();
  assert.ok(["lane-class", "credential-present", "handed-off"].every((name) => runOutputs.includes(name)), runOutputs.join(" "));
  const legs = [];
  for (const file of workflowFiles()) {
    const { jobs } = workflow(file);
    const calls = new Set(Object.entries(jobs ?? {}).filter(([, job]) => job?.uses === READ_RUNNER).map(([id]) => id));
    for (const id of calls) {
      if (jobs[id].with?.fallback === undefined) continue;
      const leg = `${file} ${id}`;
      legs.push(leg);
      const read = [...String(jobs[id].if).matchAll(/needs\.([\w-]+)\.outputs\.([\w-]+)/g)]
        .filter(([, job, output]) => calls.has(job) && runOutputs.includes(output))
        .map(([ref]) => ref);
      assert.deepEqual(read, [], leg);
    }
  }
  assert.deepEqual(legs.sort(), [
    "pr-refine.yml fix-docs-subscription",
    "pr-unblock.yml address-feedback-subscription",
    "pr-unblock.yml fix-ci-rung-up-subscription",
    "pr-unblock.yml fix-ci-subscription",
    "pr-unblock.yml resolve-conflicts-subscription",
    "pr-unblock.yml review-dependency-subscription",
    "work-resolve-issue.yml resolve-issue-subscription",
  ]);
});

// #9365: address-feedback's and review-dependency's fallback calls start as
// fix-ci's do, on a base job's jobs-API read of the first call's report. The
// read runner's report job is one job for every activity: run 39894065797's
// listing names "address-feedback / report" with its "Post the check run"
// step and "address-feedback / broker-check" with its broker step.
test("pr-unblock.yml: address-feedback's, review-dependency's and resolve-conflicts's fallback calls start on a handoff job's jobs-API read, never on a model call's output", (t) => {
  const { jobs } = workflow("pr-unblock.yml");
  const helper = jobs["fix-ci-handoff"].steps[1];
  for (const [firstId, subId, handoffId, selectId] of [
    ["address-feedback", "address-feedback-subscription", "address-feedback-handoff", "address-feedback-select"],
    ["review-dependency", "review-dependency-subscription", "review-dependency-handoff", "review-dependency-select"],
    ["resolve-conflicts", "resolve-conflicts-subscription", "resolve-conflicts-handoff", "resolve-conflicts-select"],
  ]) {
    const sub = jobs[subId];
    const handoff = jobs[handoffId];
    const proceed = `needs.${selectId}.outputs.proceed`;
    // The evaluator refuses any reference left unset: the start reads only these.
    const starts = (posted, proceeds = "true") => evaluate(sub.if, { [proceed]: proceeds, [`needs.${handoffId}.outputs.posted`]: posted });
    assert.equal(starts("false"), true, `${subId} after a call that posted no check`);
    assert.equal(starts(""), true, `${subId} after a failed read: a second leg, never a lost check`);
    assert.equal(starts("true"), false, `${subId} after a call that posted its check`);
    assert.equal(starts("false", "false"), false);
    assert.equal(sub.with.fallback, "handoff");
    // The handoff job: fix-ci-handoff's checkout and read on read-only tokens.
    assert.deepEqual(handoff.needs, [selectId, firstId]);
    assert.equal(evaluate(handoff.if, { [proceed]: "true" }), true);
    assert.equal(evaluate(handoff.if, { [proceed]: "false" }), false);
    assertHandoffEvidenceJob(handoff);
    assert.deepEqual(handoff.outputs, { posted: "${{ steps.posted.outputs.posted }}" });
    assert.deepEqual(stepSecrets(handoff), []);
    assert.doesNotMatch(JSON.stringify(handoff), new RegExp(`needs\\.${firstId}\\.outputs\\.`));
    const step = handoff.steps[1];
    assert.equal(step.uses, undefined);
    assert.equal(step.id, "posted");
    assert.equal(step.run, helper.run, "fix-ci-handoff's read");
    assert.deepEqual(step.env, { GH_TOKEN: "${{ github.token }}", CALLS: firstId });
    // Its read over this lane's calls: the first call's report posted, or not.
    const listing = (posted, options = {}) => jobListing(posted, { calls: [firstId, subId], ...options });
    const read = readPosted(t, step, listing([firstId]));
    assert.equal(read.status, 0);
    assert.equal(read.outputs.posted, "true");
    assert.match(read.calls, /^api --paginate repos\/o\/r\/actions\/runs\/99\/jobs\?filter=latest&per_page=100 --jq /);
    for (const [name, value] of Object.entries({
      "a skipped report job": listing([], { reportSkipped: [firstId] }),
      "a report that posted nothing": listing([]),
      "only the fallback call posted": listing([subId]),
    })) {
      const other = readPosted(t, step, value);
      assert.equal(other.status, 0, name);
      assert.equal(other.outputs.posted, "false", `${handoffId}: ${name}`);
    }
    const failed = readPosted(t, step, listing([firstId]), { fail: true });
    assert.notEqual(failed.status, 0);
    assert.deepEqual(failed.outputs, {});
  }
});

// --- resolve-issue on run-claude-cli: the key call, then the OAuth call on a handoff ---

// A job listing for work-resolve-issue.yml in the shape jobListing above
// takes: `broker` is the first call's broker step conclusion, `run` and
// `scan` its run and scan jobs' conclusions; a scan of null is left out of
// the listing. The subscription call's own jobs are listed too, and no read
// may count them.
function issueListing({ broker = "success", run = "success", scan = "skipped" } = {}) {
  const jobs = [
    { name: "admit", conclusion: "success", steps: [] },
    { name: "resolve-issue / broker-check", conclusion: broker === "failure" ? "failure" : "success", steps: [{ name: "Ask the broker whether the lane may run", conclusion: broker }] },
    { name: "resolve-issue / run", conclusion: run, steps: [] },
    { name: "resolve-issue / issue-fields", conclusion: "success", steps: [] },
    { name: "resolve-issue-subscription / run", conclusion: "success", steps: [] },
    { name: "resolve-issue-subscription / scan", conclusion: "skipped", steps: [] },
  ];
  if (scan !== null) jobs.push({ name: "resolve-issue / scan", conclusion: scan, steps: [] });
  return { total_count: jobs.length, jobs };
}

// Runs the handoff step with a gh stub that answers the listing through the
// step's own --jq filter, as readPosted does.
function readHandoff(t, step, listing, { fail = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), "issue-handoff-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, "bin"));
  writeFileSync(join(root, "listing.json"), JSON.stringify(listing));
  writeFileSync(
    join(root, "bin", "gh"),
    `#!/bin/bash\nprintf '%s\\n' "$*" >>"${join(root, "calls")}"\n${fail ? "exit 1\n" : ""}` +
      `while [ $# -gt 0 ]; do if [ "$1" = --jq ]; then filter=$2; fi; shift; done\njq -r "$filter" "${join(root, "listing.json")}"\n`,
    { mode: 0o755 },
  );
  const output = join(root, "out");
  writeFileSync(output, "");
  const result = runStep(step, root, {
    PATH: `${join(root, "bin")}:${process.env.PATH}`,
    GITHUB_REPOSITORY: "o/r",
    GITHUB_RUN_ID: "99",
    GH_TOKEN: "x",
    GITHUB_OUTPUT: output,
    CALL: step.env.CALL,
  });
  const calls = existsSync(join(root, "calls")) ? readFileSync(join(root, "calls"), "utf8") : "";
  return { status: result.status, outputs: outputLines(output), calls };
}

// The plan's handoff rule (#9624's follow-up, phase 6b): the read runner
// skips the scan job only on a handoff, so the subscription call starts when
// the broker allowed the first call, its run job succeeded, and its scan job
// never ran. A stale-workflow stop, an earlier run's work and a reuse still
// run the scan job, so none of them starts a second call.
test("work-resolve-issue.yml: resolve-issue-subscription starts on resolve-issue-handoff's jobs-API read of a handoff, never on a resolve-issue output", (t) => {
  const { jobs } = workflow("work-resolve-issue.yml");
  const sub = jobs["resolve-issue-subscription"];
  const handoff = jobs["resolve-issue-handoff"];
  assert.doesNotMatch(sub.if, /needs\.resolve-issue\.outputs\./, "the start reads no resolve-issue output");
  const starts = (handedOff, overrides = {}) =>
    evaluate(sub.if, {
      "github.event.label.name": "agent-ready",
      "needs.admit.outputs.proceed": "true",
      "needs.pick-slot.outputs.capped": "false",
      "needs.resolve-issue-handoff.outputs.handed-off": handedOff,
      ...overrides,
    });
  assert.equal(starts("true"), true, "a handoff");
  assert.equal(starts("false"), false, "a call that did the work");
  assert.equal(starts(""), false, "a failed read starts no second call");
  assert.equal(starts("true", { "needs.admit.outputs.proceed": "false" }), false, "an unadmitted label");
  assert.equal(starts("true", { "needs.pick-slot.outputs.capped": "true" }), false, "at the WIP cap");
  assert.equal(sub.with.fallback, "handoff");
  const { fallback, ...same } = sub.with;
  assert.deepEqual(same, jobs["resolve-issue"].with, "the fallback call runs the same activity on the same inputs");
  assert.deepEqual(sub.concurrency, jobs["resolve-issue"].concurrency, "in the same slot");
  // The handoff job: one shell step on a read-only token, no secret, no checkout.
  assert.equal(handoff.needs, "resolve-issue");
  for (const [result, runs] of [["success", true], ["failure", true], ["skipped", false]]) {
    assert.equal(evaluate(handoff.if, { "needs.resolve-issue.result": result }), runs, result);
  }
  assert.deepEqual(handoff.permissions, { actions: "read" });
  assert.deepEqual(handoff.outputs, { "handed-off": "${{ steps.handoff.outputs.handed-off }}" });
  assert.equal(handoff.steps.length, 1);
  assert.equal(handoff.steps[0].uses, undefined);
  assert.deepEqual(stepSecrets(handoff), []);
  assert.doesNotMatch(JSON.stringify(handoff), /needs\.resolve-issue\.outputs\./);
  const step = handoff.steps[0];
  assert.deepEqual(step.env, { GH_TOKEN: "${{ github.token }}", CALL: "resolve-issue" });
  for (const [name, listing, handedOff] of [
    ["a handoff, its scan job listed as skipped", issueListing(), "true"],
    ["a handoff, its scan job not listed", issueListing({ scan: null }), "true"],
    ["a skill run, or a stale-workflow, earlier-work or reuse stop, which still scans", issueListing({ scan: "success" }), "false"],
    ["a scan that failed its leak scan", issueListing({ scan: "failure" }), "false"],
    ["a kill switch, which skips the broker step", issueListing({ broker: "skipped" }), "false"],
    ["a broker refusal, which skips the run job", issueListing({ broker: "failure", run: "skipped" }), "false"],
    ["a run job that failed or timed out", issueListing({ run: "failure", scan: "success" }), "false"],
    ["a cancelled run job", issueListing({ run: "cancelled" }), "false"],
  ]) {
    const read = readHandoff(t, step, listing);
    assert.equal(read.status, 0, name);
    assert.deepEqual(read.outputs, { "handed-off": handedOff }, name);
  }
  assert.match(readHandoff(t, step, issueListing()).calls, /^api --paginate repos\/o\/r\/actions\/runs\/99\/jobs\?filter=latest&per_page=100 --jq /);
  const failed = readHandoff(t, step, issueListing(), { fail: true });
  assert.notEqual(failed.status, 0);
  assert.deepEqual(failed.outputs, {});
});

// The brief's rule: every job references exactly one Claude secret.
test("work-resolve-issue.yml: the key call reads only the API key and the subscription call only the OAuth token", () => {
  const read = [...claudeSecretJobs(["work-resolve-issue.yml"])].map(([key, { names }]) => [key, names]);
  assert.deepEqual(read, [
    ["work-resolve-issue.yml resolve-issue", ["ISSUE_LANE_CLAUDE_API_KEY"]],
    ["work-resolve-issue.yml resolve-issue-subscription", ["ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN"]],
  ]);
});

// One report-outcome and at most one PR per run: every job after the two
// calls takes each resolve-issue value from the call that ran the activity,
// the subscription call when it ran, else the first.
test("work-resolve-issue.yml: every job after the calls takes each resolve-issue value from the call that ran", () => {
  const { jobs } = workflow("work-resolve-issue.yml");
  const after = ["apply-issue-patch", "run-checks", "report-outcome", "report-statuses"];
  for (const id of after) {
    const needs = [jobs[id].needs].flat();
    assert.ok(needs.includes("resolve-issue") && needs.includes("resolve-issue-subscription"), id);
  }
  // Each with or env value that reads the calls, filled from one of them.
  const leg = (from) => (expression) => {
    const context = {};
    for (const [ref, call, rest] of String(expression).matchAll(/needs\.(resolve-issue(?:-subscription)?)\.(result|outputs\.[\w-]+)/g)) {
      if (rest === "result") context[ref] = call === "resolve-issue-subscription" && from === "resolve-issue" ? "skipped" : `${call}-result`;
      else context[ref] = call === from ? `${call}:${rest.slice("outputs.".length)}` : "";
    }
    return evaluate(expression, context);
  };
  let values = 0;
  for (const id of after) {
    const job = jobs[id];
    const entries = [...Object.entries(job.with ?? {}), ...(job.steps ?? []).flatMap((step) => Object.entries(step.env ?? {}))];
    for (const [name, expression] of entries) {
      if (!/needs\.resolve-issue/.test(String(expression))) continue;
      values += 1;
      for (const from of ["resolve-issue", "resolve-issue-subscription"]) {
        const value = leg(from)(expression);
        assert.ok(new RegExp(`^${from}(:|-result$)`).test(value), `${id} ${name} after ${from}: ${value}`);
      }
    }
  }
  assert.ok(values >= 10, `${values} values read`);
  // The started and reuse gates follow the call that ran too.
  const gate = (id, sub, first) =>
    evaluate(jobs[id].if, {
      "needs.resolve-issue-subscription.result": sub === null ? "skipped" : "success",
      "needs.resolve-issue-subscription.outputs.scan-issue-run-started": sub?.started ?? "",
      "needs.resolve-issue-subscription.outputs.scan-outcome-uploaded": sub?.uploaded ?? "",
      "needs.resolve-issue-subscription.outputs.scan-reuse-branch": "",
      "needs.resolve-issue-subscription.outputs.scan-patch-state": sub?.patch ?? "",
      "needs.resolve-issue.outputs.scan-issue-run-started": first.started ?? "",
      "needs.resolve-issue.outputs.scan-outcome-uploaded": first.uploaded ?? "",
      "needs.resolve-issue.outputs.scan-reuse-branch": "",
      "needs.resolve-issue.outputs.scan-patch-state": first.patch ?? "",
    });
  const handedOff = { started: "true" };
  const ran = { started: "true", uploaded: "true", patch: "written" };
  for (const id of after) {
    assert.equal(gate(id, ran, handedOff), true, `${id} after the subscription call ran`);
    assert.equal(gate(id, null, ran), true, `${id} after the first call ran`);
    assert.equal(gate(id, { started: "false" }, ran), false, `${id}: the first call's values are not taken once the subscription call ran`);
  }
});

// The launcher step's timeout and its leg's come from the run job's: 10 and
// 15 minutes under it. PR callers pass 60, which keeps the 50-minute step and
// 45-minute leg they ran on; the issue lane's 65-minute small size gives
// its 50-minute leg.
test("pr-run-activity-read.yml: the launcher step and leg timeouts derive from the run job's timeout", () => {
  const launch = workflow("pr-run-activity-read.yml").jobs.run.steps.find((s) => s.id === "launch");
  assert.equal(launch.env.TIMEOUT, "${{ inputs.timeout-minutes }}");
  const run = (timeout) => {
    const dir = mkdtempSync(join(tmpdir(), "launch-timeout-"));
    const output = join(dir, "out");
    writeFileSync(output, "");
    const result = spawnSync("bash", ["-e", "-c", launch.run], {
      env: { PATH: process.env.PATH, TIMEOUT: timeout, ROLE: "issue-lane", MODEL: "opus", GATING: "advisory", GITHUB_OUTPUT: output },
      encoding: "utf8",
    });
    const outputs = outputLines(output);
    rmSync(dir, { recursive: true, force: true });
    return { status: result.status, outputs };
  };
  assert.deepEqual(run("60").outputs, { "step-minutes": "50", "leg-minutes": "45", "key-name": "ISSUE_LANE_CLAUDE_API_KEY" });
  assert.deepEqual(run("65").outputs, { "step-minutes": "55", "leg-minutes": "50", "key-name": "ISSUE_LANE_CLAUDE_API_KEY" });
  assert.deepEqual(run("100").outputs, { "step-minutes": "90", "leg-minutes": "85", "key-name": "ISSUE_LANE_CLAUDE_API_KEY" });
  for (const timeout of ["15", "0", "", "6x"]) assert.notEqual(run(timeout).status, 0, JSON.stringify(timeout));
});

// Owner decision 2026-10-24: the issue lane runs in dontAsk with an explicit
// allow list, as fix-ci and fix-docs do; the launcher forces default mode, so
// auto is unreachable. Issue mode takes the launcher's inputs check, the
// staging for run-claude-cli, and a fallback only as handoff.
test("pr-run-activity-read.yml: an issue run takes the launcher in dontAsk, and only handoff as its fallback", () => {
  const steps = workflow("pr-run-activity-read.yml").jobs.run.steps;
  const launch = steps.find((s) => s.id === "launch");
  assert.equal(evaluate(launch.if, { "steps.config.outcome": "success", "steps.config.outputs.kind": "skill" }), true, "issue and PR mode alike");
  assert.equal(steps.find((s) => s.id === "stage").with.launcher, "run-claude-cli");
  const config = parse(read("../../../docs/conventions/pr-pipeline.yaml"));
  assert.equal(config.activities["resolve-issue"]["permission-mode"], undefined, "resolve-config's default, dontAsk");
  for (const id of ["act-key", "act-token"]) {
    assert.equal(steps.find((s) => s.id === id).with["permission-mode"], "${{ steps.config.outputs.permission-mode }}", id);
  }
  const first = steps[0];
  const status = (fallback) =>
    spawnSync("bash", ["-c", first.run], {
      env: {
        PATH: process.env.PATH,
        APP_SENDER_ID: "1",
        DEFAULT_BRANCH: "main",
        ISSUE_NUMBER: "7",
        EVENT_NAME: "issues",
        EVENT_ISSUE: "7",
        PR_NUMBER: "",
        DISPATCHER_RUN_ID: "",
        TRUSTED_BASE: "default-tip",
        FALLBACK: fallback,
      },
    }).status;
  assert.equal(status(""), 0);
  assert.equal(status("handoff"), 0);
  for (const fallback of ["credit-stop", "no-key"]) assert.equal(status(fallback), 1, fallback);
});
