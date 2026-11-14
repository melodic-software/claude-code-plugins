#!/usr/bin/env bash
# Owns relocate-note.test.mjs; run-plugin-tests.sh discovers only .test.sh files.
# test-scope: lib/ui-feedback/relocate-note.mjs lib/ui-feedback/note-model.mjs lib/ui-feedback/note.schema.json
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/relocate-note.test.mjs"
