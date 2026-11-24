import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const TEXT = readFileSync(new URL("../../workflows/pr-rate-merge-risk.yml", import.meta.url), "utf8");
const wf = workflowText(TEXT);
const S = await loadSelect(selectPin(TEXT));

const KEY = "rate-merge-risk";
const SUB = "rate-merge-risk-subscription";
const FB = "rate-merge-risk-fallback";
const SECRETS = { key: "PR_VERIFY_CLAUDE_API_KEY", sub: "PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN", fallback: "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN" };
const RUN = {
  "github.ref": "refs/heads/main",
  "github.event.workflow_run.event": "pull_request",
  "github.event.workflow_run.conclusion": "success",
  "github.event.workflow_run.head_repository.full_name": "o/r",
  "github.repository": "o/r",
};
const TRIGGER = "github.ref == 'refs/heads/main' && github.event.workflow_run.event == 'pull_request' && github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.head_repository.full_name == github.repository";

const OLD = {
  sub: `!cancelled() && ${TRIGGER} && needs.${KEY}.result == 'success' && (needs.${KEY}.outputs.handoff == 'true' || needs.${KEY}.outputs.credential-present == 'false' || needs.${KEY}.outputs.skip-key == 'true')`,
  fallback: `!cancelled() && ${TRIGGER} && needs.${SUB}.result == 'success' && needs.${SUB}.outputs.fallback-ready == 'true' && (needs.${SUB}.outputs.handoff == 'true' || needs.${SUB}.outputs.credential-present == 'false')`,
  subReason: `\${{ needs.${KEY}.outputs.handoff-reason || needs.${KEY}.outputs.skip-key == 'true' && 'credit-stop' || needs.${KEY}.outputs.credential-present == 'false' && 'no-key' || '' }}`,
  fallbackReason: `\${{ needs.${SUB}.outputs.handoff-reason || 'no-key' }}`,
  keyOutputs: {
    handoff: "${{ steps.rate.outputs.handoff }}",
    "handoff-reason": "${{ steps.rate.outputs.handoff-reason }}",
    "credential-present": "${{ steps.credential.outputs.present }}",
    "skip-key": "${{ steps.credit.outputs.skip-key }}",
  },
  subOutputs: {
    handoff: "${{ steps.rate.outputs.handoff }}",
    "handoff-reason": "${{ steps.rate.outputs.handoff-reason }}",
    "credential-present": "${{ steps.credential.outputs.present }}",
    "fallback-ready": "${{ steps.credential.outputs.fallback-ready }}",
  },
  fail: "always() && steps.credential.outputs.run == 'true' && steps.rating.outcome != 'success' && steps.rate.outputs.handoff != 'true'",
};
const failIf = (job) => /^ {6}- name: Fail without a rating\n {8}if: (.*)$/m.exec(wf.job(job))[1];

const prefixed = (prefix, map) => Object.fromEntries(Object.entries(map).map(([k, v]) => [`${prefix}.${k}`, v]));
const evalMap = (map, ctx) => Object.fromEntries(Object.entries(map).map(([k, v]) => [k, value(v, ctx)]));

function rateSteps(ran, end) {
  if (!ran) return { "steps.rating.outcome": "skipped" };
  const handoff = end.kind === "handoff";
  return {
    "steps.rate.outcome": end.kind === "fail" ? "failure" : "success",
    "steps.rate.outputs.handoff": String(handoff),
    "steps.rate.outputs.handoff-reason": handoff ? end.reason : "",
    "steps.rating.outcome": end.kind === "rating" ? "success" : "skipped",
  };
}

const result = (failAt, failExpr, ctx) => (failAt === "after-leg" || runs(failExpr, ctx) ? "failure" : "success");

function ends(handoffReason, leg, fallbackReady) {
  const out = [{ kind: "rating" }, { kind: "fail" }];
  for (const { reason } of launcherOutcomes(handoffReason, leg, fallbackReady)) if (reason !== "") out.push({ kind: "handoff", reason });
  return out;
}

function oldRun(s) {
  const out = { started: [KEY], legs: {} };
  const checked = s.checker === "success";
  const base = { ...RUN, "steps.checker.outcome": s.checker };
  const keyCtx = { ...base };
  if (checked) {
    keyCtx["steps.credit.outputs.skip-key"] = { ok: "false", skip: "true", failed: "" }[s.gate];
    keyCtx["steps.credential.outputs.present"] = String(s.key);
    keyCtx["steps.credential.outputs.run"] = String(s.key && keyCtx["steps.credit.outputs.skip-key"] !== "true");
  }
  const keyRuns = keyCtx["steps.credential.outputs.run"] ?? "";
  Object.assign(keyCtx, rateSteps(keyRuns === "true", s.keyEnd));
  out.legs[KEY] = { present: keyRuns };
  const needs = { ...RUN, [`needs.${KEY}.result`]: result(s.failAt, OLD.fail, keyCtx), ...prefixed(`needs.${KEY}.outputs`, evalMap(OLD.keyOutputs, keyCtx)) };
  if (!runs(OLD.sub, needs)) return out;
  out.started.push(SUB);
  const subCtx = { ...base };
  if (checked) Object.assign(subCtx, { "steps.credential.outputs.present": String(s.sub), "steps.credential.outputs.run": String(s.sub), "steps.credential.outputs.fallback-ready": String(s.fallback) });
  Object.assign(subCtx, rateSteps(subCtx["steps.credential.outputs.run"] === "true", s.subEnd));
  out.legs[SUB] = { present: subCtx["steps.credential.outputs.run"] ?? "", "fallback-ready": subCtx["steps.credential.outputs.fallback-ready"] ?? "", "fallback-reason": value(OLD.subReason, needs) };
  Object.assign(needs, { [`needs.${SUB}.result`]: result(s.failAt, OLD.fail, subCtx), ...prefixed(`needs.${SUB}.outputs`, evalMap(OLD.subOutputs, subCtx)) });
  if (!runs(OLD.fallback, needs)) return out;
  out.started.push(FB);
  out.legs[FB] = { present: checked ? String(s.fallback) : "", "fallback-reason": value(OLD.fallbackReason, needs) };
  return out;
}

