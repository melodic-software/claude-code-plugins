#!/usr/bin/env bash
# test-scope: lib/ui-feedback/frame-channel.mjs lib/ui-feedback/host.html lib/ui-feedback/host.mjs
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/frame-channel.test.mjs"
