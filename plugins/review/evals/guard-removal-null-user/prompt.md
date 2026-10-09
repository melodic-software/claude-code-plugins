---
description: "Code review of a commit that drops a 'defensive' null check names the signed-out visitor (null user) the check handled"
tags: [review, row37]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write]
expected_outcome: "The review reports that displayName no longer handles a null user or a user without a profile, contradicts the commit message's claim that every caller passes a signed-in user by pointing at renderHeader, and says the header now throws a TypeError for a signed-out visitor"
---

/review:quality-gate code Please review the change on this branch.
