#!/usr/bin/env bash
# Owns prerequisites-fleet.test.mjs; run-plugin-tests.sh discovers only .test.sh files.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/prerequisites-fleet.test.mjs"
