---
description: "Reviewer-diversity eval, fixture vacuous-slug-test, arm M+X (fanout_diversity model, plus Codex): /review:fanout run-everything on a commit whose new accent test calls assert.ok with the expected slug as its message"
tags: [review, fanout-diversity, arm-mx]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Workflow]
expected_outcome: "The run reports `fanout_diversity: model (docs/conventions/review.yaml)`, sends the review prompt to each fan-out model tier, runs the Codex surface and lists it in `## Surfaces`, and persists a report whose findings say, at IMPORTANT or CRITICAL, that the new accent test's assert.ok(slugify(title), expected) only checks that the slug is truthy and passes on main's broken slugify too, with no CRITICAL finding the ground truth marks wrong"
---

/review:fanout run-everything No pull request is open for this branch yet. Run the Codex surface, `/codex:review --wait --base <review-base>`, as one of the orchestrators, and list it in the `## Surfaces` `Ran` entry. After the report is persisted, copy it byte for byte to `.work/eval/findings.md`, then end your reply with the report's `fanout_diversity:` line and its `## Surfaces` section.
