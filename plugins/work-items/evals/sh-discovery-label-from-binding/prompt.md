---
description: 'Legacy ship 5. Container discovery with no argument and no PLAN.md pointer, under a binding that remaps container_label to epic: the fallback query uses epic, not work-map; several matches are listed for the user to pick; none routes to /work-items:decompose. queries-epic-label reads the reply. Read-only tools, graded on the reply.'
tags: [ship, discovery, binding, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Discovery resolves the container label from the binding: open items carrying "epic" are queried, not the hard-coded default work-map (had the binding been absent, the work-map default would apply with a loud warning). If several open containers match, they are listed and the user picks which journey to drive; if none match, the skill reports that no container exists and routes container publishing to /work-items:decompose rather than creating one itself.'
---

/work-items:ship

No argument. The topic PLAN.md has no spec-container pointer line. The repo's tracker binding in docs/conventions/work-items.yaml remaps tracker.config.container_label to "epic".

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why, including what it does when the query finds several open containers and when it finds none.
