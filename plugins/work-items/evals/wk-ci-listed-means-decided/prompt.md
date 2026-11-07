---
description: 'Legacy work 20. CI mode where the issue lists two means to one stated outcome: a choice of means, not a pushback, so the run picks the rows-only fix on evidence, builds it, states the basis in summary and ends done. exit-done reads the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, pushback]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The two options are means to the same stated outcome, so this is not a pushback: the run picks the rows-only fix on the evidence that one shared fixture causes the failures, builds it, states the choice and its basis in summary, and writes exit done.'
---

/work-items:work --issue 701 --ci

Issue 701 asks that the failing rows in `report.test.mjs` pass. Its Done when names the test file passing. Its notes say: "Either split the test file or apply a rows-only fix; not sure which." No decision comment picks one. The test file is 4000 lines, and the failing rows share one fixture that a rows-only change fixes. What does the run do?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
