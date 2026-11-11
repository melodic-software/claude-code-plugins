// pr-run-activity-read.yml runs one leg per call: the caller's first call
// the key, its second the subscription token, its third the fallback token,
// chosen by the caller's fallback input. Its presence steps (key-present,
// token-present, fallback-present) are ci-workflows' select-model-credential
// leg calls, fetched at the pin the workflow names, and broker-check's credit
// read is its start call. The callers chain their next call on this file's
// workflow_call outputs, which keep their names and values: this table drives
// the run job's own step conditions, inputs and outputs through every
// fallback input, fallback-ready, credit verdict, secret set or empty, each
// launcher end run-claude-cli's own handoffReason can produce, and a step
// failing after the leg, and holds each state to the expressions the file
// used before the action (quoted from 5599e627fc): the same steps run and
// credential-present, handed-off, lane-class and both fallback reasons keep
// their values.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const PATH = new URL("../../workflows/pr-run-activity-read.yml", import.meta.url);
const TEXT = readFileSync(PATH, "utf8");
// `defaults: run:` precedes the jobs, so the job reader starts at `jobs:`.
const JOBS = TEXT.slice(TEXT.indexOf("\njobs:\n"));
const wf = workflowText(JOBS);
const S = await loadSelect(selectPin(TEXT));

// A run job step's condition, single-line or folded.
function stepIf(body) {
  const folded = /^ {8}if: >-\n((?: {10}.*\n)+)/m.exec(body);
  if (folded) return folded[1].replace(/\s+/g, " ").trim();
  return /^ {8}if: (.*)$/m.exec(body)?.[1] ?? "";
}
const stepBody = (name) => {
  const found = wf.job("run").split(/\n(?= {6}- name: )/).filter((s) => s.startsWith(`      - name: ${name}\n`));
  assert.equal(found.length, 1, name);
  return found[0];
};
const envOf = (body, name) => new RegExp(`^ {10}${name}: (.*)$`, "m").exec(body)[1];

// The old presence steps, outputs and reasons, at 5599e627fc.
const READY = "steps.launch.outcome == 'success' && steps.go.outputs.run == 'true'";
const OLD = {
  keyIf: `${READY} && inputs.fallback == ''`,
  tokenIf: `${READY} && inputs.fallback != '' && inputs.fallback != 'fallback'`,
  fallbackIf: `${READY} && inputs.fallback == 'fallback'`,
  outputs: {
    "lane-class": "${{ steps.act-key.outputs.lane-class || steps.act-token.outputs.lane-class || steps.act-fallback.outputs.lane-class }}",
    "credential-present": "${{ steps.key-present.outputs.present || steps.token-present.outputs.present || steps.fallback-present.outputs.present }}",
    "handed-off": "${{ steps.key-present.outputs.present == 'false' || steps.act-key.outputs.handoff == 'true' || steps.act-token.outputs.handoff == 'true' || steps.token-present.outputs.present == 'false' && inputs.fallback-ready == 'true' }}",
  },
  reason: "${{ inputs.fallback == 'credit-stop' && 'credit-stop' || inputs.fallback == 'no-key' && 'no-key' || '' }}",
};
const SECRETS = { key: "claude-api-key", sub: "claude-code-oauth-token", fallback: "fallback-claude-code-oauth-token" };
const STEPS = { key: "key-present", sub: "token-present", fallback: "fallback-present" };
const ACT = { key: "act-key", sub: "act-token", fallback: "act-fallback" };

// The steps after the presence checks, unchanged by the action: their
// conditions come from the workflow text.
const RECORD = stepBody("Record the launcher's lane outcome");
const COLLECT = stepBody("Collect the issue outcome");
const LATER = {
  act: Object.fromEntries(Object.entries(ACT).map(([leg, id]) => [leg, wf.step("run", id).if])),
  record: stepIf(RECORD),
  collect: stepIf(COLLECT),
};

// The launcher's outputs for the leg that ran, ended by `end`.
function act(leg, end) {
  const id = ACT[leg];
  const handoff = end.kind === "handoff";
  return {
    [`steps.${id}.outcome`]: end.kind === "fail" ? "failure" : "success",
    [`steps.${id}.outputs.handoff`]: handoff ? "true" : end.kind === "fail" ? "" : "false",
    [`steps.${id}.outputs.handoff-reason`]: handoff ? end.reason : "",
    [`steps.${id}.outputs.lane-class`]: handoff ? end.reason : end.kind === "fail" ? "other" : "",
  };
}

