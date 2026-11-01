#!/usr/bin/env bash
# Part a of the shared page's browser suites, the ui_*.js that ui-parts.txt puts in a; ui-b.test.sh and
# ui-c.test.sh run the rest, and ui-run.sh runs each part.
#   bash plugins/planning/shared/tests/ui-a.test.sh
# test-scope: plugins/planning/shared/tests/browser_harness.js plugins/planning/shared/tests/harness-open.js
# test-scope: plugins/planning/shared/tests/ui_*.js plugins/planning/shared/web/*
# test-scope: plugins/planning/shared/tests/ui-run.sh plugins/planning/shared/tests/ui-parts.txt plugins/planning/shared/tests/ui-timings.txt
# test-scope: plugins/planning/.claude-plugin/plugin.json plugins/planning/shared/schema/* plugins/planning/surface/schema/*
# test-scope: plugins/planning/shared/server.py plugins/planning/shared/session.py plugins/planning/shared/session_bridge.py
# test-scope: plugins/planning/shared/share.py plugins/planning/shared/share.sh plugins/planning/shared/tunnel.py
# test-scope: plugins/planning/shared/cfdns.py plugins/planning/shared/detached.py plugins/planning/shared/liveserve.py
# test-scope: plugins/planning/shared/tests/fixtures/fake-cloudflared.sh plugins/planning/shared/tests/fixtures/live_stub_server.py
exec bash "$(dirname "${BASH_SOURCE[0]}")/ui-run.sh" a
