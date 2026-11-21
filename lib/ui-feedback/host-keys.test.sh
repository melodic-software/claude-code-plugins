#!/usr/bin/env bash
# test-scope: lib/ui-feedback/host.html lib/ui-feedback/proto-pin.js
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/host-keys.test.mjs"
