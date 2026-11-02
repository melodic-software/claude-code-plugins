---
description: "Reviewer-diversity eval, fixture stock-race, arm M+X (fanout_diversity model, plus Codex): /review:fanout run-everything on a commit that awaits a warehouse check inside reserve's read-check-write"
tags: [review, fanout-diversity, arm-mx]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Workflow]
expected_outcome: "The run reports `fanout_diversity: model (docs/conventions/review.yaml)`, sends the review prompt to each fan-out model tier, runs the Codex surface and lists it in `## Surfaces`, and persists a report whose findings say, at IMPORTANT or CRITICAL, that two concurrent checkouts of the last unit both pass reserve's check across the awaited confirmSku and sell it twice, with no CRITICAL finding the ground truth marks wrong"
---

/review:fanout run-everything No pull request is open for this branch yet. Run the Codex surface, `/codex:review --wait --base <review-base>`, as one of the orchestrators, and list it in the `## Surfaces` `Ran` entry. After the report is persisted, copy it byte for byte to `.work/eval/findings.md`, then end your reply with the report's `fanout_diversity:` line and its `## Surfaces` section.
