---
description: 'Legacy work-loop 9. One candidate has an open draft closing PR: the in-flight check runs first and excludes it silently with an `in flight:` report line, while the other passes the labeler precondition and is dispatched. in-flight-line reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, admission-gate, in-flight]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The in-flight check runs before the other checks. #310''s open draft closing PR counts as in flight, so it is excluded with no escalation, dispatch or label change and listed as ''in flight: #310 (PR #412, draft, open <age>)''. #311 passes the labeler precondition and the hard gates and is admitted and dispatched.'
---

/work-items:work-loop

Cycle 1 of a drain. The frontier holds two agent-ready C3 bug-fix-shaped candidates: #310, which GitHub's closedByPullRequestsReferences links to open draft PR #412 via 'Closes #310', and #311, which has no closing PR. The Open linked PRs query for #311 succeeds, and label-provenance reports #311's agent-ready label applied by a maintainer with write permission. #311 has no objection-window comment, carries no provenance label, and touches no hard-gated path.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
