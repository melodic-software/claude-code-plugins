// pr-verify.yml picks each judge job's credential through ci-workflows'
// select-model-credential, fetched at the pin the workflow names; the key job
// reads its credit history inside its credential call. This truth table
// drives the workflow's own conditions, inputs and outputs through every
// combination of credit verdict, secrets set or empty, the chunk that ends
// the leg (the first, a middle one, the whole-spec one), how it ends (a
// verdict, a failure, or each handoff run-claude-cli's own handoffReason can
// produce, clean or refused by the leg check), and a step failing after the
// leg, and holds each state to the expressions the workflow used before the
// action (quoted from 5599e627fc): the same jobs start, and each leg gets the
// same present, fallback-ready and fallback-reason.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const TEXT = readFileSync(new URL("../../workflows/pr-verify.yml", import.meta.url), "utf8");
const wf = workflowText(TEXT);
const S = await loadSelect(selectPin(TEXT));

const KEY = "check-intent";
const SUB = "check-intent-subscription";
const FB = "check-intent-fallback";
const CHUNKS = ["", "-2", "-3", "-4", "-5", "-6", "-7", "-8", "-9", "-10", "-11", "-12", "-spec"];
const chain = (build) => CHUNKS.map(build).join(" || ");
const SECRETS = { key: "PR_VERIFY_CLAUDE_API_KEY", sub: "PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN", fallback: "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN" };
const RUN = {
  "github.ref": "refs/heads/main",
  "github.event.workflow_run.event": "pull_request",
  "github.event.workflow_run.conclusion": "success",
  "github.event.workflow_run.head_repository.full_name": "o/r",
  "github.repository": "o/r",
};
const TRIGGER = "github.ref == 'refs/heads/main' && github.event.workflow_run.event == 'pull_request' && (github.event.workflow_run.conclusion == 'success' || github.event.workflow_run.conclusion == 'failure') && github.event.workflow_run.head_repository.full_name == github.repository";

// The old job conditions, outputs and reasons, at 5599e627fc.
const OLD = {
  sub: `!cancelled() && ${TRIGGER} && ((needs.${KEY}.result == 'success' && ((needs.${KEY}.outputs.handoff == 'true' && needs.${KEY}.outputs.key-leg-clean == 'true') || needs.${KEY}.outputs.credential-present == 'false' || needs.${KEY}.outputs.skip-key == 'true')))`,
  fallback: `!cancelled() && needs.${SUB}.result == 'success' && ${TRIGGER} && (needs.${SUB}.outputs.handoff == 'true' && needs.${SUB}.outputs.leg-clean == 'true' || needs.${SUB}.outputs.credential-present == 'false' && needs.${SUB}.outputs.fallback-ready == 'true')`,
  subReason: `\${{ needs.${KEY}.outputs.lane-class == 'credit-stop' && 'credit-stop' || needs.${KEY}.outputs.lane-class == 'auth' && 'auth' || needs.${KEY}.outputs.credential-present == 'false' && 'no-key' || needs.${KEY}.outputs.skip-key == 'true' && 'credit-stop' || '' }}`,
  fallbackReason: `\${{ needs.${SUB}.outputs.handoff-reason == 'limit-stop' && 'limit-stop' || needs.${SUB}.outputs.handoff-reason == 'credit-stop' && 'credit-stop' || needs.${SUB}.outputs.handoff-reason == 'auth' && 'auth' || needs.${SUB}.outputs.credential-present == 'false' && 'no-key' || '' }}`,
  keyOutputs: {
    "lane-class": `\${{ ${chain((c) => `steps.judge${c}.outputs.lane-class`)} }}`,
    handoff: `\${{ ${chain((c) => `steps.judge${c}.outputs.handoff == 'true'`)} }}`,
    "credential-present": "${{ steps.credential.outputs.present }}",
    "key-leg-clean": `\${{ ${chain((c) => `steps.key-leg${c}.outputs.clean`)} }}`,
    "skip-key": "${{ steps.credit.outputs.skip-key }}",
  },
  subOutputs: {
    handoff: `\${{ ${chain((c) => `steps.judge${c}.outputs.handoff == 'true'`)} }}`,
    "handoff-reason": `\${{ ${chain((c) => `steps.judge${c}.outputs.handoff-reason`)} }}`,
    "leg-clean": `\${{ ${chain((c) => `steps.sub-leg${c}.outputs.clean`)} }}`,
    "credential-present": "${{ steps.credential.outputs.present }}",
    "fallback-ready": "${{ steps.credential.outputs.fallback-ready }}",
  },
  keyFail: `always() && steps.agree.outcome == 'success' && steps.credit.outputs.skip-key != 'true' && steps.verdict.outcome != 'success' && steps.credential.outputs.present != 'false' && ${CHUNKS.map((c) => `steps.key-leg${c}.outcome != 'success'`).join(" && ")}`,
  subFail: `always() && steps.agree.outcome == 'success' && steps.verdict.outcome != 'success' && !(steps.credential.outputs.present == 'false' && steps.credential.outputs.fallback-ready == 'true') && ${CHUNKS.map((c) => `steps.sub-leg${c}.outcome != 'success'`).join(" && ")}`,
};
const failIf = (job) => wf.step(job, "credential") && /^ {6}- name: Fail without a verdict\n {8}if: (.*)$/m.exec(wf.job(job))[1];

