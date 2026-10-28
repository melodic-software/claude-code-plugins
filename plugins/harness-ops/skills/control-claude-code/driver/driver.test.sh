#!/usr/bin/env bash
# Discovery wrapper for driver.test.mjs.
#
# run-plugin-tests.sh discovers only *.test.sh, so without this wrapper the
# driver's own suite would never run in CI. The cases live in the .mjs file;
# this only locates node, runs it, and forwards the exit status.
# test-scope: plugins/harness-ops/skills/control-claude-code/config/*
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$SELF_DIR/driver.test.mjs"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

if [[ ! -f "$SUITE" ]]; then
  echo "FAIL: missing suite $SUITE" >&2
  exit 1
fi

node --test "$SUITE"
