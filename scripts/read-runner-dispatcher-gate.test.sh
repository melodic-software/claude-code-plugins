#!/usr/bin/env bash
# Structure test: pr-run-activity-read.yml admits a github-actions[bot]
# workflow_dispatch only through a pr-unblock-dispatch.yml run that sent it to
# pr-unblock.yml, as docs/conventions/pr-pipeline/pr-run-activity.md (run job
# step 3) states. The gate's own checks are check-trusted-trigger's suite; this
# asserts only the read file's wiring of them.
# test-scope: .github/workflows/pr-run-activity-read.yml .github/standards/runner-policy/package.json
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

results=$(
  cd "$ROOT" && node --input-type=module - <<'EOF'
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
const require = createRequire(`${process.cwd()}/.github/standards/runner-policy/package.json`);
const YAML = require("yaml");

const say = (good, text) => console.log(`${good ? "ok" : "fail"}\t${text}`);
const wf = YAML.parse(readFileSync(".github/workflows/pr-run-activity-read.yml", "utf8"));

const input = wf.on?.workflow_call?.inputs?.["dispatcher-run-id"] ?? {};
say(input.type === "string" && input.required === false && input.default === "",
  "dispatcher-run-id is an optional string input that defaults to empty");

const steps = wf.jobs.run.steps;
const gate = steps.find((s) => s.id === "gate")?.with ?? {};
say(gate["dispatcher-run-id"] === "${{ inputs.dispatcher-run-id }}", "the trigger gate receives the dispatcher-run-id input");
say(gate["dispatcher-workflow"] === ".github/workflows/pr-unblock-dispatch.yml",
  "the gate trusts only a pr-unblock-dispatch.yml dispatcher run");
say(gate["dispatched-workflow"] === ".github/workflows/pr-unblock.yml",
  "the gate admits a dispatcher-sent run only when it is pr-unblock.yml");
// No workflow_run dispatcher vouches for a read run: only the push-to-main
// dispatcher sends one.
for (const key of ["run-dispatcher-workflow", "run-dispatcher-upstreams", "expected-upstream-head"]) {
  say(!(key in gate), `the gate passes no ${key}`);
}

// cant-fail-ok: the allowed_bots value is the contract the gate decides.
const skill = steps.find((s) => s.id === "act-skill")?.with ?? {};
say(skill.allowed_bots === "${{ inputs.dispatcher-run-id != '' && 'melodic-automation-lanes[bot],github-actions' || 'melodic-automation-lanes[bot]' }}",
  `the skill admits github-actions only with a dispatcher-run-id (got ${JSON.stringify(skill.allowed_bots)})`);

// request-lane-token's check mode refuses a dispatcher run id.
const broker = wf.jobs["broker-check"].steps.find((s) => s.id === "broker")?.with ?? {};
say(!("dispatcher-run-id" in broker), "the broker check sends no dispatcher run id");
EOF
)
if [[ -z "$results" ]]; then
  fail "the structure check printed nothing; is .github/standards/runner-policy installed?"
fi
while IFS=$'\t' read -r verdict text; do
  [[ -n $verdict ]] || continue
  if [[ $verdict == ok ]]; then ok "$text"; else fail "$text"; fi
done <<<"$results"

test_harness::report
