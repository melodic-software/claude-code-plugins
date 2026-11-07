// maintenance-tidy-code-upkeep.yml picks each leg's credential through
// ci-workflows' select-model-credential, fetched at the pin the workflow
// names. This truth table drives the workflow's own conditions and inputs
// through every combination of gate verdict, secrets set or empty, a model
// that resolves or not, a step failing before or after the leg, and every
// launcher outcome run-claude-cli's own handoffReason can produce, and holds
// each state to the expressions the workflow used before the action (quoted
// from 5599e627fc): the same jobs start, and each leg gets the same present,
// fallback-ready and fallback-reason.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const TEXT = readFileSync(new URL("../../workflows/maintenance-tidy-code-upkeep.yml", import.meta.url), "utf8");
const wf = workflowText(TEXT);
const S = await loadSelect(selectPin(TEXT));

const KEY = "AUTOMATIONS_CLAUDE_API_KEY";
const TOKEN = "AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN";
const FALLBACK = "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN";
const LEGS = ["model", "model-subscription", "model-fallback"];

// The old conditions and reasons, at 5599e627fc. model-fallback's had no
// fallback-ready term: an empty subscription token started it whatever the
// fallback token held.
const OLD = {
  key: "needs.gate.outputs.proceed == 'true' && needs.gate.outputs.skip-key != 'true' && github.run_attempt == '1'",
  sub: "${{ !cancelled() && needs.gate.outputs.proceed == 'true' && github.run_attempt == '1' && (needs.model.outputs.handoff == 'true' || needs.model.outputs.credential-present == 'false' || needs.gate.outputs.skip-key == 'true') }}",
  fallback: "${{ !cancelled() && needs.gate.outputs.proceed == 'true' && github.run_attempt == '1' && (needs.model-subscription.outputs.handoff == 'true' || needs.model-subscription.outputs.credential-present == 'false') }}",
  subReason: "${{ needs.model.outputs.handoff-reason || needs.model.outputs.credential-present == 'false' && 'no-key' || needs.gate.outputs.skip-key == 'true' && 'credit-stop' || '' }}",
  fallbackReason: "${{ needs.model-subscription.outputs.handoff-reason || needs.model-subscription.outputs.credential-present == 'false' && 'no-key' || '' }}",
};

// A leg's run step: it starts only on a set credential and when no step
// before it failed; its handoff is the launcher's. Its lane record, which
// carries the fallback reason, runs only when it did.
const legRan = (present, failAt) => present === "true" && failAt !== "before-run";
const ran = (present, failAt, outcome) => (legRan(present, failAt) ? { handoff: outcome.handoff, "handoff-reason": outcome.reason } : { handoff: "", "handoff-reason": "" });
const prefixed = (prefix, map) => Object.fromEntries(Object.entries(map).map(([k, v]) => [`${prefix}.${k}`, v]));

function oldChain(s) {
  const ctx = { "github.run_attempt": "1", "needs.gate.outputs.proceed": s.proceed, "needs.gate.outputs.skip-key": { ok: "false", skip: "true", failed: "" }[s.gate] };
  const out = { started: [], legs: {} };
  const [key, sub, fb] = LEGS;
  if (runs(OLD.key, ctx)) {
    out.started.push(key);
    const present = s.resolves ? String(s.key) : "";
    const leg = ran(present, s.failAt, s.keyOutcome);
    out.legs[key] = { present };
    Object.assign(ctx, prefixed(`needs.${key}.outputs`, { handoff: leg.handoff, "handoff-reason": leg["handoff-reason"], "credential-present": present }));
  }
  if (runs(OLD.sub, ctx)) {
    out.started.push(sub);
    const present = s.resolves ? String(s.sub) : "";
    const ready = s.resolves ? String(s.fallback) : "";
    const leg = ran(present, s.failAt, s.subOutcome);
    out.legs[sub] = { present, "fallback-ready": ready, ...(legRan(present, s.failAt) && { "fallback-reason": value(OLD.subReason, ctx) }) };
    Object.assign(ctx, prefixed(`needs.${sub}.outputs`, { handoff: leg.handoff, "handoff-reason": leg["handoff-reason"], "credential-present": present }));
  }
  if (runs(OLD.fallback, ctx)) {
    out.started.push(fb);
    const present = s.resolves ? String(s.fallback) : "";
    out.legs[fb] = { present, ...(legRan(present, s.failAt) && { "fallback-reason": value(OLD.fallbackReason, ctx) }) };
  }
  return out;
}

