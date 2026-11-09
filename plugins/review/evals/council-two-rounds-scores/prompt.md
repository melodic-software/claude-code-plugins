---
description: "With council_max_rounds 2 and council_scores on, round 2 reviews only the before/after difference of the fix pass that ran between rounds (plus the fix's own Not applied rows), the mark table lands in the run file, and the final report says the fixes are unbuilt and points to /verification:confirm (AC11, AC12)."
tags: [council]
runs: 2
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 2 reviews the fix's before/after diff and its Not applied rows, not the whole branch; marks go in the run file's Marks section; the report says the fixes are unbuilt and names /verification:confirm."
---

My review.yaml sets council_max_rounds: 2 and council_scores: on. Round 1 of /review:council found two IMPORTANT correctness findings, and the fix pass between rounds applied both. Check the council skill's rules: what exactly does round 2 review, where do the members' marks end up, and what does the final report tell me about the fixes before I commit? Answer in under 150 words.
