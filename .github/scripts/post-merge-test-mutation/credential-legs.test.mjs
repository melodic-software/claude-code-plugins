// post-merge-test-mutation.yml picks each leg's credential through
// ci-workflows' select-model-credential, fetched at the pin the workflow
// names. This truth table drives the workflow's own conditions and inputs for
// both chains (generate and triage) through every combination of the chain's
// upstream gate and same-repo term, the credit gate's verdict, secrets set or
// empty, a step failing before the credential, before the leg or after it
// (the key job's and the later legs' each on its own), and every launcher
// outcome run-claude-cli's own handoffReason can produce, and holds each state
// to the expressions the workflow used before the action (quoted from
// 5599e627fc): the same jobs start, and each leg runs its model or not, fails
// for want of a token or not, and gets the same fallback-ready and
// fallback-reason.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const TEXT = readFileSync(new URL("../../workflows/post-merge-test-mutation.yml", import.meta.url), "utf8");
const wf = workflowText(TEXT);
const S = await loadSelect(selectPin(TEXT));

const KEY = "AUTOMATIONS_CLAUDE_API_KEY";
const TOKEN = "AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN";
const FALLBACK = "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN";
const SAME_REPO = "github.event.workflow_run.head_repository.full_name == github.repository";

// Each chain's own upstream term, as the old conditions wrote it, and the
// context that makes it true or false.
const CHAINS = {
  generate: {
    upstream: "needs.prep.outputs.proceed == 'true'",
    context: (open) => ({ "needs.prep.outputs.proceed": open ? "true" : "" }),
  },
  triage: {
    upstream: "needs.mutate.result == 'success' && needs.mutate.outputs.survivors != '' && needs.mutate.outputs.survivors != '0'",
    context: (open) => ({ "needs.prep.outputs.proceed": "true", "needs.mutate.result": open ? "success" : "failure", "needs.mutate.outputs.survivors": open ? "3" : "" }),
  },
};

// The old conditions and reasons, at 5599e627fc.
const OLD = (stage) => {
  const [key, sub] = [stage, `${stage}-subscription`];
  const head = `!cancelled() && ${CHAINS[stage].upstream} && ${SAME_REPO}`;
  return {
    key: `\${{ ${head} }}`,
    sub: `\${{ ${head} && (needs.${key}.outputs.handoff == 'true' || needs.${key}.outputs.credential-present == 'false' || needs.key-credit.outputs.skip-${stage}-key == 'true') }}`,
    fallback: `\${{ ${head} && needs.${sub}.outputs.fallback-ready == 'true' && (needs.${sub}.outputs.handoff == 'true' || needs.${sub}.outputs.credential-present == 'false') }}`,
    subReason: `\${{ needs.${key}.outputs.handoff-reason || needs.key-credit.outputs.skip-${stage}-key == 'true' && 'credit-stop' || needs.${key}.outputs.credential-present == 'false' && 'no-key' || '' }}`,
    fallbackReason: `\${{ needs.${sub}.outputs.handoff-reason || 'no-key' }}`,
  };
};

// Where a step fails in a leg job: the key job's own, the later legs' shared.
const failOf = (s, legName) => (legName === "key" ? s.keyFail : s.legFail);

// A leg's run step starts only on a model that runs and when no step between
// the credential and it failed; its handoff is the launcher's. Its lane
// record, which carries the fallback reason, runs only when it did.
const legRan = (model, failAt) => model && failAt !== "before-run";
const ran = (model, failAt, outcome) => (legRan(model, failAt) ? { handoff: outcome.handoff, "handoff-reason": outcome.reason } : { handoff: "", "handoff-reason": "" });

// What a leg did: whether its model runs, whether it failed for want of a
// token, and, when its model ran, the fallback-ready it passed the launcher
// and the fallback reason its record names.
const record = (failAt, { model, failed, ready, reason }) => ({
  model,
  failed,
  ...(ready !== undefined && legRan(model, failAt) && { "fallback-ready": ready }),
  ...(reason !== undefined && legRan(model, failAt) && { "fallback-reason": reason }),
});

const baseContext = (stage, s) => ({
  ...CHAINS[stage].context(s.head === "open"),
  "github.event.workflow_run.head_repository.full_name": "o/r",
  "github.repository": s.head === "other-repo" ? "x/y" : "o/r",
});

