---
description: "A skill step asks /multi-agent:route vendors under the Caller contract in reference/vendors.md, with routing on and vendors.auto_delegation at its shipped default (off; no user layer). Fixture coding boards are staged. The route skill resolves settings via route.sh, then stops: no board fetch, no vendor-decide, no delegate run, and it returns only `run here` with no vendor recommendation. Needs --scaffold --allow-tools Bash."
tags: [multi-agent, route, vendors, caller-contract, stop-rule, no-network]
runs: 2
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
env:
  EVAL_FETCH_DOCS_FIXTURE_DIR: eval-fixtures/boards
  EVAL_DOCS_CACHE_DIR: eval-fixtures/cache
expected_outcome: "route.sh resolves vendors.auto_delegation as false, fetch-boards, vendor-decide and delegate do not run, and the reply is `run here` without recommending a vendor."
---

/multi-agent:route vendors session=opus. Caller contract request from a skill step (see the Caller contract section of reference/vendors.md). Work type: coding. Task to run: review the diff of the CSV parser change for correctness bugs and report each finding with file:line.
