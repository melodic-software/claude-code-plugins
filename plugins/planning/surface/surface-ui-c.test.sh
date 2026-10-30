#!/usr/bin/env bash
# Phases 1 to 3 of the interview surface's ui_c browser group; the other surface-*.test.sh suites run the rest.
#   bash surface-ui-c.test.sh
# test-scope: plugins/planning/surface/schema/* plugins/planning/surface/tests/fixtures/*
# test-scope: plugins/planning/.claude-plugin/plugin.json
exec bash "$(dirname "${BASH_SOURCE[0]}")/surface-checks.sh" --part ui-c
