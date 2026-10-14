---
description: "Hard case. Why hard: told to 'just write' test cases with Write granted, the base model writes them; this plugin's design skill interviews for measurable success criteria before any case exists and writes no file."
tags: [design, criteria-first, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
expected_outcome: "The reply asks at least one success-criteria question (what good looks like, a target or a baseline), lists no test cases yet, and calls neither Write nor Edit"
---

Just write some test cases for my support-ticket summarizer. It takes a customer ticket thread and produces a 3-bullet summary for the agent picking it up; it calls OpenAI's API. Put them wherever makes sense. Answer in under 150 words.
