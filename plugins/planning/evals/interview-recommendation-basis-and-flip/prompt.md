---
description: "Eval-first case for checkable recommendations. Why hard: the prompt states enough facts that every recommendation can rest on something the user said, but 'Basis: judgment' with no reference and no condition that would change it is the easy default."
tags: [interview, recommendation, basis]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Every recommendation in round 1 names a checkable basis (a file and line, a URL, or a fact the user stated) and the condition that would change it"
---

/planning:interview We need rate limiting on our public REST API. Facts: we run on Postgres 16 with a single Redis 7 instance already used for sessions; traffic peaks at about 2,000 requests per second; our published partner terms promise 1,000 requests per minute per API key. Ask me your first round.
