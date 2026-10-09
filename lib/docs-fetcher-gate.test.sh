#!/usr/bin/env bash
# Owns docs-fetcher-gate.test.mjs; run-plugin-tests.sh discovers only .test.sh files.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/docs-fetcher-gate.test.mjs"
