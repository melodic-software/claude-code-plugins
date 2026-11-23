#!/usr/bin/env bash
# test-scope: plugins/autonomy/reference/guardrails/admission-policy.md
# test-scope: plugins/autonomy/skills/setup/evals/fixtures/security-binding/probe-transcripts/ci-pool-a-l2.json
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/check-security-binding.admission-leaf.test.mjs"
