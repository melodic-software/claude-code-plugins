#!/usr/bin/env bash
# Behavior test: the "Revoke the lane token" step in pr-run-activity-write.yml
# never fails the job (ADR 0058 calls the revoke a backstop). A DELETE other
# than 204 is a warning; a 204 whose GET read-back is not yet 401 is a notice;
# a 204 then 401 logs the confirmed revoke. Runs the step's github-script body with a stub `github` that
# answers each route with a canned status and a stub `core` that records calls.
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
const step = wf.jobs.run.steps.find((s) => s.name === "Revoke the lane token");
say(Boolean(step?.with?.script), "the run job has a Revoke the lane token step with a script");
say(step?.["continue-on-error"] === true, "the revoke step sets continue-on-error: true");

const AsyncFunction = (async () => {}).constructor;
// answers: route -> status number, or { throws: status|undefined }
async function run(answers) {
  const calls = { failed: [], warning: [], notice: [], error: [], info: [] };
  const github = {
    request: async (route) => {
      const a = answers[route];
      if (a && typeof a === "object") {
        const e = new Error("request failed");
        if (a.throws !== undefined) e.status = a.throws;
        throw e;
      }
      if (a >= 400) {
        const e = new Error(`HTTP ${a}`);
        e.status = a;
        throw e;
      }
      return { status: a };
    },
  };
  const core = {
    info: (m) => calls.info.push(m),
    setFailed: (m) => calls.failed.push(m),
    warning: (m) => calls.warning.push(m),
    notice: (m) => calls.notice.push(m),
    error: (m) => calls.error.push(m),
  };
  let threw = null;
  try {
    await new AsyncFunction("github", "core", step.with.script)(github, core);
  } catch (e) {
    threw = e;
  }
  return { ...calls, threw };
}

const DEL = "DELETE /installation/token";
const GET = "GET /installation/repositories";
const quiet = (r) => !r.threw && r.failed.length === 0 && r.error.length === 0;

let r = await run({ [DEL]: 204, [GET]: 401 });
say(quiet(r) && r.warning.length === 0 && r.notice.length === 0,
  "DELETE 204 then GET 401: no failure, warning or notice");
say(r.info.some((m) => /confirmed revoked/.test(m)),
  "DELETE 204 then GET 401: the step log records the confirmed revoke");

r = await run({ [DEL]: 204, [GET]: 200 });
say(quiet(r) && r.warning.length === 0 && r.notice.length === 1 && !r.info.some((m) => /confirmed revoked/.test(m)),
  "DELETE 204 then GET 200: one notice, no failure, warning or confirmed-revoke log");

r = await run({ [DEL]: 404, [GET]: 200 });
say(quiet(r) && r.warning.length === 1 && r.notice.length === 0,
  "DELETE 404: one warning, no failure or notice");

r = await run({ [DEL]: { throws: undefined }, [GET]: { throws: undefined } });
say(quiet(r) && r.warning.length === 1,
  "DELETE network error with no status: one warning, no failure");
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