// The run job from the presence steps on, given each presence step's
// outputs: which launcher ran, the job outputs, and both fallback reasons.
function after(base, presence, s, outputs, recordReason, collectReason) {
  const ctx = { ...base, ...presence, "steps.config.outputs.kind": "skill", "steps.act-turns.outcome": "success" };
  for (const leg of Object.keys(ACT)) {
    ctx[`steps.${ACT[leg]}.outcome`] = "skipped";
    if (runs(LATER.act[leg], ctx)) Object.assign(ctx, act(leg, s.end));
  }
  // A step failing after the leg changes no output: the job outputs and the
  // lane record (always()) read step outputs whatever the job's result.
  if (s.failAfter) ctx["steps.act-error.outcome"] = "failure";
  const out = {
    ran: Object.values(ACT).filter((id) => ctx[`steps.${id}.outcome`] !== "skipped"),
    outputs: Object.fromEntries(Object.entries(outputs).map(([k, v]) => [k, value(v, ctx)])),
    record: runs(LATER.record, ctx) ? value(recordReason, ctx) : null,
    collect: runs(LATER.collect, ctx) ? value(collectReason, ctx) : null,
  };
  return out;
}

function context(s) {
  return {
    "inputs.fallback": s.fallback,
    "inputs.fallback-ready": s.ready,
    "inputs.issue-number": s.issue ? "7" : "",
    "inputs.role": "pr-unblock",
    "steps.launch.outcome": s.reached ? "success" : "skipped",
    "steps.go.outputs.run": s.reached ? "true" : "",
    // broker-check reads the credit history on the first call alone.
    "needs.broker-check.outputs.skip-key": s.fallback === "" ? s.gate : "",
    [`secrets.${SECRETS.key}`]: s.key ? "set" : "",
    [`secrets.${SECRETS.sub}`]: s.sub ? "set" : "",
    [`secrets.${SECRETS.fallback}`]: s.fallbackSet ? "set" : "",
  };
}

function oldRun(s) {
  const base = context(s);
  const presence = {};
  const set = (leg, present) => Object.assign(presence, { [`steps.${STEPS[leg]}.outcome`]: "success", [`steps.${STEPS[leg]}.outputs.present`]: String(present) });
  for (const leg of Object.keys(STEPS)) presence[`steps.${STEPS[leg]}.outcome`] = "skipped";
  if (runs(OLD.keyIf, base)) set("key", base["needs.broker-check.outputs.skip-key"] === "true" ? false : s.key);
  if (runs(OLD.tokenIf, base)) set("sub", s.sub);
  if (runs(OLD.fallbackIf, base)) set("fallback", s.fallbackSet);
  return after(base, presence, s, OLD.outputs, OLD.reason, OLD.reason);
}

const LEG = { key: "key", sub: "subscription", fallback: "fallback" };
function newRun(s) {
  const base = context(s);
  const presence = {};
  for (const [leg, id] of Object.entries(STEPS)) {
    const call = wf.step("run", id);
    assert.equal(call.inputs.leg, LEG[leg], id);
    presence[`steps.${id}.outcome`] = "skipped";
    if (!runs(stepIf(call.text), base)) continue;
    const input = (name) => (call.inputs[name] === undefined ? "" : value(call.inputs[name], base));
    // No presence call reads the credit history itself.
    assert.equal(input("key-job"), "", id);
    const decided = S.leg({ leg: LEG[leg], role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), held: false, reason: input("reason") }).outputs;
    presence[`steps.${id}.outcome`] = "success";
    for (const [k, v] of Object.entries(decided)) presence[`steps.${id}.outputs.${k}`] = v;
  }
  const outputs = wf.outputs("run");
  return after(
    base,
    presence,
    s,
    { "lane-class": outputs["lane-class"], "credential-present": outputs["credential-present"], "handed-off": outputs["handed-off"] },
    /^ {10}fallback-reason: (.*)$/m.exec(RECORD)[1],
    envOf(COLLECT, "LANE_FALLBACK"),
  );
}

// The launcher ends a leg can have: a result, a failure, or each handoff
// run-claude-cli's handoffReason produces for that leg.
function ends(leg, ready) {
  const launcherLeg = { key: "api-key", sub: "subscription", fallback: "fallback" }[leg];
  const out = [{ kind: "result" }, { kind: "fail" }];
  for (const { reason } of launcherOutcomes(S.handoffReason, launcherLeg, ready)) if (reason !== "") out.push({ kind: "handoff", reason });
  return out;
}

