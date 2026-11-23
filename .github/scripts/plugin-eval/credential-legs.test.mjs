// maintenance-measure-skill-edit-pass.yml and pr-run-plugin-evals.yml run the
// eval on the maintenance API key alone (docs/review/evals.md, owner decision
// Q14). The key leg's credential comes from ci-workflows'
// select-model-credential, fetched at the pin the workflows name, and its
// handoff from eval-handoff.mjs (the handoffReason run-claude-cli's contract
// exports: https://github.com/melodic-software/ci-workflows/blob/main/.github/actions/run-claude-cli/contract.cjs).
// This truth table drives every state of the key (set or empty, switched off,
// skipped by the credit gate) and every launcher outcome through each
// workflow's own credential inputs and stop condition: the model runs only on
// a present key, and the stop step fires exactly when the key did not run or
// handed off, so no stopped key ends a run silently.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const read = (name) => readFileSync(new URL(`../../workflows/${name}`, import.meta.url), "utf8");
const HILL = read("maintenance-measure-skill-edit-pass.yml");
const BROWSER = read("pr-run-plugin-evals.yml");
const S = await loadSelect(selectPin(HILL, BROWSER));

for (const [file, text] of [
  ["maintenance-measure-skill-edit-pass.yml", HILL],
  ["pr-run-plugin-evals.yml", BROWSER],
]) {
  test(`${file}: the key leg runs only on a present key, and every stopped key reaches the stop step`, () => {
    const wf = workflowText(text);
    const call = wf.step("run-eval", "credential");
    const stop = wf.step("run-eval", "stop");
    const outcomes = [{ handoff: "", reason: "" }, ...launcherOutcomes(S.handoffReason, "api-key", false)];
    assert.ok(outcomes.some((o) => o.reason === "credit-stop"), "a credit stop is among the outcomes");
    let states = 0;
    for (const keySet of [true, false])
      for (const keyOff of [true, false])
        for (const gate of [{ skipKey: false }, { skipKey: true }]) {
          const start = S.start(gate);
          const ctx = {
            "secrets.MAINTENANCE_CLAUDE_API_KEY": keySet ? "set" : "",
            "vars.CLAUDE_API_KEYS_DISABLED": String(keyOff),
            "needs.check-key-credit.outputs.next-leg": start["next-leg"],
          };
          const input = (name) => value(call.inputs[name], { ...ctx, "secrets.MAINTENANCE_CLAUDE_API_KEY != ''": String(keySet) });
          const { outputs } = S.leg({ leg: "key", role: "maintenance", credentialSet: String(keySet), keyOff: String(keyOff), selected: input("selected") });
          const present = outputs.present === "true";
          assert.equal(present, keySet && !keyOff && !gate.skipKey, `${file} key set=${keySet} off=${keyOff} skip=${gate.skipKey}`);
          for (const o of present ? outcomes : [{ handoff: "", reason: "" }]) {
            states++;
            const stepCtx = { "steps.credential.outcome": "success", "steps.credential.outputs.present": outputs.present, "steps.judge.outputs.handoff": o.handoff };
            assert.equal(runs(stop.if, stepCtx), !present || o.handoff === "true", `${file} present=${present} outcome=${o.reason || "finished"}`);
          }
        }
    assert.ok(states > 8, `${states} states`);
    assert.equal(runs(stop.if, { "steps.credential.outcome": "skipped" }), false, `${file}: a step that failed before the credential check is not blamed on the key`);
  });
}
