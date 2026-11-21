#!/usr/bin/env bash
# test-scope: lib/ui-feedback/note-model.mjs lib/ui-feedback/host.html lib/ui-feedback/host.mjs
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/note-names.test.mjs"
