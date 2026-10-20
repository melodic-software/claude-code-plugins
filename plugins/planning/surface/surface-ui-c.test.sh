#!/usr/bin/env bash
# The ui_c part of the interview surface's browser groups (ui_c); surface.test.sh and surface-journey.test.sh run the rest.
#   bash surface-ui-c.test.sh
# test-scope: plugins/planning/surface/schema/* plugins/planning/surface/tests/fixtures/*
# test-scope: plugins/planning/.claude-plugin/plugin.json
exec bash "$(dirname "${BASH_SOURCE[0]}")/surface-checks.sh" --part ui-c
