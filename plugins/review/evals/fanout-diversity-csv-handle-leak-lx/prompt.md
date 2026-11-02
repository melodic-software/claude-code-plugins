---
description: "Reviewer-diversity eval, fixture csv-handle-leak, arm L+X (fanout_diversity lens, plus Codex): /review:fanout run-everything on a commit that drops countRows' try/finally around a new header check"
tags: [review, fanout-diversity, arm-lx]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Workflow]
expected_outcome: "The run reports `fanout_diversity: lens (docs/conventions/review.yaml)`, runs one reviewer agent per concern, runs the Codex surface and lists it in `## Surfaces`, and persists a report whose findings say, at IMPORTANT or CRITICAL, that a CSV with the wrong header throws before file.close() runs and leaks its file handle on every bad upload importAll goes on past, with no CRITICAL finding the ground truth marks wrong"
---

/review:fanout run-everything No pull request is open for this branch yet. Run the Codex surface, `/codex:review --wait --base <review-base>`, as one of the orchestrators, and list it in the `## Surfaces` `Ran` entry. After the report is persisted, copy it byte for byte to `.work/eval/findings.md`, then end your reply with the report's `fanout_diversity:` line and its `## Surfaces` section.
