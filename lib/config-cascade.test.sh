#!/usr/bin/env bash
# Owns config-cascade.test.mjs; run-plugin-tests.sh discovers only .test.sh files.
# test-scope: lib/fixtures/config-cascade/*
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/config-cascade.test.mjs"
