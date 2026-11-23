---
description: "Vendor routing with one unread benchmark page (AC7). terminal-bench is staged as a fixture page with a non-Claude lead (made-up model ids), while cursorbench is missing so fetch-boards marks it unread. With fewer than two independent leading sources, vendor-decide keeps coding on Claude default and the reply names cursorbench as unread. Needs --scaffold --allow-tools Bash."
tags: [multi-agent, route, vendors, outcome, no-network]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
env:
  EVAL_FETCH_DOCS_FIXTURE_DIR: eval-fixtures/boards
  EVAL_DOCS_CACHE_DIR: eval-fixtures/cache
expected_outcome: "fetch-boards marks cursorbench unread, vendor-decide keeps the coding task on claude with basis default, and the reply names cursorbench as unread."
---

/multi-agent:route vendors implement a streaming JSON decoder in the CLI session=opus
