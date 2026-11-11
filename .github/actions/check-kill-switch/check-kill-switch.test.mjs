import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { budgetStops, checkBudget, checkKillSwitch, main, startGateShare, writeOutputs } from "./check-kill-switch.mjs";
import { readOutputs } from "./fixtures/read-outputs.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const SCRIPT = fileURLToPath(new URL("./check-kill-switch.mjs", import.meta.url));
const WORKFLOWS = fileURLToPath(new URL("../../workflows/", import.meta.url));

// 2026-11-11T12:00:00Z.
const NOW_MS = Date.parse("2026-11-11T12:00:00Z");
const NOW_S = NOW_MS / 1000;
const RESET = NOW_S + 1200;

function runCli(env, script = SCRIPT) {
  const dir = tempDir("kill-switch-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    const result = spawnSync(process.execPath, [script], {
      env: { PATH: process.env.PATH, GITHUB_OUTPUT: outputPath, ...env },
      encoding: "utf8",
    });
    return { status: result.status, stdout: result.stdout, outputs: readOutputs(readFileSync(outputPath, "utf8")) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// A GET /rate_limit answer in the shape GitHub's REST docs give: a body with
// resources.core, and x-ratelimit-* headers on the response.
function rateLimitResponse({ headers = {}, core = null, status = 200 } = {}) {
  const body = core ? { resources: { core }, rate: core } : {};
  return new Response(JSON.stringify(body), { status, headers });
}

function recordingFetch(answer) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    if (answer instanceof Error) throw answer;
    return typeof answer === "function" ? answer() : answer;
  };
  return { calls, fetchImpl };
}

const headersOf = (limit, remaining, reset) => ({
  "x-ratelimit-limit": String(limit),
  "x-ratelimit-remaining": String(remaining),
  "x-ratelimit-reset": String(reset),
  "x-ratelimit-used": String(limit - remaining),
  "x-ratelimit-resource": "core",
});

test("proceeds only when the org and the repository switch both read exactly false", () => {
  assert.deepEqual(checkKillSwitch("false", "false"), { proceed: "true", reason: "ok", cause: "ok" });
});

const NOT_FALSE = [
  ["unset", undefined],
  ["empty", ""],
  ["true", "true"],
  ["FALSE in capitals", "FALSE"],
  ["false with whitespace", " false"],
  ["a timed value", "true@2026-11-11T11:00:00Z"],
];

for (const [label, value] of NOT_FALSE) {
  test(`stops when the org switch is ${label}, whatever the repository switch`, () => {
    for (const repo of ["false", "true", undefined]) {
      assert.deepEqual(checkKillSwitch(value, repo), { proceed: "false", reason: "kill-switch", cause: "switch" });
    }
  });

  test(`stops when the repository switch is ${label} and the org switch is false`, () => {
    assert.deepEqual(checkKillSwitch("false", value), { proceed: "false", reason: "kill-switch", cause: "switch" });
  });
}

// share 0.1 of a limit of 5000 is 500.
test("the budget stops under the share of the limit while the reset is ahead", () => {
  const at = (remaining, reset = RESET) => budgetStops({ limit: 5000, remaining, reset }, 0.1, NOW_S);
  assert.equal(at(499), true, "499 left, under 500");
  assert.equal(at(0), true, "nothing left");
  assert.equal(at(500), false, "500 left, at the share");
  assert.equal(at(501), false, "501 left");
  assert.equal(at(10, NOW_S), false, "reset now");
  assert.equal(at(10, NOW_S - 1), false, "reset already past");
  assert.equal(budgetStops({ limit: 5000, remaining: 0, reset: RESET }, 0, NOW_S), false, "share 0 is off");
  assert.equal(budgetStops({ limit: Number.NaN, remaining: 0, reset: RESET }, 0.1, NOW_S), false, "no limit");
});

test("the budget read decides from the headers when they carry limit, remaining and reset", async () => {
  // The body has plenty left; the headers, which GitHub says win, do not.
  const answer = rateLimitResponse({ headers: headersOf(5000, 499, RESET), core: { limit: 5000, remaining: 4000, reset: RESET, used: 1000 } });
  const { calls, fetchImpl } = recordingFetch(answer);
  const result = await checkBudget({ token: "t", api: "https://api.example", share: 0.1, now: NOW_S, fetchImpl });
  assert.equal(result.stop, true);
  assert.equal(result.reset, RESET);
  assert.equal(calls.length, 1, "exactly one call");
  assert.equal(calls[0].url, "https://api.example/rate_limit");
  assert.equal(calls[0].init.headers.Authorization, "Bearer t");
  assert.equal(
    result.line,
    `::notice title=start-gate::github-token start-gate=0.1 decided from headers: limit=5000 remaining=499 reset=${RESET} stop=true; ` +
      `body core limit=5000 remaining=4000 reset=${RESET} used=1000; headers limit=5000 remaining=499 reset=${RESET} used=4501 resource=core`,
  );
});

