#!/usr/bin/env bash
# Owns scripts/setup-env.test.mjs; CI runs it by name because
# scripts/run-plugin-tests.sh does not discover scripts/.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/setup-env.test.mjs"
