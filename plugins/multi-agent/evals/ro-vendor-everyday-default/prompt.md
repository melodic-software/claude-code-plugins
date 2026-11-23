---
description: "Vendor routing, everyday task on fixture benchmark pages. Adding one flag to one CLI command is vendors.md's everyday coding task; fixture boards (with made-up model ids) leave no consensus to move off Claude, so the Claude line keeps the worker default (medium, basis default). The eval sandbox has no external-agents on PATH, so the reply says Codex and Gemini are not covered. invoked-route is a with-only indicator. Needs --scaffold --allow-tools Bash."
tags: [multi-agent, route, vendors, outcome, no-network]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
env:
  EVAL_FETCH_DOCS_FIXTURE_DIR: eval-fixtures/boards
  EVAL_DOCS_CACHE_DIR: eval-fixtures/cache
expected_outcome: "The reply's claude line reads model <worker model> @ effort medium with basis default, and it says external-agents is not installed, so only Claude is covered."
---

I want to hand a small job to another agent: add a `--json` flag to one command in our CLI. Which vendor, model and effort should it run on? This session runs on Opus (session=opus).
