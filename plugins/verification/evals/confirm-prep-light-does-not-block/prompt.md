---
description: "Under verification: light set on the default branch, a clean change checked from PR prep gets NOT VERIFIED with the skip line, and the prep gate does not block PR creation"
tags: [confirm, setting, verification-level, pr-prep]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Stage 1 passes, no verifier is dispatched, the report carries verification: skipped (light), and it says the NOT VERIFIED verdict does not block PR creation because its only cause is the skip"
---

/verification:confirm This run is the verify gate of /source-control:pull-request prep. End the report with one line saying whether the gate blocks PR creation.
