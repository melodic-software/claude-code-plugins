// maintenance-measure-skill-edit-pass.yml and pr-run-plugin-evals.yml run the
// eval on the evals role's API key first and move to its subscription token,
// with no fallback, when the key stops: a dispatched suite run always, a pass
// only when its caller sets allow-subscription (docs/review/evals.md).
// Each leg's credential and the next leg come from ci-workflows'
// select-model-credential, fetched at the pin the workflows name, and its
// handoff from eval-handoff.mjs (the handoffReason run-claude-cli's contract
// exports:
// https://github.com/melodic-software/ci-workflows/blob/main/.github/actions/run-claude-cli/contract.cjs).
// This truth table drives every state of each credential (set or empty, the
// key switched off or skipped by the credit gate) and every launcher outcome
// through each workflow's own job conditions, credential inputs, next-leg call
// and stop step: the model runs only on a present credential, the subscription
// leg runs exactly when the key stopped and the run may move, and every stop
// that ends a run names the EVALS role.
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
const ROLE_ERROR = /^::error::EVALS credentials not assigned or used up: /m;

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

function stopScript(stop) {
  const script = /\n {8}run: \|\n((?: {10}.*\n?)+)/.exec(stop.text)[1].replace(/^ {10}/gm, "");
  return (env) => {
    const r = spawnSync("bash", ["-c", script], { env: { PATH: process.env.PATH, REASON: "credit-stop", ...env }, encoding: "utf8" });
    return { ok: r.status === 0, out: r.stdout };
  };
}

function keyStates(wf) {
  const call = wf.step("run-eval", "credential");
  const next = wf.step("run-eval", "next");
  assert.equal(next.if, "${{ always() }}", "the next leg is named even after a timed-out leg");
  const outcomes = [{ handoff: "", reason: "" }, ...launcherOutcomes(S.handoffReason, "api-key", false)];
  assert.ok(outcomes.some((o) => o.reason === "credit-stop"), "a credit stop is among the outcomes");
  const states = [];
  for (const keySet of [true, false])
    for (const keyOff of [true, false])
      for (const gate of [{ skipKey: false }, { skipKey: true }]) {
        const ctx = { "needs.check-key-credit.outputs.next-leg": S.start(gate)["next-leg"], "secrets.EVALS_CLAUDE_API_KEY != ''": String(keySet) };
        const { outputs } = S.leg({ leg: "key", role: "evals", credentialSet: String(keySet), keyOff: String(keyOff), selected: value(call.inputs.selected, ctx) });
        const present = outputs.present === "true";
        assert.equal(present, keySet && !keyOff && !gate.skipKey, `key set=${keySet} off=${keyOff} skip=${gate.skipKey}`);
        for (const o of present ? outcomes : [{ handoff: "", reason: "" }]) {
          const stepCtx = { "steps.credential.outputs.state": outputs.state, "steps.judge.outputs.handoff": o.handoff, "steps.judge.outputs.handoff-reason": o.reason };
          const { "next-leg": nextLeg } = S.next({ state: value(next.inputs.state, stepCtx), handoff: value(next.inputs.handoff, stepCtx), handoffReason: value(next.inputs["handoff-reason"], stepCtx) });
          const stopped = !present || o.handoff === "true";
          assert.equal(nextLeg === "subscription", !present || S.HANDOFF_REASONS.key.includes(o.reason), `next leg: present=${present} outcome=${o.reason}`);
          states.push({ present, outcome: o, stopped, nextLeg, label: `set=${keySet} off=${keyOff} skip=${gate.skipKey} outcome=${o.reason || "finished"}` });
        }
      }
  return states;
}

function keyLeg(wf, label) {
  const stop = wf.step("run-eval", "stop");
  const outcomes = [{ handoff: "", reason: "" }, ...launcherOutcomes(S.handoffReason, "api-key", false)];
  let states = 0;
  for (const present of [true, false]) states += checkStop(stop, present, outcomes, label);
  assert.ok(states > 4, `${states} states`);
  assert.equal(wf.outputs("run-eval")["next-leg"], "${{ steps.next.outputs.next-leg }}");
  assert.equal(wf.outputs("run-eval")["next-reason"], "${{ steps.next.outputs.next-reason }}");
}

