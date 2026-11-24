#!/usr/bin/env bash
# test-scope: lib/hook-utils.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
exec node exec-bash.seed.test.mjs
