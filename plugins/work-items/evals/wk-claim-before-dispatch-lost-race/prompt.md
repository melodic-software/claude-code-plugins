---
description: 'Legacy work 1. An attended run confirmed yes: session-start reclaim first, one frontier item through list-frontier, the seam claim before any dispatch, a lost race (claim exit 7) advancing to the next candidate, and orchestrator-dispatch as the autonomous default. lost-race-advances reads the reply. Read-only tools, graded on the reply.'
tags: [work, claim, lease]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run reclaims stale leases first (idempotent, never releasing the live lease), selects exactly one item from list-frontier, claims it through the seam claim verb (assignee plus lease) before any dispatch, and on #40''s exit 7 advances to #41 rather than retrying. Execution follows the project''s workflow; autonomous execution defaults to orchestrator-dispatch of a scope-fenced subagent in its own out-of-tree worktree, and the claim identity is the session user.'
---

/work-items:work

The frontier holds three open, unblocked, unassigned items, #40, #41 and #42, and #40 ranks first. Two other items are assigned: one carries a live lease, one an expired lease. When the run shows its confirmation prompt, take the user's answer as yes. The seam claim on #40 exits 7.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