// The run job's first step holds these: issue mode takes an empty, handoff,
// credit-stop or fallback input, and only the second call takes a
// fallback-ready.
const valid = (issue, fallback, ready) =>
  (!issue || ["", "handoff", "credit-stop", "fallback"].includes(fallback)) && (["", "fallback"].includes(fallback) ? ready === "" : true);

function* states() {
  for (const issue of [false, true])
    for (const fallback of ["", "credit-stop", "no-key", "handoff", "fallback"])
      for (const ready of ["", "true", "false"])
        if (valid(issue, fallback, ready))
          for (const reached of [true, false])
            for (const gate of ["true", "false", ""])
              for (const key of [true, false])
                for (const sub of [true, false])
                  for (const fallbackSet of [true, false])
                    for (const failAfter of [false, true]) {
                      const leg = fallback === "" ? "key" : fallback === "fallback" ? "fallback" : "sub";
                      for (const end of ends(leg, ready === "true")) yield { issue, fallback, ready, reached, gate, key, sub, fallbackSet, failAfter, end };
                    }
}

test("pr-run-activity-read's run job runs the same leg and sets the same outputs and fallback reasons as before select-model-credential", (t) => {
  let count = 0;
  const shapes = new Set();
  for (const s of states()) {
    count++;
    const before = oldRun(s);
    assert.deepEqual(newRun(s), before, JSON.stringify(s));
    shapes.add(`${before.ran.join(",")}|${before.outputs["handed-off"]}|${before.record}`);
  }
  for (const shape of ["act-key|false|", "act-key|true|", "|true|null", "act-token|false|credit-stop", "act-token|false|no-key", "act-token|true|", "act-fallback|false|"]) {
    assert.ok(shapes.has(shape), `reached ${shape}`);
  }
  assert.ok(count > 1000, `${count} states`);
  t.diagnostic(`${count} states`);
});

test("the workflow_call outputs the run and broker-check jobs set, and their sources, are unchanged from 5599e627fc", () => {
  // Quoted from 5599e627fc.
  const call = {
    "head-sha": "${{ jobs.run.outputs.head-sha }}",
    "lane-class": "${{ jobs.run.outputs.lane-class }}",
    "credential-present": "${{ jobs.run.outputs.credential-present }}",
    "handed-off": "${{ jobs.run.outputs.handed-off }}",
    "skip-reason": "${{ jobs.broker-check.outputs.skip-reason }}",
    lease: "${{ jobs.broker-check.outputs.lease }}",
    "lease-comment-id": "${{ jobs.broker-check.outputs.lease-comment-id }}",
  };
  const brokerCheck = {
    allowed: "${{ steps.broker.outcome == 'success' && steps.broker.outputs.allowed == 'true' }}",
    // Since 5599e627fc, a start-gate budget stop also sets skip-reason budget.
    "skip-reason": "${{ steps.kill.outputs.cause == 'budget' && 'budget' || steps.broker.outputs.skip-reason }}",
    attempt: "${{ github.run_attempt }}",
    lease: "${{ steps.lease.outputs.lease }}",
    "lease-comment-id": "${{ steps.lease.outputs.lease-comment-id }}",
    blocked: "${{ steps.recheck-blockers.outcome == 'success' && steps.recheck-blockers.outputs.proceed != 'true' }}",
    "skip-key": "${{ steps.credit.outputs.skip-key }}",
  };
  const outputsBlock = TEXT.slice(TEXT.indexOf("\n    outputs:\n"), TEXT.indexOf("\npermissions:"));
  for (const [name, expression] of Object.entries(call)) {
    assert.equal(new RegExp(`^ {6}${name}:\\n(?: {8}.*\\n)*? {8}value: (.*)$`, "m").exec(outputsBlock)?.[1], expression, name);
  }
  assert.deepEqual(wf.outputs("broker-check"), brokerCheck);
  // The run job's caller-visible outputs, quoted above, are the same text.
  for (const [name, expression] of Object.entries(OLD.outputs)) assert.equal(wf.outputs("run")[name], expression, name);
});

test("broker-check's start call reads the credit history on the first call alone, as check-key-credit did", () => {
  const credit = wf.step("broker-check", "credit");
  assert.equal(credit.inputs.leg, "start");
  assert.equal(credit.inputs["key-job"], "${{ inputs.key-credit-job }}");
  assert.equal(credit.inputs["probe-minutes"], '"0"');
  const old = "steps.broker.outcome == 'success' && steps.broker.outputs.allowed == 'true' && inputs.key-credit-job != '' && inputs.fallback == ''";
  assert.equal(stepIf(credit.text), old);
  assert.match(credit.text, /^ {8}continue-on-error: true$/m, "a failed read runs the key");
});
