#!/usr/bin/env bash
# Owns check-convention-facts.test.mjs; run-plugin-tests.sh discovers only .test.sh files.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/check-convention-facts.test.mjs"
