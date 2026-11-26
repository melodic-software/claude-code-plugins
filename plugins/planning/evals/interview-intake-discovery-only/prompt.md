---
description: "A first request that names a feature but not its problem, users or scope. Why hard: the skill can draft plausible answers for all of them, so the easy move is a first round of recommended answers that puts words in the user's mouth; the gap triage sorts these unknowns into discovery questions, and round 1 asks only those, open, each with a No recommendation: line, then a Your answer settles: line, and no recommended answer."
tags: [interview, intake, discovery, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Round 1 asks only open discovery questions (the problem, who it is for, what is in scope), each with No recommendation: and Your answer settles: lines and none with a My recommendation: line, then stops for the answers"
---

/planning:interview Add notifications to our team task app. I'm here and will answer; ask me your first round, then stop.
