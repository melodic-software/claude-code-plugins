// maintenance-measure-skill-edit-pass.yml and pr-run-plugin-evals.yml pick each leg's
// credential through ci-workflows' select-model-credential, fetched at the pin
// the workflows name. A leg's handoff comes from eval-handoff.mjs (its
// handoffReason, the rule run-claude-cli's lane.cjs applies), so this truth
// table drives every handoff that rule can give, with the FALLBACK_READY each
// leg passes it, through each workflow's own conditions and inputs, over every
// combination of gate verdict, gate job result, secrets set or empty, and a
// step failing before the credential, before the run or after it in each leg.
// Each state is held to the expressions the workflows used before the action
// (quoted from 5599e627fc): the same jobs start, and each leg runs its model
// (old `run`, new `present`), sees the fallback token as ready, records the
// fallback reason and fails its job exactly as before.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";
import { handoffReason } from "./eval-handoff.mjs";

const read = (name) => readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8");
const HILL = read("maintenance-measure-skill-edit-pass.yml");
const BROWSER = read("pr-run-plugin-evals.yml");
const S = await loadSelect(selectPin(HILL, BROWSER));

const KEY = "MAINTENANCE_CLAUDE_API_KEY";
const TOKEN = "MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN";
const FALLBACK = "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN";

// The dispatch every state runs as; the event terms are the same before and after.
const GITHUB = {
  "github.event_name": "workflow_dispatch",
  "github.ref": "refs/heads/main",
  "github.event.label.name": "",
  "github.event.pull_request.head.repo.full_name": "",
  "github.repository": "melodic-software/claude-code-plugins",
  "github.event.pull_request.draft": false,
};
// The shared evaluator reads neither format() nor a quoted space; the label is
// never the one compared on a dispatch.
const FORMAT = "format('refs/heads/{0}', github.event.repository.default_branch)";
const cond = (text) => text.replaceAll(FORMAT, "'refs/heads/main'").replaceAll("'eval: run'", "'eval-run'");

// workflowText's readers, each read once per argument list.
function cached(wf) {
  const memo = new Map();
  return Object.fromEntries(
    Object.entries(wf).map(([name, fn]) => [
      name,
      (...args) => {
        const key = `${name}\0${args.join("\0")}`;
        if (!memo.has(key)) memo.set(key, fn(...args));
        return memo.get(key);
      },
    ]),
  );
}

const BROWSER_EVENT =
  "((github.event_name == 'workflow_dispatch' && github.ref == format('refs/heads/{0}', github.event.repository.default_branch)) || (github.event_name == 'pull_request' && github.event.label.name == 'eval: run' && github.event.pull_request.head.repo.full_name == github.repository && !github.event.pull_request.draft))";

// The old conditions, reasons and credential steps, at 5599e627fc. `failsEmpty`
// is whether a leg's credential step failed its job on an empty token, which
// left its outputs unwritten.
const WORKFLOWS = [
  {
    file: "maintenance-measure-skill-edit-pass.yml",
    wf: cached(workflowText(HILL)),
    gate: "gate",
    legs: ["pass", "pass-subscription", "pass-fallback"],
    old: {
      key: "${{ !cancelled() && needs.gate.result == 'success' }}",
      sub: "${{ !cancelled() && needs.gate.result == 'success' && (needs.pass.outputs.handoff == 'true' || needs.pass.outputs.credential-present == 'false' || needs.gate.outputs.skip-key == 'true') }}",
      fallback: "${{ !cancelled() && needs.pass-subscription.outputs.fallback-ready == 'true' && (needs.pass-subscription.outputs.handoff == 'true' || needs.pass-subscription.outputs.credential-present == 'false') }}",
      subReason: "${{ needs.pass.outputs.handoff-reason || needs.gate.outputs.skip-key == 'true' && 'credit-stop' || needs.pass.outputs.credential-present == 'false' && 'no-key' || '' }}",
      fallbackReason: "${{ needs.pass-subscription.outputs.handoff-reason || 'no-key' }}",
      failsEmpty: { subscription: true, fallback: true },
    },
  },
  {
    file: "pr-run-plugin-evals.yml",
    wf: cached(workflowText(BROWSER)),
    gate: "eval-key-credit",
    legs: ["eval", "eval-subscription", "eval-fallback"],
    old: {
      key: `\${{ !cancelled() && needs.eval-key-credit.result == 'success' && ${BROWSER_EVENT} }}`,
      sub: "${{ !cancelled() && needs.eval-key-credit.result == 'success' && (needs.eval.outputs.handoff == 'true' || needs.eval.outputs.credential-present == 'false' || needs.eval-key-credit.outputs.skip-key == 'true') }}",
      fallback: "${{ !cancelled() && needs.eval-subscription.outputs.fallback-ready == 'true' && (needs.eval-subscription.outputs.handoff == 'true' || needs.eval-subscription.outputs.credential-present == 'false') }}",
      subReason: "${{ needs.eval.outputs.handoff-reason || needs.eval-key-credit.outputs.skip-key == 'true' && 'credit-stop' || needs.eval.outputs.credential-present == 'false' && 'no-key' || '' }}",
      fallbackReason: "${{ needs.eval-subscription.outputs.handoff-reason || 'no-key' }}",
      failsEmpty: { subscription: false, fallback: false },
    },
  },
];

