#!/usr/bin/env bash
# Phases 4 to 6 of the interview surface's ui_c browser group (the header and chips with no watcher,
# a lease and a waiter); the other surface-*.test.sh suites run the rest.
#   bash surface-ui-c-listen.test.sh
# test-scope: plugins/planning/surface/schema/* plugins/planning/surface/tests/fixtures/*
# test-scope: plugins/planning/.claude-plugin/plugin.json
exec bash "$(dirname "${BASH_SOURCE[0]}")/surface-checks.sh" --part ui-c-listen
