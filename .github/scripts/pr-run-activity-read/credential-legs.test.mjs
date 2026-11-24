import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";
import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const PATH = new URL("../../workflows/pr-run-activity-read.yml", import.meta.url);
const TEXT = readFileSync(PATH, "utf8");
const JOBS = TEXT.slice(TEXT.indexOf("\njobs:\n"));
const wf = workflowText(JOBS);
const S = await loadSelect(selectPin(TEXT));

function stepIf(body) {
  const folded = /^ {8}if: >-\n((?: {10}.*\n)+)/m.exec(body);
  if (folded) return folded[1].replace(/\s+/g, " ").trim();
  return /^ {8}if: (.*)$/m.exec(body)?.[1] ?? "";
}
const stepBody = (name) => {
  const found = wf.job("run").split(/\n(?= {6}- name: )/).filter((s) => s.startsWith(`      - name: ${name}\n`));
  assert.equal(found.length, 1, name);
  return found[0];
};
const envOf = (body, name) => new RegExp(`^ {10}${name}: (.*)$`, "m").exec(body)[1];

const READY = "steps.launch.outcome == 'success' && steps.go.outputs.run == 'true'";
const OLD = {
  keyIf: `${READY} && inputs.fallback == ''`,
  tokenIf: `${READY} && inputs.fallback != '' && inputs.fallback != 'fallback'`,
  fallbackIf: `${READY} && inputs.fallback == 'fallback'`,
  outputs: {
    "lane-class": "${{ steps.act-key.outputs.lane-class || steps.act-token.outputs.lane-class || steps.act-fallback.outputs.lane-class }}",
    "credential-present": "${{ steps.key-present.outputs.present || steps.token-present.outputs.present || steps.fallback-present.outputs.present }}",
    "handed-off": "${{ steps.key-present.outputs.present == 'false' || steps.act-key.outputs.handoff == 'true' || steps.act-token.outputs.handoff == 'true' || steps.token-present.outputs.present == 'false' && inputs.fallback-ready == 'true' }}",
  },
  reason: "${{ inputs.fallback == 'credit-stop' && 'credit-stop' || inputs.fallback == 'no-key' && 'no-key' || '' }}",
};
const SECRETS = { key: "claude-api-key", sub: "claude-code-oauth-token", fallback: "fallback-claude-code-oauth-token" };
const STEPS = { key: "key-present", sub: "token-present", fallback: "fallback-present" };
const ACT = { key: "act-key", sub: "act-token", fallback: "act-fallback" };

const RECORD = stepBody("Record the launcher's lane outcome");
const COLLECT = stepBody("Collect the issue outcome");
const LATER = {
  act: Object.fromEntries(Object.entries(ACT).map(([leg, id]) => [leg, wf.step("run", id).if])),
  record: stepIf(RECORD),
  collect: stepIf(COLLECT),
};

function act(leg, end) {
  const id = ACT[leg];
  const handoff = end.kind === "handoff";
  return {
    [`steps.${id}.outcome`]: end.kind === "fail" ? "failure" : "success",
    [`steps.${id}.outputs.handoff`]: handoff ? "true" : end.kind === "fail" ? "" : "false",
    [`steps.${id}.outputs.handoff-reason`]: handoff ? end.reason : "",
    [`steps.${id}.outputs.lane-class`]: handoff ? end.reason : end.kind === "fail" ? "other" : "",
  };
}

function after(base, presence, s, outputs, recordReason, collectReason) {
  const ctx = { ...base, ...presence, "steps.config.outputs.kind": "skill", "steps.act-turns.outcome": "success" };
  for (const leg of Object.keys(ACT)) {
    ctx[`steps.${ACT[leg]}.outcome`] = "skipped";
    if (runs(LATER.act[leg], ctx)) Object.assign(ctx, act(leg, s.end));
  }
  if (s.failAfter) ctx["steps.act-error.outcome"] = "failure";
  const out = {
    ran: Object.values(ACT).filter((id) => ctx[`steps.${id}.outcome`] !== "skipped"),
    outputs: Object.fromEntries(Object.entries(outputs).map(([k, v]) => [k, value(v, ctx)])),
    record: runs(LATER.record, ctx) ? value(recordReason, ctx) : null,
    collect: runs(LATER.collect, ctx) ? value(collectReason, ctx) : null,
  };
  return out;
}