// The stream facts eval-handoff.mjs judges, one per distinct handoff they
// give on a leg with and without the fallback token ready.
const EVAL_LEG = { key: "api-key", subscription: "subscription", fallback: "fallback" };
function facts(leg) {
  const seen = new Map();
  for (const failureClass of ["", "credit-stop", "auth", "rate-limit", "other"])
    for (const status of [null, 401, 402, 429])
      for (const limitStop of [false, true])
        for (const creditStop of [false, true]) {
          const fact = { failureClass, status, limitStop, creditStop };
          const sig = [true, false].map((fallbackReady) => reasonOf(leg, fact, fallbackReady)).join("/");
          if (!seen.has(sig)) seen.set(sig, fact);
        }
  return [...seen.values()];
}
const reasonOf = (leg, f, fallbackReady) => handoffReason(EVAL_LEG[leg], f.failureClass, f.status, { fallbackReady, limitStop: f.limitStop, creditStop: f.creditStop });

// The judge step's outputs: it runs only when the leg's credential let the
// probe run and no step before the probe failed; its handoff is
// eval-handoff.mjs's, which reads FALLBACK_READY == 'true'.
function judge(leg, runsModel, fallbackReady, failAt, fact) {
  if (!runsModel || failAt === "before-credential" || failAt === "before-run") return { ran: false, handoff: "", reason: "" };
  const reason = reasonOf(leg, fact, fallbackReady === "true");
  return { ran: true, handoff: String(reason !== ""), reason };
}

// One leg job's credential call, its stop on empty tokens if any, its
// next-leg call (not the fallback leg's), its outputs and the `Record the
// leg` step's fallback-reason input, read once.
const PARTS = new Map();
function parts(wf, id, name) {
  if (!PARTS.has(id)) {
    const job = wf.job(id);
    assert.match(job, /\n {10}FALLBACK_READY: \$\{\{ steps\.credential\.outputs\.fallback-ready \}\}\n/, `${id} judges with the action's fallback-ready`);
    const record = job.split(/\n(?= {6}- name: )/).find((s) => s.startsWith("      - name: Record the leg\n"));
    const call = wf.step(id, "credential");
    assert.equal(call.inputs.leg, name, `${id} credential leg`);
    const next = name === "fallback" ? null : wf.step(id, "next");
    if (next) assert.equal(next.if, "${{ always() }}", `${id} hands on whatever failed after its credential`);
    PARTS.set(id, {
      call,
      stop: /^ {8}id: no-credential$/m.test(job) ? wf.step(id, "no-credential") : null,
      next,
      outputs: wf.outputs(id),
      recordReason: /^ {10}fallback-reason: (.*)$/m.exec(record)[1],
      jobIf: cond(wf.jobIf(id)),
    });
  }
  return PARTS.get(id);
}

const bool = (v) => v === "true";

