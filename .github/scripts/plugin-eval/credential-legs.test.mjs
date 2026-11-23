// maintenance-measure-skill-edit-pass.yml and pr-run-plugin-evals.yml run the
// eval on the maintenance API key; each also runs, with credential
// subscription, on the maintenance subscription token with no fallback
// (docs/review/evals.md, owner decisions Q14 and Q53 as amended). Each leg's
// credential comes from ci-workflows' select-model-credential, fetched at the
// pin the workflows name, and its handoff from eval-handoff.mjs (the
// handoffReason run-claude-cli's contract exports:
// https://github.com/melodic-software/ci-workflows/blob/main/.github/actions/run-claude-cli/contract.cjs).
// This truth table drives every state of each credential (set or empty, the
// key switched off or skipped by the credit gate), both credential inputs, and
// every launcher outcome through each workflow's own job conditions,
// credential inputs and stop condition: exactly one leg runs per credential
// input, the model runs only on a present credential, and the stop step fires
// exactly when the leg did not run or its credential stopped, so no stopped
// credential ends a run silently.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const read = (name) => readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8");
const HILL = read("maintenance-measure-skill-edit-pass.yml");
const BROWSER = read("pr-run-plugin-evals.yml");
const S = await loadSelect(selectPin(HILL, BROWSER));

function checkStop(stop, present, outcomes, label) {
  let states = 0;
  for (const o of present ? outcomes : [{ handoff: "", reason: "" }]) {
    states++;
    const ctx = { "steps.credential.outcome": "success", "steps.credential.outputs.present": String(present), "steps.judge.outputs.handoff": o.handoff };
    assert.equal(runs(stop.if, ctx), !present || o.handoff === "true", `${label} present=${present} outcome=${o.reason || "finished"}`);
  }
  assert.equal(runs(stop.if, { "steps.credential.outcome": "skipped" }), false, `${label}: a step that failed before the credential check is not blamed on it`);
  return states;
}

function keyLeg(wf, label) {
  const call = wf.step("run-eval", "credential");
  const stop = wf.step("run-eval", "stop");
  const outcomes = [{ handoff: "", reason: "" }, ...launcherOutcomes(S.handoffReason, "api-key", false)];
  assert.ok(outcomes.some((o) => o.reason === "credit-stop"), "a credit stop is among the outcomes");
  let states = 0;
  for (const keySet of [true, false])
    for (const keyOff of [true, false])
      for (const gate of [{ skipKey: false }, { skipKey: true }]) {
        const ctx = { "needs.check-key-credit.outputs.next-leg": S.start(gate)["next-leg"], "secrets.MAINTENANCE_CLAUDE_API_KEY != ''": String(keySet) };
        const { outputs } = S.leg({ leg: "key", role: "maintenance", credentialSet: String(keySet), keyOff: String(keyOff), selected: value(call.inputs.selected, ctx) });
        const present = outputs.present === "true";
        assert.equal(present, keySet && !keyOff && !gate.skipKey, `${label} key set=${keySet} off=${keyOff} skip=${gate.skipKey}`);
        states += checkStop(stop, present, outcomes, label);
      }
  assert.ok(states > 8, `${states} states`);
}

test("pr-run-plugin-evals.yml: the key leg runs only on a present key, and every stopped key reaches the stop step", () => {
  keyLeg(workflowText(BROWSER), "pr-run-plugin-evals.yml");
});

test("maintenance-measure-skill-edit-pass.yml: the key leg runs only on a present key, and every stopped key reaches the stop step", () => {
  keyLeg(workflowText(HILL), "maintenance-measure-skill-edit-pass.yml");
});

test("maintenance-measure-skill-edit-pass.yml: the credential input runs exactly one leg, the subscription leg with no credit gate", () => {
  const wf = workflowText(HILL);
  for (const credential of ["api-key", "subscription"])
    for (const disabled of ["false", "true"]) {
      const ctx = { "inputs.credential": credential, "vars.CLAUDE_EVALS_DISABLED": disabled };
      const gate = runs(wf.jobIf("check-key-credit"), ctx);
      const key = gate && runs(wf.jobIf("run-eval"), { ...ctx, "needs.check-key-credit.result": "success" });
      const subscription = runs(wf.jobIf("run-eval-subscription"), ctx);
      const on = disabled === "false";
      assert.deepEqual([gate, key, subscription], [on && credential === "api-key", on && credential === "api-key", on && credential === "subscription"], `${credential} disabled=${disabled}`);
    }
});

