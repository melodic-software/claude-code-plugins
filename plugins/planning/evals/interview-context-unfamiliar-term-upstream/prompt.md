---
description: "First interview round on absorbing an upstream triage tool's cluster step, which rests on a coined upstream term (dedupe fingerprint) and on what the vendored README says. Why hard: the agent has read both files, so a question that names the cluster step and the fingerprint without defining them, or without saying what upstream does and what the repository has today, reads as complete to it while the user would have to ask before answering."
tags: [interview, context-block, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "Every question in round 1 opens with a Context block that defines the dedupe fingerprint and the cluster step, says what the upstream README does and what triage/intake.py does today, and cites a file:line or link on each line, so the user can answer every question without a follow-up"
---

/planning:interview me Should our triage intake gain a cluster step like the upstream triage tool's? Its docs are vendored at vendor/upstream-triage/README.md, and our intake is triage/intake.py. Ask me your first round, then stop for my answers.
