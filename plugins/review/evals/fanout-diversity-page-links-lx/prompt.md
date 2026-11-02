---
description: "Reviewer-diversity eval, decoy fixture page-links, arm L+X (fanout_diversity lens, plus Codex): /review:fanout run-everything on a correct commit that rewrites pageNumbers' loop to count 1-based pages with a <= bound"
tags: [review, fanout-diversity, arm-lx, decoy]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Workflow]
expected_outcome: "The run reports `fanout_diversity: lens (docs/conventions/review.yaml)`, runs one reviewer agent per concern, runs the Codex surface and lists it in `## Surfaces`, and persists a report with no IMPORTANT or CRITICAL finding, since the change is correct: the loop pushes 1 through pageCount as main did, and pageNumbers(0) still returns an empty list"
---

/review:fanout run-everything No pull request is open for this branch yet. Run the Codex surface, `/codex:review --wait --base <review-base>`, as one of the orchestrators, and list it in the `## Surfaces` `Ran` entry. After the report is persisted, copy it byte for byte to `.work/eval/findings.md`, then end your reply with the report's `fanout_diversity:` line and its `## Surfaces` section.
