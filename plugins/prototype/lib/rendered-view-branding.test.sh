#!/usr/bin/env bash
# test-scope: plugins/prototype/reference/html-tokens.css plugins/prototype/lib/view-settings.mjs plugins/prototype/notes-bridge/host.html plugins/prototype/notes-bridge/proto-pin.js plugins/prototype/skills/explore-directions/assets/variant-switcher.html
set -euo pipefail
exec node --test --test-concurrency=4 "$(dirname "${BASH_SOURCE[0]}")/rendered-view-branding.test.mjs"
