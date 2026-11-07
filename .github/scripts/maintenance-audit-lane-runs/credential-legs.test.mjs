// maintenance-audit-lane-runs.yml picks each judge leg's credential through
// ci-workflows' select-model-credential, fetched at the pin the workflow
// names: collect's start call, then in each matrix leg a credential call and,
// in the key and subscription legs, a next-leg call whose verdict the handoff
// marker records. A matrix job's outputs are not per unit, so the chain runs
// per unit through the markers and the route jobs; this truth table follows
// one unit through every combination of credit verdict, secrets set or empty,
// a model that resolves or not, a step failing before the leg or the marker
// upload failing after it, every launcher outcome run-claude-cli's own
// handoffReason can produce, and the leg check clean or not, and holds each
// state to the expressions the workflow used before the action (quoted from
// 5599e627fc): the same jobs start for the unit, each leg gets the same
// present and fallback-ready, each later leg's record the same fallback
// reason, and each marker the same reason.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs as runsRaw, selectPin, value as valueRaw } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";
import { marker, routeSkipped } from "./handoff.mjs";

const TEXT = readFileSync(new URL("../../workflows/maintenance-audit-lane-runs.yml", import.meta.url), "utf8");
const wf = workflowText(TEXT);
const S = await loadSelect(selectPin(TEXT));

const UNIT = "a1";
const UNITS = JSON.stringify([UNIT]);
const SECRETS = { key: "AUTOMATIONS_CLAUDE_API_KEY", sub: "AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN", fallback: "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN" };
const LEGS = [
  ["judge", "key", "key-leg"],
  ["judge-subscription", "subscription", "sub-leg"],
  ["judge-fallback", "fallback", ""],
];

// The shared evaluator reads only needs/steps/github/vars/inputs/secrets
// names; matrix.x is read as inputs.matrix.x.
const m = (expression) => expression.replace(/\bmatrix\./g, "inputs.matrix.");
const runs = (expression, ctx) => runsRaw(m(expression), ctx);
const value = (expression, ctx) => valueRaw(m(expression), ctx);

// The old conditions and expressions, at 5599e627fc.
const OLD = {
  judge: "needs.collect.outputs.units != '' && needs.collect.outputs.units != '[]' && needs.collect.outputs.skip-key != 'true'",
  handoffs: "${{ !cancelled() && (needs.judge.result != 'skipped' || needs.collect.outputs.skip-key == 'true' && needs.collect.outputs.units != '' && needs.collect.outputs.units != '[]') }}",
  download: "steps.kill.outputs.proceed == 'true' && needs.collect.outputs.skip-key != 'true'",
  routeSkipped: "steps.kill.outputs.proceed == 'true' && needs.collect.outputs.skip-key == 'true'",
  record: {
    judge: "steps.key-leg.outputs.clean == 'true' || steps.credential.outputs.present == 'false'",
    "judge-subscription": "steps.sub-leg.outputs.clean == 'true' || steps.credential.outputs.present == 'false' && steps.credential.outputs.fallback-ready == 'true'",
  },
  reason: "${{ steps.credential.outputs.present == 'false' && 'no-key' || steps.judge.outputs.handoff-reason }}",
  fallbackReason: {
    "judge-subscription": "${{ matrix.reason == 'credit-stop' && 'credit-stop' || matrix.reason == 'auth' && 'auth' || matrix.reason == 'no-key' && 'no-key' || '' }}",
    "judge-fallback": "${{ matrix.reason == 'limit-stop' && 'limit-stop' || matrix.reason == 'credit-stop' && 'credit-stop' || matrix.reason == 'auth' && 'auth' || matrix.reason == 'no-key' && 'no-key' || '' }}",
  },
};

const prefixed = (prefix, map) => Object.fromEntries(Object.entries(map).map(([k, v]) => [`${prefix}.${k}`, v]));
const stepBlock = (job, name) => wf.job(job).split(/\n(?= {6}- name: )/).find((b) => b.startsWith(`      - name: ${name}\n`));
const envOf = (block, name) => new RegExp(`^ {10}${name}: (.*)$`, "m").exec(block)[1];

