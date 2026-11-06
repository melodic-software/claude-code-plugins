#!/usr/bin/env bash
# Discovery wrapper for driver.test.mjs and broker.test.mjs.
#
# run-plugin-tests.sh discovers only *.test.sh, so without this wrapper the
# driver's own suites would never run in CI. The cases live in the .mjs files;
# this only locates node, runs them, and forwards the exit status.
# test-scope: plugins/harness-ops/skills/control-claude-code/config/* plugins/harness-ops/skills/control-claude-code/SKILL.md
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITES=("$SELF_DIR/driver.test.mjs" "$SELF_DIR/broker.test.mjs")

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

for suite in "${SUITES[@]}"; do
  if [[ ! -f "$suite" ]]; then
    echo "FAIL: missing suite $suite" >&2
    exit 1
  fi
done

node --test "${SUITES[@]}"
