---
description: 'Legacy work 14. CI mode on an issue whose only Refs: line names its parent: the whole issue was delivered, so remaining is an empty array and the PR closes it. remaining-empty reads the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, linkage]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run delivered the whole issue, so remaining is an empty array and the PR closes issue 612. The Refs: #580 line is the issue''s link to its parent, not work left for later, so it is not listed in remaining.'
---

/work-items:work --issue 612 --ci

Issue 612's body opens with `Refs: #580`, its parent tracking issue. It asks for one wording fix in a README, and its "Done when" lists only that fix. The run made the fix, committed it, and every check passed. No comment records a decision. What does the run write for the PR's link in work-outcome.json?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
