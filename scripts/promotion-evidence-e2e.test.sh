#!/usr/bin/env bash
# Discovery wrapper: scripts/run-plugin-tests.sh finds scripts/**/*.test.sh, so this
# hands off to the Node suite, which drives the source-control resolver and the
# autonomy checker end to end. It builds their paths from parts, so it declares them.
# test-scope: plugins/source-control/skills/babysit-loop/scripts/resolve-promotion-evidence.mjs
# test-scope: plugins/source-control/skills/babysit-loop/scripts/operator-options.mjs
# test-scope: plugins/autonomy/skills/setup/scripts/check-security-binding.mjs
# test-scope: plugins/autonomy/skills/setup/evals/fixtures/security-binding/promoted-c2c3.json
# test-scope: plugins/autonomy/skills/setup/evals/fixtures/security-binding/evidence-*.json
# test-scope: plugins/autonomy/skills/setup/evals/fixtures/security-binding/probe-transcripts/ci-pool-a-l2.json
# test-scope: plugins/autonomy/reference/guardrails/work-classes.md
set -euo pipefail

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$(dirname "${BASH_SOURCE[0]}")/promotion-evidence-e2e.test.mjs"
