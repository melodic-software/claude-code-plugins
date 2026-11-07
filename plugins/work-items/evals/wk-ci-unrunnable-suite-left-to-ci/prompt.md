---
description: 'Legacy work 16. CI mode whose runner-named test suite cannot execute in the sandbox: the test-run exception puts it in not_done as required false, the passed changelog check leaves nothing required, and the run ends done. suite-false-exit-done reads the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, checks]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'A test run the lane could not execute is the exception, since the PR''s CI runs the suites: it goes in not_done as left to the PR''s CI with required false and does not stop the run. The changelog-fragment check passed, so nothing required is left, and the run ends done, not stopped.'
---

/work-items:work --issue 612 --ci

Issue 612 asks for a small fix in one helper script and a unit test for it. The runner's system prompt names the repository's changelog-fragment check and the plugin's test suite as checks to run. The changelog-fragment check runs and passes. The test suite cannot run in this sandbox: its test runner is not installed and the lane has no network to install it. Everything else is done. What does the run record in work-outcome.json, and does it stop?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