const prefixed = (prefix, map) => Object.fromEntries(Object.entries(map).map(([k, v]) => [`${prefix}.${k}`, v]));
const evalMap = (map, ctx) => Object.fromEntries(Object.entries(map).map(([k, v]) => [k, value(v, ctx)]));

// The judge steps' outputs when the leg ran and ended at chunk `at` in
// `end`: earlier chunks judged and handed nothing on. `legStep` is the job's
// leg check (key-leg or sub-leg), which passes on a clean handoff.
function legSteps(ran, at, end, legStep) {
  const ctx = {};
  if (!ran) return ctx;
  for (const c of CHUNKS.slice(0, CHUNKS.indexOf(at))) Object.assign(ctx, { [`steps.judge${c}.outcome`]: "success", [`steps.judge${c}.outputs.handoff`]: "false" });
  const handoff = end.kind === "handoff";
  Object.assign(ctx, {
    [`steps.judge${at}.outcome`]: end.kind === "fail" ? "failure" : "success",
    [`steps.judge${at}.outputs.handoff`]: String(handoff),
    [`steps.judge${at}.outputs.handoff-reason`]: handoff ? end.reason : "",
    [`steps.judge${at}.outputs.lane-class`]: handoff ? end.reason : end.kind === "fail" ? "other" : "",
  });
  if (handoff) Object.assign(ctx, { [`steps.${legStep}${at}.outcome`]: end.clean ? "success" : "failure", [`steps.${legStep}${at}.outputs.clean`]: end.clean ? "true" : "" });
  if (end.kind === "verdict") ctx["steps.verdict.outcome"] = "success";
  return ctx;
}

// A job's result: a step that failed after the leg, or its own last check.
const result = (failAt, failExpr, ctx) => (failAt === "after-leg" || runs(failExpr, ctx) ? "failure" : "success");

function ends(handoffReason, leg, fallbackReady) {
  const out = [{ kind: "verdict" }, { kind: "fail" }];
  for (const { reason } of launcherOutcomes(handoffReason, leg, fallbackReady)) {
    if (reason !== "") for (const clean of [true, false]) out.push({ kind: "handoff", reason, clean });
  }
  return out;
}

function oldRun(s) {
  const out = { started: [], legs: {} };
  const base = { ...RUN, "steps.agree.outcome": s.agree ? "success" : "skipped" };
  // check-intent
  const keyCtx = { ...base };
  if (s.agree) keyCtx["steps.credit.outputs.skip-key"] = { ok: "false", skip: "true", failed: "" }[s.gate];
  if (s.agree && keyCtx["steps.credit.outputs.skip-key"] !== "true") keyCtx["steps.credential.outputs.present"] = String(s.key);
  const keyRan = keyCtx["steps.credential.outputs.present"] === "true";
  Object.assign(keyCtx, legSteps(keyRan, s.at, s.keyEnd, "key-leg"));
  out.started.push(KEY);
  out.legs[KEY] = { runs: keyRan };
  const needs = { ...RUN, [`needs.${KEY}.result`]: result(s.failAt, OLD.keyFail, keyCtx), ...prefixed(`needs.${KEY}.outputs`, evalMap(OLD.keyOutputs, keyCtx)) };
  if (!runs(OLD.sub, needs)) return out;
  out.started.push(SUB);
  const subCtx = { ...base };
  if (s.agree) Object.assign(subCtx, { "steps.credential.outputs.present": String(s.sub), "steps.credential.outputs.fallback-ready": String(s.fallback) });
  Object.assign(subCtx, legSteps(subCtx["steps.credential.outputs.present"] === "true", s.at, s.subEnd, "sub-leg"));
  out.legs[SUB] = { present: subCtx["steps.credential.outputs.present"] ?? "", "fallback-ready": subCtx["steps.credential.outputs.fallback-ready"] ?? "", "fallback-reason": value(OLD.subReason, needs) };
  Object.assign(needs, { [`needs.${SUB}.result`]: result(s.failAt, OLD.subFail, subCtx), ...prefixed(`needs.${SUB}.outputs`, evalMap(OLD.subOutputs, subCtx)) });
  if (!runs(OLD.fallback, needs)) return out;
  out.started.push(FB);
  out.legs[FB] = { present: s.agree ? String(s.fallback) : "", "fallback-reason": value(OLD.fallbackReason, needs) };
  return out;
}