function context(s) {
  return {
    "inputs.fallback": s.fallback,
    "inputs.fallback-ready": s.ready,
    "inputs.issue-number": s.issue ? "7" : "",
    "inputs.role": "pr-unblock",
    "steps.launch.outcome": s.reached ? "success" : "skipped",
    "steps.go.outputs.run": s.reached ? "true" : "",
    "needs.check-broker.outputs.skip-key": s.fallback === "" ? s.gate : "",
    [`secrets.${SECRETS.key}`]: s.key ? "set" : "",
    [`secrets.${SECRETS.sub}`]: s.sub ? "set" : "",
    [`secrets.${SECRETS.fallback}`]: s.fallbackSet ? "set" : "",
  };
}

function oldRun(s) {
  const base = context(s);
  const presence = {};
  const set = (leg, present) => Object.assign(presence, { [`steps.${STEPS[leg]}.outcome`]: "success", [`steps.${STEPS[leg]}.outputs.present`]: String(present) });
  for (const leg of Object.keys(STEPS)) presence[`steps.${STEPS[leg]}.outcome`] = "skipped";
  if (runs(OLD.keyIf, base)) set("key", base["needs.check-broker.outputs.skip-key"] === "true" ? false : s.key);
  if (runs(OLD.tokenIf, base)) set("sub", s.sub);
  if (runs(OLD.fallbackIf, base)) set("fallback", s.fallbackSet);
  return after(base, presence, s, OLD.outputs, OLD.reason, OLD.reason);
}

const LEG = { key: "key", sub: "subscription", fallback: "fallback" };
function newRun(s) {
  const base = context(s);
  const presence = {};
  for (const [leg, id] of Object.entries(STEPS)) {
    const call = wf.step("run", id);
    assert.equal(call.inputs.leg, LEG[leg], id);
    presence[`steps.${id}.outcome`] = "skipped";
    if (!runs(stepIf(call.text), base)) continue;
    const input = (name) => (call.inputs[name] === undefined ? "" : value(call.inputs[name], base));
    assert.equal(input("key-job"), "", id);
    const decided = S.leg({ leg: LEG[leg], role: input("role"), credentialSet: input("credential-set"), fallbackSet: input("fallback-set"), keyOff: input("key-off"), selected: input("selected"), held: false, reason: input("reason") }).outputs;
    presence[`steps.${id}.outcome`] = "success";
    for (const [k, v] of Object.entries(decided)) presence[`steps.${id}.outputs.${k}`] = v;
  }
  const outputs = wf.outputs("run");
  return after(
    base,
    presence,
    s,
    { "lane-class": outputs["lane-class"], "credential-present": outputs["credential-present"], "handed-off": outputs["handed-off"] },
    /^ {10}fallback-reason: (.*)$/m.exec(RECORD)[1],
    envOf(COLLECT, "LANE_FALLBACK"),
  );
}

function ends(leg, ready) {
  const launcherLeg = { key: "api-key", sub: "subscription", fallback: "fallback" }[leg];
  const out = [{ kind: "result" }, { kind: "fail" }];
  for (const { reason } of launcherOutcomes(S.handoffReason, launcherLeg, ready)) if (reason !== "") out.push({ kind: "handoff", reason });
  return out;
}

const valid = (issue, fallback, ready) =>
  (!issue || ["", "handoff", "credit-stop", "fallback"].includes(fallback)) && (["", "fallback"].includes(fallback) ? ready === "" : true);

