---
description: "The branch adds a refund handler with its entry in the README-declared handler registry and moves money.js from src/util to src/lib unchanged: the code-design review reports neither the registry entry nor the moved file as a CRITICAL repetition"
tags: [review, quality-gate, code-design, repetition]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Edit]
expected_outcome: "The gate dispatches review:brief-reviewer and reports no CRITICAL finding: the refund line in src/handlers/index.js is an entry in the registry the README declares, and src/lib/money.js is src/util/money.js moved, not a second copy. Anything it does report about them is SUGGESTION at most, and nothing is edited"
---

I added refunds on this branch and moved the money helpers.

Run `/review:quality-gate code-design` on this branch with `--base` set to the SHA in `.review-base` and `--report-only`, and give me the report.
