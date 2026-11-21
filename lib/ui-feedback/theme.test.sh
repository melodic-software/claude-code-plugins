#!/usr/bin/env bash
# test-scope: lib/ui-feedback/host.html lib/ui-feedback/proto-pin.js plugins/prototype/skills/explore-directions/assets/variant-switcher.html
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/theme.test.mjs"