function* states() {
  for (const issue of [false, true])
    for (const fallback of ["", "credit-stop", "no-key", "handoff", "fallback"])
      for (const ready of ["", "true", "false"])
        if (valid(issue, fallback, ready))
          for (const reached of [true, false])
            for (const gate of ["true", "false", ""])
              for (const key of [true, false])
                for (const sub of [true, false])
                  for (const fallbackSet of [true, false])
                    for (const failAfter of [false, true]) {
                      const leg = fallback === "" ? "key" : fallback === "fallback" ? "fallback" : "sub";
                      for (const end of ends(leg, ready === "true")) yield { issue, fallback, ready, reached, gate, key, sub, fallbackSet, failAfter, end };
                    }
}

test("pr-run-activity-read's run job runs the same leg and sets the same outputs and fallback reasons as before select-model-credential", (t) => {
  let count = 0;
  const shapes = new Set();
  for (const s of states()) {
    count++;
    const before = oldRun(s);
    assert.deepEqual(newRun(s), before, JSON.stringify(s));
    shapes.add(`${before.ran.join(",")}|${before.outputs["handed-off"]}|${before.record}`);
  }
  for (const shape of ["act-key|false|", "act-key|true|", "|true|null", "act-token|false|credit-stop", "act-token|false|no-key", "act-token|true|", "act-fallback|false|"]) {
    assert.ok(shapes.has(shape), `reached ${shape}`);
  }
  assert.ok(count > 1000, `${count} states`);
  t.diagnostic(`${count} states`);
});

test("the workflow_call outputs the run and check-broker jobs set, and their sources, are unchanged from 5599e627fc", () => {
  const call = {
    "head-sha": "${{ jobs.run.outputs.head-sha }}",
    "lane-class": "${{ jobs.run.outputs.lane-class }}",
    "credential-present": "${{ jobs.run.outputs.credential-present }}",
    "handed-off": "${{ jobs.run.outputs.handed-off }}",
    "skip-reason": "${{ jobs.check-broker.outputs.skip-reason }}",
    lease: "${{ jobs.check-broker.outputs.lease }}",
    "lease-comment-id": "${{ jobs.check-broker.outputs.lease-comment-id }}",
  };
  const brokerCheck = {
    allowed: "${{ steps.broker.outcome == 'success' && steps.broker.outputs.allowed == 'true' }}",
    "skip-reason": "${{ steps.kill.outputs.cause == 'budget' && 'budget' || steps.broker.outputs.skip-reason }}",
    attempt: "${{ github.run_attempt }}",
    lease: "${{ steps.lease.outputs.lease }}",
    "lease-comment-id": "${{ steps.lease.outputs.lease-comment-id }}",
    blocked: "${{ steps.recheck-blockers.outcome == 'success' && steps.recheck-blockers.outputs.proceed != 'true' }}",
    "skip-key": "${{ steps.credit.outputs.skip-key }}",
  };
  const outputsBlock = TEXT.slice(TEXT.indexOf("\n    outputs:\n"), TEXT.indexOf("\npermissions:"));
  for (const [name, expression] of Object.entries(call)) {
    assert.equal(new RegExp(`^ {6}${name}:\\n(?: {8}.*\\n)*? {8}value: (.*)$`, "m").exec(outputsBlock)?.[1], expression, name);
  }
  const { "skip-run": skipRun, ...kept } = wf.outputs("check-broker");
  assert.equal(typeof skipRun, "string");
  assert.deepEqual(kept, brokerCheck);
  for (const [name, expression] of Object.entries(OLD.outputs)) assert.equal(wf.outputs("run")[name], expression, name);
});

test("check-broker's start call reads the credit history on the first call alone, as check-key-credit did", () => {
  const credit = wf.step("check-broker", "credit");
  assert.equal(credit.inputs.leg, "start");
  assert.equal(credit.inputs["key-job"], "${{ inputs.key-credit-job }}");
  assert.equal(credit.inputs["probe-minutes"], '"0"');
  const old = "steps.broker.outcome == 'success' && steps.broker.outputs.allowed == 'true' && inputs.key-credit-job != '' && inputs.fallback == ''";
  assert.equal(stepIf(credit.text), old);
  assert.match(credit.text, /^ {8}continue-on-error: true$/m, "a failed read runs the key");
});

