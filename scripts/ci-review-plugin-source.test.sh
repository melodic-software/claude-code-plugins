#!/usr/bin/env bash
# Structure test: each review caller runs melodic-software/ci-workflows'
# pr-review-cli.yml at main and passes it no input naming a
# plugin path. That reusable stages the review plugin from claude-code-plugins'
# default-branch tip, never the pull request's head, so the review-evidence
# binder (babysit_review_evidence.py) does not list plugins/review/ as lane
# source. A caller that loaded the plugin from its checkout would let a pull
# request change its own review, and this test fails first.
# test-scope: .github/workflows/pr-review-hosted.yml .github/workflows/pr-review-security-hosted.yml plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py .github/standards/runner-policy/package.json
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
const REUSABLE = "melodic-software/ci-workflows/.github/workflows/pr-review-cli.yml@";
// Inputs the reusable reads as path globs for the prompt or a docs-only skip,
// never as a path to load: a plugins/ glob there loads nothing.
const GLOB_INPUTS = new Set(["hold-paths", "docs-only-paths"]);

// The problems with one caller's jobs, or [] when it is sound.
function problems(jobs) {
  const calls = Object.entries(jobs ?? {}).filter(
    ([, job]) => typeof job?.uses === "string" && job.uses.includes("pr-review-cli.yml"),
  );
  if (calls.length !== 1) return [`${calls.length} jobs call pr-review-cli.yml, want 1`];
  const [id, job] = calls[0];
  const found = [];
  if (job.uses !== `${REUSABLE}main`) {
    found.push(`job ${id} uses '${job.uses}', not ${REUSABLE}main`);
  }
  for (const [key, value] of Object.entries(job.with ?? {})) {
    if (/plugin/i.test(key) || (!GLOB_INPUTS.has(key) && /plugins?\//i.test(String(value)))) {
      found.push(`job ${id} passes ${key}: ${JSON.stringify(value)}, a plugin path`);
    }
  }
  return found;
}

for (const file of ["pr-review-hosted.yml", "pr-review-security-hosted.yml"]) {
  const wf = YAML.parse(readFileSync(`.github/workflows/${file}`, "utf8"));
  const found = problems(wf.jobs);
  say(found.length === 0,
    `${file} calls pr-review-cli.yml at main with no plugin path${found.length ? `: ${found.join("; ")}` : ""}`);
}

// The check itself rejects each shape it guards against.
const sha = "0123456789abcdef0123456789abcdef01234567";
const MAIN = `${REUSABLE}main`;
const call = (uses, inputs) => ({ review: { uses, with: inputs } });
for (const [name, jobs] of [
  ["a tag ref", call(`${REUSABLE}v0.65.12`, {})],
  ["a short SHA", call(`${REUSABLE}${sha.slice(0, 12)}`, {})],
  ["a full SHA", call(`${REUSABLE}${sha}`, {})],
  ["another branch", call(`${REUSABLE}feature`, {})],
  ["another repository's copy", call("someone/ci-workflows/.github/workflows/pr-review-cli.yml@main", {})],
  ["a plugin-dirs input", call(MAIN, { "plugin-dirs": "plugins/review" })],
  ["a plugin path in another input", call(MAIN, { extra: "./plugins/review" })],
  ["no call to the reusable", { review: { "runs-on": "ubuntu-latest" } }],
  ["two calls to the reusable", { ...call(MAIN, {}), again: { uses: MAIN } }],
]) {
  say(problems(jobs).length > 0, `the check rejects ${name}`);
}
say(problems(call(MAIN, { lane: "code", "hold-label": "needs-human" })).length === 0,
  "the check accepts a call at main with no plugin path");
say(problems(call(MAIN, { "hold-paths": "plugins/*/hooks/**\nplugins/review/**" })).length === 0,
  "the check accepts plugins/ globs in hold-paths, which only the prompt reads");
EOF
)
status=$?
if [[ $status -ne 0 || -z "$results" ]]; then
  fail "the node check did not run (exit $status)"
fi
while IFS=$'\t' read -r verdict text; do
  [[ -n "$verdict" ]] || continue
  if [[ "$verdict" == ok ]]; then ok "$text"; else fail "$text"; fi
done <<<"$results"

test_harness::report
