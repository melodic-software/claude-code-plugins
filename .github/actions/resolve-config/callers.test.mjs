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
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

import { parse } from "yaml";

import { DEFAULTS as CI_FIX_DEFAULTS, skipReason } from "../../scripts/pr-unblock/fix-ci-dispatch.mjs";
import { main as checkTrustedTrigger } from "../check-trusted-trigger/check-trusted-trigger.mjs";
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
    "steps.leak-scan.outputs.clean": "true",
  };
  const handoffs = {
    "an empty key": { ...base, "steps.key-present.outputs.present": "false", "steps.act-key.outcome": "skipped", "steps.act-key.outputs.lane-class": "" },
    "a credit stop": { ...base, "steps.key-present.outputs.present": "true", "steps.act-key.outcome": "failure", "steps.act-key.outputs.lane-class": "credit-stop" },
  };
  const ran = { ...base, "steps.key-present.outputs.present": "true", "steps.act-key.outcome": "success", "steps.act-key.outputs.lane-class": "" };
  const guarded = run.steps.filter((s) => /^actions\/upload-artifact@|\/report-lane-outcome@/.test(String(s.uses ?? "")) || s.id === "patch");
  assert.deepEqual(
    guarded.map((s) => s.id ?? s.name),
    ["lane-record", "Record the launcher's lane outcome", "patch", "reply-upload", "patch-upload", "Upload the issue outcome", "Upload the verdict"],
  );
  for (const step of guarded) {
    for (const [name, context] of Object.entries(handoffs)) {
      assert.equal(atStep(step.if, context), false, `${step.id ?? step.name} after ${name}`);
    }
  }
  // A PR-mode call that ran uploads its reply, patch and verdict and records its outcome.
  for (const step of guarded.filter((s) => !String(s.if).replace(CLEAN_GATE, "").includes("inputs.issue-number != ''"))) {
    assert.equal(atStep(step.if, ran), true, step.id ?? step.name);
  }
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
const CLEAN_GATE = "(inputs.issue-number != '' || steps.leak-scan.outputs.clean == 'true')";
// Issue-mode steps.
const UNSCANNED = new Set(["Upload the issue outcome", "Check the gate skill's verdict"]);
const writesSummary = (step) => /GITHUB_STEP_SUMMARY|core\.summary/.test(`${step.run ?? ""}${step.with?.script ?? ""}`);

