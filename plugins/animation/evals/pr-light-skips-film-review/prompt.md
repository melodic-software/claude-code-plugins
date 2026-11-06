---
description: "A repository whose default branch sets verification: light in docs/conventions/animation.yaml, with a film work directory whose step 8 pack check passed: produce step 9 reads the level, dispatches no fresh-context reviewer, writes the skip token and delivers the film marked as not independently reviewed rather than judging it itself. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: git for the scaffold."
tags: [animation, produce, setting, verification-level, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no subagent; writes verification: skipped (light); says the film was not independently reviewed."
---

Use the animation produce skill. My film work directory is ./film: it is rendered, and step 8's pack check passed (output in ./film/check-output.txt). Continue from step 9 and tell me whether it is ready to deliver.