test("the budget read proceeds at the share and above it", async () => {
  for (const remaining of [500, 501]) {
    const { fetchImpl } = recordingFetch(rateLimitResponse({ headers: headersOf(5000, remaining, RESET) }));
    const result = await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl });
    assert.equal(result.stop, false, `${remaining} left`);
    assert.match(result.line, /^::notice title=start-gate::.* stop=false; body core absent; /);
  }
});

test("the budget read proceeds when the reset is already past", async () => {
  const { fetchImpl } = recordingFetch(rateLimitResponse({ headers: headersOf(5000, 3, NOW_S - 5) }));
  assert.equal((await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl })).stop, false);
});

test("the budget read falls back to the body's resources.core when a header is missing", async () => {
  const headers = headersOf(5000, 4999, RESET);
  delete headers["x-ratelimit-remaining"];
  const { fetchImpl } = recordingFetch(rateLimitResponse({ headers, core: { limit: 1000, remaining: 99, reset: RESET + 60, used: 901 } }));
  const result = await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl });
  assert.equal(result.stop, true, "99 of 1000 is under 100");
  assert.equal(result.reset, RESET + 60, "the body's reset");
  assert.match(result.line, /decided from body: limit=1000 remaining=99 /);
  assert.match(result.line, /headers limit=5000 remaining=na /);
});

const FAILED_READS = [
  ["a 500", () => rateLimitResponse({ status: 500, headers: headersOf(5000, 0, RESET) }), /HTTP 500/],
  ["a 401", () => rateLimitResponse({ status: 401 }), /HTTP 401/],
  ["a network error", new Error("connect ECONNREFUSED"), /connect ECONNREFUSED/],
  ["no headers and no body reading", () => new Response("not json", { status: 200 }), /neither the headers nor the body/],
];

for (const [label, answer, why] of FAILED_READS) {
  test(`a budget read that meets ${label} proceeds with a warning`, async () => {
    const { calls, fetchImpl } = recordingFetch(answer);
    const result = await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl });
    assert.equal(result.stop, false);
    assert.equal(calls.length, 1, "no retry");
    assert.match(result.line, /^::warning title=start-gate::the GITHUB_TOKEN budget was not read \(/);
    assert.match(result.line, why);
    assert.match(result.line, /; the lane proceeds$/);
  });
}

test("with no token the budget is not read and the lane proceeds with a warning", async () => {
  const { calls, fetchImpl } = recordingFetch(rateLimitResponse({ headers: headersOf(5000, 0, RESET) }));
  const result = await checkBudget({ token: "", share: 0.1, now: NOW_S, fetchImpl });
  assert.deepEqual([result.stop, calls.length], [false, 0]);
  assert.match(result.line, /^::warning title=start-gate::no token/);
});

test("a value in the answer cannot start a workflow command", async () => {
  const headers = { ...headersOf(5000, 4000, RESET), "x-ratelimit-resource": "core%0A::error::x" };
  const { fetchImpl } = recordingFetch(rateLimitResponse({ headers }));
  const { line } = await checkBudget({ token: "t", share: 0.1, now: NOW_S, fetchImpl });
  assert.equal(line.split("::").length, 3, "the notice's own two :: only");
  assert.match(line, /resource=core 0A  error  x$/);
});

