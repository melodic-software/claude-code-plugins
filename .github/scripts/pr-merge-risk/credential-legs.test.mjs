// pr-rate-merge-risk.yml picks each leg's credential through ci-workflows'
// select-model-credential, fetched at the pin the workflow names; the key
// job reads its credit history inside its credential call. This truth table
// drives the workflow's own conditions, inputs and outputs through every
// combination of the checker step's outcome, credit verdict, secrets set or
// empty, how each leg's rating ends (a rating, a failure, or each handoff
// run-claude-cli's own handoffReason can produce), and a step failing after
// the leg, and holds each state to the expressions the workflow used before
// the action (quoted from 5599e627fc): for a head the resolver rates, the
// same jobs start and each leg gets the same present, fallback-ready and
// fallback-reason; for any head, the same legs run the model.
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

// The old job conditions, outputs, reasons and fail steps, at 5599e627fc.
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

// The rate and rating steps' outputs when the leg ran (or did not) and
// ended in `end`.
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

// A job's result: a step that failed after the leg, or its own last check.
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
  // rate-merge-risk: the credit step, then the credential step's present and run.
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

// One job as the workflow now runs it. `s.checker` is whether the resolver
// and the steps after it would carry this head to the model; the checker
// step only runs where the resolver does, so a key job that decides its
// credential first and skips the resolver never reaches it.
function newJob(job, leg, s, needs, end) {
  const base = {
    ...RUN,
    ...needs,
    "steps.kill.outputs.proceed": "true",
    ...prefixed("secrets", Object.fromEntries(Object.entries(SECRETS).map(([k, name]) => [name, s[k] ? "set" : ""]))),
  };
  const resolver = wf.step(job, "pr");
  const credentialFirst = wf.job(job).indexOf("\n        id: credential\n") < wf.job(job).indexOf("\n        id: pr\n");
  let resolved = false;
  const resolve = (ctx) => {
    resolved = runs(resolver.if, ctx);
    ctx["steps.checker.outcome"] = resolved ? s.checker : "skipped";
  };
  if (!credentialFirst) resolve(base);
  // The key job's credit read is its own step under continue-on-error: a read
  // that fails or times out (gate "failed") leaves its outputs empty, the
  // key call's selected with them, and the key runs, as before.
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
    // The key call reads the credit history itself when it names key-job;
    // a failed read runs the key.
    const held = leg === "key" && input("key-job") !== "" && s.gate === "skip";
    credential = S.leg({ leg, role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), held, reason: input("reason") }).outputs;
  }
  const decided = { ...base, ...prefixed("steps.credential.outputs", credential) };
  if (credentialFirst) resolve(decided);
  // The model's steps start from Write the prompt and schema, whose if the
  // rate step follows.
  const ran = runs(wf.step(job, "prompt").if, decided);
  const ctx = { ...decided, ...rateSteps(ran, end) };
  const outputs = { result: result(s.failAt, failIf(job), ctx) };
  if (leg !== "fallback") {
    const next = wf.step(job, "next");
    assert.equal(next.if, "", `${job}'s next-leg call has no if`);
    // No if: it runs only when no step before it failed. The failing step
    // of an after-leg state sits before it; the fail step comes after it.
    const decided = s.failAt === "after-leg" ? {} : S.next({ state: value(next.inputs.state, ctx), handoff: value(next.inputs.handoff, ctx), handoffReason: value(next.inputs["handoff-reason"], ctx) });
    Object.assign(outputs, evalMap(wf.outputs(job), { ...ctx, ...prefixed("steps.next.outputs", decided) }));
  } else {
    assert.throws(() => wf.step(job, "next"), undefined, "the fallback leg names no next leg");
  }
  return { credential, outputs, ran, resolved };
}

