#!/usr/bin/env bash
# test-scope: plugins/multi-agent/*
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/vendor-state.test.mjs"
