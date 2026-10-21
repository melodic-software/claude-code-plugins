// The workflows that resolve a model route for a reusable lane. Contract: the
// review callers read the models block from the default branch, never the PR
// head, so a PR cannot choose the model through its own pr-pipeline.yaml
// (the caller workflow itself stays editable in a same-repo PR); a failed resolution
// leaves the review on the reusable's defaults; intake never runs without
// resolved arguments; and each sparse checkout holds what this action loads.
// Also: pr-unblock.yml leaves a publish-feedback check on the head whether or
// not its reply job runs, and a fix-ci check when fix-ci-context skips, and
// work-resolve-issue.yml caps its concurrent runs.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

import { parse } from "yaml";

import { DEFAULTS as CI_FIX_DEFAULTS, skipReason } from "../../scripts/pr-unblock/fix-ci-dispatch.mjs";
import { main as checkTrustedTrigger } from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { generate as generateCarrierKey } from "../open-lane-output/keygen.mjs";
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
  let body = expression.trim().replace(/^\$\{\{([\s\S]*)\}\}$/, "$1").replaceAll("!cancelled()", "true");
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

test("pr-unblock.yml: report-conflict-status runs only for an unresolved-conflict escalation with a gated head", () => {
  const head = "c".repeat(40);
  const { jobs } = workflow("pr-unblock.yml");
  const job = jobs["report-conflict-status"];
  const context = (reason, headSha) => ({
    "needs.resolve-conflicts.outputs.escalation-reason": reason,
    "needs.resolve-conflicts.outputs.head-sha": headSha,
  });
  assert.equal(evaluate(job.if, context("unresolved-conflict", head)), true);
  for (const reason of ["repeat-cap", "protected-path-conflict", "workflow-staged", ""]) {
    assert.equal(evaluate(job.if, context(reason, head)), false, reason);
  }
  assert.equal(evaluate(job.if, context("unresolved-conflict", "")), false, "no gated head to post on");
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

// address-feedback's head-sha output is empty after a gate stop.
test("pr-unblock.yml: publish-feedback is reported neutral when address-feedback ran no feedback round", async () => {
  const head = "c".repeat(40);
  const { jobs } = workflow("pr-unblock.yml");
  const publish = jobs["publish-feedback"];
  const notRun = jobs["publish-feedback-not-run"];
  const context = (round, headSha, activity = "address-feedback") => ({
    "inputs.activity": activity,
    "needs.address-feedback.outputs.feedback-round": round,
    "needs.address-feedback.outputs.head-sha": headSha,
  });
  assert.equal(evaluate(publish.if, context("true", head)), true);
  assert.equal(evaluate(notRun.if, context("true", head)), false);
  assert.equal(evaluate(publish.if, context("false", head)), false);
  assert.equal(evaluate(notRun.if, context("false", head)), true);
  assert.equal(evaluate(notRun.if, context("false", "")), false, "a gate stop gated no head to post on");
  assert.equal(evaluate(notRun.if, context("", "", "resolve-conflicts")), false);

  const calls = await postNotRunCheck(notRun, context("false", head));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, "pr-unblock / publish-feedback");
  assert.equal(calls[0].head_sha, head);
  assert.equal(calls[0].conclusion, "neutral");
  assert.equal(calls[0].output.summary, "Skip reason: not-applicable");
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
  const context = (proceed, escalation, headSha, activity = "fix-ci") => ({
    "inputs.activity": activity,
    "needs.fix-ci-context.outputs.proceed": proceed,
    "needs.fix-ci-context.outputs.escalation-reason": escalation,
    "needs.fix-ci-context.outputs.head-sha": headSha,
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
                  },
                ].map((run) => ({ __typename: "CheckRun", checkSuite: { app: { databaseId: 15368 } }, ...run })),
                pageInfo: { hasNextPage: false },
              },
            },
          },
        },
      ],
    },
  };
  const options = { ...CI_FIX_DEFAULTS, appSenderId, restarts: 1 };
  assert.equal(skipReason(node, options), "head already has a pr-unblock / fix-ci check run");
});

