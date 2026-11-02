---
description: "Reviewer-diversity eval, fixture empty-ratings, arm M (fanout_diversity model, no Codex): /review:fanout run-everything on a 'simplify' commit that drops average_rating's empty-reviews guard"
tags: [review, fanout-diversity, arm-m]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Workflow]
expected_outcome: "The run reports `fanout_diversity: model (docs/conventions/review.yaml)`, sends the review prompt to each fan-out model tier, leaves Codex out, and persists a report whose findings say, at IMPORTANT or CRITICAL, that average_rating now raises ZeroDivisionError for a product with no reviews, with no CRITICAL finding the ground truth marks wrong"
---

/review:fanout run-everything No pull request is open for this branch yet. Leave out the Codex surface even when it is installed. After the report is persisted, copy it byte for byte to `.work/eval/findings.md`, then end your reply with the report's `fanout_diversity:` line and its `## Surfaces` section.
