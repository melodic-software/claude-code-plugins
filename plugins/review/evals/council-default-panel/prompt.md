---
description: "With no council configuration anywhere, /review:council runs three Opus brief-reviewer members briefed correctness, design and adversarial, for one round, with scores off (issue 14714 AC1)."
tags: [council]
runs: 2
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Three members (correctness, design, adversarial), each a brief-reviewer agent on Opus, one round, no mark table."
---

My repository has no docs/conventions/review.yaml and I never set any review plugin options. Check what the /review:council skill's rules say: if I run it on my branch, which members review the change, on what model and as which agent, how many rounds run, and does the report carry scores? Load /review:council with the Skill tool to read its rules; this is a question, not a run. Answer in under 120 words.
