#!/usr/bin/env bash
# test-scope: lib/hook-enabled.mjs
set -euo pipefail
exec node --test --test-concurrency=4 "$(dirname "${BASH_SOURCE[0]}")/hook-enabled.test.mjs"