async function runMain(env, answer, { rateLimits } = {}) {
  const dir = tempDir("kill-switch-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    let limitsPath;
    if (rateLimits !== undefined) {
      limitsPath = path.join(dir, "rate-limits.json");
      writeFileSync(limitsPath, typeof rateLimits === "string" ? rateLimits : JSON.stringify(rateLimits));
    }
    const lines = [];
    const { calls, fetchImpl } = recordingFetch(answer);
    await main({ GITHUB_OUTPUT: outputPath, BUDGET_TOKEN: "t", ...env }, { fetchImpl, now: () => NOW_MS, log: (line) => lines.push(line), ...(limitsPath && { rateLimits: limitsPath }) });
    return { calls, lines, outputs: readOutputs(readFileSync(outputPath, "utf8")) };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const OFF = { KILL_SWITCH_VALUE: "false", REPO_KILL_SWITCH_VALUE: "false" };
const START = { ...OFF, BUDGET_CHECK: "true" };
const empty = () => rateLimitResponse({ headers: headersOf(5000, 0, RESET) });

test("by default the gate checks the switches only and makes no /rate_limit call", async () => {
  for (const value of [undefined, "", "false", "FALSE", "yes"]) {
    const { calls, lines, outputs } = await runMain({ ...OFF, BUDGET_CHECK: value }, empty);
    assert.equal(calls.length, 0, `BUDGET_CHECK=${JSON.stringify(value)}`);
    assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" }, "an empty pool does not stop it");
    assert.ok(!lines.some((line) => line.includes("start-gate")), "no start-gate notice or warning");
  }
  const { calls, outputs } = await runMain({ KILL_SWITCH_VALUE: "true", REPO_KILL_SWITCH_VALUE: "false" }, empty);
  assert.deepEqual([calls.length, outputs], [0, { proceed: "false", reason: "kill-switch", cause: "switch", reset: "" }]);
});

test("a start gate whose switch stops makes no budget call", async () => {
  const { calls, outputs } = await runMain({ ...START, KILL_SWITCH_VALUE: "true" }, empty);
  assert.equal(calls.length, 0);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "switch", reset: "" });
});

test("a low budget stops a start gate with reason kill-switch, cause budget and the window's reset", async () => {
  const { calls, lines, outputs } = await runMain(START, rateLimitResponse({ headers: headersOf(5000, 499, RESET) }));
  assert.equal(calls.length, 1);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "budget", reset: String(RESET) });
  assert.equal(lines.filter((line) => line.startsWith("::notice title=start-gate::")).length, 1, "one notice per run");
  assert.ok(lines.includes(`check-kill-switch: proceed=false reason=kill-switch cause=budget reset=${RESET}`));
});

test("a start gate at the share proceeds", async () => {
  const { outputs } = await runMain(START, rateLimitResponse({ headers: headersOf(5000, 500, RESET) }));
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
});

test("the share is rate-limits.json's github-token start-gate", async () => {
  // 0.5 of 5000 is 2500.
  const half = { "github-token": { "start-gate": 0.5 } };
  assert.equal((await runMain(START, rateLimitResponse({ headers: headersOf(5000, 2499, RESET) }), { rateLimits: half })).outputs.cause, "budget");
  assert.equal((await runMain(START, rateLimitResponse({ headers: headersOf(5000, 2500, RESET) }), { rateLimits: half })).outputs.cause, "ok");
  assert.equal((await runMain(START, empty, { rateLimits: { "github-token": { "start-gate": 0 } } })).outputs.cause, "ok", "0 turns it off");
  assert.equal(startGateShare(fileURLToPath(new URL("../log-api-budget/rate-limits.json", import.meta.url)), () => {}), 0.1, "the shipped value");
});

test("a share that cannot be read makes no call and proceeds with a warning", async () => {
  for (const [label, rateLimits] of [
    ["not JSON", "{"],
    ["no start-gate", { "github-token": {} }],
    ["a share over 1", { "github-token": { "start-gate": 2 } }],
  ]) {
    const { calls, lines, outputs } = await runMain(START, empty, { rateLimits });
    assert.equal(calls.length, 0, label);
    assert.equal(outputs.cause, "ok", label);
    assert.ok(lines.some((line) => line.startsWith("::warning title=start-gate::rate-limits.json gave no start-gate share")), label);
  }
});

test("a failed budget read proceeds", async () => {
  const { outputs, lines } = await runMain(START, new Error("socket hang up"));
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
  assert.ok(lines.some((line) => line.startsWith("::warning title=start-gate::the GITHUB_TOKEN budget was not read (socket hang up)")));
});

