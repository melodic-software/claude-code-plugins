#!/usr/bin/env bash
# Classifies declined suites without guessing a runner, and runs the registered
# packages' own npm test.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=lib/test-harness.sh
. scripts/lib/test-harness.sh

RUNNER="scripts/run-outside-node-suites.sh"
list="$(mktemp)"
trap 'rm -f "$list"' EXIT

printf '%s\n' \
  "plugins/testing/skills/audit/evals/fixtures/positive/cant-fail-js.test.js" \
  "plugins/machine-health/skills/audit/tests/windows/lib/ConvertFrom-Jsonc.Tests.ps1" \
  "plugins/knowledge/skills/video-digest/extraction/watch/run-watch.test.js" \
  "plugins/attribution/skills/audit/scripts/fingerprint.test.mjs" \
  >"$list"

out="$(bash "$RUNNER" --paths "$list")"
if grep -q "EXCLUDED: plugins/testing/skills/audit/evals/fixtures/positive/cant-fail-js.test.js" <<<"$out"; then
  ok "eval fixtures are excluded"
else
  fail "eval fixtures were not excluded: $out"
fi
if grep -q "PESER: plugins/machine-health/skills/audit/tests/windows/lib/ConvertFrom-Jsonc.Tests.ps1" <<<"$out"; then
  ok "Pester paths are handed to test-windows"
else
  fail "Pester path was not classified: $out"
fi
if grep -q "OWNED: plugins/knowledge/skills/video-digest/extraction/watch/run-watch.test.js" <<<"$out"; then
  ok "the four sub-projects stay on their own steps"
else
  fail "sub-project suite was not owned: $out"
fi
if grep -q "OWNED: plugins/attribution/skills/audit/scripts/fingerprint.test.mjs" <<<"$out"; then
  ok "a sibling .test.sh wrapper is owned by the shell runner"
else
  fail "wrapped node suite was not owned: $out"
fi

if bash "$RUNNER"; then
  ok "registered packages pass their own npm test"
else
  fail "registered packages failed npm test"
fi

printf '%s\n' "plugins/knowledge/vendor/not-a-suite/missing.test.js" >"$list"
if bash "$RUNNER" --paths "$list" >/dev/null 2>"$list.err"; then
  fail "an unclassified path should fail"
else
  ok "an unclassified path fails closed"
fi
rm -f "$list.err"

test_harness::report