function oldChain(stage, s) {
  const o = OLD(stage);
  const [key, sub, fb] = [stage, `${stage}-subscription`, `${stage}-fallback`];
  const ctx = { ...baseContext(stage, s), [`needs.key-credit.outputs.skip-${stage}-key`]: { ok: "false", skip: "true", failed: "" }[s.gate] };
  const out = { started: [], legs: {} };
  if (runs(o.key, ctx)) {
    out.started.push(key);
    const checked = s.keyFail !== "before-credential";
    // present: whether the key is set; run: that, unless the gate skipped it.
    const present = checked ? String(s.key) : "";
    const model = checked && s.key && ctx[`needs.key-credit.outputs.skip-${stage}-key`] !== "true";
    const leg = ran(model, s.keyFail, s.keyOutcome);
    out.legs[key] = record(s.keyFail, { model, failed: false });
    Object.assign(ctx, { [`needs.${key}.outputs.handoff`]: leg.handoff, [`needs.${key}.outputs.handoff-reason`]: leg["handoff-reason"], [`needs.${key}.outputs.credential-present`]: present });
  }
  const checked = s.legFail !== "before-credential";
  if (runs(o.sub, ctx)) {
    out.started.push(sub);
    // With both tokens empty the step exits 1 before it writes an output.
    const failed = checked && !s.sub && !s.fallback;
    const present = checked && !failed ? String(s.sub) : "";
    const ready = checked && !failed ? String(s.fallback) : "";
    const model = present === "true";
    const leg = ran(model, s.legFail, s.subOutcome);
    out.legs[sub] = record(s.legFail, { model, failed, ready, reason: value(o.subReason, ctx) });
    Object.assign(ctx, { [`needs.${sub}.outputs.handoff`]: leg.handoff, [`needs.${sub}.outputs.handoff-reason`]: leg["handoff-reason"], [`needs.${sub}.outputs.credential-present`]: present, [`needs.${sub}.outputs.fallback-ready`]: ready });
  }
  if (runs(o.fallback, ctx)) {
    out.started.push(fb);
    const failed = checked && !s.fallback;
    const model = checked && !failed;
    out.legs[fb] = record(s.legFail, { model, failed, reason: value(o.fallbackReason, ctx) });
  }
  return out;
}

const prefixed = (prefix, map) => Object.fromEntries(Object.entries(map).map(([k, v]) => [`${prefix}.${k}`, v]));

// One leg job as the workflow now runs it: the credential call, the no-token
// stop, the leg, and the next-leg call, each from the workflow's own inputs.
function newLeg(id, legName, ctx, failAt, outcome) {
  const call = wf.step(id, "credential");
  assert.equal(call.inputs.leg, legName, `${id} credential leg`);
  assert.equal(call.if, "", `${id} credential call runs unless a step before it failed`);
  let outputs = {};
  let failed = false;
  if (failAt !== "before-credential") {
    const input = (name) => (call.inputs[name] === undefined ? "" : value(call.inputs[name], ctx));
    outputs = S.leg({ leg: legName, role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), reason: input("reason") }).outputs;
    if (legName !== "key") failed = runs(wf.step(id, "no-token").if, prefixed("steps.credential.outputs", outputs));
  }
  const model = outputs.present === "true";
  assert.ok(!(failed && model), `${id} fails only when its model does not run`);
  const leg = ran(model, failAt, outcome);
  const stepCtx = { ...ctx, ...prefixed("steps.credential.outputs", outputs), ...prefixed("steps.run.outputs", leg) };
  const result = { outputs, model, failed };
  if (legName !== "fallback") {
    const next = wf.step(id, "next");
    assert.equal(next.if, "${{ always() }}", `${id} hands on whatever failed after its credential`);
    assert.match(next.text, /^ {8}continue-on-error: true$/m, `${id} next-leg call`);
    const decided = S.next({ state: value(next.inputs.state, stepCtx), handoff: value(next.inputs.handoff, stepCtx), handoffReason: value(next.inputs["handoff-reason"], stepCtx) });
    const jobOutputs = wf.outputs(id);
    result.needs = Object.fromEntries(["next-leg", "next-reason"].map((name) => [`needs.${id}.outputs.${name}`, value(jobOutputs[name], { ...stepCtx, ...prefixed("steps.next.outputs", decided) })]));
  } else {
    assert.equal(wf.job(id).includes("id: next\n"), false, `${id}, the last leg, names no next leg`);
  }
  return result;
}

// The lane record's fallback reason (the step has no id, so it is found by
// name) and the launcher's fallback-ready, from the workflow's own inputs.
const recordInput = (id) => {
  const steps = wf.job(id).split(/\n(?= {6}- name: )/).filter((step) => step.startsWith("      - name: Record the leg\n"));
  assert.equal(steps.length, 1, `${id} Record the leg`);
  return /^ {10}fallback-reason: (.*)$/m.exec(steps[0])[1];
};
const recordReason = (id, outputs) => value(recordInput(id), prefixed("steps.credential.outputs", outputs));
const runReady = (id, outputs) => value(wf.step(id, "run").inputs["fallback-ready"], prefixed("steps.credential.outputs", outputs));

