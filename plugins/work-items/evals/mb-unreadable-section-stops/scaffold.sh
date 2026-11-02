#!/usr/bin/env bash
# Offline brief inputs: four readable sections and a PR list that is a GitHub error document.
set -euo pipefail
mkdir -p brief
printf '%s\n' '{"needs-triage": 5, "status: ready": 12, "status: needs-decision": 1, "needs-human": 2}' >brief/counts.json
printf '%s\n' '["needs-triage", "status: ready", "status: needs-decision", "needs-human"]' >brief/labels.json
printf '%s\n' '{"message": "API rate limit exceeded for user. Retry after 2026-07-20T09:00Z", "documentation_url": "https://docs.github.com/rest/rate-limit"}' >brief/prs.json
printf '%s\n' '[{"number": 412, "title": "Pick the cache backend", "url": "https://github.com/acme/widgets/issues/412", "body": "Two options.\nRECOMMENDED: use the sqlite cache with a seven-day TTL.", "comments": []}]' >brief/decisions.json
printf '%s\n' '[{"body": "<!-- harness-ops:lane-telemetry marker=lane:babysit -->\n- lane: babysit\n- last-cycle: 2026-07-19T20:00Z\n- flags: none"}]' >brief/telemetry.json
printf '%s\n' '[{"data": {"repository": {"pullRequests": {"pageInfo": {"hasNextPage": false, "endCursor": null}, "nodes": [{"number": 388, "title": "all clear", "url": "https://github.com/acme/widgets/pull/388", "mergedAt": "2026-07-19T16:00:00Z", "reviewThreads": {"nodes": []}}]}}}}]' >brief/merged.json
