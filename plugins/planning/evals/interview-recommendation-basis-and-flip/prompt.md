---
description: "Eval-first case for checkable recommendations. Why hard: the prompt states enough facts that every recommendation can rest on something the user said, but 'Basis: judgment' with no reference and no condition that would change it is the easy default. The prompt starts past the intake round, so the first decision round carries the recommendations and its Scope check: header line."
tags: [interview, recommendation, basis]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Every recommendation in round 2 names a checkable basis in its printed reason (a file and line, a URL, a check run this session named with what it showed, a session-transcript finding the user said or a tool returned (never the reply's own earlier claim), or a fact the user stated), and names the condition that would change it only where one exists"
---

/planning:interview We need rate limiting on our public REST API. Facts: we run on Postgres 16 with a single Redis 7 instance already used for sessions; traffic peaks at about 2,000 requests per second; our published partner terms promise 1,000 requests per minute per API key.

Round 1 is answered: Q1, the problem is that a few partner integrations send bursts that slow the API for everyone; Q2, the users are partner developers calling the API with their keys, and our on-call engineers.

Ask me round 2 now, then stop for my answers.