const OLD_GATES = {
  run: "!(github.event_name == 'pull_request' && format('{0}', github.event.sender.id) == vars.AUTOMATION_LANES_APP_SENDER_ID) && needs.check-broker.outputs.skip-reason == ''",
  report:
    "always() && (inputs.issue-number == '' && needs.run.outputs.handed-off != 'true' && !(github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name != github.repository) && !(github.event_name == 'pull_request' && format('{0}', github.event.sender.id) == vars.AUTOMATION_LANES_APP_SENDER_ID) || inputs.issue-number != '' && needs.check-broker.outputs.lease == 'held' && needs.check-broker.outputs.lease-comment-id != '' && !(inputs.caller-releases-lease && needs.run.outputs.handed-off != 'true' && (needs.check-issue-fields.outputs.issue-run-started == 'true' || needs.check-issue-fields.outputs.reuse-branch != '')))",
};
const SENDER = "format('{0}', github.event.sender.id)";
const gate = (text) => {
  assert.equal(text.split(SENDER).length, 2, `one sender id comparison in ${text}`);
  return text.replace(SENDER, "github.event.sender.id");
};
const NEW_GATES = { run: gate(wf.jobIf("run")), report: gate(wf.jobIf("report")) };
const SKIP_RUN = wf.outputs("check-broker")["skip-run"];

function* gateContexts() {
  for (const event of ["pull_request", "workflow_dispatch"])
    for (const sender of ["5", "6"])
      for (const headRepo of ["o/r", "fork/r"])
        for (const issue of ["", "7"])
          for (const skipReason of ["", "kill-switch", "budget"])
            for (const skipKey of ["true", "false", ""])
              for (const postDecline of [true, false])
                for (const handedOff of ["true", "false", ""])
                  for (const lease of ["held", "already-leased", ""])
                    for (const leaseId of ["9", ""])
                      for (const releases of [true, false])
                        for (const started of ["true", ""])
                          for (const reuse of ["b", ""]) {
                            const ctx = {
                              "github.event_name": event,
                              "github.event.sender.id": sender,
                              "vars.AUTOMATION_LANES_APP_SENDER_ID": "5",
                              "github.event.pull_request.head.repo.full_name": headRepo,
                              "github.repository": "o/r",
                              "inputs.issue-number": issue,
                              "inputs.post-decline": postDecline,
                              "inputs.caller-releases-lease": releases,
                              "steps.credit.outputs.skip-key": skipKey,
                              "needs.check-broker.outputs.skip-reason": skipReason,
                              "needs.check-broker.outputs.skip-key": skipKey,
                              "needs.check-broker.outputs.lease": lease,
                              "needs.check-broker.outputs.lease-comment-id": leaseId,
                              "needs.run.outputs.handed-off": handedOff,
                              "needs.check-issue-fields.outputs.issue-run-started": started,
                              "needs.check-issue-fields.outputs.reuse-branch": reuse,
                            };
                            ctx["needs.check-broker.outputs.skip-run"] = value(SKIP_RUN, ctx);
                            yield ctx;
                          }
}

test("check-broker skips the key leg's run only for a pull-request first call whose key was skipped and whose declines are posted", () => {
  const skip = (issue, postDecline, skipKey) =>
    value(SKIP_RUN, { "inputs.issue-number": issue, "inputs.post-decline": postDecline, "steps.credit.outputs.skip-key": skipKey });
  assert.equal(skip("", true, "true"), "true", "pr-unblock's key leg after a credit stop");
  assert.equal(skip("", false, "true"), "false", "fix-docs posts no decline, so its handoff read needs the run job");
  assert.equal(skip("7", true, "true"), "false", "issue mode releases its lease through the run job's outputs");
  assert.equal(skip("", true, "false"), "false", "the key has credit");
  assert.equal(skip("", true, ""), "false", "no credit read: the key runs");
});

