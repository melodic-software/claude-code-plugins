---
schema_version: "1.1"
name: glossary-no-term-asks-reference
description: "Hard: a vague description pulls toward a confident invented label; the case needs the closest real term marked approximate and a request for a reference."
tags: [glossary, no-term-fits, hard]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply names the closest existing term (idle animation, ambient float or pulse) as an approximation, coins no term, and asks for a reference image, recording or link"
---

You know that thing some apps do where the whole screen sort of breathes and the colors drift when it's idle? I don't know how else to describe it. What's it called?