// One leg job as the workflow now runs it: the credential call, the leg, and
// the next-leg call, each from the workflow's own inputs.
function newLeg(id, legName, ctx, s, outcome) {
  const call = wf.step(id, "credential");
  assert.equal(call.inputs.leg, legName, `${id} credential leg`);
  let outputs = {};
  if (s.resolves) {
    const input = (name) => (call.inputs[name] === undefined ? "" : value(call.inputs[name], ctx));
    outputs = S.leg({ leg: legName, role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), reason: input("reason") }).outputs;
  }
  const leg = ran(outputs.present ?? "", s.failAt, outcome);
  const stepCtx = { ...ctx, ...prefixed("steps.credential.outputs", outputs), ...prefixed("steps.run.outputs", leg) };
  const result = { outputs };
  if (legName !== "fallback") {
    const next = wf.step(id, "next");
    assert.equal(next.if, "${{ always() }}", `${id} hands on whatever failed after its credential`);
    const decided = S.next({ state: value(next.inputs.state, stepCtx), handoff: value(next.inputs.handoff, stepCtx), handoffReason: value(next.inputs["handoff-reason"], stepCtx) });
    const jobOutputs = wf.outputs(id);
    const names = Object.keys(jobOutputs).filter((n) => !n.startsWith("sealed-"));
    result.needs = Object.fromEntries(names.map((name) => [`needs.${id}.outputs.${name}`, value(jobOutputs[name], { ...stepCtx, ...prefixed("steps.next.outputs", decided) })]));
  }
  return result;
}

function newChain(s) {
  const gate = s.gate === "failed" ? {} : S.start({ skipKey: s.gate === "skip" });
  const gateOutputs = wf.outputs("gate");
  const ctx = {
    "github.run_attempt": "1",
    "needs.gate.outputs.proceed": s.proceed,
    ...Object.fromEntries(["next-leg", "next-reason"].map((n) => [`needs.gate.outputs.${n}`, value(gateOutputs[n], prefixed("steps.credit.outputs", gate))])),
    [`secrets.${KEY}`]: s.key ? "set" : "",
    [`secrets.${TOKEN}`]: s.sub ? "set" : "",
    [`secrets.${FALLBACK}`]: s.fallback ? "set" : "",
  };
  const out = { started: [], legs: {} };
  const [key, sub, fb] = LEGS;
  const record = (outputs, withReady, withReason) => ({
    present: outputs.present ?? "",
    ...(withReady && { "fallback-ready": outputs["fallback-ready"] ?? "" }),
    ...(withReason && legRan(outputs.present, s.failAt) && { "fallback-reason": outputs["fallback-reason"] ?? "" }),
  });
  if (runs(wf.jobIf(key), ctx)) {
    out.started.push(key);
    const r = newLeg(key, "key", ctx, s, s.keyOutcome);
    out.legs[key] = record(r.outputs, false, false);
    Object.assign(ctx, r.needs);
  }
  if (runs(wf.jobIf(sub), ctx)) {
    out.started.push(sub);
    const r = newLeg(sub, "subscription", ctx, s, s.subOutcome);
    out.legs[sub] = record(r.outputs, true, true);
    Object.assign(ctx, r.needs);
  }
  if (runs(wf.jobIf(fb), ctx)) {
    out.started.push(fb);
    out.legs[fb] = record(newLeg(fb, "fallback", ctx, s, { handoff: "", reason: "" }).outputs, false, true);
  }
  return out;
}

function* states() {
  for (const proceed of ["true", ""])
    for (const gate of ["ok", "skip", "failed"])
      for (const resolves of [true, false])
        for (const key of [true, false])
          for (const sub of [true, false])
            for (const fallback of [true, false])
              for (const failAt of ["none", "before-run", "after-run"])
                for (const keyOutcome of launcherOutcomes(S.handoffReason, "api-key", false))
                  for (const subOutcome of launcherOutcomes(S.handoffReason, "subscription", fallback))
                    yield { proceed, gate, resolves, key, sub, fallback, failAt, keyOutcome, subOutcome };
}

test("the sweep's legs start the same jobs with the same credential decisions as before select-model-credential", () => {
  let count = 0;
  const started = new Set();
  for (const s of states()) {
    count++;
    const before = oldChain(s);
    assert.deepEqual(newChain(s), before, JSON.stringify(s));
    started.add(before.started.join(","));
  }
  // Every shape of the chain is reached: none, key only, key then
  // subscription, the subscription alone (a gate skip), and on to fallback.
  for (const shape of ["", LEGS[0], LEGS.slice(0, 2).join(","), LEGS.join(","), LEGS[1], LEGS.slice(1).join(",")]) {
    assert.ok(started.has(shape), `reached ${shape || "no leg"}`);
  }
  assert.ok(count > 1000, `${count} states`);
});

test("a step that fails after a handoff still starts the next leg, as the old job outputs did", () => {
  const s = { proceed: "true", gate: "ok", resolves: true, key: true, sub: true, fallback: true, failAt: "after-run", keyOutcome: { handoff: "true", reason: "credit-stop" }, subOutcome: { handoff: "false", reason: "" } };
  assert.deepEqual(newChain(s).started, LEGS.slice(0, 2));
});

test("an empty subscription token starts model-fallback even with the fallback token empty, as before", () => {
  const s = { proceed: "true", gate: "ok", resolves: true, key: false, sub: false, fallback: false, failAt: "none", keyOutcome: { handoff: "", reason: "" }, subOutcome: { handoff: "", reason: "" } };
  assert.deepEqual(newChain(s), oldChain(s));
  assert.deepEqual(newChain(s).started, LEGS);
});
