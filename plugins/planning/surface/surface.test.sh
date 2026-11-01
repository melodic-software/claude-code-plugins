#!/usr/bin/env bash
# The interview surface's hygiene checks and its main browser groups (ui_a, ui_b, ui_e, ui_live);
# the other surface-*.test.sh suites run the rest.
#   bash surface.test.sh
# test-scope: plugins/planning/surface/schema/* plugins/planning/surface/tests/fixtures/*
# test-scope: plugins/planning/.claude-plugin/plugin.json
# test-scope: plugins/planning/shared/schema/event.schema.json plugins/planning/shared/schema/question-shape.schema.json
exec bash "$(dirname "${BASH_SOURCE[0]}")/surface-checks.sh"
