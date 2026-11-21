#!/usr/bin/env bash
# test-scope: plugins/external-agents/*
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/runner.test.mjs"