test("the run and report job conditions keep their old values unless check-broker skips the key leg's run, and both skip when it does", () => {
  let same = 0;
  let skipped = 0;
  for (const ctx of gateContexts()) {
    const label = JSON.stringify(ctx);
    if (ctx["needs.check-broker.outputs.skip-run"] !== "true") {
      same++;
      assert.equal(runs(NEW_GATES.run, ctx), runs(gate(OLD_GATES.run), ctx), `run, ${label}`);
      assert.equal(runs(NEW_GATES.report, ctx), runs(gate(OLD_GATES.report), ctx), `report, ${label}`);
      continue;
    }
    skipped++;
    assert.equal(runs(NEW_GATES.run, ctx), false, `run skipped, ${label}`);
    assert.equal(runs(NEW_GATES.report, ctx), false, `report skipped, ${label}`);
  }
  assert.ok(same > 10000 && skipped > 1000, `${same} unchanged, ${skipped} skipped`);
});

test("without the report guard a skipped key-leg run would post the check, which starts no subscription call", () => {
  const ctx = [...gateContexts()].find(
    (c) =>
      c["needs.check-broker.outputs.skip-run"] === "true" &&
      c["github.event_name"] === "workflow_dispatch" &&
      c["needs.check-broker.outputs.skip-reason"] === "" &&
      c["needs.run.outputs.handed-off"] === "",
  );
  assert.equal(runs(gate(OLD_GATES.run), ctx), true, "the old run job ran on a skipped key");
  assert.equal(runs(gate(OLD_GATES.report), ctx), true, "the old report would post once the run job's handed-off is empty");
  assert.equal(runs(NEW_GATES.report, ctx), false);
});

test("with the key leg's run and report skipped, the jobs after them skip as they did on its handoff", () => {
  const ctx = { "inputs.issue-number": "", "needs.run.result": "skipped", "needs.run.outputs.handed-off": "", "needs.scan.result": "skipped" };
  assert.equal(runs(wf.jobIf("check-issue-fields"), ctx), false, "check-issue-fields");
  assert.equal(runs(wf.jobIf("scan"), ctx), false, "scan");
  assert.equal(runs(wf.jobIf("scan-refusal"), ctx), false, "scan-refusal");
  assert.equal(runs(wf.jobIf("generate-reuse-summary"), ctx), false, "generate-reuse-summary");
  assert.equal(runs(wf.jobIf("record-broker-allow"), { "needs.check-broker.outputs.allowed": "true" }), true, "record-broker-allow still records the allow");
});

const EVIDENCE = fileURLToPath(new URL("../lib/handoff-evidence.sh", import.meta.url));
function evidence(jobs, calls, facts) {
  const dir = tempDir("skip-run-evidence-");
  const bin = join(dir, "bin");
  mkdirSync(bin);
  writeFileSync(join(dir, "answer"), ["HTTP/2.0 200", 'etag: "e"', "", JSON.stringify({ total_count: jobs.length, jobs })].join("\r\n"));
  writeFileSync(join(bin, "gh"), `#!/usr/bin/env bash\ncat "${dir}/answer"\n`);
  chmodSync(join(bin, "gh"), 0o755);
  const output = join(dir, "output");
  writeFileSync(output, "");
  const result = spawnSync("bash", [EVIDENCE, ...facts], {
    encoding: "utf8",
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: "", GH_TOKEN: "t", GITHUB_REPOSITORY: "o/r", GITHUB_RUN_ID: "7", GITHUB_OUTPUT: output, CALLS: calls, HANDOFF_EVIDENCE_DELAYS: "0" },
  });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  return Object.fromEntries(readFileSync(output, "utf8").trim().split("\n").map((line) => line.split("=")));
}