test("pr-run-plugin-evals.yml: the key leg runs only on a present key, and every stopped key reaches the stop step", () => {
  keyLeg(workflowText(BROWSER), "pr-run-plugin-evals.yml");
});

test("maintenance-measure-skill-edit-pass.yml: the key leg runs only on a present key, and every stopped key reaches the stop step", () => {
  keyLeg(workflowText(HILL), "maintenance-measure-skill-edit-pass.yml");
});

test("maintenance-measure-skill-edit-pass.yml: the subscription leg runs exactly when the key named it and the caller allows it", () => {
  const wf = workflowText(HILL);
  const stop = stopScript(wf.step("run-eval", "stop"));
  const nextEnv = wf.step("run-eval", "stop").env.NEXT;
  let count = 0;
  for (const allow of [true, false])
    for (const disabled of ["false", "true"])
      for (const state of keyStates(wf)) {
        const ctx = { "inputs.allow-subscription": allow, "vars.CLAUDE_EVALS_DISABLED": disabled };
        const gate = runs(wf.jobIf("check-key-credit"), ctx);
        const key = gate && runs(wf.jobIf("run-eval"), { ...ctx, "needs.check-key-credit.result": "success" });
        const on = disabled === "false";
        assert.equal(gate, on, `gate disabled=${disabled}`);
        assert.equal(key, on, `key disabled=${disabled}`);
        let keyResult = "success";
        if (state.stopped) {
          const { ok, out } = stop({ NEXT: value(nextEnv, { ...ctx, "steps.next.outputs.next-leg": state.nextLeg }) });
          const moves = allow && state.nextLeg === "subscription";
          assert.equal(ok, moves, `stop allow=${allow} ${state.label}`);
          if (!moves) assert.match(out, ROLE_ERROR, `the stop names the role: ${state.label}`);
          keyResult = ok ? "success" : "failure";
        }
        const subscription = runs(wf.jobIf("run-eval-subscription"), {
          ...ctx,
          "needs.run-eval.result": key ? keyResult : "skipped",
          "needs.run-eval.outputs.next-leg": key ? state.nextLeg : "",
        });
        assert.equal(subscription, on && allow && state.stopped && state.nextLeg === "subscription", `subscription allow=${allow} disabled=${disabled} ${state.label}`);
        count++;
      }
  assert.ok(count > 32, `${count} states`);
});

test("maintenance-measure-skill-edit-pass.yml: the subscription leg runs only on a present token, and every token stop ends the pass with no fallback", () => {
  const wf = workflowText(HILL);
  const call = wf.step("run-eval-subscription", "credential");
  const stop = wf.step("run-eval-subscription", "stop");
  const judge = wf.step("run-eval-subscription", "judge");
  assert.equal(call.inputs.leg, "subscription");
  assert.equal(call.inputs.role, "evals");
  assert.equal(call.inputs.reason, "${{ needs.run-eval.outputs.next-reason }}");
  assert.equal(call.inputs["fallback-set"], undefined, "no fallback token is read");
  assert.equal(judge.env.LEG, "subscription");
  const fallbackReady = value(judge.env.FALLBACK_READY, {});
  assert.equal(fallbackReady, "true", "the token's stops are judged as stops, so they end the pass");
  const outcomes = [{ handoff: "", reason: "" }, ...launcherOutcomes(S.handoffReason, "subscription", fallbackReady === "true")];
  for (const reason of ["limit-stop", "credit-stop", "auth"]) assert.ok(outcomes.some((o) => o.reason === reason), `a ${reason} is among the outcomes`);
  assert.deepEqual(wf.ids, ["check-key-credit", "run-eval", "run-eval-subscription"], "no fallback job follows the token");
  assert.doesNotMatch(HILL, /FALLBACK_CLAUDE_CODE_OAUTH_TOKEN/, "no fallback token");
  assert.doesNotMatch(wf.job("run-eval-subscription"), /id: next\n/, "nothing follows the token");
  let states = 0;
  for (const tokenSet of [true, false]) {
    const { outputs } = S.leg({ leg: "subscription", role: "evals", credentialSet: value(call.inputs["credential-set"], { "secrets.EVALS_CLAUDE_CODE_OAUTH_TOKEN": tokenSet ? "token" : "" }) });
    assert.equal(outputs.present, String(tokenSet));
    assert.equal(outputs["secret-name"], "EVALS_CLAUDE_CODE_OAUTH_TOKEN");
    states += checkStop(stop, tokenSet, outcomes, `token set=${tokenSet}`);
  }
  assert.ok(states > 4, `${states} states`);
  const { ok, out } = stopScript(stop)({ KEY_REASON: "credit-stop", REASON: "limit-stop" });
  assert.equal(ok, false);
  assert.match(out, ROLE_ERROR);
  assert.match(out, /no fallback leg runs/);
});

