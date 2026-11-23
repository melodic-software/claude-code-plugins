---
description: "Vendor routing when an in-use vendor is unavailable (AC4). Codex is declared in_use: true in docs/conventions/multi-agent.yaml, while a stub external-agents binary on PATH returns status: unavailable for codex; Antigravity is marked in_use: false. The route skill prints Claude's line, emits one unavailable line for Codex, and skips Antigravity silently. Needs --scaffold --allow-tools Bash."
tags: [multi-agent, route, vendors, outcome, no-network]
plugins: ["../..", "external-agents-path"]
runs: 2
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
env:
  EVAL_FETCH_DOCS_FIXTURE_DIR: eval-fixtures/boards
  EVAL_DOCS_CACHE_DIR: eval-fixtures/cache
expected_outcome: "vendor-decide keeps the coding task on claude and notes codex as unavailable; the reply includes Claude's recommendation line, one unavailable line for codex, and no line for antigravity/gemini."
---

/multi-agent:route vendors add a --quiet flag to the export command session=opus
