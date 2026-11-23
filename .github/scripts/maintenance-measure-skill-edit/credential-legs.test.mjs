import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { launcherOutcomes, loadSelect, runs, selectPin, value } from "../lib/model-credential.mjs";
import { workflowText } from "../lib/workflow-text.mjs";

const TEXT = readFileSync(new URL("../../workflows/maintenance-measure-skill-edit.yml", import.meta.url), "utf8");
const wf = workflowText(TEXT);
const S = await loadSelect(selectPin(TEXT));
const JOB = "generate-edit";

test("generate-edit runs on the API key alone, and a stopped key fails the job", () => {
  const call = wf.step(JOB, "key");
  const run = wf.step(JOB, "run-key");
  const stop = wf.step(JOB, "stop");
  const collect = wf.step(JOB, "collect");
  assert.doesNotMatch(wf.job(JOB), /CLAUDE_CODE_OAUTH_TOKEN|subscription-token|fallback-token/, "no subscription credential in the job");
  const outcomes = [{ handoff: "", reason: "" }, ...launcherOutcomes(S.handoffReason, "api-key", false)];
  let states = 0;
  for (const keySet of [true, false])
    for (const keyOff of [true, false])
      for (const skipKey of [false, true])
        for (const prompt of ["success", "failure"]) {
          const start = S.start({ skipKey });
          const ctx = { "needs.check-key-credit.outputs.next-leg": start["next-leg"], "steps.prompt.outcome": prompt };
          const { outputs } = S.leg({ leg: "key", role: "maintenance", credentialSet: String(keySet), keyOff: String(keyOff), selected: value(call.inputs.selected, ctx) });
          const present = outputs.present === "true";
          assert.equal(present, keySet && !keyOff && !skipKey);
          const stepCtx = { ...ctx, "steps.key.outputs.present": outputs.present };
          const modelRuns = runs(run.if, stepCtx);
          assert.equal(modelRuns, present && prompt === "success", `key=${keySet} off=${keyOff} skip=${skipKey} prompt=${prompt}`);
          for (const o of modelRuns ? outcomes : [{ handoff: "", reason: "" }]) {
            states++;
            const finished = modelRuns && o.handoff !== "true";
            const after = {
              ...stepCtx,
              "steps.run-key.outcome": modelRuns ? (finished ? "success" : "failure") : "skipped",
              "steps.run-key.outputs.handoff": o.handoff,
              "steps.run-key.outputs.structured-output-file": finished ? "out.json" : "",
            };
            assert.equal(runs(stop.if, after), prompt === "success" && (!present || o.handoff === "true"), `stop: ${JSON.stringify(after)}`);
            assert.equal(runs(collect.if, after), finished, `collect: ${JSON.stringify(after)}`);
          }
        }
  assert.ok(states > 16, `${states} states`);
});