test("pr-unblock starts each subscription call on a skipped key-leg run exactly as on the run job's handoff", () => {
  const UNBLOCK = readFileSync(new URL("../../workflows/pr-unblock.yml", import.meta.url), "utf8");
  const unblock = workflowText(UNBLOCK.slice(UNBLOCK.indexOf("\njobs:\n")));
  const legs = [...UNBLOCK.matchAll(/^ {2}([a-z0-9-]+):\n(?:(?! {2}\S).*\n)*? {6}key-credit-job: \1\n/gm)].map((m) => m[1]);
  assert.deepEqual(legs, ["resolve-conflicts", "address-feedback", "review-dependency", "fix-ci", "fix-ci-rung-up"]);
  for (const leg of legs) {
    assert.doesNotMatch(unblock.job(leg), /post-decline/, `${leg} posts its declines`);
    const named = leg.replace(/[a-z0-9]+/g, (w) => (w === "ci" ? "CI" : w[0].toUpperCase() + w.slice(1))).replaceAll("-", " ");
    const job = (callee, conclusion, steps = []) => ({ name: `${named} / ${callee}`, conclusion, steps });
    const common = [job("Check Broker", "success", [{ name: "Ask the broker whether the lane may run", conclusion: "success" }]), job("Record Broker Allow", "success")];
    const handoff = evidence([...common, job("Run", "success", [{ name: "Mark a key credit stop", conclusion: "skipped" }]), job("Scan", "skipped"), job("Report", "skipped")], leg, ["posted", "allowed", "credit-stop"]);
    const skippedRun = evidence([...common, job("Run", "skipped"), job("Scan", "skipped"), job("Report", "skipped")], leg, ["posted", "allowed", "credit-stop"]);
    assert.deepEqual(skippedRun, { posted: "false", allowed: "true", "credit-stop": "false" }, leg);
    assert.deepEqual(skippedRun, handoff, `${leg}: the same facts as the run job's handoff`);
    // A call whose run job skipped while its check-broker succeeded is not
    // `skipped` to the caller: run 42742077371's address-feedback call had
    // check-broker and report success and every other job skipped, and
    // upload-key-credit-markers, whose if needs one call's result != 'skipped' with
    // the other four calls skipped, ran. Only != 'skipped' is read here.
    const ctx = {
      [`needs.${leg}-select.outputs.proceed`]: "true",
      "needs.fix-ci-context.outputs.proceed": "true",
      [`needs.${leg}.result`]: "success",
      [`needs.${leg}-handoff.outputs.posted`]: skippedRun.posted,
    };
    assert.equal(runs(unblock.jobIf(`${leg}-handoff`), ctx), true, `${leg}-handoff`);
    assert.equal(runs(unblock.jobIf(`${leg}-subscription`), ctx), true, `${leg}-subscription`);
  }
});

test("every leg turns the sandbox off for ci-context alone", () => {
  assert.doesNotMatch(TEXT, /^ +sandbox: "false"$/m);
  for (const id of Object.values(ACT)) {
    const sandbox = wf.step("run", id).inputs.sandbox;
    for (const prepare of ["ci-context", "review-threads", "dependency-review", "merge-base", ""]) {
      const want = prepare === "ci-context" ? "false" : "true";
      assert.equal(value(sandbox, { "steps.config.outputs.prepare": prepare }), want, `${id}, prepare "${prepare}"`);
    }
  }
});

test("pr-refine's fix-docs, which posts no decline, keeps its run job on a skipped key", () => {
  const REFINE = readFileSync(new URL("../../workflows/pr-refine.yml", import.meta.url), "utf8");
  const fixDocs = workflowText(REFINE.slice(REFINE.indexOf("\njobs:\n"))).job("fix-docs");
  assert.match(fixDocs, /^ {6}key-credit-job: fix-docs$/m);
  assert.match(fixDocs, /^ {6}post-decline: false$/m);
  const ctx = { "inputs.issue-number": "", "inputs.post-decline": false, "steps.credit.outputs.skip-key": "true" };
  assert.equal(value(SKIP_RUN, ctx), "false");
});
