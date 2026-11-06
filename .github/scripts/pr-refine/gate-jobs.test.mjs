// pr-refine.yml's job gates and limits: the plan job decides which passes
// start, a PR the plan matches to no pass skips every job after it, and every
// job has a timeout so a hung job cannot strand the run.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const TEXT = readFileSync(new URL("../../workflows/pr-refine.yml", import.meta.url), "utf8");

// Each job's lines, from `  <job>:` to the next job, in file order.
function jobs(text) {
  const lines = text.slice(text.indexOf("\njobs:\n") + 1).split("\n").slice(1);
  const out = new Map();
  let name = null;
  for (const line of lines) {
    const start = /^ {2}([a-z][\w-]*):$/.exec(line);
    if (start) out.set((name = start[1]), []);
    else if (name) out.get(name).push(line);
  }
  return out;
}

// A job's needs and if:, single-line or folded, as written.
function gateOf(block) {
  const needsLine = block.find((line) => /^ {4}needs: /.test(line));
  const needs = needsLine ? needsLine.slice("    needs: ".length).replace(/^\[|\]$/g, "").split(",").map((n) => n.trim()).filter(Boolean) : [];
  const at = block.findIndex((line) => /^ {4}if: /.test(line));
  if (at === -1) return { needs, gate: null };
  let gate = block[at].slice("    if: ".length);
  if (gate === ">-") {
    const folded = [];
    for (const line of block.slice(at + 1)) {
      if (!line.startsWith("      ")) break;
      folded.push(line.trim());
    }
    gate = folded.join(" ");
  }
  return { needs, gate: gate.replace(/^\$\{\{([\s\S]*)\}\}$/, "$1").trim() };
}

// Evaluates a gate with each context reference read from `context` (a needs
// output nobody set reads ''), covering the operators and functions these
// gates use: ==, !=, &&, ||, !, parentheses, format('{0}', x), !cancelled().
// GitHub compares strings case-insensitively; every value here is already in
// the gate's case.
function evaluate(gate, context) {
  const literals = [];
  let body = gate.replace(/'[^']*'/g, (literal) => `__L${literals.push(literal) - 1}__`);
  body = body.replaceAll("!cancelled()", "true");
  body = body.replace(/\b(?:needs|inputs|vars|github)(?:\.[\w-]+)+/g, (ref) => {
    if (Object.hasOwn(context, ref)) return JSON.stringify(context[ref]);
    assert.match(ref, /^needs\.[\w-]+\.outputs\./, `an unset context reference ${ref}`);
    return '""';
  });
  body = body.replace(/format\(__L\d+__, ([^)]*)\)/g, "String($1)");
  body = body.replace(/__L(\d+)__/g, (_, i) => JSON.stringify(literals[Number(i)].slice(1, -1)));
  assert.doesNotMatch(body, /[A-Za-z_][\w-]*\.[\w.-]+|\(\)/, `an unresolved reference in ${body}`);
  return Function(`return (${body});`)();
}

// Runs the jobs in file order as GitHub would: a job whose gate names no
// status function also needs every job it needs to have succeeded; a job
// that runs succeeds with the outputs `outputs` gives it.
function simulate(text, base, outputs) {
  const results = {};
  const context = { ...base };
  for (const [name, block] of jobs(text)) {
    const { needs, gate } = gateOf(block);
    const statusFree = gate === null || !/cancelled\(\)|always\(\)|failure\(\)/.test(gate);
    const needsOk = needs.every((n) => results[n] === "success");
    const runs = (!statusFree || needsOk) && (gate === null || evaluate(gate, context));
    results[name] = runs ? "success" : "skipped";
    context[`needs.${name}.result`] = results[name];
    if (runs) for (const [key, value] of Object.entries(outputs[name] ?? {})) context[`needs.${name}.outputs.${key}`] = value;
  }
  return results;
}

const DISPATCH = {
  "inputs.pr-number": "7",
  "inputs.activity": "fix-docs",
  "inputs.dispatcher-run-id": "",
  "github.event.sender.id": 1,
  "vars.AUTOMATION_LANES_APP_SENDER_ID": "2",
};
const ran = (results) => Object.keys(results).filter((name) => results[name] === "success");

test("an empty plan skips every job after it, with no model turn", () => {
  const results = simulate(TEXT, DISPATCH, { plan: { passes: "[]", "fix-docs": "" } });
  assert.deepEqual(ran(results), ["dispatcher-current", "plan"]);
  assert.ok(Object.keys(results).length > 8, "every job was simulated");
});

test("a plan with fix-docs starts fix-docs and records its pass (positive control)", () => {
  const results = simulate(TEXT, DISPATCH, {
    plan: { passes: '["fix-docs"]', "fix-docs": "true" },
    "fix-docs-head": { held: "false", "head-sha": "a".repeat(40) },
    "fix-docs": { "scan-patch-state": "written" },
  });
  for (const job of ["plan", "fix-docs-head", "fix-docs", "fix-docs-handoff", "apply-docs-patch", "record-passes"]) {
    assert.equal(results[job], "success", job);
  }
});

test("the plan job waits on a current dispatcher, and fix-docs-head on the plan's fix-docs output", () => {
  const block = jobs(TEXT);
  const plan = gateOf(block.get("plan"));
  assert.deepEqual(plan.needs, ["dispatcher-current"]);
  assert.equal(evaluate(plan.gate, { ...DISPATCH, "needs.dispatcher-current.outputs.stale": "false" }), true);
  assert.equal(evaluate(plan.gate, { ...DISPATCH, "needs.dispatcher-current.outputs.stale": "true" }), false);
  assert.equal(evaluate(plan.gate, { ...DISPATCH, "inputs.pr-number": "" }), false);
  const head = gateOf(block.get("fix-docs-head"));
  assert.ok(head.needs.includes("plan"));
  const starts = (planned) => evaluate(head.gate, { ...DISPATCH, "needs.plan.outputs.fix-docs": planned });
  assert.equal(starts("true"), true);
  assert.equal(starts(""), false);
  assert.equal(starts("false"), false);
});

test("record-passes runs after a failed pass, and not when the plan is empty or did not run", () => {
  const { needs, gate } = gateOf(jobs(TEXT).get("record-passes"));
  assert.ok(needs.includes("plan") && needs.includes("apply-docs-patch") && needs.includes("fix-docs"));
  const records = (result, passes) => evaluate(gate, { "needs.plan.result": result, "needs.plan.outputs.passes": passes });
  assert.equal(records("success", '["fix-docs"]'), true);
  assert.equal(records("success", "[]"), false);
  assert.equal(records("skipped", ""), false);
  const results = simulate(TEXT, DISPATCH, { plan: { passes: '["fix-docs"]', "fix-docs": "true" }, "fix-docs-head": { held: "false" } });
  assert.equal(results["record-passes"], "success", "it runs whatever the pass jobs did");
});

test("every pr-refine job has a timeout: its own, or its reusable workflow's timeout-minutes input", () => {
  const all = jobs(TEXT);
  assert.ok(all.size > 8);
  for (const [name, block] of all) {
    const own = block.some((line) => /^ {4}timeout-minutes: \d+$/.test(line));
    const passed = block.some((line) => /^ {4}uses: /.test(line)) && block.some((line) => /^ {6}timeout-minutes: \d+$/.test(line));
    assert.ok(own || passed, `${name} sets timeout-minutes`);
  }
});
