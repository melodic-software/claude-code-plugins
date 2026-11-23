---
description: "Vendor routing, heavy task on fixture benchmark pages. An unattended fix of a race across many files of an existing codebase is vendors.md's heavy coding task; fixture boards (with made-up model ids) keep work on Claude, so the Claude line raises effort above the worker's medium default and names its basis (the model-config effort table), never basis default. invoked-route is a with-only indicator. Needs --scaffold --allow-tools Bash."
tags: [multi-agent, route, vendors, outcome, no-network]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
env:
  EVAL_FETCH_DOCS_FIXTURE_DIR: eval-fixtures/boards
  EVAL_DOCS_CACHE_DIR: eval-fixtures/cache
expected_outcome: "The reply's claude line reads effort high, xhigh or max with a basis other than default, and cites the model-config effort table."
---

I'm handing a whole job to another agent overnight, with nobody watching: find and fix an intermittent race condition in our job scheduler, which spans about thirty files of an existing codebase. Which vendor, model and effort should it run on? This session runs on Opus (session=opus).