function newJob(job, leg, s, needs, end) {
  const base = {
    ...RUN,
    ...needs,
    "steps.kill.outputs.proceed": "true",
    ...prefixed("secrets", Object.fromEntries(Object.entries(SECRETS).map(([k, name]) => [name, s[k] ? "set" : ""]))),
  };
  const resolved = runs(wf.step(job, "pr").if, base);
  if (resolved) base["steps.pr.outputs.proceed"] = String(s.checker === "success" || s.refusal === "trigger");
  const trigger = wf.step(job, "gate");
  const credentialFirst = wf.job(job).indexOf("\n        id: credential\n") < wf.job(job).indexOf("\n        id: gate\n");
  let triggered = false;
  const check = (ctx) => {
    triggered = runs(trigger.if, ctx);
    ctx["steps.checker.outcome"] = triggered && s.checker === "success" ? "success" : "skipped";
  };
  if (!credentialFirst) check(base);
  const credit = leg === "key" ? wf.step(job, "credit") : null;
  if (credit) {
    assert.equal(credit.inputs.leg, "start", job);
    assert.match(credit.text, /^ {8}continue-on-error: true$/m, job);
    if (runs(credit.if, base) && s.gate !== "failed") Object.assign(base, prefixed("steps.credit.outputs", S.start({ skipKey: s.gate === "skip" })));
  }
  const call = wf.step(job, "credential");
  assert.equal(call.inputs.leg, leg, job);
  let credential = {};
  if (runs(call.if, base)) {
    const input = (name) => (call.inputs[name] === undefined ? "" : value(call.inputs[name], base));
    const held = leg === "key" && input("key-job") !== "" && s.gate === "skip";
    credential = S.leg({ leg, role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), held, reason: input("reason") }).outputs;
  }
  const decided = { ...base, ...prefixed("steps.credential.outputs", credential) };
  if (credentialFirst) check(decided);
  const ran = runs(wf.step(job, "prompt").if, decided);
  const ctx = { ...decided, ...rateSteps(ran, end) };
  const outputs = { result: result(s.failAt, failIf(job), ctx) };
  if (leg !== "fallback") {
    const next = wf.step(job, "next");
    assert.equal(next.if, "", `${job}'s next-leg call has no if`);
    const decided = s.failAt === "after-leg" ? {} : S.next({ state: value(next.inputs.state, ctx), handoff: value(next.inputs.handoff, ctx), handoffReason: value(next.inputs["handoff-reason"], ctx) });
    Object.assign(outputs, evalMap(wf.outputs(job), { ...ctx, ...prefixed("steps.next.outputs", decided) }));
  } else {
    assert.throws(() => wf.step(job, "next"), undefined, "the fallback leg names no next leg");
  }
  return { credential, outputs, ran, resolved, triggered };
}

function traced(s) {
  const trace = { resolved: [], triggered: [], ran: [] };
  const note = (id, j) => {
    if (j.resolved) trace.resolved.push(id);
    if (j.triggered) trace.triggered.push(id);
    if (j.ran) trace.ran.push(id);
    return j;
  };
  return { trace, out: newRun(s, note) };
}

function newRun(s, note = (_id, j) => j) {
  const out = { started: [KEY], legs: {} };
  assert.equal(runs(wf.jobIf(KEY), RUN), true);
  const key = note(KEY, newJob(KEY, "key", s, {}, s.keyEnd));
  out.legs[KEY] = { present: key.credential.present ?? "" };
  const needs = { [`needs.${KEY}.result`]: key.outputs.result, ...prefixed(`needs.${KEY}.outputs`, key.outputs) };
  if (!runs(wf.jobIf(SUB), { ...RUN, ...needs })) return out;
  out.started.push(SUB);
  const sub = note(SUB, newJob(SUB, "subscription", s, needs, s.subEnd));
  out.legs[SUB] = { present: sub.credential.present ?? "", "fallback-ready": sub.credential["fallback-ready"] ?? "", "fallback-reason": sub.credential["fallback-reason"] ?? "" };
  Object.assign(needs, { [`needs.${SUB}.result`]: sub.outputs.result, ...prefixed(`needs.${SUB}.outputs`, sub.outputs) });
  if (!runs(wf.jobIf(FB), { ...RUN, ...needs })) return out;
  out.started.push(FB);
  const fb = note(FB, newJob(FB, "fallback", s, needs, { kind: "rating" }));
  out.legs[FB] = { present: fb.credential.present ?? "", "fallback-reason": fb.credential["fallback-reason"] ?? "" };
  return out;
}

