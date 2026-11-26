#!/usr/bin/env bash
# test-scope: plugins/engineering-concepts/*
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/lookup.test.mjs"
