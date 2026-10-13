---
description: "Contract case for the interview skill when the user arrives mid-flow after an interview and is unsure where that leaves the work. Why hard: guessing one specific pipeline step is wrong when the user has not said what is settled."
tags: [interview, handoff]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The user is pointed to the workflow navigator that works out the right next stage for them, instead of being handed a guessed specific pipeline step"
---

/planning:interview I picked this session up midway: an interview about replacing our cron-based cleanup job finished earlier today and I think a Brief got written, but I honestly don't remember what was settled or what stage we are in. I'm unsure where this leaves the work. What should I run next?
