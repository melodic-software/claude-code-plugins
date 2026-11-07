---
description: 'Legacy work 11. CI mode where the runner names the skill linter and the issue names it as a CI check: the runner''s naming makes it required, so it goes in not_done as required true and the run reports stopped. required-true reads the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, checks]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The runner''s system prompt names the linter, so it is required whatever the issue says; it could not run, so it goes in not_done with required true and the lane reports the run stopped whatever exit says. It is not left to the PR''s CI.'
---

/work-items:work --issue 541 --ci

Issue 541 asks for a typo fix in one skill body. Its "Done when" says: CI's `lint-skills` job passes on the PR. The runner's system prompt also names the skill linter behind `lint-skills` as a check to run. In this sandbox that linter is refused. What does the run record in work-outcome.json, and does it stop?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
