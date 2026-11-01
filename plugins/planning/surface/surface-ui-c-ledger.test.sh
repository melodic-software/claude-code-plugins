#!/usr/bin/env bash
# Phases 7 to 10 of the interview surface's ui_c browser group (the meter against export-ledger, and
# accepts on a restated interview); the other surface-*.test.sh suites run the rest.
#   bash surface-ui-c-ledger.test.sh
# test-scope: plugins/planning/surface/schema/* plugins/planning/surface/tests/fixtures/*
# test-scope: plugins/planning/.claude-plugin/plugin.json
# test-scope: plugins/planning/shared/schema/event.schema.json plugins/planning/shared/schema/question-shape.schema.json
exec bash "$(dirname "${BASH_SOURCE[0]}")/surface-checks.sh" --part ui-c-ledger