// The judge step and its leg check: the judge runs on a present credential
// when no step before it failed; the check passes on a clean handoff.
function legSteps(present, s, outcome, check) {
  const ran = present === "true" && s.failAt !== "before-run";
  const ctx = { "steps.judge.outcome": ran ? "success" : "skipped" };
  if (ran) Object.assign(ctx, { "steps.judge.outputs.handoff": outcome.handoff, "steps.judge.outputs.handoff-reason": outcome.reason });
  if (ran && check && outcome.handoff === "true" && outcome.clean) ctx[`steps.${check}.outputs.clean`] = "true";
  return { ran, ctx };
}

// The marker a leg uploads, from its record step's condition and REASON:
// handoff.mjs refuses a reason outside its closed set, and a failed upload
// leaves none.
function uploaded(leg, recorded, reason, s) {
  if (!recorded || s.failAt === "before-run") return null;
  let record;
  try {
    record = marker(leg, UNIT, reason);
  } catch {
    return null;
  }
  return s.failAt === "after-upload" ? null : record;
}

// One unit's run, given how each leg job decides it: `decide(job, leg, ctx,
// s, outcome, check)` returns { leg record, marker }.
function chain(s, collect, decide, ifs) {
  const out = { started: [], legs: {} };
  const ctx = { "needs.collect.outputs.units": UNITS, ...collect, ...prefixed("secrets", Object.fromEntries(Object.entries(SECRETS).map(([k, n]) => [n, s[k] ? "set" : ""]))) };
  let routed = null;
  if (runs(ifs.judge, ctx)) {
    out.started.push("judge");
    const r = decide("judge", "key", ctx, s, s.keyOutcome, "key-leg");
    out.legs.judge = r.record;
    routed = r.marker;
  }
  ctx["needs.judge.result"] = out.started.includes("judge") ? "success" : "skipped";
  if (!runs(ifs.handoffs, ctx)) return out;
  out.started.push("judge-handoffs");
  const route = { "steps.kill.outputs.proceed": "true", ...ctx };
  let reason = null;
  if (runs(ifs.download, route)) reason = routed?.reason ?? null;
  if (runs(ifs.routeSkipped, route)) reason = routeSkipped([UNIT]).include[0].reason;
  if (reason === null) return out;
  out.started.push("judge-subscription");
  const r = decide("judge-subscription", "subscription", { ...ctx, "inputs.matrix.reason": reason }, s, s.subOutcome, "sub-leg");
  out.legs["judge-subscription"] = r.record;
  if (!r.marker) return out;
  out.started.push("judge-fallback");
  out.legs["judge-fallback"] = decide("judge-fallback", "fallback", { ...ctx, "inputs.matrix.reason": r.marker.reason }, s, { handoff: "", reason: "" }, "").record;
  return out;
}

function oldDecide(job, leg, ctx, s, outcome, check) {
  const present = s.resolves ? String(s[{ key: "key", subscription: "sub", fallback: "fallback" }[leg]]) : "";
  const ready = leg === "subscription" && s.resolves ? String(s.fallback) : "";
  const steps = { ...ctx, "steps.credential.outputs.present": present, "steps.credential.outputs.fallback-ready": ready };
  const { ran, ctx: run } = legSteps(present, s, outcome, check);
  Object.assign(steps, run);
  const record = { present, ...(leg === "subscription" && { "fallback-ready": ready }), ...(ran && leg !== "key" && { "fallback-reason": value(OLD.fallbackReason[job], steps) }) };
  const recorded = leg !== "fallback" && runs(OLD.record[job], steps);
  return { record, marker: uploaded(leg, recorded, recorded ? value(OLD.reason, steps) : "", s) };
}

function newDecide(job, leg, ctx, s, outcome, check) {
  const call = wf.step(job, "credential");
  assert.equal(call.inputs.leg, leg, job);
  let credential = {};
  if (s.resolves) {
    const input = (name) => (call.inputs[name] === undefined ? "" : value(call.inputs[name], ctx));
    credential = S.leg({ leg, role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), reason: input("reason") }).outputs;
  }
  const present = credential.present ?? "";
  const steps = { ...ctx, ...prefixed("steps.credential.outputs", credential) };
  const { ran, ctx: run } = legSteps(present, s, outcome, check);
  Object.assign(steps, run);
  const report = stepBlock(job, "Report the judgment's outcome");
  const reasonInput = /^ {10}fallback-reason: (.*)$/m.exec(report)?.[1];
  const record = { present, ...(leg === "subscription" && { "fallback-ready": credential["fallback-ready"] ?? "" }), ...(ran && leg !== "key" && { "fallback-reason": value(reasonInput, steps) }) };
  if (leg === "fallback") return { record, marker: null };
  const next = wf.step(job, "next");
  assert.equal(next.if, "", `${job}'s next-leg call has no if, as the record step after it has none`);
  // No if: it runs only when every step before it passed.
  if (s.failAt !== "before-run") {
    const input = (name) => value(next.inputs[name], steps);
    Object.assign(steps, prefixed("steps.next.outputs", S.next({ state: input("state"), handoff: input("handoff"), handoffReason: input("handoff-reason") })));
  }
  const recordStep = wf.step(job, "handoff");
  const recorded = runs(recordStep.if, steps);
  return { record, marker: uploaded(leg, recorded, recorded ? value(envOf(recordStep.text, "REASON"), steps) : "", s) };
}

