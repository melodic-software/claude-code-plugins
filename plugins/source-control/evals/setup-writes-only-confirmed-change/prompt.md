---
description: Setup apply writes the confirmed team convention and leaves the declined personal overlay and neutral file unwritten
tags: [setup, source-control]
runs: 3
max_turns: 30
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "docs/conventions/source-control.yaml exists with the ticket-prefixed convention; .claude/source-control.local.md and docs/conventions/source-control/commit-convention.yml were never written"
---

/source-control:setup apply layer=team

I am answering the interview up front, so do not ask me anything. Our team convention is ticket-prefixed subjects, `^[A-Z]+-\d+: .+`, and I confirm you write that to the team file `docs/conventions/source-control.yaml`. I decline two other changes: do not create a personal overlay at `.claude/source-control.local.md`, and do not create the neutral convention file `docs/conventions/source-control/commit-convention.yml`. Write nothing else apart from the team file.