function* states() {
  for (const [checker, refusal] of [["success", ""], ["skipped", "resolver"], ["skipped", "trigger"]])
    for (const gate of ["ok", "skip", "failed"])
      for (const key of [true, false])
        for (const sub of [true, false])
          for (const fallback of [true, false])
            for (const failAt of ["none", "after-leg"])
              for (const keyEnd of ends(S.handoffReason, "api-key", false))
                for (const subEnd of ends(S.handoffReason, "subscription", fallback))
                  if (checker === "success" || (failAt === "none" && keyEnd.kind === "rating" && subEnd.kind === "rating")) yield { checker, refusal, gate, key, sub, fallback, failAt, keyEnd, subEnd };
}

const oldRan = (s, before) => (s.checker === "success" ? Object.entries(before.legs).filter(([, l]) => l.present === "true").map(([id]) => id) : []);

test("pr-rate-merge-risk's legs start the same jobs with the same credential decisions as before select-model-credential", () => {
  let count = 0;
  const shapes = new Set();
  for (const s of states()) {
    count++;
    const before = oldRun(s);
    const { out, trace } = traced(s);
    assert.deepEqual(trace.ran, oldRan(s, before), `the same legs run the model: ${JSON.stringify(s)}`);
    if (s.refusal !== "trigger") {
      assert.deepEqual(out, before, JSON.stringify(s));
    } else {
      const handsOff = out.legs[KEY].present !== "true";
      assert.deepEqual(out.started, handsOff ? [KEY, SUB] : [KEY], `a refused head starts no model leg: ${JSON.stringify(s)}`);
      assert.deepEqual(trace.triggered, handsOff ? [SUB] : [KEY], `each started leg's trigger check judges the head: ${JSON.stringify(s)}`);
      assert.deepEqual(trace.ran, [], `a refused head runs no model: ${JSON.stringify(s)}`);
    }
    shapes.add(before.started.join(","));
  }
  for (const shape of [KEY, `${KEY},${SUB}`, `${KEY},${SUB},${FB}`]) assert.ok(shapes.has(shape), `reached ${shape}`);
  assert.ok(count > 500, `${count} states`);
});

test("a key the credit history holds off hands off after the key job's resolver, before its trigger check", () => {
  const s = { checker: "success", refusal: "", gate: "skip", key: true, sub: true, fallback: true, failAt: "none", keyEnd: { kind: "rating" }, subEnd: { kind: "rating" } };
  const { out, trace } = traced(s);
  assert.deepEqual(out.started, [KEY, SUB], "the subscription job starts");
  assert.deepEqual(trace.resolved, [KEY, SUB], "both jobs run their own resolver");
  assert.deepEqual(trace.triggered, [SUB], "only the subscription job runs the trigger check");
  assert.deepEqual(trace.ran, [SUB], "the subscription leg rates");
  assert.equal(out.legs[SUB]["fallback-reason"], "credit-stop");
  const empty = traced({ ...s, gate: "ok", key: false });
  assert.deepEqual(empty.trace.triggered, [SUB], "an empty key also skips the key job's trigger check");
  assert.equal(empty.out.legs[SUB]["fallback-reason"], "no-key");
  const refused = traced({ ...s, checker: "skipped", refusal: "resolver" });
  assert.deepEqual(refused.out.started, [KEY], "a refused head starts only the key job");
  assert.deepEqual(refused.out.legs[KEY].present, "", "and the key job makes no credential call");
});

test("a credit read that fails runs the key leg through the trigger check, as before", () => {
  const s = { checker: "success", refusal: "", gate: "failed", key: true, sub: true, fallback: true, failAt: "none", keyEnd: { kind: "rating" }, subEnd: { kind: "rating" } };
  const { out, trace } = traced(s);
  assert.deepEqual(out.started, [KEY], "the key rates, so no later leg starts");
  assert.deepEqual(trace.triggered, [KEY], "the key job runs its own trigger check");
  assert.deepEqual(trace.ran, [KEY], "the key leg runs the model");
});

test("a step that fails after a handoff starts no next leg, as the old result == 'success' term required", () => {
  const s = { checker: "success", refusal: "", gate: "ok", key: true, sub: true, fallback: true, failAt: "after-leg", keyEnd: { kind: "handoff", reason: "credit-stop" }, subEnd: { kind: "rating" } };
  assert.deepEqual(newRun(s).started, [KEY]);
  assert.deepEqual(oldRun(s).started, [KEY]);
  assert.deepEqual(newRun({ ...s, failAt: "none" }).started, [KEY, SUB]);
});