// Every check-kill-switch gate in the workflows, by workflow and job: `start`
// gates begin new work and read the budget; `switch` gates finish or judge
// existing work (reviews, merges, verdicts, post-model writes, model legs that
// take over a handed-off turn) and check the switches only.
const GATES = {
  "eval-browser-dispatch.yml": { eval: "switch", "eval-subscription": "switch", "eval-fallback": "switch" },
  "eval-hill-climb-pass.yml": { pass: "switch", "pass-subscription": "switch", "pass-fallback": "switch" },
  "intake-reenter.yml": { reenter: "start" },
  "intake-triage.yml": {
    "kill-switch": "start",
    "apply-verdict": "switch",
    "refine-select": "start",
    "refine-issue": "switch",
    "refine-issue-subscription": "switch",
    "refine-issue-fallback": "switch",
    "apply-refinement": "switch",
  },
  "maintenance-audit-lane-runs.yml": {
    collect: "start",
    judge: "switch",
    "judge-handoffs": "switch",
    "judge-subscription": "switch",
    "judge-subscription-handoffs": "switch",
    "judge-fallback": "switch",
    file: "switch",
    "triage-sweep": "start",
  },
  "maintenance-delete-stale-branches.yml": { plan: "start", delete: "switch" },
  "maintenance-file-recurring-issues.yml": { "file-recurring-issues": "start" },
  "maintenance-measure-skill-edit.yml": { gate: "start", propose: "switch", "push-branch": "switch", publish: "switch" },
  "maintenance-monitor-signals.yml": { monitor: "start" },
  "maintenance-reconcile-lost-runs.yml": { reconcile: "start" },
  "maintenance-tidy-code-upkeep.yml": { gate: "start", model: "switch", "model-subscription": "switch", "model-fallback": "switch", "push-branches": "switch", publish: "switch" },
  "post-merge-demotion-alert.yml": { "report-red-main": "switch" },
  "post-merge-test-mutation.yml": { prep: "start" },
  "pr-feedback-dispatch.yml": { "post-verify-notes": "switch", dispatch: "switch", "rerun-ci-status": "switch" },
  "pr-merge.yml": { "post-merge-dispatch": "switch", merge: "switch", "enable-auto-merge": "switch" },
  "pr-rate-merge-risk.yml": { "rate-merge-risk": "switch", "rate-merge-risk-subscription": "switch", "rate-merge-risk-fallback": "switch" },
  "pr-review-hosted.yml": { "kill-switch": "switch" },
  "pr-review-main.yml": { trigger: "switch", "trusted-text": "switch", review: "switch", "review-subscription": "switch", "review-fallback": "switch" },
  "pr-review-security-hosted.yml": { "kill-switch": "switch" },
  // broker-check reads the budget only for a caller passing start-gate, and
  // only on a call that is the first in its slot (FIRST_CALL).
  "pr-run-activity-read.yml": { "broker-check": "first-call", run: "switch" },
  "pr-run-activity-write.yml": { run: "switch" },
  "pr-unblock-dispatch.yml": { dispatch: "start", refine: "start" },
  "pr-unblock.yml": {
    "resolve-conflicts-select": "switch",
    "sync-shared-copies-select": "switch",
    "address-feedback-select": "switch",
    "adjudicate-feedback": "switch",
    "review-dependency-select": "switch",
    "fix-ci-context": "switch",
  },
  "pr-verify-capture.yml": { capture: "switch" },
  "pr-verify.yml": { "check-intent": "switch", "check-intent-subscription": "switch", "check-intent-fallback": "switch" },
  "upstream-apply-changelog.yml": {
    gate: "start",
    model: "switch",
    "model-subscription": "switch",
    "model-fallback": "switch",
    "scrub-probe": "switch",
    "scrub-probe-subscription": "switch",
    "scrub-probe-fallback": "switch",
    "push-branches": "switch",
    publish: "switch",
  },
  "work-unblock.yml": { "label-unblocked": "start", "publish-lane-level": "switch", "sync-status": "switch" },
};

const FIRST_CALL = /^ {10}budget: \$\{\{ inputs\.start-gate && \(inputs\.fallback == '' \|\| inputs\.fallback == 'credit-stop'\) && 'true' \|\| 'false' \}\}$/m;

// The read-runner calls that pass start-gate, by workflow and job: the issue
// lane and pr-refine start new work; pr-unblock fixes existing PRs and passes
// none. Each listed call's handed-off and fallback legs read no budget
// through FIRST_CALL's fallback test.
const START_CALLS = {
  "work-resolve-issue.yml": ["resolve-issue", "resolve-issue-subscription", "resolve-issue-fallback"],
  "pr-refine.yml": ["fix-docs", "fix-docs-subscription", "fix-docs-fallback"],
};

test("only the issue lane's and pr-refine's read-runner calls pass start-gate", () => {
  for (const file of readdirSync(WORKFLOWS).filter((name) => name.endsWith(".yml"))) {
    const lines = readFileSync(path.join(WORKFLOWS, file), "utf8").split("\n");
    const starting = [];
    let calls = 0;
    let job = null;
    lines.forEach((line, i) => {
      const id = /^ {2}([a-z][a-z0-9-]*):$/.exec(line);
      if (id) job = id[1];
      if (!/^ {4}uses: \.\/\.github\/workflows\/pr-run-activity-read\.yml\b/.test(line)) return;
      calls += 1;
      const next = lines.findIndex((other, j) => j > i && /^ {2}[a-z]/.test(other));
      if (/^ {6}start-gate: true$/m.test(lines.slice(i, next < 0 ? undefined : next).join("\n"))) starting.push(job);
    });
    if (calls) assert.deepEqual(starting, START_CALLS[file] ?? [], file);
  }
});

