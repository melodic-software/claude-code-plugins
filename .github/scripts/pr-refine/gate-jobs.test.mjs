// pr-refine.yml's job gates and limits: the select-passes job decides which passes
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

function ifAt(lines, at, indent) {
  let gate = lines[at].slice(indent + "if: ".length);
  if (gate === ">-") {
    const folded = [];
    for (const line of lines.slice(at + 1)) {
      if (!line.startsWith(" ".repeat(indent + 2))) break;
      folded.push(line.trim());
    }
    gate = folded.join(" ");
  }
  return gate.replace(/^\$\{\{([\s\S]*)\}\}$/, "$1").trim();
}

function gateOf(block) {
  const needsLine = block.find((line) => /^ {4}needs: /.test(line));
  const needs = needsLine ? needsLine.slice("    needs: ".length).replace(/^\[|\]$/g, "").split(",").map((n) => n.trim()).filter(Boolean) : [];
  const at = block.findIndex((line) => /^ {4}if: /.test(line));
  return { needs, gate: at === -1 ? null : ifAt(block, at, 4) };
}

function stepIf(block, id) {
  const at = block.indexOf(`        id: ${id}`);
  assert.notEqual(at, -1, `a step with id ${id}`);
  let start = at;
  while (!block[start].startsWith("      - name: ")) start--;
  const step = block.slice(start, block.findIndex((line, i) => i > start && line.startsWith("      - ")) >>> 0);
  const ifLine = step.findIndex((line) => /^ {8}if: /.test(line));
  assert.notEqual(ifLine, -1, `step ${id} has an if:`);
  return ifAt(step, ifLine, 8);
}

