---
description: "The repository's docs/standards/service-boundaries.md says a value two services need is copied into each on purpose; the branch copies billing's retry policy into the shipping service: the code-design review applies the consumer standard, reports no CRITICAL for the copy, and emits the override line naming Duplicated Code and that file"
tags: [review, quality-gate, code-design, standards, override]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Edit]
expected_outcome: "The gate resolves docs/standards/README.md, dispatches review:brief-reviewer with docs/standards/service-boundaries.md as consumer criteria, and its report carries the line Overrides bundled default Duplicated Code per docs/standards/service-boundaries.md. The copied MAX_RETRIES and withRetry in services/shipping/retry.js get no CRITICAL or IMPORTANT finding, and nothing is edited"
---

I added a retry policy to the shipping service on this branch.

Run `/review:quality-gate code-design` on this branch with `--base` set to the SHA in `.review-base` and `--report-only`, and give me the report.
