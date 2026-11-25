#!/usr/bin/env bash
# test-scope: plugins/planning/shared/tests/browser_harness.js plugins/planning/shared/tests/harness-open.js
# test-scope: plugins/planning/shared/tests/ui_*.js plugins/planning/shared/web/*
# test-scope: plugins/planning/shared/tests/ui-run.sh plugins/planning/shared/tests/ui-parts.txt plugins/planning/shared/tests/ui-timings.txt
exec bash "$(dirname "${BASH_SOURCE[0]}")/ui-run.sh" c