// One job as the workflow now runs it.
function newJob(job, leg, s, needs, end, legStep) {
  const base = { ...RUN, ...needs, "steps.agree.outcome": s.agree ? "success" : "skipped", ...prefixed("secrets", Object.fromEntries(Object.entries(SECRETS).map(([k, name]) => [name, s[k] ? "set" : ""]))) };
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
    // The key call reads the credit history itself when it names key-job.
    const held = leg === "key" && input("key-job") !== "" && s.gate === "skip";
    credential = S.leg({ leg, role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), held, reason: input("reason") }).outputs;
  }
  const ctx = { ...base, ...prefixed("steps.credential.outputs", credential), ...legSteps(credential.present === "true", s.at, end, legStep) };
  const res = result(s.failAt, failIf(job), ctx);
  const outputs = { result: res };
  if (leg !== "fallback") {
    const next = wf.step(job, "next");
    assert.equal(next.if, "", `${job}'s next-leg call has no if`);
    // No if: it runs only when every step before it passed.
    const decided = res === "success" ? S.next({ state: value(next.inputs.state, ctx), handoff: value(next.inputs.handoff, ctx), handoffReason: value(next.inputs["handoff-reason"], ctx) }) : {};
    Object.assign(outputs, evalMap(wf.outputs(job), { ...ctx, ...prefixed("steps.next.outputs", decided) }));
  }
  return { credential, outputs };
}

function newRun(s) {
  const out = { started: [KEY], legs: {} };
  const key = newJob(KEY, "key", s, {}, s.keyEnd, "key-leg");
  // A held key's present is now `false` where the skipped step left it
  // empty; whether the key's judge runs, the one reader that matters, is
  // compared. The fail step reads key-skipped beside present.
  out.legs[KEY] = { runs: key.credential.present === "true" };
  const needs = { [`needs.${KEY}.result`]: key.outputs.result, ...prefixed(`needs.${KEY}.outputs`, key.outputs) };
  if (!runs(wf.jobIf(SUB), { ...RUN, ...needs })) return out;
  out.started.push(SUB);
  const sub = newJob(SUB, "subscription", s, needs, s.subEnd, "sub-leg");
  out.legs[SUB] = { present: sub.credential.present ?? "", "fallback-ready": sub.credential["fallback-ready"] ?? "", "fallback-reason": sub.credential["fallback-reason"] ?? "" };
  Object.assign(needs, { [`needs.${SUB}.result`]: sub.outputs.result, ...prefixed(`needs.${SUB}.outputs`, sub.outputs) });
  if (!runs(wf.jobIf(FB), { ...RUN, ...needs })) return out;
  out.started.push(FB);
  const fb = newJob(FB, "fallback", s, needs, { kind: "verdict" }, "fb-leg");
  out.legs[FB] = { present: fb.credential.present ?? "", "fallback-reason": fb.credential["fallback-reason"] ?? "" };
  return out;
}

function* states() {
  for (const agree of [true, false])
    for (const gate of ["ok", "skip", "failed"])
      for (const key of [true, false])
        for (const sub of [true, false])
          for (const fallback of [true, false])
            for (const failAt of ["none", "after-leg"])
              for (const at of ["", "-3", "-spec"])
                for (const keyEnd of ends(S.handoffReason, "api-key", false))
                  for (const subEnd of ends(S.handoffReason, "subscription", fallback))
                    // A run the gates stop judges nothing: one state of it is enough.
                    if (agree || (gate === "ok" && failAt === "none" && at === "" && keyEnd.kind === "verdict" && subEnd.kind === "verdict")) yield { agree, gate, key, sub, fallback, failAt, at, keyEnd, subEnd };
}

test("pr-verify's judge jobs start the same legs with the same credential decisions as before select-model-credential", () => {
  let count = 0;
  const shapes = new Set();
  for (const s of states()) {
    count++;
    const before = oldRun(s);
    assert.deepEqual(newRun(s), before, JSON.stringify(s));
    shapes.add(before.started.join(","));
  }
  for (const shape of [KEY, `${KEY},${SUB}`, `${KEY},${SUB},${FB}`]) assert.ok(shapes.has(shape), `reached ${shape}`);
  assert.ok(count > 1000, `${count} states`);
});

test("a step that fails after a clean handoff starts no next leg, as the old result == 'success' term required", () => {
  const s = { agree: true, gate: "ok", key: true, sub: true, fallback: true, failAt: "after-leg", at: "", keyEnd: { kind: "handoff", reason: "credit-stop", clean: true }, subEnd: { kind: "verdict" } };
  assert.deepEqual(newRun(s).started, [KEY]);
  assert.deepEqual(newRun({ ...s, failAt: "none" }).started, [KEY, SUB]);
});