function oldChain(w, s) {
  const o = w.old;
  const [keyId, subId, fbId] = w.legs;
  const ctx = { ...GITHUB, [`needs.${w.gate}.result`]: s.gateResult, [`needs.${w.gate}.outputs.skip-key`]: { ok: "false", skip: "true", failed: "" }[s.gate] };
  const out = { started: [], legs: {} };
  const set = { key: s.key, subscription: s.sub, fallback: s.fallback };
  const step = (leg) => {
    const failAt = s.failAt[leg];
    if (failAt === "before-credential") return { failed: false, outputs: {} };
    const present = String(set[leg]);
    if (o.failsEmpty[leg] && !set[leg] && (leg === "fallback" || !s.fallback)) return { failed: true, outputs: {} };
    if (leg === "key") return { failed: false, outputs: { present, run: String(set.key && ctx[`needs.${w.gate}.outputs.skip-key`] !== "true") } };
    if (leg === "subscription") return { failed: false, outputs: { present, run: present, "fallback-ready": String(s.fallback) } };
    return { failed: false, outputs: { present, run: present } };
  };
  const leg = (id, name, reasonExpr) => {
    out.started.push(id);
    const { failed, outputs } = step(name);
    const j = judge(name, bool(outputs.run), outputs["fallback-ready"] ?? "", s.failAt[name], s.facts[name]);
    out.legs[id] = {
      runs: bool(outputs.run),
      ...(name === "subscription" && { ready: bool(outputs["fallback-ready"]) }),
      ...(reasonExpr && j.ran && { "fallback-reason": value(reasonExpr, ctx) }),
      failed,
    };
    Object.assign(ctx, {
      [`needs.${id}.outputs.handoff`]: j.handoff,
      [`needs.${id}.outputs.handoff-reason`]: j.reason,
      [`needs.${id}.outputs.credential-present`]: outputs.present ?? "",
      [`needs.${id}.outputs.fallback-ready`]: outputs["fallback-ready"] ?? "",
    });
  };
  if (runs(cond(o.key), ctx)) leg(keyId, "key", "");
  if (runs(o.sub, ctx)) leg(subId, "subscription", o.subReason);
  if (runs(o.fallback, ctx)) leg(fbId, "fallback", o.fallbackReason);
  return out;
}

const prefixed = (prefix, map) => Object.fromEntries(Object.entries(map).map(([k, v]) => [`${prefix}.${k}`, v]));

function newChain(w, s) {
  const { wf } = w;
  const [keyId, subId, fbId] = w.legs;
  const start = s.gate === "failed" ? {} : S.start({ skipKey: s.gate === "skip" });
  const gateOutputs = wf.outputs(w.gate);
  const ctx = {
    ...GITHUB,
    [`needs.${w.gate}.result`]: s.gateResult,
    ...Object.fromEntries(["next-leg", "next-reason"].map((n) => [`needs.${w.gate}.outputs.${n}`, value(gateOutputs[n], prefixed("steps.credit.outputs", start))])),
    [`secrets.${KEY}`]: s.key ? "set" : "",
    [`secrets.${TOKEN}`]: s.sub ? "set" : "",
    [`secrets.${FALLBACK}`]: s.fallback ? "set" : "",
  };
  const out = { started: [], legs: {} };
  const leg = (id, name) => {
    out.started.push(id);
    const failAt = s.failAt[name];
    const { call, stop, next, outputs: jobOutputs, recordReason } = parts(wf, id, name);
    let outputs = {};
    if (failAt !== "before-credential") {
      const input = (key) => (call.inputs[key] === undefined ? "" : value(call.inputs[key], ctx));
      outputs = S.leg({ leg: name, role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), reason: input("reason") }).outputs;
    }
    const j = judge(name, bool(outputs.present), outputs["fallback-ready"] ?? "", failAt, s.facts[name]);
    const stepCtx = { ...ctx, ...prefixed("steps.credential.outputs", outputs), "steps.judge.outputs.handoff": j.handoff, "steps.judge.outputs.handoff-reason": j.reason };
    out.legs[id] = {
      runs: bool(outputs.present),
      ...(name === "subscription" && { ready: bool(outputs["fallback-ready"]) }),
      ...(name !== "key" && j.ran && { "fallback-reason": value(recordReason, stepCtx) }),
      failed: Boolean(stop) && failAt !== "before-credential" && runs(stop.if, stepCtx),
    };
    if (next) {
      const decided = S.next({ state: value(next.inputs.state, stepCtx), handoff: value(next.inputs.handoff, stepCtx), handoffReason: value(next.inputs["handoff-reason"], stepCtx) });
      for (const n of ["next-leg", "next-reason"]) ctx[`needs.${id}.outputs.${n}`] = value(jobOutputs[n], prefixed("steps.next.outputs", decided));
    }
  };
  if (runs(parts(wf, keyId, "key").jobIf, ctx)) leg(keyId, "key");
  if (runs(parts(wf, subId, "subscription").jobIf, ctx)) leg(subId, "subscription");
  if (runs(parts(wf, fbId, "fallback").jobIf, ctx)) leg(fbId, "fallback");
  return out;
}

