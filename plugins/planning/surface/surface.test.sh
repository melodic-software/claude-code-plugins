#!/usr/bin/env bash
# The interview surface's hygiene checks and its main browser groups (ui_a, ui_b, ui_e, ui_live,
# ui_page); surface-ui-c.test.sh and surface-journey.test.sh run the rest.
#   bash surface.test.sh
# test-scope: plugins/planning/surface/schema/* plugins/planning/surface/tests/fixtures/*
# test-scope: plugins/planning/.claude-plugin/plugin.json
exec bash "$(dirname "${BASH_SOURCE[0]}")/surface-checks.sh"
