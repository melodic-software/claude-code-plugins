---
description: 'Legacy decompose 4. One AFK slice finishes an already-open PR: its body uses the agent-brief PR-variant (current-behavior-of-the-diff, finish-what-exists) while the greenfield slice keeps the ordinary template; approval and born-triaged rules hold. pr-variant reads the reply for the PR-variant field names. Read-only tools, graded on the reply.'
tags: [decompose, agent-brief, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The slice finishing PR #318 has an Outcome whose Current behavior is what the attached diff does today and whose Desired behavior is finishing what exists (the missing load path, the failing CI, the open review comment), not a greenfield re-specification. The sharing slice keeps the ordinary bug/feature template. The approval gate and the born-triaged publish still hold.'
---

/work-items:decompose

One AFK slice is finishing an already-open PR whose diff started the feature; remaining work is review and CI, not a greenfield rewrite.

The topic is saved-filters. Its approved PLAN.md has two phases. Phase 1, saving a search filter, is already started in open PR #318: its diff stores the filter and adds the save button, has no load path yet, has a failing CI check, and has one unanswered review comment. Phase 2, sharing a saved filter with a teammate, has no code yet.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why, and show the `## Outcome` section of each item body as it would be published.
