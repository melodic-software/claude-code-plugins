---
description: "Contract case for the PRD skill when the user arrives mid-flow after a PRD and is unsure where it leaves the work. Why hard: the user gives no signal about engineering scope, so any single specific step is a guess."
tags: [prd, handoff]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The user is pointed to the workflow navigator that works out the right next stage for them, instead of being handed a guessed specific pipeline step"
---

/planning:prd I'm joining this session midway. A PRD for a shared playlist comments feature was written earlier and is locked, but I don't know how much engineering detail exists yet or what stage comes after it. I'm unsure where this leaves the work. What should I run next?
