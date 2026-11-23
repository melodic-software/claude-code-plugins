#!/usr/bin/env bash
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/sync-credential-legs.test.mjs"
