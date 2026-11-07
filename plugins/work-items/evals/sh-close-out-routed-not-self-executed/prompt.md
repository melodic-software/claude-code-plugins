---
description: 'Legacy ship 4. Status on a per-item-PRs container whose sub-items are all closed, asked to close it out: the close ritual routed to /work-items:decompose''s container lifecycle, the close-out review composed presence-gated (/planning:plan close-out, review machinery, manual acceptance-criteria fallback), and no bare close. close-out-review-named reads the reply. Read-only tools, graded on the reply.'
tags: [ship, status, close-out, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Routes the close-out to the owning ritual instead of executing a bare close: the container closes only after a close-out review of the shipped whole against the container body (/planning:plan close-out, plus /review:quality-gate close-out --container when the review plugin is installed, else a manual pass against the Brief''s acceptance criteria), then a closing comment linking the shipping PRs, per /work-items:decompose''s container-lifecycle ship ritual. The container is never closed without the review and never left open as documentation after it passes.'
---

/work-items:ship

The discovered container is #400 (labeled work-map), whose body carries `**Execution shape:** per-item PRs`. It has every sub-item closed. Close it out.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
