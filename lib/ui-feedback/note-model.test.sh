#!/usr/bin/env bash
# Owns note-model.test.mjs; run-plugin-tests.sh discovers only .test.sh files.
# test-scope: lib/ui-feedback/note.schema.json lib/ui-feedback/fixtures/*
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/note-model.test.mjs"
