// test-scope: .github/scripts/pr-unblock/fixtures/ci-workflows-394af27bda4bda2e02e0ef0691eacd120389108f/*
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";
import { MAX_THREADS } from "./adjudicate-feedback.mjs";

const TEXT = readFileSync(new URL("../../workflows/pr-unblock.yml", import.meta.url), "utf8");
const memo = (read) => {
  const seen = new Map();
  return (...args) => {
    const key = args.join("\0");
    if (!seen.has(key)) seen.set(key, read(...args));
    return seen.get(key);
  };
};
const parsed = workflowText(TEXT);
const wf = { ...parsed, step: memo(parsed.step), outputs: memo(parsed.outputs), job: memo(parsed.job) };
const S = await loadSelect(selectPin(TEXT), fileURLToPath(new URL("./fixtures/ci-workflows-394af27bda4bda2e02e0ef0691eacd120389108f/", import.meta.url)));

const GATE = "check-adjudicator-key-credit";
const JOB = "adjudicate-feedback";
const SECRETS = { key: "PR_UNBLOCK_CLAUDE_API_KEY", sub: "PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN", fallback: "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN" };
const SLOTS = Array.from({ length: MAX_THREADS }, (_, n) => n);
const named = memo((job, name) => {
  const found = wf.job(job).split(/\n(?= {6}- name: )/).filter((s) => s.startsWith(`      - name: ${name}\n`));
  assert.equal(found.length, 1, `${job} step ${name}`);
  const inputs = {};
  const withBlock = /^ {8}with:\n((?: {10}.*\n?)+)/m.exec(found[0]);
  for (const [, key, v] of (withBlock?.[1] ?? "").matchAll(/^ {10}([\w-]+): (.*)$/gm)) inputs[key] = v;
  return { if: /^ {8}if: (.*)$/m.exec(found[0])?.[1] ?? "", inputs };
});
const counted = (n) => `fromJSON(steps.prepare.outputs.count || '0') > ${n}`;
const withCount = (expression, n, count) => expression.replace(counted(n), count > n ? "'true'" : "''");

const oldKey = (s) => {
  const skip = { ok: "false", skip: "true", failed: "" }[s.gate];
  if (skip === "true") return { key: "false", reason: "credit-stop" };
  return { key: String(s.key), reason: s.key ? "" : "no-key" };
};
const OLD = {
  stage: (n) => `steps.token.outputs.any == 'true' && ${counted(n)}`,
  key: (n) => `steps.key.outputs.key == 'true' && ${counted(n)}`,
  sub: (n) => `steps.token.outputs.token == 'true' && ${counted(n)} && (steps.judge-${n}.outcome == 'skipped' || steps.judge-${n}.outputs.handoff == 'true')`,
  fb: (n) =>
    `steps.token.outputs.fallback == 'true' && ${counted(n)} && (steps.judge-${n}-subscription.outputs.handoff == 'true' || steps.token.outputs.token != 'true' && (steps.judge-${n}.outcome == 'skipped' || steps.judge-${n}.outputs.handoff == 'true'))`,
  subReady: "${{ steps.token.outputs.fallback }}",
  subReason: (n) => `\${{ steps.judge-${n}.outputs.handoff-reason || steps.key.outputs.key-reason }}`,
  fbReason: (n) => `\${{ steps.judge-${n}-subscription.outputs.handoff-reason || 'no-key' }}`,
  report: "steps.credit.outputs.skip-key == 'true'",
};

function judged(id, ran, end) {
  if (!ran) return { [`steps.${id}.outcome`]: "skipped" };
  const handoff = end.kind === "handoff";
  return {
    [`steps.${id}.outcome`]: end.kind === "verdict" ? "success" : "failure",
    [`steps.${id}.outputs.handoff`]: String(handoff),
    [`steps.${id}.outputs.handoff-reason`]: handoff ? end.reason : "",
  };
}

