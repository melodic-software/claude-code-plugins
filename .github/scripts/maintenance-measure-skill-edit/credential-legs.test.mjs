// maintenance-measure-skill-edit.yml's propose job runs its three legs as
// steps of one job (run-claude-cli's one-job rule), and picks each leg's
// credential through ci-workflows' select-model-credential, fetched at the
// pin the workflow names: propose-key-credit's start call, then in propose a
// credential call and a next-leg call per leg. This truth table drives the
// workflow's own step conditions and inputs through every combination of
// gate verdict, secrets set or empty, a prompt written or not, a step failing
// before or after the legs, and every launcher outcome run-claude-cli's own
// handoffReason can produce, and holds each state to the step conditions and
// the "Check the API key" script the job used before the action (quoted from
// 5599e627fc): the same legs run, each subscription leg gets the same
// fallback-ready, and each later leg's record the same fallback reason.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const TEXT = readFileSync(new URL("../../workflows/maintenance-measure-skill-edit.yml", import.meta.url), "utf8");
const wf = workflowText(TEXT);
const S = await loadSelect(selectPin(TEXT));

const JOB = "propose";
const SECRETS = { key: "MAINTENANCE_CLAUDE_API_KEY", sub: "MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN", fallback: "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN" };
// The run steps, in order, and their lane record's fallback reason.
const RUNS = ["run-key", "run", "run-fallback"];

// The old step conditions and record reasons, at 5599e627fc.
const OLD = {
  runKey: "steps.prompt.outcome == 'success' && steps.key.outputs.key == 'true'",
  run: "steps.prompt.outcome == 'success' && steps.credential.outputs.present == 'true' && (steps.run-key.outcome == 'skipped' || steps.run-key.outputs.handoff == 'true')",
  runFallback:
    "steps.prompt.outcome == 'success' && steps.credential.outputs.fallback-ready == 'true' && (steps.run.outputs.handoff == 'true' || steps.credential.outputs.present != 'true' && (steps.run-key.outcome == 'skipped' || steps.run-key.outputs.handoff == 'true'))",
  subReason: "${{ steps.run-key.outputs.handoff-reason || steps.key.outputs.key-reason }}",
  fallbackReason: "${{ steps.run.outputs.handoff-reason || 'no-key' }}",
};

// The old "Check the API key" script: key=$KEY, unless SKIP_KEY is true
// (key=false, reason credit-stop); an empty key's reason is no-key.
function oldKeyStep(keySet, skipKey) {
  if (skipKey === "true") return { key: "false", "key-reason": "credit-stop" };
  return { key: String(keySet), "key-reason": keySet ? "" : "no-key" };
}

const prefixed = (prefix, map) => Object.fromEntries(Object.entries(map).map(([k, v]) => [`${prefix}.${k}`, v]));
// A run step's outputs once it ran, or its skipped outcome.
const launched = (id, ok, outcome) =>
  ok ? { [`steps.${id}.outcome`]: "success", [`steps.${id}.outputs.handoff`]: outcome.handoff, [`steps.${id}.outputs.handoff-reason`]: outcome.reason } : { [`steps.${id}.outcome`]: "skipped" };

function result(ctx, fallbackReady, subReason, fbReason) {
  const out = { ran: RUNS.filter((id) => ctx[`steps.${id}.outcome`] === "success") };
  if (out.ran.includes("run")) Object.assign(out, { "run fallback-ready": fallbackReady, "run fallback-reason": subReason });
  if (out.ran.includes("run-fallback")) out["run-fallback fallback-reason"] = fbReason;
  return out;
}

function oldRun(s) {
  const skipKey = { ok: "false", skip: "true", failed: "" }[s.gate];
  const ctx = { "steps.prompt.outcome": s.prompt ? "success" : "skipped" };
  if (s.prompt) {
    Object.assign(ctx, prefixed("steps.key.outputs", oldKeyStep(s.key, skipKey)));
    Object.assign(ctx, { "steps.credential.outputs.present": String(s.sub), "steps.credential.outputs.fallback-ready": String(s.fallback) });
  }
  // A step that fails before the legs skips every leg (none has always()).
  const go = (cond) => s.failAt !== "before-run" && runs(cond, ctx);
  Object.assign(ctx, launched("run-key", go(OLD.runKey), s.keyOutcome));
  Object.assign(ctx, launched("run", go(OLD.run), s.subOutcome));
  Object.assign(ctx, launched("run-fallback", go(OLD.runFallback), { handoff: "", reason: "" }));
  return result(ctx, ctx["steps.credential.outputs.fallback-ready"], value(OLD.subReason, ctx), value(OLD.fallbackReason, ctx));
}