// The jobs that start and each leg's credential decision, as oldRun reports
// them, plus which jobs run the resolver and which run the model.
function traced(s) {
  const trace = { resolved: [], ran: [] };
  const note = (id, j) => {
    if (j.resolved) trace.resolved.push(id);
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
  for (const checker of ["success", "skipped"])
    for (const gate of ["ok", "skip", "failed"])
      for (const key of [true, false])
        for (const sub of [true, false])
          for (const fallback of [true, false])
            for (const failAt of ["none", "after-leg"])
              for (const keyEnd of ends(S.handoffReason, "api-key", false))
                for (const subEnd of ends(S.handoffReason, "subscription", fallback))
                  // A head the resolver does not rate rates nothing, so its
                  // legs' ends do not matter; every credential state does.
                  if (checker === "success" || (failAt === "none" && keyEnd.kind === "rating" && subEnd.kind === "rating")) yield { checker, gate, key, sub, fallback, failAt, keyEnd, subEnd };
}

// The legs that run the model, by the old run's own decision: a leg whose
// credential call said present on a head the resolver rates.
const oldRan = (s, before) => (s.checker === "success" ? Object.entries(before.legs).filter(([, l]) => l.present === "true").map(([id]) => id) : []);

test("pr-rate-merge-risk's legs start the same jobs with the same credential decisions as before select-model-credential", () => {
  let count = 0;
  const shapes = new Set();
  for (const s of states()) {
    count++;
    const before = oldRun(s);
    const { out, trace } = traced(s);
    assert.deepEqual(trace.ran, oldRan(s, before), `the same legs run the model: ${JSON.stringify(s)}`);
    if (s.checker === "success") {
      assert.deepEqual(out, before, JSON.stringify(s));
    } else {
      // A head the resolver refuses: the key job may now hand a held-off or
      // empty key to the subscription job before it reads the pull request,
      // and that job's own resolver stops it, so nothing runs a model and
      // the fallback job never starts.
      const handsOff = out.legs[KEY].present !== "true";
      assert.deepEqual(out.started, handsOff ? [KEY, SUB] : [KEY], `a refused head starts no model leg: ${JSON.stringify(s)}`);
      assert.deepEqual(trace.ran, [], `a refused head runs no model: ${JSON.stringify(s)}`);
    }
    shapes.add(before.started.join(","));
  }
  for (const shape of [KEY, `${KEY},${SUB}`, `${KEY},${SUB},${FB}`]) assert.ok(shapes.has(shape), `reached ${shape}`);
  assert.ok(count > 500, `${count} states`);
});

test("a key the credit history holds off hands off before the key job reads the pull request", () => {
  const s = { checker: "success", gate: "skip", key: true, sub: true, fallback: true, failAt: "none", keyEnd: { kind: "rating" }, subEnd: { kind: "rating" } };
  const { out, trace } = traced(s);
  assert.deepEqual(out.started, [KEY, SUB], "the subscription job starts");
  assert.deepEqual(trace.resolved, [SUB], "only the subscription job runs the resolver");
  assert.deepEqual(trace.ran, [SUB], "the subscription leg rates");
  assert.equal(out.legs[SUB]["fallback-reason"], "credit-stop");
  // An empty key hands off the same way, for no-key.
  const empty = traced({ ...s, gate: "ok", key: false });
  assert.deepEqual(empty.trace.resolved, [SUB], "an empty key also skips the key job's resolver");
  assert.equal(empty.out.legs[SUB]["fallback-reason"], "no-key");
});

test("a credit read that fails runs the key leg through the resolver, as before", () => {
  const s = { checker: "success", gate: "failed", key: true, sub: true, fallback: true, failAt: "none", keyEnd: { kind: "rating" }, subEnd: { kind: "rating" } };
  const { out, trace } = traced(s);
  assert.deepEqual(out.started, [KEY], "the key rates, so no later leg starts");
  assert.deepEqual(trace.resolved, [KEY], "the key job runs its own resolver");
  assert.deepEqual(trace.ran, [KEY], "the key leg runs the model");
});

test("a step that fails after a handoff starts no next leg, as the old result == 'success' term required", () => {
  const s = { checker: "success", gate: "ok", key: true, sub: true, fallback: true, failAt: "after-leg", keyEnd: { kind: "handoff", reason: "credit-stop" }, subEnd: { kind: "rating" } };
  assert.deepEqual(newRun(s).started, [KEY]);
  assert.deepEqual(oldRun(s).started, [KEY]);
  assert.deepEqual(newRun({ ...s, failAt: "none" }).started, [KEY, SUB]);
});