// Runs a not-run job's report-check-run step, its inputs reaching
// report-check-run.mjs through the action's env map; returns the POST bodies.
async function postNotRunCheck(job, context) {
  const action = parse(read("../report-check-run/action.yml"));
  const step = job.steps.find((s) => s.uses === "./.base/.github/actions/report-check-run");
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
  assert.equal(jobs["resolve-issue"].with["timeout-minutes"], "${{ fromJSON(needs.pick-slot.outputs.timeout-minutes || '25') }}");
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
// rule before any model turn and fails red; work-unblock's sweep re-fires a
// failed run that left no outcome marker.
test("pr-run-activity-read.yml: an issue run on stale workflow files fails before any model turn", () => {
  const { jobs } = workflow("pr-run-activity-read.yml");
  const steps = jobs.run.steps;
  const index = (id) => steps.findIndex((step) => step.id === id);
  const check = steps[index("workflow-current")];
  assert.ok(check, "the run job has a workflow-current step");
  assert.ok(index("base") < index("workflow-current"), "it reads the default branch checkout");
  assert.ok(index("workflow-current") < index("issue-prior"));
  assert.ok(index("workflow-current") < index("go"), "it runs before the run decides to start");
  assert.ok(index("go") < index("act-skill"));
  // Every step from the check to the decision runs only while no step failed.
  for (const step of steps.slice(index("workflow-current") + 1, index("go") + 1)) {
    assert.doesNotMatch(String(step.if ?? ""), /always\(\)|failure\(\)|!cancelled\(\)/, step.name);
  }
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
  const runCheck = (sha = run, ref = `melodic-software/claude-code-plugins/${caller}@refs/heads/main`) =>
    spawnSync("bash", ["-c", check.run], {
      cwd: dir,
      encoding: "utf8",
      env: { ...process.env, WORKFLOW_REF: ref, WORKFLOW_SHA: sha },
    });

  assert.equal(runCheck().status, 0, "the run's own commit is main's tip");
  commit({ "README.md": "b\n" });
  assert.equal(runCheck().status, 0, "main moved, but neither workflow file changed");
  commit({ [caller]: "caller 2\n" });
  const callerStale = runCheck();
  assert.equal(callerStale.status, 1, "the caller changed on main");
  assert.match(callerStale.stdout, /::error::workflow-stale: \.github\/workflows\/work-resolve-issue\.yml /);
  const fresh = git("rev-parse", "HEAD");
  assert.equal(runCheck(fresh).status, 0, "a run on main's current files proceeds");
  commit({ [reusable]: "write 2\n" });
  const reusableStale = runCheck(fresh);
  assert.equal(reusableStale.status, 1, "the write runner changed on main");
  assert.match(reusableStale.stdout, /::error::workflow-stale: \.github\/workflows\/pr-run-activity-write\.yml /);

  // A commit or caller this checkout cannot read is left to the broker.
  assert.equal(runCheck("0".repeat(40)).status, 0);
  assert.equal(runCheck("").status, 0);
  assert.equal(runCheck(run, "").status, 0);
});

// The issue lane's model job holds no write token. resolve-issue
// runs on the read runner, whose run job (the one that runs the model) gets
// only the job's read-only GITHUB_TOKEN; the App token is minted only by the
// apply job that commits the patch.
test("work-resolve-issue.yml: the resolve-issue model job receives no App token and no write permission", () => {
  const { jobs } = workflow("work-resolve-issue.yml");
  const resolve = jobs["resolve-issue"];
  assert.equal(resolve.uses, "./.github/workflows/pr-run-activity-read.yml");
  assert.equal(resolve.with.activity, "resolve-issue");
  assert.equal(resolve.with["output-mode"], undefined, "patch mode comes from the activity's applied-by");
  assert.deepEqual(Object.keys(resolve.secrets), ["claude-code-oauth-token"], "only the issue lane's Claude credential");
  assert.equal(resolve.secrets["claude-code-oauth-token"], "${{ secrets.ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN }}");

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
  // The issue skill's step and the launcher steps each name one Claude
  // secret, and nothing else is a secret.
  const secrets = [...text.matchAll(/secrets\.([\w-]+)/g)].map((m) => m[1]);
  assert.deepEqual([...new Set(secrets)].sort(), ["claude-api-key", "claude-code-oauth-token"]);
  const skill = run.steps.find((s) => s.id === "act-skill");
  assert.deepEqual(stepSecrets(skill), ["claude-code-oauth-token"]);
  assert.equal(skill.with.github_token, "${{ github.token }}", "the action gets the job's read-only token only");
  // No job of the read runner holds a write permission but the report job's
  // checks and the broker-check job's id-token, neither of which runs the model.
  for (const [name, job] of Object.entries(read.jobs)) {
    for (const [scope, level] of Object.entries(job.permissions ?? {})) {
      if (level === "write") {
        assert.ok((name === "report" && scope === "checks") || (name === "broker-check" && scope === "id-token"), `${name} ${scope}`);
      }
    }
  }
});

test("work-resolve-issue.yml: apply-issue-patch commits the written patch from the write runner, one per issue at a time", () => {
  const { jobs } = workflow("work-resolve-issue.yml");
  const apply = jobs["apply-issue-patch"];
  assert.equal(apply.uses, "./.github/workflows/pr-run-activity-write.yml");
  assert.equal(apply.needs, "resolve-issue");
  assert.equal(apply.with.activity, "apply-issue-patch");
  assert.equal(apply.with["patch-activity"], "resolve-issue");
  assert.equal(apply.secrets, undefined, "the apply job gets no Claude credential");
  for (const [input, output] of [
    ["patch-state", "patch-state"],
    ["patch-sha256", "patch-sha256"],
    ["patch-attempt", "patch-attempt"],
    ["patch-base-sha", "base-sha"],
    ["patch-resume-tip", "resume-tip"],
  ]) {
    assert.equal(apply.with[input], `\${{ needs.resolve-issue.outputs.${output} }}`, input);
  }
  assert.equal(apply.concurrency.group, "work-resolve-issue-write-${{ github.event.issue.number }}");
  assert.equal(apply.concurrency.queue, "max");
  const runs = (started, state) =>
    evaluate(apply.if, { "needs.resolve-issue.outputs.issue-run-started": started, "needs.resolve-issue.outputs.patch-state": state });
  assert.equal(runs("true", "written"), true);
  assert.equal(runs("true", "empty"), false, "an empty patch makes no branch");
  assert.equal(runs("true", ""), false);
  assert.equal(runs("false", "written"), false);
  for (const job of ["run-checks", "report-outcome"]) {
    assert.ok(jobs[job].needs.includes("apply-issue-patch"), `${job} waits for the branch`);
  }
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
  assert.deepEqual(guarded.map(([id]) => id), ["resolve-issue"]);
  for (const [id, job] of [...guarded, ["pick-slot", jobs["pick-slot"]]]) {
    assert.ok(needsOf(jobs, id).has("admit"), `${id} needs admit`);
    assert.ok(String(job.if).includes(ADMITTED), `${id} requires the gate's proceed`);
    const context = {
      "github.event.label.name": "agent-ready",
      "needs.admit.outputs.proceed": "true",
      "needs.pick-slot.outputs.capped": "false",
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

test("every read-runner caller job passes exactly one Claude secret, named for its role", () => {
  const callers = [];
  for (const file of workflowFiles()) {
    for (const [id, job] of Object.entries(workflow(file).jobs ?? {})) {
      if (job?.uses !== READ_RUNNER) continue;
      callers.push(`${file} ${id}`);
      const names = Object.keys(job.secrets ?? {});
      assert.equal(names.length, 1, `${file} ${id} passes ${names.join(", ")}`);
      const [name] = names;
      assert.ok(Object.hasOwn(CLAUDE_SECRETS, name), `${file} ${id} passes ${name}`);
      assert.match(job.with.role, /^[a-z][a-z0-9-]*$/, `${file} ${id} names a role`);
      const role = job.with.role.toUpperCase().replaceAll("-", "_");
      assert.equal(job.secrets[name], `\${{ secrets.${role}_${CLAUDE_SECRETS[name]} }}`, `${file} ${id}`);
      assert.equal(job.with["output-mode"], undefined, `${file} ${id}: patch mode comes from the activity's applied-by`);
    }
  }
  assert.deepEqual(callers.sort(), ["pr-unblock.yml fix-ci", "pr-unblock.yml fix-ci-subscription", "work-resolve-issue.yml resolve-issue"]);
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
  const launcher = "melodic-software/ci-workflows/.github/actions/run-claude-cli@7b362428c76085a160e28656cd2c75c3147a69ff";
  for (const [id, input, secret] of [
    ["act-key", "api-key", "claude-api-key"],
    ["act-token", "subscription-token", "claude-code-oauth-token"],
  ]) {
    const launch = step(id);
    assert.equal(launch.uses, launcher, id);
    assert.deepEqual(stepSecrets(launch), [secret], id);
    assert.equal(launch.with[input], `\${{ secrets.${secret} }}`, id);
    assert.equal(launch.with[input === "api-key" ? "subscription-token" : "api-key"], undefined, id);
    assert.equal(launch.with["permission-mode"], "dontAsk", id);
    assert.equal(launch["continue-on-error"], true, id);
    assert.equal(launch["timeout-minutes"], 50, id);
    assert.equal(launch.with["leg-timeout-minutes"], "45", id);
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
    "steps.act-skill.outcome": "skipped",
    "steps.act-token.outcome": "skipped",
    "steps.token-present.outcome": "skipped",
    "steps.token-present.outputs.present": "",
    "steps.key-present.outcome": "success",
    "steps.patch.outputs.state": "written",
  };
  const handoffs = {
    "an empty key": { ...base, "steps.key-present.outputs.present": "false", "steps.act-key.outcome": "skipped", "steps.act-key.outputs.lane-class": "" },
    "a credit stop": { ...base, "steps.key-present.outputs.present": "true", "steps.act-key.outcome": "failure", "steps.act-key.outputs.lane-class": "credit-stop" },
  };
  const ran = { ...base, "steps.key-present.outputs.present": "true", "steps.act-key.outcome": "success", "steps.act-key.outputs.lane-class": "" };
  const guarded = run.steps.filter((s) => /^actions\/upload-artifact@|\/report-lane-outcome@/.test(String(s.uses ?? "")) || s.id === "patch");
  assert.deepEqual(
    guarded.map((s) => s.id ?? s.name),
    ["lane-record", "Record the launcher's lane outcome", "patch", "reply-upload", "patch-upload", "Upload the issue outcome"],
  );
  for (const step of guarded) {
    for (const [name, context] of Object.entries(handoffs)) {
      assert.equal(atStep(step.if, context), false, `${step.id ?? step.name} after ${name}`);
    }
  }
  // A PR-mode call that ran collects its patch and records its outcome; its uploads are the scan job's.
  for (const step of guarded.filter((s) => !String(s.if).includes("inputs.issue-number != ''"))) {
    assert.equal(atStep(step.if, ran), true, step.id ?? step.name);
  }
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
  assert.equal(handedOff({ "steps.key-present.outputs.present": "", "steps.act-key.outputs.lane-class": "" }), false, "the fallback call never hands off");
  assert.equal(handedOff({ ...ran, "steps.act-key.outcome": "failure", "steps.act-key.outputs.lane-class": "rate-limit" }), false);

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
  assert.equal(atStep(fail.if, { ...ran, "steps.act-key.outcome": "failure", "steps.act-key.outputs.lane-class": "max-turns" }), true);
  const noToken = {
    ...base,
    "inputs.fallback": "credit-stop",
    "steps.key-present.outcome": "skipped",
    "steps.key-present.outputs.present": "",
    "steps.act-key.outcome": "skipped",
    "steps.act-key.outputs.lane-class": "",
    "steps.token-present.outcome": "success",
    "steps.token-present.outputs.present": "false",
  };
  assert.equal(atStep(fail.if, noToken), true, "an empty token on the fallback call fails red");
  assert.equal(spawnSync("bash", ["-c", fail.run]).status, 1);
});

test("pr-run-activity-read.yml: the fallback call's lane record names why it ran", () => {
  const { jobs } = workflow("pr-run-activity-read.yml");
  const record = jobs.run.steps.find((s) => s.name === "Record the launcher's lane outcome");
  const lane = (fallback) =>
    atStep(
      record.with.lane.replace(/format\('([^']*)', inputs\.lane, inputs\.activity(?:, steps\.launch\.outputs\.key-name)?\)/g, (_, text) =>
        JSON.stringify(text.replace("{0}", "pr-unblock").replace("{1}", "fix-ci").replace("{2}", "AUTOMATIONS_CLAUDE_API_KEY")),
      ),
      { "inputs.fallback": fallback },
    );
  assert.equal(lane(""), "pr-unblock/fix-ci");
  assert.equal(lane("credit-stop"), "pr-unblock/fix-ci (key AUTOMATIONS_CLAUDE_API_KEY hit a credit stop)");
  assert.equal(lane("no-key"), "pr-unblock/fix-ci (key AUTOMATIONS_CLAUDE_API_KEY is empty)");
  assert.equal(record.with["step-timeout-minutes"], 50, "the launcher step's timeout");
});

test("pr-unblock.yml: fix-ci-subscription runs only on fix-ci's credit stop or empty key and reads only those two outputs", () => {
  const { jobs } = workflow("pr-unblock.yml");
  const first = jobs["fix-ci"];
  const sub = jobs["fix-ci-subscription"];
  assert.deepEqual(sub.needs, ["fix-ci-context", "fix-ci"]);
  assert.equal(sub.uses, READ_RUNNER);
  assert.deepEqual(first.secrets, { "claude-api-key": "${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}" });
  assert.deepEqual(sub.secrets, { "claude-code-oauth-token": "${{ secrets.AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN }}" });
  assert.equal(first.with.role, "automations");
  assert.equal(first.with.fallback, undefined);
  const { fallback, ...same } = sub.with;
  assert.deepEqual(same, first.with, "the fallback call runs the same activity on the same inputs");
  // fix-ci's outputs reach the fallback call only through two exact compares.
  const text = JSON.stringify(sub);
  const compares = [...text.matchAll(/needs\.fix-ci\.outputs\.([\w-]+) == '([^']*)'/g)].map((m) => `${m[1]} == ${m[2]}`);
  assert.deepEqual([...new Set(compares)].sort(), ["credential-present == false", "lane-class == credit-stop"]);
  assert.doesNotMatch(text.replace(/needs\.fix-ci\.outputs\.(lane-class == 'credit-stop'|credential-present == 'false')/g, ""), /needs\.fix-ci\.outputs\./);
  const runs = (proceed, laneClass, present) =>
    evaluate(sub.if, {
      "needs.fix-ci-context.outputs.proceed": proceed,
      "needs.fix-ci.outputs.lane-class": laneClass,
      "needs.fix-ci.outputs.credential-present": present,
    });
  assert.equal(runs("true", "credit-stop", "true"), true);
  assert.equal(runs("true", "", "false"), true);
  for (const laneClass of ["", "rate-limit", "max-turns", "timeout", "other", "credit-stop "]) {
    assert.equal(runs("true", laneClass, "true"), false, JSON.stringify(laneClass));
  }
  assert.equal(runs("true", "", ""), false, "a fix-ci that stopped before its credential step");
  assert.equal(runs("false", "credit-stop", "true"), false);
  assert.equal(evaluate(fallback, { "needs.fix-ci.outputs.lane-class": "credit-stop" }), "credit-stop");
  assert.equal(evaluate(fallback, { "needs.fix-ci.outputs.lane-class": "" }), "no-key");
  // No run: script in the lane reads fix-ci's outputs.
  for (const [id, job] of Object.entries(jobs)) {
    for (const step of job.steps ?? []) {
      assert.doesNotMatch(String(step.run ?? ""), /needs\.fix-ci\.outputs\./, `${id} ${step.name}`);
    }
  }
  // Both calls and the push job queue in the per-PR write group, never cancelled.
  for (const id of ["fix-ci", "fix-ci-subscription", "apply-patch"]) {
    assert.deepEqual(jobs[id].concurrency, { group: "pr-pipeline-write-${{ inputs.pr-number }}", queue: "max" }, id);
  }
  assert.equal(first.with["timeout-minutes"], 60, "the run job holds the 50-minute launcher step");
});

test("pr-run-activity-write.yml passes the producer's prepare mode to both apply-patch steps, and pr-unblock names fix-ci's", () => {
  const { jobs } = workflow("pr-run-activity-write.yml");
  const steps = Object.values(jobs).flatMap((job) => job.steps ?? []);
  for (const name of ["Select the patch", "Run the script activity"]) {
    const step = steps.find((candidate) => candidate.name === name);
    assert.ok(step, name);
    assert.equal(step.env.PATCH_PREPARE, "${{ inputs.patch-prepare }}", `${name} sets PATCH_PREPARE, or apply-patch.mjs uses the default row`);
  }
  const config = parse(read("../../../docs/conventions/pr-pipeline.yaml"));
  const prepare = config.activities["fix-ci"].prepare;
  assert.equal(prepare, "ci-context");
  assert.equal(workflow("pr-unblock.yml").jobs["apply-patch"].with["patch-prepare"], prepare);
});

test("pr-unblock.yml: apply-patch takes the patch from whichever fix-ci call ran the activity", () => {
  const { jobs } = workflow("pr-unblock.yml");
  const apply = jobs["apply-patch"];
  assert.deepEqual(apply.needs, ["fix-ci", "fix-ci-subscription"]);
  assert.equal(apply.uses, "./.github/workflows/pr-run-activity-write.yml");
  assert.equal(apply.with.activity, "apply-patch");
  assert.equal(apply.with["patch-activity"], "fix-ci");
  assert.equal(apply.secrets, undefined, "the push job gets no Claude credential");
  const outputs = { "patch-state": "patch-state", "patch-sha256": "patch-sha256", "patch-attempt": "patch-attempt", "reply-attempt": "reply-attempt", "patch-head-sha": "head-sha" };
  const context = (from) => {
    const values = {};
    for (const job of ["fix-ci-subscription", "fix-ci"]) {
      for (const output of Object.values(outputs)) {
        values[`needs.${job}.outputs.${output}`] = job === from ? `${job}:${output}` : "";
      }
    }
    return values;
  };
  for (const from of ["fix-ci", "fix-ci-subscription"]) {
    for (const [input, output] of Object.entries(outputs)) {
      assert.equal(evaluate(apply.with[input], context(from)), `${from}:${output}`, `${input} after ${from}`);
    }
  }
  const runs = (first, second) =>
    evaluate(apply.if, { "needs.fix-ci-subscription.outputs.patch-state": second, "needs.fix-ci.outputs.patch-state": first });
  assert.equal(runs("written", ""), true);
  assert.equal(runs("", "written"), true);
  assert.equal(runs("", "empty"), true, "an empty patch hands the PR to a person");
  assert.equal(runs("", ""), false, "a handoff whose fallback call left no patch");
  assert.ok(jobs["report-escalation"].needs.includes("apply-patch"));
  for (const need of jobs["report-escalation"].needs) assert.ok(Object.hasOwn(jobs, need), `report-escalation needs ${need}, a job of the file`);
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
  assert.ok(index((s) => s === guard) < index((s) => s.id === "act-skill"));
});

// --- the PR-mode leak scan, before any upload or summary ---

const runSteps = () => workflow("pr-run-activity-read.yml").jobs.run.steps;
const scanSteps = () => workflow("pr-run-activity-read.yml").jobs.scan.steps;
const writesSummary = (step) => /GITHUB_STEP_SUMMARY|core\.summary/.test(`${step.run ?? ""}${step.with?.script ?? ""}`);
const isUpload = (step) => String(step.uses ?? "").startsWith("actions/upload-artifact@");

test("pr-run-activity-read.yml: in PR mode the model job uploads nothing and writes no step summary", () => {
  const steps = runSteps();
  const out = steps.filter((step) => isUpload(step) || writesSummary(step));
  assert.ok(out.length >= 4, out.map((s) => s.name).join(", "));
  // claude-code-action runs only in issue mode, so a PR run's act-skill is skipped.
  const actSkill = steps.find((s) => s.id === "act-skill");
  assert.equal(atStep(actSkill.if, prRun(actSkill.if, { "steps.config.outputs.kind": "skill" })), false);
  for (const step of out) {
    // Under every PR-mode context, the step stays off.
    const pr = [{}, { "steps.act-key.outcome": "failure" }, { "steps.act-key.outcome": "skipped", "steps.act-token.outcome": "success" }, { "steps.config.outputs.gating": "gate" }];
    for (const overrides of pr) {
      assert.equal(atStep(step.if, prRun(step.if, overrides)), false, `${step.name} ${JSON.stringify(overrides)}`);
    }
  }
  // The leak scan and the verdict are the scan job's alone.
  for (const step of steps) {
    assert.notEqual(step.id, "leak-scan");
    assert.doesNotMatch(String(step.with?.name ?? ""), /^verdict-/, step.name);
    assert.doesNotMatch(String(step.run ?? ""), /verdict\.json/, step.name);
  }
});

test("pr-run-activity-read.yml: the scan job holds only the scan-carrier key, in its decode step, under its environment, with no id-token, no cache and no artifact from the run job", () => {
  const { jobs } = workflow("pr-run-activity-read.yml");
  const scan = jobs.scan;
  assert.equal(scan["runs-on"], "ubuntu-24.04");
  assert.equal(scan.needs, "run");
  assert.deepEqual(scan.permissions, { contents: "read" });
  assert.equal(scan.environment, "pr-pipeline-scan-carrier");
  assert.deepEqual(stepSecrets(scan), ["SCAN_CARRIER_PRIVATE_KEY"], "the one secret in the job");
  assert.deepEqual(scan.steps.filter((step) => stepSecrets(step).length > 0).map((step) => step.id), ["open"], "read in the decode step alone");
  assert.doesNotMatch(JSON.stringify(scan), /id-token|ACTIONS_ID_TOKEN/);
  // The one action from a checkout is the opener, from the run job's base SHA.
  const base = scan.steps.find((step) => step.id === "base");
  assert.deepEqual([base.with.ref, base.with.path, base.with["persist-credentials"]], ["${{ needs.run.outputs.base-sha }}", ".base", false]);
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
  assert.deepEqual(["base", "key", "open", "decode"].map(at), [0, 1, 2, 3]);
  assert.ok(at("decode") < scan);
  const outputs = steps.filter((step) => (isUpload(step) && !String(step.with.name).startsWith("verdict-")) || writesSummary(step));
  assert.equal(outputs.length, 3);
  const context = (clean) => ({ "steps.leak-scan.outputs.clean": clean, "steps.decode.outputs.reply": "true", "steps.decode.outputs.patch": "true" });
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
  assert.equal(step("Check out the gated head").if, "steps.decode.outputs.patch == 'true'");
  // Nothing sealed: no base checkout, no key read and no open.
  const base = steps.find((s) => s.id === "base");
  assert.equal(atStep(base.if, { ...stopped, "needs.run.outputs.carry-sealed-length": "" }), false);
  assert.equal(atStep(base.if, { ...stopped, "needs.run.outputs.go": "true", "needs.run.outputs.carry-sealed-length": "" }), false);
  assert.equal(atStep(base.if, { ...stopped, "needs.run.outputs.go": "true", "needs.run.outputs.carry-sealed-length": "100" }), true);
  for (const id of ["key", "open"]) assert.equal(steps.find((s) => s.id === id).if, "steps.base.outcome == 'success'", id);
});

test("pr-run-activity-read.yml: the leak scan loads the publish gate from the API at the base SHA, never from the checkout", () => {
  const step = scanSteps().find((s) => s.id === "leak-scan");
  const script = step.with.script;
  // The run job's base, from its trusted-base step before any head code.
  assert.equal(step.env.BASE_SHA, "${{ needs.run.outputs.base-sha }}");
  assert.equal(workflow("pr-run-activity-read.yml").jobs.run.outputs["base-sha"], "${{ steps.trusted-base.outputs.commit }}");
  assert.match(script, /getContent\(\{ \.\.\.context\.repo, path: 'lib\/publish-gate\.mjs', ref: BASE_SHA \}\)/);
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
async function scanWith(t, plant, gate = read("../../../lib/publish-gate.mjs"), { afterCollect = () => {}, headRepo = (work) => work } = {}) {
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
  const outputs = {};
  let failed = null;
  const warnings = [];
  const core = { setOutput: (name, value) => (outputs[name] = value), setFailed: (message) => (failed = message), warning: (message) => warnings.push(message) };
  const github = {
    rest: {
      repos: {
        getContent: async ({ owner, repo, path: file, ref }) => {
          assert.deepEqual({ owner, repo, file, ref }, { owner: "o", repo: "r", file: "lib/publish-gate.mjs", ref: "b".repeat(40) }, "the gate at the base SHA only");
          return { data: { content: Buffer.from(gate).toString("base64") } };
        },
      },
    },
  };
  const env = {
    BASE_SHA: "b".repeat(40),
    HEAD_SHA: head,
    REPLY_DIR: join(temp, "skill-reply"),
    PATCH_FILE: join(temp, "patch", "patch.diff"),
    GITHUB_WORKSPACE: headRepo(work, root),
    HOME: process.env.HOME,
  };
  const script = scanSteps().find((s) => s.id === "leak-scan").with.script;
  const { createRequire } = await import("node:module");
  await new AsyncFunction("require", "core", "github", "context", "process", script)(
    createRequire(import.meta.url),
    core,
    github,
    { repo: { owner: "o", repo: "r" } },
    { env },
  );
  return { clean: outputs.clean, failed, work, temp, warnings, outputs };
}

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

test("leak scan: a missing base or head, or a gate that imports beyond node builtins, fails closed", async (t) => {
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
  assert.equal(runs({ "inputs.issue-number": "7" }), false, "issue mode is unchanged");
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
const CARRIER_SECRET = "${{ secrets.SCAN_CARRIER_PRIVATE_KEY }}";
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
function carry(t, files, { publicLine = CARRIER.publicLine } = {}) {
  const root = mkdtempSync(join(tmpdir(), "carry-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const temp = join(root, "temp");
  const workspace = join(root, "workspace");
  for (const dir of ["skill-reply", "patch", "seal-lane-output"]) mkdirSync(join(temp, dir), { recursive: true });
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
  // The committed key file, until the owner runs keygen: the seal step fails and carries nothing.
  const placeholder = carry(t, { "skill-reply/reply.txt": "x\n" }, { publicLine: read("../../lane-keys/scan-carrier.pub") });
  assert.equal(placeholder.seal.status, 1);
  assert.match(placeholder.log, /^::error::seal-lane-output: the public key file holds no x25519 key line/m);
  assert.deepEqual(placeholder.seal.outputs, {});
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
  const values = { "runner.temp": temp, "steps.key.outputs.id": CARRIER.keyId, "secrets.SCAN_CARRIER_PRIVATE_KEY": privateText };
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
function decodeEnv(runOutputs, inputs = { "issue-number": "" }, open = { status: 1, ran: false }) {
  const step = scanSteps().find((s) => s.id === "decode");
  const env = {};
  for (const [name, expression] of Object.entries(step.env)) {
    const output = OUTPUT_EXPRESSION.exec(expression);
    const input = /^\$\{\{ inputs\.([\w-]+) \}\}$/.exec(expression);
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
function runOutputsAfterCarry(t, files) {
  const { outputs, seal } = carry(t, files);
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

test("scan job: a re-run at another attempt of the same run opens; a bundle from another run, or opened with another key, fails closed without rotation", async (t) => {
  const outputs = runOutputsAfterCarry(t, { "skill-reply/reply.txt": "done\n" });
  const rerun = await scanIn(t, outputs, { runAttempt: "2" });
  assert.equal(rerun.open.status, 0, rerun.open.log);
  assert.deepEqual(rerun.files, { "reply.txt": Buffer.from("done\n") });
  for (const [name, options] of Object.entries({ "another run": { runId: "78" }, "another key": { privateText: generateCarrierKey().privateText }, "no key": { privateText: "" } })) {
    const { open } = await scanIn(t, outputs, options);
    assert.equal(open.status, 1, name);
    assert.match(open.log, /^::error::(sealed-mismatch|no-key): /m, name);
    assert.doesNotMatch(open.log, /rotate/, name);
    assert.equal(open.dir, "", name);
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

test("pr-run-activity-read.yml: the scan-carrier key is named once in the repository's workflows, as the scan job's open step's private-key, and its environment on that job alone", () => {
  const files = workflowFiles();
  const named = files.filter((file) => read(`../../workflows/${file}`).includes("SCAN_CARRIER_PRIVATE_KEY"));
  assert.deepEqual(named, ["pr-run-activity-read.yml"]);
  assert.equal(read("../../workflows/pr-run-activity-read.yml").split("SCAN_CARRIER_PRIVATE_KEY").length - 1, 2, "the step and the keygen line in the scan job's header comment");
  const { jobs } = workflow("pr-run-activity-read.yml");
  for (const [id, job] of Object.entries(jobs)) {
    const steps = (job.steps ?? []).filter((step) => JSON.stringify(step).includes("SCAN_CARRIER_PRIVATE_KEY"));
    assert.equal(steps.length, id === "scan" ? 1 : 0, id);
  }
  const open = jobs.scan.steps.find((s) => s.id === "open");
  assert.deepEqual(stepSecrets(open), ["SCAN_CARRIER_PRIVATE_KEY"]);
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

test("pr-run-activity-read.yml: the patch and reply outputs come from the scan job in PR mode and the run job in issue mode, and every caller's reads resolve", () => {
  const read = workflow("pr-run-activity-read.yml");
  const outputs = read.on.workflow_call.outputs;
  for (const name of ["patch-state", "patch-sha256", "patch-attempt", "reply-attempt"]) {
    assert.equal(outputs[name].value, `\${{ jobs.scan.outputs.${name} || jobs.run.outputs.${name} }}`, name);
    assert.ok(Object.hasOwn(read.jobs.scan.outputs, name) && Object.hasOwn(read.jobs.run.outputs, name), name);
  }
  // In PR mode the run job's own patch outputs stay empty, so the scan job's alone count.
  const runPatchState = read.jobs.run.outputs["patch-state"];
  assert.equal(atStep(runPatchState, prRun(runPatchState, { "steps.patch-upload.outcome": "skipped", "steps.patch.outputs.state": "empty" })), "");
  for (const id of ["patch-upload", "reply-upload"]) {
    const step = read.jobs.run.steps.find((s) => s.id === id);
    assert.equal(atStep(step.if, prRun(step.if, { "steps.patch.outputs.state": "written", "steps.act-key.outcome": "success" })), false, id);
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
    evaluate(post.with["run-result"], { "needs.broker-check.result": broker, "needs.run.result": run, "needs.scan.result": scan });
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
  // the pinned 7b362428. cant-fail-ok: an external contract's value list.
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
