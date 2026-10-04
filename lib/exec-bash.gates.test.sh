#!/usr/bin/env bash
# Owns lib/exec-bash.gates.test.mjs for the plugin test lane.
# scripts/run-outside-node-suites.sh treats a sibling .test.sh as the runner.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec node exec-bash.gates.test.mjs