test("maintenance-measure-skill-edit-pass.yml: the subscription leg runs only on a present token, and every token stop ends the pass with no fallback", () => {
  const wf = workflowText(HILL);
  const call = wf.step("run-eval-subscription", "credential");
  const stop = wf.step("run-eval-subscription", "stop");
  const judge = wf.step("run-eval-subscription", "judge");
  assert.equal(call.inputs.leg, "subscription");
  assert.equal(call.inputs["fallback-set"], undefined, "no fallback token is read");
  assert.equal(judge.env.LEG, "subscription");
  const fallbackReady = value(judge.env.FALLBACK_READY, {});
  assert.equal(fallbackReady, "true", "the token's stops are judged as stops, so they end the pass");
  const outcomes = [{ handoff: "", reason: "" }, ...launcherOutcomes(S.handoffReason, "subscription", fallbackReady === "true")];
  for (const reason of ["limit-stop", "credit-stop", "auth"]) assert.ok(outcomes.some((o) => o.reason === reason), `a ${reason} is among the outcomes`);
  assert.deepEqual(wf.ids, ["check-key-credit", "run-eval", "run-eval-subscription"], "no fallback job follows the token");
  assert.doesNotMatch(HILL, /FALLBACK_CLAUDE_CODE_OAUTH_TOKEN|id: next\n/, "no fallback token, no next-leg call");
  let states = 0;
  for (const tokenSet of [true, false]) {
    const { outputs } = S.leg({ leg: "subscription", role: "maintenance", credentialSet: value(call.inputs["credential-set"], { "secrets.MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN": tokenSet ? "token" : "" }) });
    assert.equal(outputs.present, String(tokenSet));
    assert.equal(outputs["secret-name"], "MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN");
    states += checkStop(stop, tokenSet, outcomes, `token set=${tokenSet}`);
  }
  assert.ok(states > 4, `${states} states`);
  assert.match(stop.text, /::error::The subscription token stopped [^\n]*no fallback leg runs[^\n]*\n {10}exit 1\n/);
});

test("pr-run-plugin-evals.yml: a suite dispatch runs exactly one leg, the subscription leg only on its own input, and the label run never", () => {
  const wf = workflowText(BROWSER);
  const label = { "github.event.workflow_run.event": "pull_request", "github.event.workflow_run.conclusion": "success", "github.event.workflow_run.head_repository.full_name": "o/r", "github.repository": "o/r" };
  let states = 0;
  for (const event of ["workflow_dispatch", "workflow_run"])
    for (const mode of ["suite", "compare"])
      for (const credential of ["api-key", "subscription"])
        for (const ref of ["refs/heads/main", "refs/heads/feat/x"])
          for (const disabled of ["false", "true"]) {
            const dispatch = event === "workflow_dispatch";
            const ctx = {
              "vars.CLAUDE_EVALS_DISABLED": disabled,
              "github.event_name": event,
              "github.ref": ref,
              "github.event.repository.default_branch": "main",
              ...(dispatch ? { "inputs.mode": mode, "inputs.credential": credential } : label),
            };
            const gate = runs(wf.jobIf("check-key-credit"), ctx);
            const key = gate && runs(wf.jobIf("run-eval"), { ...ctx, "needs.check-key-credit.result": "success" });
            const subscription = runs(wf.jobIf("run-eval-subscription"), ctx);
            const on = disabled === "false";
            const suite = dispatch && mode === "suite";
            const where = `${event} ${mode} ${credential} ${ref} disabled=${disabled}`;
            assert.equal(key, on && ((suite && credential === "api-key" && ref === "refs/heads/main") || !dispatch), `${where}: the key leg as before`);
            assert.equal(gate, key, where);
            assert.equal(subscription, on && suite && credential === "subscription", `${where}: the token leg starts on any ref, so its first step refuses there`);
            states++;
          }
  assert.equal(states, 32);
});