// Each gate step in a workflow: its job and the step's text.
function gatesIn(file) {
  const lines = readFileSync(path.join(WORKFLOWS, file), "utf8").split("\n");
  const jobsAt = lines.indexOf("jobs:");
  const found = [];
  let job = null;
  lines.forEach((line, i) => {
    const id = i > jobsAt && /^ {2}([a-z][a-z0-9-]*):$/.exec(line);
    if (id) job = id[1];
    // Any path to the action, at any ref.
    if (!/^\s*(?:-\s+)?uses:\s*["']?[^\s"'#]*actions\/check-kill-switch(?:@[^\s"'#]*)?["']?\s*(?:#.*)?$/.test(line)) return;
    const next = lines.findIndex((other, j) => j > i && /^ {6}- |^ {2}[a-z]/.test(other));
    found.push({ job, step: lines.slice(i, next < 0 ? undefined : next).join("\n") });
  });
  return found;
}

test("every gate in the workflows is classified, and only start gates read the budget", () => {
  const seen = new Set();
  for (const file of readdirSync(WORKFLOWS).filter((name) => name.endsWith(".yml"))) {
    for (const { job, step } of gatesIn(file)) {
      const kind = GATES[file]?.[job];
      assert.ok(kind, `${file} ${job}: a gate this test does not classify as start or switch`);
      seen.add(`${file} ${job}`);
      if (kind === "start") {
        assert.match(step, /^ {10}budget: "true"$/m, `${file} ${job} starts new work`);
      } else if (kind === "first-call") {
        assert.match(step, FIRST_CALL, `${file} ${job} starts new work on a starting caller's first call only`);
      } else {
        assert.doesNotMatch(step, /budget:/, `${file} ${job} checks the switches only`);
      }
    }
  }
  for (const [file, jobs] of Object.entries(GATES)) {
    for (const job of Object.keys(jobs)) {
      assert.ok(seen.has(`${file} ${job}`), `${file} ${job}: classified but has no gate`);
    }
  }
});

test("CLI writes proceed=true when both switches are exactly false and exits 0", () => {
  const { status, stdout, outputs } = runCli({ KILL_SWITCH_VALUE: "false", REPO_KILL_SWITCH_VALUE: "false" });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
  assert.doesNotMatch(stdout, /start-gate/);
});

test("CLI start gate without a token reads no budget, warns and proceeds", () => {
  const { status, stdout, outputs } = runCli({ ...START });
  assert.equal(status, 0);
  assert.equal(outputs.cause, "ok");
  assert.match(stdout, /::warning title=start-gate::no token/);
});

test("CLI start gate in a checkout without log-api-budget warns, reads no budget and proceeds", () => {
  const dir = tempDir("kill-switch-sparse-");
  try {
    const script = path.join(dir, "check-kill-switch", "check-kill-switch.mjs");
    mkdirSync(path.dirname(script));
    copyFileSync(SCRIPT, script);
    const { status, stdout, outputs } = runCli({ ...START, BUDGET_TOKEN: "t" }, script);
    assert.equal(status, 0);
    assert.match(stdout, /::warning title=start-gate::rate-limits\.json gave no start-gate share \(ENOENT\)/);
    assert.deepEqual(outputs, { proceed: "true", reason: "ok", cause: "ok", reset: "" });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("CLI writes proceed=false when the repository switch is unset and exits 0", () => {
  const { status, outputs } = runCli({ KILL_SWITCH_VALUE: "false" });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "switch", reset: "" });
});

test("CLI writes proceed=false when both variables are unset and exits 0", () => {
  const { status, outputs } = runCli({});
  assert.equal(status, 0);
  assert.deepEqual(outputs, { proceed: "false", reason: "kill-switch", cause: "switch", reset: "" });
});

test("output values cannot inject a second output line", () => {
  const dir = tempDir("kill-switch-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    writeOutputs({ "head-ref": "a\nproceed=true" }, outputPath);
    assert.deepEqual(readOutputs(readFileSync(outputPath, "utf8")), {
      "head-ref": "a\nproceed=true",
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
