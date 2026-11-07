---
description: 'Legacy work 10. CI mode with two checks it cannot run: the issue''s PR-CI job goes in not_done as required false, the runner-named changelog check as required true, so the lane reports the run stopped. both-required-values reads the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, checks]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'lint-skills is a check the issue names as the PR''s CI, so it goes in not_done as left to the PR''s CI with required false and does not stop the run. The runner-named changelog-fragment check could not run, so it goes in not_done with required true, and the lane reports the run stopped whatever exit says.'
---

/work-items:work --issue 540 --ci

Issue 540 asks for a wording fix in one skill body. Its "Done when" says: the skill text is updated, and CI's `lint-skills` job passes on the PR. The runner's system prompt names the repository's changelog-fragment check as a check to run. In this sandbox the skill linter behind `lint-skills` is refused, and the changelog-fragment check also cannot run because a dependency fails to install. What does the run record in work-outcome.json, and does it stop?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