function outputOf(block, name) {
  const line = block.find((l) => l.startsWith(`      ${name}: `));
  assert.ok(line, `an output ${name}`);
  return line.slice(`      ${name}: `.length).replace(/^\$\{\{([\s\S]*)\}\}$/, "$1").trim();
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
  body = body.replace(/\b(?:needs|inputs|vars|github|steps)(?:\.[\w-]+)+/g, (ref) => {
    if (Object.hasOwn(context, ref)) return JSON.stringify(context[ref]);
    assert.match(ref, /^(?:needs|steps)\.[\w-]+\.outputs\./, `an unset context reference ${ref}`);
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
function simulate(text, base, outputs, forced = {}) {
  const results = {};
  const context = { ...base };
  for (const [name, block] of jobs(text)) {
    const { needs, gate } = gateOf(block);
    const statusFree = gate === null || !/cancelled\(\)|always\(\)|failure\(\)/.test(gate);
    const needsOk = needs.every((n) => results[n] === "success");
    const runs = (!statusFree || needsOk) && (gate === null || evaluate(gate, context));
    results[name] = runs ? (forced[name] ?? "success") : "skipped";
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
const PLANNED = { passes: '["fix-docs"]', "fix-docs": "true", held: "false", "plan-result": "success" };

test("an empty plan skips every job after it, with no model turn", () => {
  const results = simulate(TEXT, DISPATCH, { "select-passes": { passes: "[]", "fix-docs": "", held: "false", "plan-result": "success", "head-result": "skipped" } });
  assert.deepEqual(ran(results), ["select-passes"]);
  assert.ok(Object.keys(results).length > 8, "every job was simulated");
});

test("a plan with fix-docs starts fix-docs and records its pass (positive control)", () => {
  const results = simulate(TEXT, DISPATCH, {
    "select-passes": { ...PLANNED, "hold-held": "false", "head-sha": "a".repeat(40), "head-result": "success" },
    "fix-docs": { "scan-patch-state": "written" },
  });
  for (const job of ["select-passes", "fix-docs", "fix-docs-handoff", "apply-docs-patch", "record-passes"]) {
    assert.equal(results[job], "success", job);
  }
});

test("a stale dispatcher starts no pass, no hold and no record", () => {
  const results = simulate(TEXT, { ...DISPATCH, "inputs.dispatcher-run-id": "9" }, { "select-passes": { stale: "true", "plan-result": "skipped", "head-result": "skipped" } });
  assert.deepEqual(ran(results), ["select-passes"]);
});

test("select-passes runs the compare for a dispatcher run, and plans only on a current dispatcher", () => {
  const block = jobs(TEXT).get("select-passes");
  const job = gateOf(block);
  assert.deepEqual(job.needs, [], "the first job");
  const jobRuns = (context) => evaluate(job.gate, { ...DISPATCH, ...context });
  assert.equal(jobRuns({}), true);
  assert.equal(jobRuns({ "github.event.sender.id": 2, "inputs.dispatcher-run-id": "9" }), true, "a dispatcher run is compared whoever sent it");
  assert.equal(jobRuns({ "github.event.sender.id": 2 }), false);
  assert.equal(jobRuns({ "inputs.activity": "apply-patch" }), false);
  assert.equal(jobRuns({ "inputs.pr-number": "" }), false);
  assert.equal(stepIf(block, "current"), "inputs.dispatcher-run-id != ''");

  const start = stepIf(block, "start");
  const plans = (context) => evaluate(start, { ...DISPATCH, "steps.current.outcome": "skipped", ...context });
  assert.equal(plans({}), true, "a human dispatch: no compare");
  assert.equal(plans({ "inputs.dispatcher-run-id": "9", "steps.current.outcome": "success", "steps.current.outputs.stale": "false" }), true);
  assert.equal(plans({ "inputs.dispatcher-run-id": "9", "steps.current.outcome": "success", "steps.current.outputs.stale": "true" }), false);
  assert.equal(plans({ "inputs.dispatcher-run-id": "9", "steps.current.outcome": "failure" }), false, "a red compare");
  assert.equal(plans({ "inputs.dispatcher-run-id": "9", "steps.current.outcome": "skipped" }), false, "a red tip before the compare");
  assert.equal(plans({ "inputs.pr-number": "" }), false);
  assert.equal(plans({ "inputs.activity": "apply-patch" }), false);
  assert.equal(plans({ "github.event.sender.id": 2 }), false);
  assert.equal(stepIf(block, "files"), "steps.start.outcome == 'success'");

  const reads = (planned) => evaluate(stepIf(block, "head"), { "steps.plan.outputs.fix-docs": planned });
  assert.equal(reads("true"), true);
  assert.equal(reads(""), false);
  assert.equal(reads("false"), false);
});

test("plan-result and head-result give each part's own result", () => {
  const block = jobs(TEXT).get("select-passes");
  const plan = (start, files, held, planOutcome) =>
    evaluate(outputOf(block, "plan-result"), { "steps.start.outcome": start, "steps.files.outputs.held": held, "steps.files.outcome": files, "steps.plan.outcome": planOutcome });
  assert.equal(plan("skipped", "skipped", "", "skipped"), "skipped", "not planned: stale, a red compare, or no fix-docs dispatch");
  assert.equal(plan("success", "success", "true", "skipped"), "success", "a held file list");
  assert.equal(plan("success", "success", "false", "success"), "success");
  assert.equal(plan("success", "failure", "", "skipped"), "failure", "a red file list");
  assert.equal(plan("success", "success", "false", "skipped"), "failure", "a red step before the plan");
  assert.equal(plan("success", "success", "false", "failure"), "failure");
  const head = (planned, unread, hold) =>
    evaluate(outputOf(block, "head-result"), { "steps.plan.outputs.fix-docs": planned, "steps.head.outputs.unread": unread, "steps.hold.outcome": hold });
  assert.equal(head("", "", "skipped"), "skipped");
  assert.equal(head("true", "true", "skipped"), "success", "an unread head holds green");
  assert.equal(head("true", "", "success"), "success");
  assert.equal(head("true", "", "skipped"), "failure", "a red head read");
  assert.equal(head("true", "", "failure"), "failure");
});

test("a failed plan starts no pass, and record-passes still runs to log refine-failed", () => {
  const results = simulate(TEXT, DISPATCH, { "select-passes": { "plan-result": "failure" } }, { "select-passes": "failure" });
  assert.deepEqual(ran(results), ["record-passes"]);
  assert.deepEqual(ran(simulate(TEXT, DISPATCH, {}, { "select-passes": "failure" })), ["record-passes"], "a failed job with no outputs read counts as a failed plan");
  const compare = simulate(TEXT, { ...DISPATCH, "inputs.dispatcher-run-id": "9" }, { "select-passes": { "plan-result": "skipped" } }, { "select-passes": "failure" });
  assert.deepEqual(ran(compare), [], "a red compare or tip on a dispatcher run never started the plan, so nothing records");
});

test("a failed head read after a plan records the fix-docs pass, not the plan", () => {
  const results = simulate(TEXT, DISPATCH, { "select-passes": { ...PLANNED, "head-result": "failure" } }, { "select-passes": "failure" });
  assert.deepEqual(ran(results), ["record-passes"]);
  const record = jobs(TEXT).get("record-passes");
  assert.ok(record.includes("          PLAN_RESULT: ${{ needs.select-passes.outputs.plan-result || needs.select-passes.result }}"));
  assert.ok(record.includes('            {"fix-docs-head": "${{ needs.select-passes.outputs.head-result }}",'));
});

test("a held plan starts no pass and no record, and fix-docs-head-held logs the hold", () => {
  const results = simulate(TEXT, DISPATCH, { "select-passes": { held: "true", "plan-result": "success", "head-result": "skipped" } });
  assert.deepEqual(ran(results), ["select-passes", "fix-docs-head-held"]);
  // Positive control: a read plan holds nothing.
  const read = simulate(TEXT, DISPATCH, { "select-passes": { held: "false", passes: "[]", "fix-docs": "", "plan-result": "success" } });
  assert.equal(read["fix-docs-head-held"], "skipped");
});

test("an unread head starts no pass, records the pass, and fix-docs-head-held logs the hold", () => {
  const results = simulate(TEXT, DISPATCH, { "select-passes": { ...PLANNED, unread: "true", "head-result": "success" } });
  assert.deepEqual(ran(results), ["select-passes", "fix-docs-head-held", "record-passes"]);
});

test("record-passes runs after a failed pass, and not when the plan is empty or did not run", () => {
  const { needs, gate } = gateOf(jobs(TEXT).get("record-passes"));
  assert.ok(needs.includes("select-passes") && needs.includes("apply-docs-patch") && needs.includes("fix-docs"));
  const records = (result, planResult, passes) =>
    evaluate(gate, { "needs.select-passes.result": result, "needs.select-passes.outputs.plan-result": planResult, "needs.select-passes.outputs.passes": passes });
  assert.equal(records("success", "success", '["fix-docs"]'), true);
  assert.equal(records("success", "success", "[]"), false);
  assert.equal(records("success", "skipped", ""), false);
  assert.equal(records("skipped", "", ""), false);
  assert.equal(records("failure", "failure", ""), true);
  assert.equal(records("failure", "", ""), true);
  assert.equal(records("failure", "skipped", ""), false);
  const results = simulate(TEXT, DISPATCH, { "select-passes": { ...PLANNED, "hold-held": "false" } });
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

// The plan reads the base config through resolve-config's own loader, the one
// plan-passes.test.mjs and live-config.test.mjs run, not a yq conversion.
test("the plan step runs write-pass-plan.mjs on the base checkout, with no yq conversion", () => {
  const plan = jobs(TEXT).get("select-passes");
  assert.ok(plan.includes("          BASE_PATH: .base"));
  assert.ok(plan.includes("        run: node .base/.github/scripts/pr-refine/write-pass-plan.mjs"));
  assert.ok(!plan.some((line) => /\byq\b/.test(line)), "no yq in the select-passes job");
});