function oldRun(s) {
  const collect = { "needs.collect.outputs.skip-key": { ok: "false", skip: "true", failed: "" }[s.gate] };
  return chain(s, collect, oldDecide, { judge: OLD.judge, handoffs: OLD.handoffs, download: OLD.download, routeSkipped: OLD.routeSkipped });
}

function newRun(s) {
  const start = s.gate === "failed" ? {} : S.start({ skipKey: s.gate === "skip" });
  const outputs = wf.outputs("collect");
  const collect = { "needs.collect.outputs.next-leg": value(outputs["next-leg"], prefixed("steps.credit.outputs", start)) };
  return chain(s, collect, newDecide, {
    judge: wf.jobIf("judge"),
    handoffs: wf.jobIf("judge-handoffs"),
    download: wf.step("judge-handoffs", "download").if,
    routeSkipped: wf.step("judge-handoffs", "route-skipped").if,
  });
}

// Each launcher outcome, and for a handoff the leg check clean or not.
function outcomes(leg, fallbackReady) {
  return launcherOutcomes(S.handoffReason, leg, fallbackReady).flatMap((o) => (o.handoff === "true" ? [true, false].map((clean) => ({ ...o, clean })) : [o]));
}

function* states() {
  for (const gate of ["ok", "skip", "failed"])
    for (const resolves of [true, false])
      for (const key of [true, false])
        for (const sub of [true, false])
          for (const fallback of [true, false])
            for (const failAt of ["none", "before-run", "after-upload"])
              for (const keyOutcome of outcomes("api-key", false))
                for (const subOutcome of outcomes("subscription", fallback)) yield { gate, resolves, key, sub, fallback, failAt, keyOutcome, subOutcome };
}

test("one unit starts the same legs with the same credential decisions as before select-model-credential", () => {
  let count = 0;
  const shapes = new Set();
  for (const s of states()) {
    count++;
    const before = oldRun(s);
    assert.deepEqual(newRun(s), before, JSON.stringify(s));
    shapes.add(before.started.join(","));
  }
  for (const shape of [
    "judge,judge-handoffs",
    "judge,judge-handoffs,judge-subscription",
    "judge,judge-handoffs,judge-subscription,judge-fallback",
    "judge-handoffs,judge-subscription",
    "judge-handoffs,judge-subscription,judge-fallback",
  ]) {
    assert.ok(shapes.has(shape), `reached ${shape}`);
  }
  assert.ok(count > 1000, `${count} states`);
});

test("a key leg that hit a denial hands its unit on to no leg, as before", () => {
  const s = { gate: "ok", resolves: true, key: true, sub: true, fallback: true, failAt: "none", keyOutcome: { handoff: "true", reason: "credit-stop", clean: false }, subOutcome: { handoff: "false", reason: "" } };
  assert.deepEqual(newRun(s).started, ["judge", "judge-handoffs"]);
  assert.deepEqual(newRun({ ...s, keyOutcome: { ...s.keyOutcome, clean: true } }).started, ["judge", "judge-handoffs", "judge-subscription"]);
});

test("a failed marker upload after a clean handoff hands the unit on to no leg, as before", () => {
  const s = { gate: "ok", resolves: true, key: true, sub: true, fallback: true, failAt: "after-upload", keyOutcome: { handoff: "true", reason: "auth", clean: true }, subOutcome: { handoff: "false", reason: "" } };
  assert.deepEqual(newRun(s), oldRun(s));
  assert.deepEqual(newRun(s).started, ["judge", "judge-handoffs"]);
});
