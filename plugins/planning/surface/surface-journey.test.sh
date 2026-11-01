#!/usr/bin/env bash
# The journey part of the interview surface's browser groups (ui_journey); the other surface-*.test.sh suites run the rest.
#   bash surface-journey.test.sh
# test-scope: plugins/planning/surface/schema/* plugins/planning/surface/tests/fixtures/*
# test-scope: plugins/planning/.claude-plugin/plugin.json
# test-scope: plugins/planning/shared/schema/event.schema.json plugins/planning/shared/schema/question-shape.schema.json
exec bash "$(dirname "${BASH_SOURCE[0]}")/surface-checks.sh" --part journey
