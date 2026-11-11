---
description: "An unattended run (claude -p in a lane) whose repository has not set council_lanes: on stops with success and its reason before dispatching any member (AC17)."
tags: [council]
runs: 2
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The run stops with success, reason lane switch off, and dispatches no member."
---

A scheduled lane runs `claude -p "/review:council"` on a branch with nobody watching. The repository's review.yaml has council keys for members and rules but no council_lanes key. Check the council skill's rules: does the council review the change in this lane? What does it report? Load /review:council with the Skill tool to read its rules; this is a question, not a run. Answer in under 100 words.
