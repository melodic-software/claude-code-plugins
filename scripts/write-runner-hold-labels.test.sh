#!/usr/bin/env bash
# Behavior test: the "Read the hold labels from the base" step in
# pr-run-activity-write.yml, which gives apply-patch its hold labels: do-not-merge,
# the human-gated role label unless the caller's base-code verdict lifts it,
# and the activity's labels-absent list. Runs the step's bash with a stub
# gate-recheck.mjs.
# test-scope: .github/workflows/pr-run-activity-write.yml .github/standards/runner-policy/package.json
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
const wf = YAML.parse(readFileSync(".github/workflows/pr-run-activity-write.yml", "utf8"));
// The hold-label step: its bash run with a resolved config naming the
// activity's labels-absent, from a directory with no .base tracker file, so
// the human-gated label is the needs-human default.
const { execFileSync } = await import("node:child_process");
const { existsSync, mkdirSync, mkdtempSync, writeFileSync, rmSync } = await import("node:fs");
const { tmpdir } = await import("node:os");
const { join } = await import("node:path");
const holdStep = wf.jobs.run.steps.find((s) => s.id === "hold-label");
// gate: the caller's patch-human-gate. On lane-escalation the step runs the
// base's gate-recheck.mjs; a stub in its place answers `recheck` and records
// the environment it was given.
const holdLabelsFor = (gate, labelsAbsent, recheck = "true") => {
  const dir = mkdtempSync(join(tmpdir(), "hold-label-"));
  try {
    const resolved = join(dir, "resolved.json");
    const out = join(dir, "out");
    const seen = join(dir, "seen.json");
    writeFileSync(resolved, JSON.stringify({ selected: { "applies-when": { "labels-absent": labelsAbsent } } }));
    writeFileSync(out, "");
    const stub = join(dir, ".base/.github/scripts/pr-unblock");
    mkdirSync(stub, { recursive: true });
    writeFileSync(join(stub, "gate-recheck.mjs"), `import { appendFileSync, writeFileSync } from "node:fs";
writeFileSync(${JSON.stringify(seen)}, JSON.stringify({ label: process.env.LABEL, pr: process.env.PR_NUMBER, head: process.env.HEAD_SHA, activity: process.env.ACTIVITY, out: process.env.GITHUB_OUTPUT === ${JSON.stringify(out)} }));
${recheck === "fail" ? "process.exit(1);" : `appendFileSync(process.env.GITHUB_OUTPUT, "lane-escalation=${recheck}\\n");`}
`);
    try {
      execFileSync("bash", ["-e", "-c", holdStep.run], { cwd: dir, stdio: "pipe", env: { PATH: process.env.PATH, TMPDIR: dir, RESOLVED: resolved, HUMAN_GATE: gate, ACTIVITY: "fix-ci", PR_NUMBER: "7", HEAD_SHA: "a".repeat(40), GITHUB_OUTPUT: out } });
    } catch {
      return { failed: true, seen: existsSync(seen) ? JSON.parse(readFileSync(seen, "utf8")) : null };
    }
    return { holds: JSON.parse(readFileSync(out, "utf8").replace(/^labels=/, "")), seen: existsSync(seen) ? JSON.parse(readFileSync(seen, "utf8")) : null };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
};
say(String(holdStep?.env?.ACTIVITY) === "${{ inputs.patch-activity }}", "the hold-label step hands gate-recheck.mjs the caller's patch-activity");
say(String(holdStep?.env?.HUMAN_GATE) === "${{ steps.config.outputs.prepare == 'apply-patch' && inputs.patch-human-gate || '' }}",
  "the hold-label step reads the caller's base-code verdict (patch-human-gate) only for an apply-patch run");
let r_ = holdLabelsFor("fix-request", ["do-not-merge"]);
say(JSON.stringify(r_.holds) === '["do-not-merge"]' && r_.seen === null,
  `a write-access fix request on a needs-human PR lifts only the human-gated hold, with no re-read (${JSON.stringify(r_)})`);
r_ = holdLabelsFor("fix-request", ["needs-human"]);
say(r_.holds.includes("do-not-merge") && r_.holds.includes("needs-human"),
  "do-not-merge stays a hold beside a fix request, and a listed labels-absent label still holds");
r_ = holdLabelsFor("lane-escalation", ["do-not-merge"], "true");
say(JSON.stringify(r_.holds) === '["do-not-merge"]' && r_.seen?.label === "needs-human" && r_.seen.pr === "7" && r_.seen.head === "a".repeat(40) && r_.seen.activity === "fix-ci" && r_.seen.out === false,
  `a lane escalation the re-read still finds lifts only the human-gated hold (${JSON.stringify(r_)})`);
r_ = holdLabelsFor("lane-escalation", ["do-not-merge"], "false");
say(r_.holds?.includes("needs-human") && r_.holds.includes("do-not-merge") && r_.seen !== null,
  `a lane escalation the re-read no longer finds keeps the human-gated hold (${JSON.stringify(r_)})`);
r_ = holdLabelsFor("lane-escalation", ["do-not-merge"], "fail");
say(r_.failed === true, `a re-read that fails fails the step (${JSON.stringify(r_)})`);
for (const gate of ["false", "", "true", "FIX-REQUEST", "lane-escalation-x"]) {
  r_ = holdLabelsFor(gate, ["do-not-merge"]);
  say(r_.holds?.includes("needs-human") && r_.holds.includes("do-not-merge") && r_.seen === null,
    `with patch-human-gate ${JSON.stringify(gate)} the human-gated label stays a hold (${JSON.stringify(r_)})`);
}
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
