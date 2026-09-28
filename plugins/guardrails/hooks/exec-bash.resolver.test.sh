#!/usr/bin/env bash
# Owns plugins/guardrails/hooks/exec-bash.resolver.test.mjs for the plugin
# test lane. scripts/run-outside-node-suites.sh treats a sibling .test.sh as
# the runner and does not look for a package.json test command.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec node exec-bash.resolver.test.mjs
