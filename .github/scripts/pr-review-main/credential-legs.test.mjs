import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { admits } from "../lib/gate-expression.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const TEXT = readFileSync(new URL("../../workflows/pr-review-main.yml", import.meta.url), "utf8");
const memo = (fn) => {
  const seen = new Map();
  return (...args) => {
    const key = args.join("\0");
    if (!seen.has(key)) seen.set(key, fn(...args));
    return seen.get(key);
  };
};
const parsed = workflowText(TEXT);
const wf = { job: memo(parsed.job), jobIf: memo(parsed.jobIf), outputs: memo(parsed.outputs), step: memo(parsed.step), stepNamed: memo(parsed.stepNamed) };
const S = await loadSelect(selectPin(TEXT));

const GATE = "review-handoffs-credit";
const [KEY, SUB, FB] = ["review", "review-subscription", "review-fallback"];
const LANES = [
  { lane: "claude-review", env: "CODE", sw: "CLAUDE_REVIEW_DISABLED" },
  { lane: "claude-security-review", env: "SECURITY", sw: "CLAUDE_SECURITY_REVIEW_DISABLED" },
];
const SECRETS = { key: "REVIEWS_CLAUDE_API_KEY", sub: "REVIEWS_CLAUDE_CODE_OAUTH_TOKEN", fallback: "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN" };
const SHA = "a".repeat(40);
const SLOTS = [1, 2, 3, 4];

const expr = (text) => text.replace(/\bmatrix\./g, "inputs.matrix.");
const val = (text, ctx) => value(expr(text), ctx);
const stepRuns = (condition, ctx, jobOk) => admits(expr(condition), ctx, { status: jobOk ? "success" : "failure" });
const named = wf.stepNamed;

const CASE = /case "\$REASON" in\n\s+([a-z| -]+)\) ;;/.exec(named(KEY, "Hand the lane on").text)[1].split("|").map((r) => r.trim());

const OLD = {
  key: "needs.review-handoffs-credit.outputs.skip-key != 'true' && !cancelled() && needs.check-trigger.result == 'success' && github.ref == 'refs/heads/main' && github.event.workflow_run.event == 'pull_request' && github.event.workflow_run.conclusion == 'success' && github.event.workflow_run.head_repository.full_name == github.repository && (needs.check-trigger.outputs.run-attempt != github.run_attempt || needs.check-trigger.outputs.review != 'false' && needs.check-trigger.outputs.judged != 'true' && needs.check-trigger.outputs.held != 'true')",
  report: (sw) => `steps.gate.outputs.skip-key == 'true' && needs.check-trigger.outputs.proceed == 'true' && needs.check-trigger.outputs.review == 'true' && needs.check-trigger.outputs.judged != 'true' && needs.check-trigger.outputs.held != 'true' && vars.${sw} != 'true'`,
  route: "!cancelled() && github.ref == 'refs/heads/main' && (needs.review.outputs.claude-review != '' || needs.review.outputs.claude-security-review != '' || needs.review.result == 'skipped' && needs.review-handoffs-credit.outputs.skip-key == 'true' && needs.check-trigger.outputs.run-attempt == github.run_attempt && needs.check-trigger.outputs.proceed == 'true' && needs.check-trigger.outputs.review == 'true' && needs.check-trigger.outputs.judged != 'true' && needs.check-trigger.outputs.held != 'true')",
  routeEnv: (lane, sw) => `\${{ needs.review.outputs.${lane} || needs.review.result == 'skipped' && needs.review-handoffs-credit.outputs.skip-key == 'true' && vars.${sw} != 'true' && 'credit-stop' || '' }}`,
  handoffIf: `${SLOTS.map((k) => `steps.review-${k}.outputs.handoff == 'true'`).join(" || ")} || steps.credential.outputs.present == 'false'`,
  handoffReason: `\${{ steps.credential.outputs.present == 'false' && 'no-key' || ${SLOTS.map((k) => `steps.review-${k}.outputs.handoff-reason`).join(" || ")} }}`,
  fallbackReason: "${{ matrix.reason == 'credit-stop' && 'credit-stop' || matrix.reason == 'auth' && 'auth' || matrix.reason == 'limit-stop' && 'limit-stop' || matrix.reason == 'no-key' && 'no-key' || '' }}",
};

