#!/usr/bin/env bash
# Part b of the shared page's browser suites, the ui_*.js that ui-parts.txt puts in b; ui-a.test.sh and
# ui-c.test.sh run the rest, and ui-run.sh runs each part.
#   bash plugins/planning/shared/tests/ui-b.test.sh
# test-scope: plugins/planning/shared/tests/browser_harness.js plugins/planning/shared/tests/harness-open.js
# test-scope: plugins/planning/shared/tests/ui_*.js plugins/planning/shared/web/*
exec bash "$(dirname "${BASH_SOURCE[0]}")/ui-run.sh" b