// A select-model-credential call as the workflow writes it.
function call(id, ctx) {
  const step = wf.step(JOB, id);
  const input = (name) => (step.inputs[name] === undefined ? "" : value(step.inputs[name], ctx));
  if (step.inputs.leg !== undefined) {
    return S.leg({ leg: step.inputs.leg, role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), reason: input("reason") }).outputs;
  }
  return S.next({ state: input("state"), handoff: input("handoff"), handoffReason: input("handoff-reason") });
}

function newRun(s) {
  const start = s.gate === "failed" ? {} : S.start({ skipKey: s.gate === "skip" });
  const gateOutputs = wf.outputs("propose-key-credit");
  const ctx = {
    "steps.prompt.outcome": s.prompt ? "success" : "skipped",
    "needs.propose-key-credit.outputs.next-leg": value(gateOutputs["next-leg"], prefixed("steps.credit.outputs", start)),
    ...prefixed("secrets", Object.fromEntries(Object.entries(SECRETS).map(([k, name]) => [name, s[k] ? "set" : ""]))),
  };
  // The steps after the key's credential call follow the failing step, so a
  // failure before the legs skips them all: none has always().
  const order = [
    ["key", "call"],
    ["run-key", "run", s.keyOutcome],
    ["next-key", "call"],
    ["credential", "call"],
    ["run", "run", s.subOutcome],
    ["next", "call"],
    ["fallback", "call"],
    ["run-fallback", "run", { handoff: "", reason: "" }],
  ];
  for (const [id, kind, outcome] of order) {
    const step = wf.step(JOB, id);
    const go = (id === "key" || s.failAt !== "before-run") && (step.if === "" || runs(step.if, ctx));
    if (kind === "run") Object.assign(ctx, launched(id, go, outcome));
    else if (go) Object.assign(ctx, prefixed(`steps.${id}.outputs`, call(id, ctx)));
  }
  const runInput = wf.step(JOB, "run").inputs["fallback-ready"];
  const record = (name) => {
    const block = wf.job(JOB).split(/\n(?= {6}- name: )/).find((b) => b.startsWith(`      - name: ${name}\n`));
    return value(/^ {10}fallback-reason: (.*)$/m.exec(block)[1], ctx);
  };
  return result(ctx, value(runInput, ctx), record("Record the subscription leg"), record("Record the fallback leg"));
}

function* states() {
  for (const prompt of [true, false])
    for (const gate of ["ok", "skip", "failed"])
      for (const key of [true, false])
        for (const sub of [true, false])
          for (const fallback of [true, false])
            for (const failAt of ["none", "before-run", "after-legs"])
              for (const keyOutcome of launcherOutcomes(S.handoffReason, "api-key", false))
                for (const subOutcome of launcherOutcomes(S.handoffReason, "subscription", fallback))
                  yield { prompt, gate, key, sub, fallback, failAt, keyOutcome, subOutcome };
}

test("propose runs the same legs with the same credential decisions as before select-model-credential", () => {
  let count = 0;
  const shapes = new Set();
  for (const s of states()) {
    count++;
    const before = oldRun(s);
    assert.deepEqual(newRun(s), before, JSON.stringify(s));
    shapes.add(before.ran.join(","));
  }
  for (const shape of ["", "run-key", "run-key,run", "run-key,run,run-fallback", "run", "run,run-fallback", "run-fallback"]) assert.ok(shapes.has(shape), `reached ${shape || "no leg"}`);
  assert.ok(count > 1000, `${count} states`);
});

test("a key leg that finished hands nothing on, whatever the subscription token holds", () => {
  const s = { prompt: true, gate: "ok", key: true, sub: false, fallback: true, failAt: "none", keyOutcome: { handoff: "false", reason: "" }, subOutcome: { handoff: "false", reason: "" } };
  assert.deepEqual(newRun(s).ran, ["run-key"]);
  assert.deepEqual(newRun({ ...s, gate: "skip" }).ran, ["run-fallback"]);
});

test("a step that fails after the legs changes no leg", () => {
  const s = { prompt: true, gate: "ok", key: true, sub: true, fallback: true, failAt: "after-legs", keyOutcome: { handoff: "true", reason: "credit-stop" }, subOutcome: { handoff: "false", reason: "" } };
  assert.deepEqual(newRun(s), oldRun(s));
  assert.deepEqual(newRun(s).ran, ["run-key", "run"]);
});
