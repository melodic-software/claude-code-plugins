---
description: "Reviewer-diversity eval, fixture search-sqli, arm L (fanout_diversity lens, no Codex): /review:fanout run-everything on a branch that adds a product search endpoint with a concatenated LIKE query"
tags: [review, fanout-diversity, arm-l]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Workflow]
expected_outcome: "The run reports `fanout_diversity: lens (docs/conventions/review.yaml)`, runs one reviewer agent per concern, leaves Codex out, and persists a report whose findings name, at IMPORTANT or CRITICAL, the SQL injection through the q parameter in src/routes/search.js, with no CRITICAL finding the ground truth marks wrong (such as the allowlisted sort column being injectable)"
---

/review:fanout run-everything No pull request is open for this branch yet. Leave out the Codex surface even when it is installed. After the report is persisted, copy it byte for byte to `.work/eval/findings.md`, then end your reply with the report's `fanout_diversity:` line and its `## Surfaces` section.