function oldCredential(legName, s) {
  const own = { key: s.key, subscription: s.sub, fallback: s.fallback }[legName];
  const later = { key: true, subscription: s.fallback, fallback: false }[legName];
  return { present: own ? "true" : later ? "false" : "", "fallback-ready": String(later) };
}

function chunks(ran, l, outcome) {
  const steps = {};
  for (const k of SLOTS) {
    const hit = ran && k === l.at;
    const before = ran && k < l.at;
    steps[`steps.review-${k}.outputs.handoff`] = hit ? outcome.handoff : before ? "false" : "";
    steps[`steps.review-${k}.outputs.handoff-reason`] = hit ? outcome.reason : "";
  }
  return steps;
}

function legInstance(version, job, legName, s, l, reason) {
  const base = { "inputs.matrix.lane": l.lane, "inputs.matrix.reason": reason, ...s.secrets };
  const reached = l.applies && !l.off;
  let credential = {};
  if (reached) {
    if (version === "old") credential = oldCredential(legName, s);
    else {
      const call = wf.step(job, "credential");
      assert.equal(call.inputs.leg, legName, `${job} credential leg`);
      const input = (name) => (call.inputs[name] === undefined ? "" : val(call.inputs[name], base));
      credential = S.leg({ leg: legName, role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), reason: input("reason") }).outputs;
    }
  }
  const willRun = credential.present === "true";
  const ran = willRun && l.failAt !== "before-run";
  const jobOk = !(willRun && (l.failAt === "before-run" || l.failAt === "between"));
  const outcome = { key: l.keyOutcome, subscription: l.subOutcome(s.fallback), fallback: { handoff: "", reason: "" } }[legName];
  const ctx = { ...base, ...prefixed("steps.credential.outputs", credential), ...chunks(ran, l, outcome) };
  const result = { model: willRun };
  if (legName === "subscription") result["fallback-ready"] = credential["fallback-ready"] ?? "";
  if (legName !== "key" && ran) {
    const record = named(job, "Report chunk 1's outcome").inputs["fallback-reason"];
    result["fallback-reason"] = val(version === "old" ? OLD.fallbackReason : record, ctx);
  }
  let handedOn = "";
  if (legName !== "fallback") {
    let handoffIf = OLD.handoffIf;
    let reasonExpr = OLD.handoffReason;
    if (version === "new") {
      const next = wf.step(job, "next");
      assert.equal(next.if, "${{ always() }}", `${job} picks the next leg whatever failed before`);
      const decided = S.next({ state: val(next.inputs.state, ctx), handoff: val(next.inputs.handoff, ctx), handoffReason: val(next.inputs["handoff-reason"], ctx) });
      Object.assign(ctx, prefixed("steps.next.outputs", decided));
      const hand = named(job, "Hand the lane on");
      handoffIf = hand.if;
      reasonExpr = hand.env.REASON;
    }
    if (stepRuns(handoffIf, ctx, jobOk)) {
      const r = val(reasonExpr, ctx);
      handedOn = CASE.includes(r) ? r : "";
    }
  }
  return { result, handedOn };
}
const prefixed = (prefix, map) => Object.fromEntries(Object.entries(map).map(([k, v]) => [`${prefix}.${k}`, v]));

function route(id, envFor, ctx) {
  const reasons = named(id, "Route the handed-off lanes").env.REASONS.split(" ");
  const rows = LANES.map((l) => ({ lane: l.lane, reason: val(envFor(l), ctx) })).filter((r) => r.reason !== "");
  return rows.every((r) => reasons.includes(r.reason)) ? { result: "success", rows } : { result: "failure", rows: [] };
}

