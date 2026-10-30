#!/usr/bin/env bash
# Owns yaml-subset-parity.test.mjs; run-plugin-tests.sh discovers only .test.sh files.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/yaml-subset-parity.test.mjs"
