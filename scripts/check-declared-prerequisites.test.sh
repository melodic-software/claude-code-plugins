#!/usr/bin/env bash
# Owns scripts/check-declared-prerequisites.test.mjs; CI runs it by name because
# scripts/run-plugin-tests.sh does not discover scripts/.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/check-declared-prerequisites.test.mjs"