function chain(version, s) {
  const ctx = {
    "github.ref": "refs/heads/main",
    "github.run_attempt": "1",
    "github.repository": "o/r",
    "github.event.workflow_run.event": "pull_request",
    "github.event.workflow_run.conclusion": "success",
    "github.event.workflow_run.head_repository.full_name": "o/r",
    "needs.check-trigger.result": "success",
    "needs.check-trigger.outputs.run-attempt": "1",
    "needs.check-trigger.outputs.proceed": "true",
    "needs.check-trigger.outputs.review": "true",
    "needs.check-trigger.outputs.judged": "",
    "needs.check-trigger.outputs.held": s.held,
    "needs.check-trigger.outputs.main-sha": SHA,
    ...Object.fromEntries(s.lanes.map((l, i) => [`vars.${LANES[i].sw}`, l.off ? "true" : ""])),
  };
  const out = { reports: [], started: [], legs: {} };
  if (version === "old") {
    ctx["steps.gate.outputs.skip-key"] = { ok: "false", skip: "true", failed: "" }[s.gate];
    ctx[`needs.${GATE}.outputs.skip-key`] = ctx["steps.gate.outputs.skip-key"];
  } else {
    const gate = s.gate === "failed" ? {} : S.start({ skipKey: s.gate === "skip" });
    Object.assign(ctx, prefixed("steps.gate.outputs", gate));
    for (const [name, v] of Object.entries(wf.outputs(GATE))) ctx[`needs.${GATE}.outputs.${name}`] = val(v, ctx);
  }
  for (const l of LANES) {
    const condition = version === "old" ? OLD.report(l.sw) : named(GATE, `Report the skipped ${l.lane} key leg`).if;
    if (runs(condition, ctx)) out.reports.push(l.lane);
  }
  const handed = {};
  if (runs(version === "old" ? OLD.key : wf.jobIf(KEY), ctx)) {
    out.started.push(KEY);
    s.lanes.forEach((l, i) => {
      const { result, handedOn } = legInstance(version, KEY, "key", s, l, "");
      out.legs[`${KEY}/${LANES[i].lane}`] = result;
      handed[LANES[i].lane] = handedOn;
    });
  }
  ctx["needs.review.result"] = out.started.includes(KEY) ? "success" : "skipped";
  for (const l of LANES) {
    ctx[`needs.review.outputs.${l.lane}`] = handed[l.lane] ?? "";
    ctx[`needs.review.outputs.${l.lane}-base-sha`] = handed[l.lane] ? SHA : "";
  }
  let rows = [];
  if (runs(version === "old" ? OLD.route : wf.jobIf("review-handoffs"), ctx)) {
    const r = route("review-handoffs", (l) => (version === "old" ? OLD.routeEnv(l.lane, l.sw) : named("review-handoffs", "Route the handed-off lanes").env[l.env]), ctx);
    out.started.push(`review-handoffs:${r.result}`);
    ctx["needs.review-handoffs.result"] = r.result;
    rows = r.rows;
  } else ctx["needs.review-handoffs.result"] = "skipped";
  const later = (job, legName, nextRoute) => {
    const handedOn = {};
    if (rows.length && runs(wf.jobIf(job), ctx)) {
      for (const row of rows) {
        out.started.push(`${job}/${row.lane}`);
        const l = s.lanes[LANES.findIndex((x) => x.lane === row.lane)];
        const r = legInstance(version, job, legName, s, l, row.reason);
        out.legs[`${job}/${row.lane}`] = r.result;
        handedOn[row.lane] = r.handedOn;
      }
    }
    if (!nextRoute) return;
    for (const l of LANES) {
      ctx[`needs.${job}.outputs.${l.lane}`] = handedOn[l.lane] ?? "";
      ctx[`needs.${job}.outputs.${l.lane}-base-sha`] = handedOn[l.lane] ? SHA : "";
    }
    rows = [];
    if (runs(wf.jobIf(nextRoute), ctx)) {
      const r = route(nextRoute, (l) => named(nextRoute, "Route the handed-off lanes").env[l.env], ctx);
      out.started.push(`${nextRoute}:${r.result}`);
      ctx[`needs.${nextRoute}.result`] = r.result;
      rows = r.rows;
    } else ctx[`needs.${nextRoute}.result`] = "skipped";
  };
  later(SUB, "subscription", "collect-subscription-handoffs");
  later(FB, "fallback", null);
  return out;
}

const KEY_OUTCOMES = launcherOutcomes(S.handoffReason, "api-key", false);
const SUB_OUTCOMES = { true: launcherOutcomes(S.handoffReason, "subscription", true), false: launcherOutcomes(S.handoffReason, "subscription", false) };
const subOutcomes = (fallback) => SUB_OUTCOMES[fallback];

