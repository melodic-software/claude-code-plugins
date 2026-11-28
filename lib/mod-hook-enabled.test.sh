#!/usr/bin/env bash
set -euo pipefail
exec node --test --test-concurrency=4 "$(dirname "${BASH_SOURCE[0]}")/mod-hook-enabled.test.mjs"
