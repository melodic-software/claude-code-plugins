---
description: "Reviewer-diversity eval, fixture price-cents, arm M+X (fanout_diversity model, plus Codex): /review:fanout run-everything on a commit that switches parsePrice to cents and leaves invoiceLine on dollars"
tags: [review, fanout-diversity, arm-mx]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Workflow]
expected_outcome: "The run reports `fanout_diversity: model (docs/conventions/review.yaml)`, sends the review prompt to each fan-out model tier, runs the Codex surface and lists it in `## Surfaces`, and persists a report whose findings say, at IMPORTANT or CRITICAL, that invoiceLine still reads parsePrice's new cents as dollars, so every invoice line prints 100 times too large, with no CRITICAL finding the ground truth marks wrong"
---

/review:fanout run-everything No pull request is open for this branch yet. Run the Codex surface, `/codex:review --wait --base <review-base>`, as one of the orchestrators, and list it in the `## Surfaces` `Ran` entry. After the report is persisted, copy it byte for byte to `.work/eval/findings.md`, then end your reply with the report's `fanout_diversity:` line and its `## Surfaces` section.