test("pr-run-plugin-evals.yml: a suite dispatch runs the key first and the subscription leg only after the key named it; the label run never", () => {
  const wf = workflowText(BROWSER);
  const stop = stopScript(wf.step("run-eval", "stop"));
  const label = { "github.event.workflow_run.event": "pull_request", "github.event.workflow_run.conclusion": "success", "github.event.workflow_run.head_repository.full_name": "o/r", "github.repository": "o/r" };
  const keyStatesList = keyStates(wf);
  let count = 0;
  for (const event of ["workflow_dispatch", "workflow_run"])
    for (const mode of ["suite", "compare"])
      for (const ref of ["refs/heads/main", "refs/heads/feat/x"])
        for (const disabled of ["false", "true"])
          for (const filter of [{}, { CASE: "a-case" }, { CASES: "a b" }, { TAGS: "t" }, { CASE: "*" }])
          for (const state of keyStatesList) {
            const dispatch = event === "workflow_dispatch";
            const filtered = Boolean(filter.CASES || filter.TAGS || (filter.CASE && filter.CASE !== "*"));
            const ctx = {
              "vars.CLAUDE_EVALS_DISABLED": disabled,
              "github.event_name": event,
              "github.ref": ref,
              "github.event.repository.default_branch": "main",
              ...(dispatch ? { "inputs.mode": mode } : label),
            };
            const gate = runs(wf.jobIf("check-key-credit"), ctx);
            const key = gate && runs(wf.jobIf("run-eval"), { ...ctx, "needs.check-key-credit.result": "success" });
            const on = disabled === "false";
            const suite = dispatch && mode === "suite";
            const where = `${event} ${mode} ${ref} disabled=${disabled} filter=${JSON.stringify(filter)} ${state.label}`;
            assert.equal(key, on && ((suite && ref === "refs/heads/main") || !dispatch), `${where}: the key leg as before`);
            assert.equal(gate, key, where);
            let keyResult = "success";
            if (key && state.stopped) {
              const { ok, out } = stop({ EVENT: event, NEXT: state.nextLeg, ...filter });
              const moves = dispatch && state.nextLeg === "subscription" && filtered;
              assert.equal(ok, !dispatch || moves, `stop: ${where}`);
              if (dispatch && !moves) assert.match(out, ROLE_ERROR, `the stop names the role: ${where}`);
              if (!dispatch) assert.match(out, /^::warning::EVALS_CLAUDE_API_KEY stopped [^\n]*never moves to the subscription token/m, where);
              keyResult = ok ? "success" : "failure";
            }
            const subscription = runs(wf.jobIf("run-eval-subscription"), {
              ...ctx,
              "needs.run-eval.result": key ? keyResult : "skipped",
              "needs.run-eval.outputs.next-leg": key ? state.nextLeg : "",
            });
            assert.equal(subscription, key && suite && state.stopped && state.nextLeg === "subscription" && filtered, `${where}: the token leg follows only a stopped key on a suite dispatch that names its cases`);
            count++;
          }
  assert.ok(count > 128, `${count} states`);
});