test("pr-run-activity-read.yml: the leak scan runs after the act and collect steps and gates every later upload and summary", () => {
  const steps = runSteps();
  const at = (id) => steps.findIndex((step) => step.id === id);
  const scan = at("leak-scan");
  for (const id of ["act-key", "act-token", "act-turns", "patch"]) {
    assert.ok(at(id) >= 0 && at(id) < scan, `${id} runs before the scan`);
  }
  const outputs = steps.slice(at("act-key")).filter((step) => String(step.uses ?? "").startsWith("actions/upload-artifact@") || writesSummary(step));
  assert.ok(outputs.length >= 3);
  for (const step of outputs.filter((step) => !UNSCANNED.has(step.name))) {
    assert.ok(steps.indexOf(step) > scan, `${step.name} comes after the scan`);
    assert.ok(String(step.if).includes(CLEAN_GATE), `${step.name} needs clean == 'true'`);
  }
  for (const id of ["reply-upload", "patch-upload"]) assert.ok(String(steps[at(id)].if).includes(CLEAN_GATE), id);
  // A hit skips the patch upload, so the run's patch-state is never `written`.
  const { outputs: jobOutputs } = workflow("pr-run-activity-read.yml").jobs.run;
  assert.match(jobOutputs["patch-state"], /^\$\{\{ steps\.patch-upload\.outcome == 'success' && 'written'/);
});

test("pr-run-activity-read.yml: the leak scan loads the publish gate from the API at the base SHA, never from the checkout", () => {
  const step = runSteps().find((s) => s.id === "leak-scan");
  const script = step.with.script;
  assert.equal(step.env.BASE_SHA, "${{ steps.trusted-base.outputs.commit }}");
  assert.match(script, /getContent\(\{ \.\.\.context\.repo, path: 'lib\/publish-gate\.mjs', ref: BASE_SHA \}\)/);
  assert.doesNotMatch(script, /require\(['"]\.|import\(['"]\.|GITHUB_WORKSPACE[^)]*publish-gate|\.base\/|RUNNER_TEMP/);
  assert.match(script, /mkdtempSync/);
  assert.equal(step.env.GITHUB_TOKEN, undefined);
  assert.equal(Object.keys(step.with).toSorted().join(","), "retries,script", "no token input beyond the job's default");
  for (const value of Object.values(step.env)) assert.doesNotMatch(String(value), /secrets\./);
});

const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor;
const KEY = ["sk", "ant", "api03", "x".repeat(40)].join("-");

async function scanWith(t, plant, gate = read("../../../lib/publish-gate.mjs")) {
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
  writeFileSync(join(temp, "patch", "patch.diff"), "diff --git a/x b/x\n");
  writeFileSync(join(temp, "execution.json"), "[]\n");
  plant({ work, temp });
  const outputs = {};
  let failed = null;
  const core = { setOutput: (name, value) => (outputs[name] = value), setFailed: (message) => (failed = message) };
  const github = {
    rest: { repos: { getContent: async ({ ref }) => ({ data: { content: Buffer.from(gate).toString("base64"), ref } }) } },
  };
  const env = {
    BASE_SHA: "b".repeat(40),
    HEAD_SHA: head,
    EXECUTION_FILE: join(temp, "execution.json"),
    REPLY_DIR: join(temp, "skill-reply"),
    PATCH_FILE: join(temp, "patch", "patch.diff"),
    GITHUB_WORKSPACE: work,
    HOME: process.env.HOME,
  };
  const script = runSteps().find((s) => s.id === "leak-scan").with.script;
  const { createRequire } = await import("node:module");
  await new AsyncFunction("require", "core", "github", "context", "process", script)(
    createRequire(import.meta.url),
    core,
    github,
    { repo: { owner: "o", repo: "r" } },
    { env },
  );
  return { clean: outputs.clean, failed };
}

test("leak scan: a clean run is clean", async (t) => {
  assert.deepEqual(await scanWith(t, () => {}), { clean: "true", failed: null });
});

test("leak scan: a key in the reply, in a binary changed file, in an untracked file or in the execution file fails it, naming the pattern and never the key", async (t) => {
  const plants = {
    reply: ({ temp }) => writeFileSync(join(temp, "skill-reply", "reply.txt"), `done ${KEY}\n`),
    "binary changed file": ({ work }) => writeFileSync(join(work, "tracked.txt"), Buffer.concat([Buffer.from([0, 255, 0]), Buffer.from(KEY)])),
    "binary file the index marks assume-unchanged": ({ work }) => {
      writeFileSync(join(work, "tracked.txt"), Buffer.concat([Buffer.from([0, 255, 0]), Buffer.from(KEY)]));
      spawnSync("git", ["update-index", "--assume-unchanged", "tracked.txt"], { cwd: work });
      assert.equal(spawnSync("git", ["diff", "--name-only"], { cwd: work, encoding: "utf8" }).stdout, "", "the real index hides it");
    },
    "untracked file": ({ work }) => writeFileSync(join(work, "new.bin"), Buffer.concat([Buffer.from([0, 1]), Buffer.from(KEY)])),
    "execution file": ({ temp }) => writeFileSync(join(temp, "execution.json"), JSON.stringify([{ type: "user", text: KEY }])),
  };
  for (const [where, plant] of Object.entries(plants)) {
    const { clean, failed } = await scanWith(t, plant);
    assert.equal(clean, "false", where);
    assert.match(failed, /^leak-scan: Anthropic key; .*\nrotate this credential$/, where);
    assert.ok(!failed.includes(KEY), where);
  }
});

test("leak scan: a missing base or head, or a gate that imports beyond node builtins, fails closed", async (t) => {
  const outputs = {};
  let failed = null;
  const { createRequire } = await import("node:module");
  const script = runSteps().find((s) => s.id === "leak-scan").with.script;
  await new AsyncFunction("require", "core", "github", "context", "process", script)(
    createRequire(import.meta.url),
    { setOutput: (name, value) => (outputs[name] = value), setFailed: (message) => (failed = message) },
    {},
    { repo: {} },
    { env: {} },
  );
  assert.equal(outputs.clean, "false");
  assert.match(failed, /no finished scan/);
  // A gate that loads and passes everything, but imports beyond node builtins, is refused.
  const evil = 'import "data:text/javascript,export default 1";\nexport const findSecret = () => null;\n';
  const refused = await scanWith(t, ({ temp }) => writeFileSync(join(temp, "skill-reply", "reply.txt"), "clean\n"), evil);
  assert.equal(refused.clean, "false");
  assert.match(refused.failed, /^leak-scan: no finished scan \(Error\)/);
});
