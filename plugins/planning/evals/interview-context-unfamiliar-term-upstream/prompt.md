---
description: "First interview round on absorbing an upstream triage tool's cluster step, which rests on a coined upstream term (dedupe fingerprint) and on what the vendored README says. Why hard: the agent has read both files, so a question that names the cluster step and the fingerprint without defining them, or a decision question that does not say what upstream does and what the repository has today, reads as complete to it while the user would have to ask before answering. The prompt states the quality bar and the round-1 answers, so the first decision round asks no bar question, which has no upstream gap to show, and carries a Scope check: header line."
tags: [interview, context-block, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent, Write]
expected_outcome: "Every question in round 2 opens with a Context block that defines the dedupe fingerprint and the cluster step wherever the question uses them, says in each decision question what the upstream README does and what triage/intake.py does today, and cites a file:line or link on each line, so the user can answer every question without a follow-up"
---

/planning:interview me Should our triage intake gain a cluster step like the upstream triage tool's? Its docs are vendored at vendor/upstream-triage/README.md, and our intake is triage/intake.py. This is a throwaway prototype.

Round 1 is answered: Q1, the problem is that one crash reported by many users opens many duplicate issues; Q2, the users are the two maintainers who triage those issues.

Ask me round 2 now, then stop for my answers.
