#!/usr/bin/env bash
# Structure test: pr-run-activity-read.yml admits a github-actions[bot]
# workflow_dispatch only through a pr-unblock-dispatch.yml run, or a
# pr-feedback-dispatch.yml run whose recorded review run reviewed the PR's
# current head, that sent it to pr-unblock.yml, or to pr-refine.yml for the
# pr-refine lane, as
# docs/conventions/pr-pipeline/pr-run-activity.md (run job step 3) states. The gate's own checks are check-trusted-trigger's suite; this
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
say(gate["dispatched-workflow"] === "${{ inputs.lane == 'pr-refine' && '.github/workflows/pr-refine.yml' || '.github/workflows/pr-unblock.yml' }}",
  "the gate admits a dispatcher-sent run only when it is pr-refine.yml for the pr-refine lane, else pr-unblock.yml");
// pr-feedback-dispatch.yml, started by workflow_run after a review lane,
// vouches for address-feedback's model calls only: the gate gets it only with
// the select job's feedback context, which only a review-threads call passes.
say(gate["run-dispatcher-workflow"] === "${{ inputs.feedback-context-sha256 != '' && '.github/workflows/pr-feedback-dispatch.yml' || '' }}",
  "the gate trusts a pr-feedback-dispatch.yml dispatcher run only for a review-threads call");
say(gate["run-dispatcher-upstreams"] === "${{ inputs.feedback-context-sha256 != '' && '.github/workflows/pr-review-hosted.yml .github/workflows/pr-review-security-hosted.yml' || '' }}",
  "the review run must be one of the two review lanes, for a review-threads call only");
say(!("expected-upstream-head" in gate), "the gate passes no expected-upstream-head");

// Every model call runs on run-claude-cli, which keeps no actor allow list of
// its own: the trigger gate above is the one place a dispatcher run is admitted.
const actionSteps = Object.values(wf.jobs).flatMap((job) => job.steps ?? []).filter((s) => String(s.uses ?? "").startsWith("anthropics/claude-code-action@"));
say(actionSteps.length === 0, `no step runs claude-code-action and its allowed_bots (found ${actionSteps.map((s) => s.id).join(", ")})`);

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
