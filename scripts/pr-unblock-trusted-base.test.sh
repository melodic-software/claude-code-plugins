#!/usr/bin/env bash
# Structure test: every pr-unblock.yml job that runs an activity through a
# runner passes trusted-base: default-tip, so a dispatched run resolves config,
# actions and trusted actors from the default branch tip, never from the stale
# base SHA an older PR keeps (docs/adr/0069). The read runner takes the same
# trusted-base input as the write runner and hands it to check-trusted-base.
# The action's own modes are check-trusted-base's suite; this asserts wiring.
# test-scope: .github/workflows/pr-unblock.yml .github/workflows/pr-run-activity-read.yml .github/workflows/pr-run-activity-write.yml .github/standards/runner-policy/package.json
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
const load = (file) => YAML.parse(readFileSync(`.github/workflows/${file}`, "utf8"));

for (const file of ["pr-run-activity-read.yml", "pr-run-activity-write.yml"]) {
  const wf = load(file);
  const input = wf.on?.workflow_call?.inputs?.["trusted-base"] ?? {};
  say(input.type === "string" && input.required === false && input.default === "pr-base",
    `${file}: trusted-base is an optional string input that defaults to pr-base`);
  const step = wf.jobs.run.steps.find((s) => s.id === "trusted-base")?.with ?? {};
  say(step.mode === "${{ inputs.trusted-base }}", `${file}: check-trusted-base receives the trusted-base input as its mode`);
}

const RUNNERS = new Set([
  "./.github/workflows/pr-run-activity-read.yml",
  "./.github/workflows/pr-run-activity-write.yml",
]);
const callers = Object.entries(load("pr-unblock.yml").jobs).filter(([, job]) => RUNNERS.has(job.uses));
say(callers.some(([name]) => name === "fix-ci"), "pr-unblock.yml runs fix-ci through a runner");
for (const [name, job] of callers) {
  say(job.with?.["trusted-base"] === "default-tip", `pr-unblock.yml job ${name} passes trusted-base: default-tip`);
}
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