function* firstLane() {
  for (const applies of [true, false])
    for (const off of [false, true])
      for (const failAt of ["none", "before-run", "between", "after-run"])
        for (const at of [1, 2])
          for (const keyOutcome of KEY_OUTCOMES)
            for (const subIndex of [0, 1, 2, 3])
              yield { applies, off, failAt, at, keyOutcome, subOutcome: (fb) => subOutcomes(fb)[subIndex % subOutcomes(fb).length] };
}
const SECOND = [
  { applies: true, off: false, failAt: "none", at: 1, keyOutcome: { handoff: "false", reason: "" }, subOutcome: () => ({ handoff: "false", reason: "" }) },
  { applies: true, off: false, failAt: "none", at: 1, keyOutcome: { handoff: "true", reason: "credit-stop" }, subOutcome: (fb) => subOutcomes(fb).at(-1) },
  { applies: true, off: false, failAt: "between", at: 2, keyOutcome: { handoff: "true", reason: "auth" }, subOutcome: () => ({ handoff: "false", reason: "" }) },
  { applies: false, off: true, failAt: "none", at: 1, keyOutcome: { handoff: "false", reason: "" }, subOutcome: () => ({ handoff: "false", reason: "" }) },
];

function* states() {
  for (const held of ["", "true"])
  for (const gate of ["ok", "skip", "failed"])
    for (const key of [true, false])
      for (const sub of [true, false])
        for (const fallback of [true, false])
          for (const first of firstLane())
            for (const second of SECOND) {
              const secrets = { [`secrets.${SECRETS.key}`]: key ? "set" : "", [`secrets.${SECRETS.sub}`]: sub ? "set" : "", [`secrets.${SECRETS.fallback}`]: fallback ? "set" : "" };
              yield { held, gate, key, sub, fallback, secrets, lanes: [first, second] };
            }
}

const show = (s) => JSON.stringify({ ...s, secrets: undefined, lanes: s.lanes.map((l) => ({ ...l, subOutcome: l.subOutcome(s.fallback) })) });

test("both lanes' chains start the same legs with the same credential decisions as before select-model-credential", () => {
  let count = 0;
  const shapes = new Set();
  for (const s of states()) {
    count++;
    const before = chain("old", s);
    const after = chain("new", s);
    assert.deepEqual(after, before, show(s));
    shapes.add(before.started.filter((j) => !j.includes(":")).join(","));
  }
  for (const shape of ["", KEY, `${KEY},${SUB}/claude-review`, `${KEY},${SUB}/claude-review,${FB}/claude-review`, `${SUB}/claude-review,${SUB}/claude-security-review`, `${SUB}/claude-review,${FB}/claude-review`]) {
    assert.ok(shapes.has(shape), `reached ${shape || "no leg"}`);
  }
  assert.ok(count > 10000, `${count} states`);
});

test("a step that fails after a handoff still hands the lane on, as the old handoff step did", () => {
  const lane = { ...SECOND[1], failAt: "after-run" };
  const s = { gate: "ok", key: true, sub: true, fallback: true, secrets: { [`secrets.${SECRETS.key}`]: "set", [`secrets.${SECRETS.sub}`]: "set", [`secrets.${SECRETS.fallback}`]: "set" }, lanes: [lane, SECOND[0]] };
  assert.deepEqual(chain("new", s).started.slice(0, 3), [KEY, "review-handoffs:success", `${SUB}/claude-review`]);
  assert.deepEqual(chain("new", s), chain("old", s));
});

test("with both tokens empty, the subscription leg runs no model and hands nothing on", () => {
  const s = { gate: "skip", key: false, sub: false, fallback: false, secrets: {}, lanes: [SECOND[0], SECOND[0]] };
  const after = chain("new", s);
  assert.deepEqual(after.started, ["review-handoffs:success", `${SUB}/claude-review`, `${SUB}/claude-security-review`]);
  assert.equal(after.legs[`${SUB}/claude-review`].model, false);
  assert.deepEqual(after, chain("old", s));
});


test("every reader of a leg's present compares it to true", () => {
  const reads = [...TEXT.matchAll(/steps\.credential\.outputs\.present\b(.{0,12})/g)].map((m) => m[1]);
  assert.ok(reads.length > 0);
  for (const rest of reads) assert.match(rest, /^ == 'true'/);
});