function newChain(stage, s) {
  const [key, sub, fb] = [stage, `${stage}-subscription`, `${stage}-fallback`];
  const gate = s.gate === "failed" ? {} : S.start({ skipKey: s.gate === "skip" });
  const gateOutputs = wf.outputs("key-credit");
  const ctx = {
    ...baseContext(stage, s),
    ...Object.fromEntries(["next-leg", "next-reason"].map((n) => [`needs.key-credit.outputs.${stage}-${n}`, value(gateOutputs[`${stage}-${n}`], prefixed(`steps.credit-${stage}.outputs`, gate))])),
    [`secrets.${KEY}`]: s.key ? "set" : "",
    [`secrets.${TOKEN}`]: s.sub ? "set" : "",
    [`secrets.${FALLBACK}`]: s.fallback ? "set" : "",
  };
  const out = { started: [], legs: {} };
  if (runs(wf.jobIf(key), ctx)) {
    out.started.push(key);
    const r = newLeg(key, "key", ctx, failOf(s, "key"), s.keyOutcome);
    out.legs[key] = record(s.keyFail, r);
    Object.assign(ctx, r.needs);
  }
  if (runs(wf.jobIf(sub), ctx)) {
    out.started.push(sub);
    const r = newLeg(sub, "subscription", ctx, failOf(s, "subscription"), s.subOutcome);
    out.legs[sub] = record(s.legFail, { ...r, ready: runReady(sub, r.outputs), reason: recordReason(sub, r.outputs) });
    Object.assign(ctx, r.needs);
  }
  if (runs(wf.jobIf(fb), ctx)) {
    out.started.push(fb);
    const r = newLeg(fb, "fallback", ctx, failOf(s, "fallback"), { handoff: "", reason: "" });
    out.legs[fb] = record(s.legFail, { ...r, reason: recordReason(fb, r.outputs) });
  }
  return out;
}

// A step failing after the leg reads, for the credential decisions, as no
// failure: the next-leg call runs on !cancelled() either way.
const FAILS = ["before-credential", "before-run", "after-run"];

// A closed upstream gate or another repository starts no leg, so one launcher
// outcome each is enough there.
function* states() {
  for (const head of ["open", "closed", "other-repo"])
    for (const gate of ["ok", "skip", "failed"])
      for (const key of [true, false])
        for (const sub of [true, false])
          for (const fallback of [true, false])
            for (const keyFail of FAILS)
              for (const legFail of FAILS)
                for (const keyOutcome of launcherOutcomes(S.handoffReason, "api-key", false).slice(0, head === "open" ? undefined : 1))
                  for (const subOutcome of launcherOutcomes(S.handoffReason, "subscription", fallback).slice(0, head === "open" ? undefined : 1))
                    yield { head, gate, key, sub, fallback, keyFail, legFail, keyOutcome, subOutcome };
}

for (const stage of Object.keys(CHAINS)) {
  test(`the ${stage} chain starts the same legs with the same credential decisions as before select-model-credential`, () => {
    let count = 0;
    const started = new Set();
    const failed = new Set();
    for (const s of states()) {
      count++;
      const before = oldChain(stage, s);
      const after = newChain(stage, s);
      assert.deepEqual(after, before, JSON.stringify(s));
      started.add(before.started.join(","));
      for (const [id, leg] of Object.entries(before.legs)) if (leg.failed) failed.add(id);
    }
    // Every shape of the chain is reached: none, key only, key then
    // subscription, and on to fallback.
    const legs = [stage, `${stage}-subscription`, `${stage}-fallback`];
    for (const shape of ["", legs[0], legs.slice(0, 2).join(","), legs.join(",")]) {
      assert.ok(started.has(shape), `reached ${shape || "no leg"}`);
    }
    assert.ok(failed.has(legs[1]), "an empty subscription and fallback token fails the subscription leg");
    assert.ok(count > 1000, `${count} states`);
  });
}

const one = { head: "open", key: true, sub: true, fallback: true, keyOutcome: { handoff: "", reason: "" }, subOutcome: { handoff: "", reason: "" } };

test("a step that fails after a handoff still starts the next leg, as the old job outputs did", () => {
  const s = { ...one, gate: "ok", keyFail: "after-run", legFail: "after-run", keyOutcome: { handoff: "true", reason: "credit-stop" }, subOutcome: { handoff: "true", reason: "limit-stop" } };
  for (const stage of Object.keys(CHAINS)) {
    assert.deepEqual(newChain(stage, s).started, [stage, `${stage}-subscription`, `${stage}-fallback`]);
    assert.deepEqual(newChain(stage, s), oldChain(stage, s));
  }
});

test("a key job that fails before its credential still hands a credit-gated chain to the subscription leg, for credit-stop", () => {
  const s = { ...one, gate: "skip", keyFail: "before-credential", legFail: "none", subOutcome: { handoff: "false", reason: "" } };
  for (const stage of Object.keys(CHAINS)) {
    const sub = `${stage}-subscription`;
    const after = newChain(stage, s);
    assert.deepEqual(after.started, [stage, sub]);
    assert.equal(after.legs[sub]["fallback-reason"], "credit-stop");
    assert.deepEqual(after, oldChain(stage, s));
  }
});