function oldRun(s) {
  const out = { report: runs(OLD.report, { "steps.credit.outputs.skip-key": { ok: "false", skip: "true", failed: "" }[s.gate] }), slots: [] };
  const ctx = {};
  if (s.count > 0) {
    const { key, reason } = oldKey(s);
    const any = key === "true" || s.sub || s.fallback;
    Object.assign(ctx, {
      "steps.key.outputs.key": key,
      "steps.key.outputs.key-reason": reason,
      "steps.token.outputs.token": String(s.sub),
      "steps.token.outputs.fallback": String(s.fallback),
      "steps.token.outputs.any": String(any),
    });
  }
  for (const n of SLOTS) {
    const slot = { stage: runs(withCount(OLD.stage(n), n, s.count), ctx), legs: [] };
    const keyRan = runs(withCount(OLD.key(n), n, s.count), ctx);
    Object.assign(ctx, judged(`judge-${n}`, keyRan, s.ends[n].key));
    if (keyRan) slot.legs.push("key");
    if (runs(withCount(OLD.sub(n), n, s.count), ctx)) {
      Object.assign(ctx, judged(`judge-${n}-subscription`, true, s.ends[n].sub));
      slot.legs.push("sub");
      slot.subReady = value(OLD.subReady, ctx);
      slot.subReason = value(OLD.subReason(n), ctx);
    } else Object.assign(ctx, judged(`judge-${n}-subscription`, false));
    if (runs(withCount(OLD.fb(n), n, s.count), ctx)) {
      slot.legs.push("fb");
      slot.fbReason = value(OLD.fbReason(n), ctx);
    }
    out.slots.push(slot);
  }
  return out;
}

function newRun(s) {
  const credit = wf.step(GATE, "credit");
  assert.equal(credit.inputs.leg, "start");
  assert.match(credit.text, /^ {8}continue-on-error: true$/m);
  const started = s.gate === "failed" ? {} : S.start({ skipKey: s.gate === "skip" });
  const gateCtx = Object.fromEntries(Object.entries(started).map(([k, v]) => [`steps.credit.outputs.${k}`, v]));
  const out = { report: runs(named(GATE, "Report the skipped key leg").if, gateCtx), slots: [] };
  const needs = Object.fromEntries(Object.entries(wf.outputs(GATE)).map(([k, v]) => [`needs.${GATE}.outputs.${k}`, value(v, gateCtx)]));
  const ctx = {
    ...needs,
    "steps.models.outcome": s.count > 0 ? "success" : "skipped",
    ...Object.fromEntries(Object.entries(SECRETS).map(([k, name]) => [`secrets.${name}`, s[k] ? "set" : ""])),
  };
  for (const [id, leg] of [["key", "key"], ["sub", "subscription"], ["fb", "fallback"]]) {
    const call = wf.step(JOB, id);
    assert.equal(call.inputs.leg, leg, id);
    if (!runs(call.if, ctx)) continue;
    const arg = (name) => (call.inputs[name] === undefined ? "" : value(call.inputs[name], ctx));
    const decided = S.leg({ leg, role: arg("role"), credentialSet: arg("credential-set"), fallbackSet: arg("fallback-set"), keyOff: arg("key-off"), selected: arg("selected"), reason: arg("reason") }).outputs;
    for (const [k, v] of Object.entries(decided)) ctx[`steps.${id}.outputs.${k}`] = v;
  }
  const step = (id) => wf.step(JOB, id);
  const pick = (id) => {
    assert.ok(runs(step(id).if, ctx), `${id} runs whatever ran before it`);
    const { inputs } = step(id);
    const decided = S.next({ state: value(inputs.state, ctx), handoff: value(inputs.handoff, ctx), handoffReason: value(inputs["handoff-reason"], ctx) });
    for (const [k, v] of Object.entries(decided)) ctx[`steps.${id}.outputs.${k}`] = v;
  };
  for (const n of SLOTS) {
    const slot = { stage: runs(withCount(named(JOB, `Stage disputed thread ${n}`).if, n, s.count), ctx), legs: [] };
    const keyRan = runs(withCount(step(`judge-${n}`).if, n, s.count), ctx);
    Object.assign(ctx, judged(`judge-${n}`, keyRan, s.ends[n].key));
    if (keyRan) slot.legs.push("key");
    pick(`next-${n}`);
    const subRan = runs(withCount(step(`judge-${n}-subscription`).if, n, s.count), ctx);
    Object.assign(ctx, judged(`judge-${n}-subscription`, subRan, s.ends[n].sub));
    if (subRan) {
      slot.legs.push("sub");
      slot.subReady = value(step(`judge-${n}-subscription`).inputs["fallback-ready"], ctx);
      slot.subReason = value(named(JOB, `Record disputed thread ${n}'s leg on the subscription`).inputs["fallback-reason"], ctx);
    }
    pick(`next-${n}-subscription`);
    if (runs(withCount(step(`judge-${n}-fallback`).if, n, s.count), ctx)) {
      slot.legs.push("fb");
      slot.fbReason = value(named(JOB, `Record disputed thread ${n}'s leg on the fallback token`).inputs["fallback-reason"], ctx);
    }
    out.slots.push(slot);
  }
  return out;
}

