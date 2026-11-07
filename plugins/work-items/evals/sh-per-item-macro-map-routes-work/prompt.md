---
description: 'Legacy ship 1. Status on a per-item-PRs container: seam verbs for identity, rollup and scoped frontier, the Brief through a provider-mechanic read, a compact macro map (4/7 closed, two frontier items, one blocked), the per-item-PRs discipline, and a route to /work-items:work with no tracker mutation. rollup-4-of-7 reads the reply. Read-only tools, graded on the reply.'
tags: [ship, status, per-item-prs, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Resolves the container''s identity and rollup through seam verbs (get-item, list-sub-items --state all, list-frontier --parent), and reads the Brief through the bound adapter''s provider-mechanic read rather than expecting a body field back from get-item. Reports a compact macro map: 4/7 closed, the two frontier items, one blocked. States the per-item-PRs discipline (separate branch and worktree per item from the default branch, per-item PR closes each item, seam claim as the collision signal, parallel items allowed) and routes the next step to /work-items:work. Reads only; mutates nothing on the tracker.'
---

/work-items:ship #300

Item #300 is an open container item (labeled work-map) whose body carries the Brief and the line `**Execution shape:** per-item PRs`. Four of seven sub-items are closed; two are open and unblocked; one is open but blocked.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
