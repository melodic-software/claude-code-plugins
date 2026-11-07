---
description: 'Legacy work 17. CI mode where the suite ran and a test still fails after two fix attempts: a test that ran and failed is required, so it goes in not_done as required true and the lane reports stopped. required-true-stopped reads the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, checks]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The suite ran and a test failed, so the unrunnable-test exception does not apply: the failing test goes in not_done with required true and the lane reports the run stopped whatever exit says. It is not left to the PR''s CI.'
---

/work-items:work --issue 613 --ci

Issue 613 asks for a small fix in one helper script. The runner's system prompt names the plugin's test suite as a check to run. The suite runs in this sandbox, and one of its tests fails after the change. Two attempts to fix the code do not make it pass, and the run has no turns left to try again. What does the run record in work-outcome.json, and does it stop?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
