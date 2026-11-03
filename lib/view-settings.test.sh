#!/usr/bin/env bash
# Owns view-settings.test.mjs; run-plugin-tests.sh discovers only .test.sh files.
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/view-settings.test.mjs"
