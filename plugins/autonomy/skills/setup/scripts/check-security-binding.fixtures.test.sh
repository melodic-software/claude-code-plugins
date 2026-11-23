#!/usr/bin/env bash
# test-scope: plugins/autonomy/skills/setup/evals/fixtures/security-binding/*
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node "$SCRIPT_DIR/check-security-binding.fixtures.test.mjs"
