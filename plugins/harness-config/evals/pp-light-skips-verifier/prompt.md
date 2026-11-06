---
description: "The quay repo with three project skills, one destructive with no gate, whose default branch sets verification: light in docs/conventions/harness-config.yaml. The Agent tool is granted, but Phase D dispatches no verifier: the report writes the skip token and marks each proposal (unverified). Needs network: Phase A aborts when the best-practices page cannot be fetched. Needs --scaffold --allow-tools Bash Write WebFetch Agent."
tags: [audit-prompting-postures, setting, verification-level, scaffold, plugin-data-risk]
runs: 3
max_turns: 30
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, WebFetch, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no Phase D verifier; writes verification: skipped (light); marks each proposal (unverified)."
---

/harness-config:audit-prompting-postures skills

Quick posture check on our skills, please.