function ends(leg, fallbackReady) {
  const out = [{ kind: "verdict" }, { kind: "fail" }];
  for (const { reason } of launcherOutcomes(S.handoffReason, leg, fallbackReady)) if (reason !== "") out.push({ kind: "handoff", reason });
  return out;
}

function* states() {
  for (const gate of ["ok", "skip", "failed"])
    for (const key of [true, false])
      for (const sub of [true, false])
        for (const fallback of [true, false])
          for (const count of [0, 1, MAX_THREADS]) {
            const pairs = ends("api-key", false).flatMap((k) => ends("subscription", fallback).map((u) => ({ key: k, sub: u })));
            for (const first of pairs)
              for (const second of count > 0 ? pairs : [first]) yield { gate, key, sub, fallback, count, ends: [first, second, first] };
          }
}

test("adjudicate-feedback's slots stage and judge on the same legs, with the same reasons, as before select-model-credential", () => {
  let count = 0;
  const shapes = new Set();
  for (const s of states()) {
    count++;
    const before = oldRun(s);
    assert.deepEqual(newRun(s), before, JSON.stringify(s));
    for (const slot of before.slots) shapes.add(slot.legs.join(","));
  }
  for (const shape of ["", "key", "key,sub", "key,sub,fb", "sub", "sub,fb", "fb"]) assert.ok(shapes.has(shape), `reached ${shape || "no leg"}`);
  assert.ok(count > 1000, `${count} states`);
});

test("a slot the key answered starts no fallback leg, though the subscription token is empty", () => {
  const s = { gate: "ok", key: true, sub: false, fallback: true, count: 1, ends: SLOTS.map(() => ({ key: { kind: "verdict" }, sub: { kind: "verdict" } })) };
  assert.deepEqual(newRun(s).slots[0].legs, ["key"]);
  assert.deepEqual(oldRun(s).slots[0].legs, ["key"]);
  const handedOff = { ...s, ends: SLOTS.map(() => ({ key: { kind: "handoff", reason: "credit-stop" }, sub: { kind: "verdict" } })) };
  assert.deepEqual(newRun(handedOff).slots[0], { stage: true, legs: ["key", "fb"], fbReason: "no-key" });
});

test("every next-leg call runs under always(), on the pinned action, and each leg call after the model resolves", () => {
  for (const n of SLOTS) {
    for (const id of [`next-${n}`, `next-${n}-subscription`]) {
      assert.equal(wf.step(JOB, id).if, "${{ always() }}", id);
      assert.match(wf.step(JOB, id).text, /^ {8}continue-on-error: true$/m, id);
    }
  }
  for (const id of ["key", "sub", "fb"]) assert.equal(wf.step(JOB, id).if, "steps.models.outcome == 'success'", id);
});
