#!/usr/bin/env bash
# test-scope: plugins/planning/shared/*.py
# Part c of the page alignment check, the sizes align.js PARTS puts in c; align-a.test.sh and align-b.test.sh run
# the rest, and align-run.sh runs each part.
#   bash plugins/planning/shared/tests/align-c.test.sh
# test-scope: plugins/planning/shared/tests/align-run.sh plugins/planning/shared/tests/align.js
# test-scope: plugins/planning/.claude-plugin/plugin.json plugins/planning/shared/detached.py plugins/planning/shared/server.py plugins/planning/shared/session.py plugins/planning/shared/session_bridge.py plugins/planning/shared/share.py plugins/planning/shared/share.sh plugins/planning/shared/tunnel.py plugins/planning/shared/schema/*.schema.json plugins/planning/shared/tests/browser_harness.js plugins/planning/shared/tests/fixtures/fake-cloudflared.sh plugins/planning/shared/web/*.css plugins/planning/shared/web/*.js plugins/planning/shared/web/index.html plugins/planning/shared/web/proto.html plugins/planning/surface/schema.py plugins/planning/surface/schema/*.schema.json
exec bash "$(dirname "${BASH_SOURCE[0]}")/align-run.sh" c
