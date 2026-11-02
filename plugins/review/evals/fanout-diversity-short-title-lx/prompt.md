---
description: "Reviewer-diversity eval, fixture short-title, arm L+X (fanout_diversity lens, plus Codex): /review:fanout run-everything on a commit that drops shorten's 'redundant' length check. Probe result: L and M tie at 24/24 recall, so lens stays the default; the Codex arms are not measurable under codex 1.0.6 (#12151, 2026-11-02; #12495)."
tags: [review, fanout-diversity, arm-lx]
runs: 3
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Workflow]
expected_outcome: "The run reports `fanout_diversity: lens (docs/conventions/review.yaml)`, runs one reviewer agent per concern, runs the Codex surface and lists it in `## Surfaces`, and persists a report whose findings say, at IMPORTANT or CRITICAL, that shorten now appends an ellipsis to titles at or under the limit, with no CRITICAL finding the ground truth marks wrong"
---

/review:fanout run-everything No pull request is open for this branch yet. Run the Codex surface as one of the orchestrators, and report it in `## Surfaces` by the status its script prints. After the report is persisted, copy it byte for byte to `.work/eval/findings.md`, then end your reply with the report's `fanout_diversity:` line and its `## Surfaces` section.
