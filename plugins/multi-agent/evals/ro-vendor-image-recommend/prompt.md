---
description: "Vendor routing for an image generation task with vendors.auto_delegation set to false (AC8). A stub external-agents binary on PATH reports Codex as image-capable (image: true) with made-up model sparrow-1 while Antigravity is marked in_use: false. The route skill runs vendor-decide, does not invoke external-agents run, recommends Codex with basis claude-cannot, and shows how to run it. Needs --scaffold --allow-tools Bash."
tags: [multi-agent, route, vendors, outcome, no-network]
plugins: ["../..", "external-agents-path"]
runs: 2
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
env:
  EVAL_FETCH_DOCS_FIXTURE_DIR: eval-fixtures/boards
  EVAL_DOCS_CACHE_DIR: eval-fixtures/cache
expected_outcome: "vendor-decide routes the image task to codex (sparrow-1) with basis claude-cannot, external-agents run is not called, and the reply recommends Codex and shows how to run external-agents run codex --use task --mode write."
---

/multi-agent:route vendors generate a minimalist icon illustration for the settings screen session=opus
