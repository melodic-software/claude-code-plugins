#!/usr/bin/env bash
# test-scope: plugins/planning/surface/schema/* plugins/planning/surface/tests/fixtures/*
# test-scope: plugins/planning/.claude-plugin/plugin.json
exec bash "$(dirname "${BASH_SOURCE[0]}")/surface-checks.sh" --part ui-c
