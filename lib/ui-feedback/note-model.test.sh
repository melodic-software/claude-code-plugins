#!/usr/bin/env bash
# test-scope: lib/ui-feedback/note.schema.json lib/ui-feedback/controls.schema.json lib/ui-feedback/controls.js lib/ui-feedback/fixtures/*
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/note-model.test.mjs"
