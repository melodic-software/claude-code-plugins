---
description: "Reviewer-diversity eval, decoy fixture sort-column, arm M+X (fanout_diversity model, plus Codex): /review:fanout run-everything on a correct commit that adds a product sort whose column is interpolated into the SQL from a fixed map"
tags: [review, fanout-diversity, arm-mx, decoy]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Workflow]
expected_outcome: "The run reports `fanout_diversity: model (docs/conventions/review.yaml)`, sends the review prompt to each fan-out model tier, runs the Codex surface and lists it in `## Surfaces`, and persists a report with no IMPORTANT or CRITICAL finding, since the change is correct: only a value from the SORT_COLUMNS Map reaches ORDER BY, any other sort falls back to name, and the search term stays bound as a parameter"
---

/review:fanout run-everything No pull request is open for this branch yet. Run the Codex surface, `/codex:review --wait --base <review-base>`, as one of the orchestrators, and list it in the `## Surfaces` `Ran` entry. After the report is persisted, copy it byte for byte to `.work/eval/findings.md`, then end your reply with the report's `fanout_diversity:` line and its `## Surfaces` section.