test("pr-run-plugin-evals.yml: the subscription leg refuses an off-default ref or a run with no case filter before any step that reads the token", () => {
  const wf = workflowText(BROWSER);
  const steps = wf.steps("run-eval-subscription");
  const refuse = wf.stepNamed("run-eval-subscription", "Refuse a run off the default branch or without a case filter");
  assert.equal(steps[0].name, refuse.name, "the refusal is the first step");
  assert.equal(refuse.if, "", "the refusal has no condition to skip it");
  assert.doesNotMatch(refuse.text, /secrets\./);
  const reads = steps.findIndex((s) => /secrets\.MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN/.test(s.text));
  assert.ok(reads > 0, "a later step reads the token");
  assert.deepEqual(refuse.env, {
    REF: "${{ github.ref }}",
    DEFAULT_BRANCH: "${{ github.event.repository.default_branch }}",
    CASE: "${{ inputs.case }}",
    CASES: "${{ inputs.cases }}",
    TAGS: "${{ inputs.tag }}",
  });
  const script = /\n {8}run: \|\n((?: {10}.*\n?)+)/.exec(refuse.text)[1].replace(/^ {10}/gm, "");
  const verdict = (env) => {
    const r = spawnSync("bash", ["-c", script], { env: { PATH: process.env.PATH, REF: "refs/heads/main", DEFAULT_BRANCH: "main", CASE: "", CASES: "", TAGS: "", ...env }, encoding: "utf8" });
    return { ok: r.status === 0, out: r.stdout };
  };
  for (const ok of [{ CASE: "p1-*" }, { CASES: "c1 c2" }, { TAGS: "interview" }]) assert.ok(verdict(ok).ok, JSON.stringify(ok));
  const refused = [{}, { CASE: "*" }, { CASE: " ** " }, { CASE: "?" }, { CASES: "  " }, { TAGS: " " }, { REF: "refs/heads/feat/x", CASES: "c1" }, { REF: "refs/tags/v1", TAGS: "t" }];
  for (const env of refused) {
    const { ok, out } = verdict(env);
    assert.ok(!ok, JSON.stringify(env));
    assert.match(out, /^::error::/, JSON.stringify(env));
  }
});

test("pr-run-plugin-evals.yml: the subscription leg keeps the cost ceiling, --no-publish, the kill switch and no fallback, and its stop ends the run", () => {
  const wf = workflowText(BROWSER);
  const job = wf.job("run-eval-subscription");
  const run = wf.step("run-eval-subscription", "eval");
  assert.equal(run.env.CLAUDE_CODE_OAUTH_TOKEN, "${{ secrets.MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN }}");
  assert.equal(run.env.MAX_COST, "${{ inputs.max-cost-usd || 5 }}");
  assert.match(run.text, /--no-publish\n/);
  assert.match(run.text, /--max-cost-usd "\$MAX_COST"\n/);
  assert.match(run.text, /if ! \[\[ \$MAX_COST =~ \^\[1-9\]\[0-9\]\*\$ \]\] \|\| \(\(MAX_COST > 12\)\); then\n/);
  assert.match(wf.stepNamed("run-eval-subscription", "Check the kill switch").text, /uses: \.\/\.base\/\.github\/actions\/check-kill-switch /);
  assert.ok(wf.jobIf("run-eval-subscription").startsWith("vars.CLAUDE_EVALS_DISABLED == 'false' && "));
  assert.doesNotMatch(job, /MAINTENANCE_CLAUDE_API_KEY|FALLBACK_CLAUDE_CODE_OAUTH_TOKEN|needs:|id: next\n/, "the token alone, after no other leg, with none after it");
  assert.doesNotMatch(BROWSER, /FALLBACK_CLAUDE_CODE_OAUTH_TOKEN|run-eval-fallback/);
  const call = wf.step("run-eval-subscription", "credential");
  assert.deepEqual(call.inputs, { leg: "subscription", role: "maintenance", "credential-set": "${{ secrets.MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN != '' }}" });
  const judge = wf.step("run-eval-subscription", "judge");
  assert.equal(judge.env.LEG, "subscription");
  assert.equal(value(judge.env.FALLBACK_READY, {}), "true", "the token's stops are judged as stops, so they end the run");
  const stop = wf.step("run-eval-subscription", "stop");
  const outcomes = [{ handoff: "", reason: "" }, ...launcherOutcomes(S.handoffReason, "subscription", true)];
  assert.ok(outcomes.some((o) => o.reason === "limit-stop"), "a limit stop is among the outcomes");
  let states = 0;
  for (const tokenSet of [true, false]) {
    const { outputs } = S.leg({ leg: "subscription", role: "maintenance", credentialSet: value(call.inputs["credential-set"], { "secrets.MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN": tokenSet ? "token" : "" }) });
    assert.equal(outputs.present, String(tokenSet));
    states += checkStop(stop, tokenSet, outcomes, `token set=${tokenSet}`);
  }
  assert.ok(states > 4, `${states} states`);
  assert.match(stop.text, /::error::The subscription token stopped [^\n]*no fallback leg runs[^\n]*\n {10}exit 1\n/);
});

