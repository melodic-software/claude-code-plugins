---
description: "A member naming claude/flagship runs on Fable and is marked frontier, while every other Claude member runs on an explicitly named non-frontier model (Opus), so the fan-out guard still holds for them (AC7, AC8, B12)."
tags: [council]
runs: 2
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The flagship member runs on fable, marked frontier; the two default members run on opus, not on the session's model."
---

My session runs on Fable. My council panel is the default correctness and design members plus `top` with provider: claude, model: claude/flagship. Check the /review:council skill and its files: which model does each of the three members run on, and how does the report mark them? Load /review:council with the Skill tool to read its rules; this is a question, not a run. Answer in under 120 words.
