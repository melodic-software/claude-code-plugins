#!/usr/bin/env bash
# Behavior test: the "Check the skill's failure is only the turn cap" step in
# pr-run-activity-write.yml counts a failed skill step as a success only when
# the execution file's last result message is subtype success, is_error false,
# with num_turns over --max-turns. Every other failure, and a missing or
# unreadable execution file, fails the step. Runs the step's github-script
# body with a stub `core` against temp execution files.
# test-scope: .github/workflows/pr-run-activity-write.yml .github/standards/runner-policy/package.json
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

results=$(
  cd "$ROOT" && node --input-type=module - <<'EOF'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
const require = createRequire(`${process.cwd()}/.github/standards/runner-policy/package.json`);
const YAML = require("yaml");

const say = (good, text) => console.log(`${good ? "ok" : "fail"}\t${text}`);
const wf = YAML.parse(readFileSync(".github/workflows/pr-run-activity-write.yml", "utf8"));
const steps = wf.jobs.run.steps;
const at = steps.findIndex((s) => s.id === "act-skill");
const step = steps[at + 1];
say(step?.id === "act-result" && Boolean(step?.with?.script), "the turn-cap check is the step right after the skill step");
say(steps[at]?.["continue-on-error"] === true, "the skill step's failure is left to the turn-cap check");
const record = steps.find((s) => s.id === "lane-record");
say(/steps\.act-result\.outputs\.outcome/.test(String(record?.with?.outcome)), "the lane record reads the checked outcome");

const dir = mkdtempSync(join(tmpdir(), "over-cap-"));
const AsyncFunction = (async () => {}).constructor;

// messages: the execution file's JSON, or a raw string, or null for no file.
async function run({ outcome = "failure", messages, maxTurns = "75" } = {}) {
  const file = join(dir, `exec-${Math.random().toString(36).slice(2)}.json`);
  if (messages !== null) {
    writeFileSync(file, typeof messages === "string" ? messages : JSON.stringify(messages));
  }
  const calls = { failed: [], outputs: {} };
  const core = {
    notice: () => {},
    setFailed: (m) => calls.failed.push(m),
    setOutput: (k, v) => {
      calls.outputs[k] = v;
    },
  };
  Object.assign(process.env, { ACT_OUTCOME: outcome, EXECUTION_FILE: file, MAX_TURNS: maxTurns });
  await new AsyncFunction("core", "require", step.with.script)(core, require);
  return calls;
}

const result = (fields) => [{ type: "system" }, { type: "assistant" }, { type: "result", ...fields }];
const succeeded = (r) => r.outputs.outcome === "success" && r.failed.length === 0;
const failed = (r) => r.outputs.outcome === undefined && r.failed.length === 1;

let r = await run({ messages: result({ subtype: "success", is_error: false, num_turns: 140 }) });
say(succeeded(r), "a failed step whose result is a success over the cap counts as a success");

r = await run({ messages: result({ subtype: "error_max_turns", is_error: true, num_turns: 76 }) });
say(failed(r), "an over-cap error result stays a failure");

r = await run({ messages: result({ subtype: "success", is_error: true, num_turns: 140 }) });
say(failed(r), "an over-cap success with is_error true stays a failure");

r = await run({ messages: result({ subtype: "success", is_error: false, num_turns: 140 }), maxTurns: "" });
say(failed(r), "an over-cap success with no cap configured stays a failure");

r = await run({ messages: result({ subtype: "success", is_error: false, num_turns: 75 }) });
say(failed(r), "a failed step whose success result is within the cap stays a failure");

r = await run({ messages: null });
say(failed(r), "a failed step with no execution file stays a failure");

r = await run({ messages: "{not json" });
say(failed(r), "a failed step with an unparsable execution file stays a failure");

r = await run({ messages: [{ type: "assistant" }] });
say(failed(r), "a failed step with no result message stays a failure");

r = await run({
  messages: [...result({ subtype: "success", is_error: false, num_turns: 140 }), { type: "result", subtype: "error_during_execution", is_error: true, num_turns: 141 }],
});
say(failed(r), "only the last result message counts");

r = await run({ outcome: "success", messages: result({ subtype: "success", is_error: false, num_turns: 20 }) });
say(succeeded(r), "a skill step that succeeded within the cap is unchanged");
rmSync(dir, { recursive: true, force: true });
EOF
)
if [[ -z "$results" ]]; then
  fail "the check printed nothing; is .github/standards/runner-policy installed?"
fi
while IFS=$'\t' read -r verdict text; do
  [[ -n "$verdict" ]] || continue
  if [[ "$verdict" == ok ]]; then ok "$text"; else fail "$text"; fi
done <<<"$results"

test_harness::report
