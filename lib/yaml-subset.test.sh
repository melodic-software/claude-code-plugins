#!/usr/bin/env bash
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/yaml-subset.test.mjs"
