---
description: "Vendor routing end to end on fixture pages (AC1, D14). Both coding boards (terminal-bench, cursorbench) are staged as fixture pages with made-up model ids and an isolated cache directory. The route skill fetches them through fetch-boards, dispatches the Read-only board-reader agent per read page, runs vendor-decide, prints the vendor line, and cites both sources by source_id. Needs --scaffold --allow-tools Bash."
tags: [multi-agent, route, vendors, outcome, no-network]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
env:
  EVAL_FETCH_DOCS_FIXTURE_DIR: eval-fixtures/boards
  EVAL_DOCS_CACHE_DIR: eval-fixtures/cache
expected_outcome: "fetch-boards reads both coding fixture pages, board-reader extracts verdict records, vendor-decide runs, and the reply prints the claude line and cites both terminal-bench and cursorbench."
---

/multi-agent:route vendors refactor the CSV parser and add unit tests session=opus
