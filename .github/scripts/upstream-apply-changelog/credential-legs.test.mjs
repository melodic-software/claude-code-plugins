// upstream-apply-changelog.yml picks each leg's credential through
// ci-workflows' select-model-credential, fetched at the pin the workflow
// names. This truth table drives the workflow's own conditions and inputs
// through every combination of gate verdict, secrets set or empty, a model
// slot that applies or not, a step failing before or after the leg, and every
// launcher outcome run-claude-cli's own handoffReason can produce, and holds
// each state to the expressions the workflow used before the action (quoted
// from 5599e627fc): the same jobs start, and each leg gets the same present,
// fallback-ready and fallback-reason.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const TEXT = readFileSync(new URL("../../workflows/upstream-apply-changelog.yml", import.meta.url), "utf8");
const wf = workflowText(TEXT);
const S = await loadSelect(selectPin(TEXT));

const KEY = "ISSUE_LANE_CLAUDE_API_KEY";
const TOKEN = "ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN";
const FALLBACK = "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN";

// The two chains: the model's legs and the scrub probe's. `record` is whether
// a leg's lane record names a fallback reason (the probe's does not).
const CHAINS = [
  { legs: ["model", "model-subscription", "model-fallback"], launcher: "run", record: true },
  { legs: ["scrub-probe", "scrub-probe-subscription", "scrub-probe-fallback"], launcher: "probe", record: false },
];

// The old conditions and reasons, at 5599e627fc.
const OLD = ([key, sub]) => ({
  key: "needs.gate.outputs.proceed == 'true' && needs.gate.outputs.skip-key != 'true' && github.run_attempt == '1'",
  sub: `\${{ !cancelled() && needs.gate.outputs.proceed == 'true' && github.run_attempt == '1' && (needs.${key}.outputs.handoff == 'true' || needs.${key}.outputs.credential-present == 'false' || needs.gate.outputs.skip-key == 'true') }}`,
  fallback: `\${{ !cancelled() && needs.gate.outputs.proceed == 'true' && github.run_attempt == '1' && needs.${sub}.outputs.fallback-ready == 'true' && (needs.${sub}.outputs.handoff == 'true' || needs.${sub}.outputs.credential-present == 'false') }}`,
  subReason: `\${{ needs.${key}.outputs.handoff-reason || needs.${key}.outputs.credential-present == 'false' && 'no-key' || needs.gate.outputs.skip-key == 'true' && 'credit-stop' || '' }}`,
  fallbackReason: `\${{ needs.${sub}.outputs.handoff-reason || needs.${sub}.outputs.credential-present == 'false' && 'no-key' || '' }}`,
});

// A leg's run step: it starts only on a set credential and when no step
// before it failed; its handoff is the launcher's. Its lane record, which
// carries the fallback reason, runs only when it did.
const legRan = (present, failAt) => present === "true" && failAt !== "before-run";
const ran = (present, failAt, outcome) =>
  present === "true" && failAt !== "before-run" ? { handoff: outcome.handoff, "handoff-reason": outcome.reason } : { handoff: "", "handoff-reason": "" };

function oldChain(chain, s) {
  const o = OLD(chain.legs);
  const ctx = { "github.run_attempt": "1", "needs.gate.outputs.proceed": s.proceed, "needs.gate.outputs.skip-key": { ok: "false", skip: "true", failed: "" }[s.gate] };
  const out = { started: [], legs: {} };
  const [key, sub, fb] = chain.legs;
  if (runs(o.key, ctx)) {
    out.started.push(key);
    const present = s.applies ? String(s.key) : "";
    const leg = ran(present, s.failAt, s.keyOutcome);
    out.legs[key] = { present };
    Object.assign(ctx, { [`needs.${key}.outputs.handoff`]: leg.handoff, [`needs.${key}.outputs.handoff-reason`]: leg["handoff-reason"], [`needs.${key}.outputs.credential-present`]: present });
  }
  if (runs(o.sub, ctx)) {
    out.started.push(sub);
    const present = s.applies ? String(s.sub) : "";
    const ready = s.applies ? String(s.fallback) : "";
    const leg = ran(present, s.failAt, s.subOutcome);
    out.legs[sub] = { present, "fallback-ready": ready, ...(chain.record && legRan(present, s.failAt) && { "fallback-reason": value(o.subReason, ctx) }) };
    Object.assign(ctx, { [`needs.${sub}.outputs.handoff`]: leg.handoff, [`needs.${sub}.outputs.handoff-reason`]: leg["handoff-reason"], [`needs.${sub}.outputs.credential-present`]: present, [`needs.${sub}.outputs.fallback-ready`]: ready });
  }
  if (runs(o.fallback, ctx)) {
    out.started.push(fb);
    const present = s.applies ? String(s.fallback) : "";
    out.legs[fb] = { present, ...(chain.record && legRan(present, s.failAt) && { "fallback-reason": value(o.fallbackReason, ctx) }) };
  }
  return out;
}

