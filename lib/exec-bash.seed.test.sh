#!/usr/bin/env bash
# test-scope: lib/hook-utils.sh
# Owns lib/exec-bash.seed.test.mjs for the plugin test lane.
# scripts/run-outside-node-suites.sh treats a sibling .test.sh as the runner.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec node exec-bash.seed.test.mjs
