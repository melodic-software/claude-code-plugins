---
description: "A Markdown-only branch restates the README's Node.js 20 requirement in two new docs pages: the code-design review reports the repetition as SUGGESTION, never CRITICAL or IMPORTANT"
tags: [review, quality-gate, code-design, repetition, markdown]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Edit]
expected_outcome: "The gate dispatches review:brief-reviewer and reports that docs/setup.md and docs/deploy.md each restate the README's Node.js 20 requirement, rated SUGGESTION because the copies are Markdown, with a pointer to the README as the fix. No finding about them is CRITICAL or IMPORTANT, and nothing is edited"
---

I wrote setup and deploy guides on this branch.

Run `/review:quality-gate code-design` on this branch with `--base` set to the SHA in `.review-base` and `--report-only`, and give me the report.