const FAIL_AT = ["none", "before-credential", "before-run", "after-run"];
const KEY_FACTS = facts("key");
const SUB_FACTS = facts("subscription");
const NO_FACT = { failureClass: "", status: null, limitStop: false, creditStop: false };

function* states() {
  for (const gate of ["ok", "skip", "failed"])
    for (const gateResult of ["success", "failure"])
      for (const key of [true, false])
        for (const sub of [true, false])
          for (const fallback of [true, false])
            for (const keyFail of FAIL_AT)
              for (const subFail of FAIL_AT)
                for (const keyFact of KEY_FACTS)
                  for (const subFact of SUB_FACTS)
                    yield { gate, gateResult, key, sub, fallback, failAt: { key: keyFail, subscription: subFail, fallback: "none" }, facts: { key: keyFact, subscription: subFact, fallback: NO_FACT } };
}

for (const w of WORKFLOWS) {
  test(`${w.file}: every leg starts, runs and records as before select-model-credential`, () => {
    const began = Date.now();
    let count = 0;
    const shapes = new Set();
    for (const s of states()) {
      count++;
      const before = oldChain(w, s);
      assert.deepEqual(newChain(w, s), before, JSON.stringify(s));
      shapes.add(before.started.join(","));
    }
    // Every shape of the chain is reached: none, key only, key then
    // subscription, the subscription alone (a gate skip), and on to fallback.
    const [k, sb, fb] = w.legs;
    for (const shape of ["", k, `${k},${sb}`, `${k},${sb},${fb}`]) assert.ok(shapes.has(shape), `reached ${shape || "no leg"}`);
    assert.ok(count > 5000, `${count} states`);
    assert.ok(Date.now() - began < 10000, `${count} states in ${Date.now() - began} ms`);
  });

  test(`${w.file}: a step that fails after a handoff still starts the next leg, with the leg's reason`, () => {
    const credit = SUB_FACTS.find((f) => reasonOf("subscription", f, true) === "credit-stop");
    const s = {
      gate: "ok",
      gateResult: "success",
      key: true,
      sub: true,
      fallback: true,
      failAt: { key: "after-run", subscription: "after-run", fallback: "none" },
      facts: { key: KEY_FACTS.find((f) => reasonOf("key", f, false) === "auth"), subscription: credit, fallback: NO_FACT },
    };
    const after = newChain(w, s);
    assert.deepEqual(after.started, w.legs);
    assert.equal(after.legs[w.legs[1]]["fallback-reason"], "auth");
    assert.equal(after.legs[w.legs[2]]["fallback-reason"], "credit-stop");
    assert.deepEqual(after, oldChain(w, s));
  });
}

test("each leg's handoff reasons are the action's closed reasons, so the next-leg call loses none", () => {
  for (const [leg, list] of Object.entries(S.HANDOFF_REASONS)) {
    for (const fact of facts(leg)) {
      for (const fallbackReady of [true, false]) {
        const reason = reasonOf(leg, fact, fallbackReady);
        assert.ok(reason === "" || list.includes(reason), `${leg} ${reason}`);
      }
    }
  }
  assert.deepEqual(Object.keys(S.HANDOFF_REASONS), Object.keys(EVAL_LEG));
});
