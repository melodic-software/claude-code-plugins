#!/usr/bin/env bash
# The journey part of the interview surface's browser groups (ui_journey); surface.test.sh and surface-ui-c.test.sh run the rest.
#   bash surface-journey.test.sh
# test-scope: plugins/planning/surface/schema/* plugins/planning/surface/tests/fixtures/*
# test-scope: plugins/planning/.claude-plugin/plugin.json
exec bash "$(dirname "${BASH_SOURCE[0]}")/surface-checks.sh" --part journey
