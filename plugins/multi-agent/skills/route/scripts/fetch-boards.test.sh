#!/usr/bin/env bash
# test-scope: plugins/multi-agent/*
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/fetch-boards.test.mjs"
