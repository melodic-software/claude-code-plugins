---
description: "Legacy do-your-research 3 (prompt verbatim, its dash a colon; narration, no workspace). The audit names the solution reached before the problem was framed (problem-framed-first, llm, exp 1), flags 'the standard choice' and 'from experience' as unverified training-data recall (recall-flagged, llm, exp 2), and corrects forward this turn (corrects-forward, llm, exp 3). skill-fired is a with-only indicator."
tags: [discipline, do-your-research, outcome, narration, no-network]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Names the premature Redis choice and the recall-based 'standard choice' claim as findings, frames the rate limiter's actual problem, and treats the recalled standard as unverified."
---

Let's just use Redis for the rate limiter: that's the standard choice, I know it from experience. do your research.