// One leg job as the workflow now runs it: the credential call, the leg, and
// the next-leg call, each from the workflow's own inputs.
function newLeg(id, legName, ctx, s, outcome, launcher) {
  const call = wf.step(id, "credential");
  assert.equal(call.inputs.leg, legName, `${id} credential leg`);
  let outputs = {};
  if (s.applies) {
    const input = (name) => (call.inputs[name] === undefined ? "" : value(call.inputs[name], ctx));
    outputs = S.leg({ leg: legName, role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), reason: input("reason") }).outputs;
  }
  const leg = ran(outputs.present ?? "", s.failAt, outcome);
  const stepCtx = { ...ctx, ...prefixed("steps.credential.outputs", outputs), ...prefixed(`steps.${launcher}.outputs`, leg) };
  const result = { outputs };
  if (legName !== "fallback") {
    const next = wf.step(id, "next");
    assert.equal(next.if, "${{ always() }}", `${id} hands on whatever failed after its credential`);
    // A job that hit its own timeout after the leg is cancelled: only a step
    // whose if: still holds then runs. The job outputs the old shape read
    // survived it.
    const nextCtx = { ...stepCtx, "cancelled()": s.failAt === "timeout" };
    const decided = runs(next.if, nextCtx) ? S.next({ state: value(next.inputs.state, stepCtx), handoff: value(next.inputs.handoff, stepCtx), handoffReason: value(next.inputs["handoff-reason"], stepCtx) }) : {};
    const jobOutputs = wf.outputs(id);
    result.needs = Object.fromEntries(["next-leg", "next-reason"].map((name) => [`needs.${id}.outputs.${name}`, value(jobOutputs[name], { ...stepCtx, ...prefixed("steps.next.outputs", decided) })]));
  }
  return result;
}
const prefixed = (prefix, map) => Object.fromEntries(Object.entries(map).map(([k, v]) => [`${prefix}.${k}`, v]));

function newChain(chain, s) {
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
  const [key, sub, fb] = chain.legs;
  const record = (id, outputs, withReady, withReason) => ({
    present: outputs.present ?? "",
    ...(withReady && { "fallback-ready": outputs["fallback-ready"] ?? "" }),
    ...(withReason && chain.record && legRan(outputs.present, s.failAt) && { "fallback-reason": outputs["fallback-reason"] ?? "" }),
  });
  if (runs(wf.jobIf(key), ctx)) {
    out.started.push(key);
    const r = newLeg(key, "key", ctx, s, s.keyOutcome, chain.launcher);
    out.legs[key] = record(key, r.outputs, false, false);
    Object.assign(ctx, r.needs);
  }
  if (runs(wf.jobIf(sub), ctx)) {
    out.started.push(sub);
    const r = newLeg(sub, "subscription", ctx, s, s.subOutcome, chain.launcher);
    out.legs[sub] = record(sub, r.outputs, true, true);
    Object.assign(ctx, r.needs);
  }
  if (runs(wf.jobIf(fb), ctx)) {
    out.started.push(fb);
    out.legs[fb] = record(fb, newLeg(fb, "fallback", ctx, s, { handoff: "", reason: "" }, chain.launcher).outputs, false, true);
  }
  return out;
}

function* states() {
  for (const proceed of ["true", ""])
    for (const gate of ["ok", "skip", "failed"])
      for (const applies of [true, false])
        for (const key of [true, false])
          for (const sub of [true, false])
            for (const fallback of [true, false])
              for (const failAt of ["none", "before-run", "after-run", "timeout"])
                for (const keyOutcome of launcherOutcomes(S.handoffReason, "api-key", false))
                  for (const subOutcome of launcherOutcomes(S.handoffReason, "subscription", fallback))
                    yield { proceed, gate, applies, key, sub, fallback, failAt, keyOutcome, subOutcome };
}

for (const chain of CHAINS) {
  test(`${chain.legs[0]}'s chain starts the same legs with the same credential decisions as before select-model-credential`, () => {
    let count = 0;
    const started = new Set();
    for (const s of states()) {
      count++;
      const before = oldChain(chain, s);
      const after = newChain(chain, s);
      assert.deepEqual(after, before, JSON.stringify(s));
      started.add(before.started.join(","));
    }
    // Every shape of the chain is reached: none, key only, key then
    // subscription, the subscription alone (a gate skip), and on to fallback.
    for (const shape of ["", chain.legs[0], chain.legs.slice(0, 2).join(","), chain.legs.join(","), chain.legs[1], chain.legs.slice(1).join(",")]) {
      assert.ok(started.has(shape), `reached ${shape || "no leg"}`);
    }
    assert.ok(count > 1000, `${count} states`);
  });
}

test("a step that fails after a handoff still starts the next leg, as the old job outputs did", () => {
  const s = { proceed: "true", gate: "ok", applies: true, key: true, sub: true, fallback: true, failAt: "after-run", keyOutcome: { handoff: "true", reason: "credit-stop" }, subOutcome: { handoff: "false", reason: "" } };
  for (const chain of CHAINS) assert.deepEqual(newChain(chain, s).started, chain.legs.slice(0, 2));
});

test("a job that hits its own timeout after a handoff still starts the next leg, as the old job outputs did", () => {
  const s = { proceed: "true", gate: "ok", applies: true, key: true, sub: true, fallback: true, failAt: "timeout", keyOutcome: { handoff: "true", reason: "credit-stop" }, subOutcome: { handoff: "false", reason: "" } };
  for (const chain of CHAINS) assert.deepEqual(newChain(chain, s).started, chain.legs.slice(0, 2));
});
