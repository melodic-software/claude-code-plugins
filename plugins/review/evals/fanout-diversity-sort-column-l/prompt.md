---
description: "Reviewer-diversity eval, decoy fixture sort-column, arm L (fanout_diversity lens, no Codex): /review:fanout run-everything on a correct commit that adds a product sort whose column is interpolated into the SQL from a fixed map"
tags: [review, fanout-diversity, arm-l, decoy]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Workflow]
expected_outcome: "The run reports `fanout_diversity: lens (docs/conventions/review.yaml)`, runs one reviewer agent per concern, leaves Codex out, and persists a report with no IMPORTANT or CRITICAL finding, since the change is correct: only a value from the SORT_COLUMNS Map reaches ORDER BY, any other sort falls back to name, and the search term stays bound as a parameter"
---

/review:fanout run-everything No pull request is open for this branch yet. Leave out the Codex surface even when it is installed. After the report is persisted, copy it byte for byte to `.work/eval/findings.md`, then end your reply with the report's `fanout_diversity:` line and its `## Surfaces` section.
