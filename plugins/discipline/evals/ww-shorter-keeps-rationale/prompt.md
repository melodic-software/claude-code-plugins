---
description: "Legacy wait-what 4, its prompt behind the slash command. History: a dense reply on a retry policy whose rationale rests on numbers and an unstated premise (synchronized retries). Re-pitch means re-ground, not compress: full precision stays and the missing premise comes back (SKILL.md lines 24-26). keeps-numbers needs 5 retries, jitter, the 10 s gateway timeout and the 60 s budget reset, premise-restored the synchronized-retry premise, short-sentences no run of 35 or more words without sentence punctuation, regrounded-not-blunt (llm) the three legacy expectations verbatim. A history_file case runs single-arm, so pass --ablation with-without."
tags: [discipline, wait-what, outcome, history, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Short sentences that keep 5 retries, full jitter, the 60 s budget reset and the 10 s gateway timeout, and explain that without jitter all pods retry at the same moment."
---

/discipline:wait-what shorter please, but I still need to understand the full rationale, not a blunt summary.