test("pr-run-plugin-evals.yml: the subscription leg refuses an off-default ref or a run with no case filter before any step that reads the token", () => {
  const wf = workflowText(BROWSER);
  const steps = wf.steps("run-eval-subscription");
  const refuse = wf.stepNamed("run-eval-subscription", "Refuse a run off the default branch or without a case filter");
  assert.equal(steps[0].name, refuse.name, "the refusal is the first step");
  assert.equal(refuse.if, "", "the refusal has no condition to skip it");
  assert.doesNotMatch(refuse.text, /secrets\./);
  const reads = steps.findIndex((s) => /secrets\.EVALS_CLAUDE_CODE_OAUTH_TOKEN/.test(s.text));
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
  assert.equal(run.env.CLAUDE_CODE_OAUTH_TOKEN, "${{ secrets.EVALS_CLAUDE_CODE_OAUTH_TOKEN }}");
  assert.equal(run.env.MAX_COST, "${{ inputs.max-cost-usd || 5 }}");
  assert.match(run.text, /--no-publish\n/);
  assert.match(run.text, /--max-cost-usd "\$MAX_COST"\n/);
  assert.match(run.text, /if ! \[\[ \$MAX_COST =~ \^\[1-9\]\[0-9\]\*\$ \]\] \|\| \(\(MAX_COST > 12\)\); then\n/);
  assert.match(wf.stepNamed("run-eval-subscription", "Check the kill switch").text, /uses: \.\/\.base\/\.github\/actions\/check-kill-switch /);
  assert.ok(wf.jobIf("run-eval-subscription").startsWith("${{ !cancelled() && vars.CLAUDE_EVALS_DISABLED == 'false' && "));
  assert.match(job, /\n {4}needs: run-eval\n/, "the token follows the key leg");
  assert.doesNotMatch(job, /secrets\.EVALS_CLAUDE_API_KEY|FALLBACK_CLAUDE_CODE_OAUTH_TOKEN|id: next\n/, "the token alone, with no leg after it");
  assert.doesNotMatch(BROWSER, /FALLBACK_CLAUDE_CODE_OAUTH_TOKEN|run-eval-fallback/);
  const call = wf.step("run-eval-subscription", "credential");
  assert.deepEqual(call.inputs, { leg: "subscription", role: "evals", "credential-set": "${{ secrets.EVALS_CLAUDE_CODE_OAUTH_TOKEN != '' }}", reason: "${{ needs.run-eval.outputs.next-reason }}" });
  const judge = wf.step("run-eval-subscription", "judge");
  assert.equal(judge.env.LEG, "subscription");
  assert.equal(value(judge.env.FALLBACK_READY, {}), "true", "the token's stops are judged as stops, so they end the run");
  const stop = wf.step("run-eval-subscription", "stop");
  const outcomes = [{ handoff: "", reason: "" }, ...launcherOutcomes(S.handoffReason, "subscription", true)];
  assert.ok(outcomes.some((o) => o.reason === "limit-stop"), "a limit stop is among the outcomes");
  let states = 0;
  for (const tokenSet of [true, false]) {
    const { outputs } = S.leg({ leg: "subscription", role: "evals", credentialSet: value(call.inputs["credential-set"], { "secrets.EVALS_CLAUDE_CODE_OAUTH_TOKEN": tokenSet ? "token" : "" }) });
    assert.equal(outputs.present, String(tokenSet));
    states += checkStop(stop, tokenSet, outcomes, `token set=${tokenSet}`);
  }
  assert.ok(states > 4, `${states} states`);
  const { ok, out } = stopScript(stop)({ KEY_REASON: "no-key", REASON: "no-token" });
  assert.equal(ok, false);
  assert.match(out, ROLE_ERROR);
  assert.match(out, /EVALS_CLAUDE_API_KEY stopped \(no-key\) and EVALS_CLAUDE_CODE_OAUTH_TOKEN stopped \(no-token\)/);
});
