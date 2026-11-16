#!/usr/bin/env bash
# Owns the plugin's node suites; run-plugin-tests.sh discovers only .test.sh files.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec node --test --test-concurrency=4 "$root/lib/"*.test.mjs "$root/scripts/"*.test.mjs
