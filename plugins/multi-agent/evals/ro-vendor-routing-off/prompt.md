---
description: "Vendor routing with vendors.routing set to false in the team layer (AC11). Fixture coding boards with made-up model ids are staged, and docs/conventions/multi-agent.yaml disables routing. The route skill resolves settings via route.sh, calls vendor-decide, skips fetching boards, reports that routing is off, and recommends no vendor. Needs --scaffold --allow-tools Bash."
tags: [multi-agent, route, vendors, outcome, no-network]
runs: 2
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
env:
  EVAL_FETCH_DOCS_FIXTURE_DIR: eval-fixtures/boards
  EVAL_DOCS_CACHE_DIR: eval-fixtures/cache
expected_outcome: "route.sh resolves vendors.routing as false, fetch-boards does not run, vendor-decide emits basis routing-off, and the reply states routing is off without recommending a vendor."
---

/multi-agent:route vendors refactor the CSV parser and add unit tests session=opus
