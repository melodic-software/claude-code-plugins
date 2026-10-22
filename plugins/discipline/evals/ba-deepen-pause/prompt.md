---
description: "In-progress deepen, pause path, and a regression guard: today's pre-work raise also stops, so this case passes before and after the change. The feedback turns one incident write-up into alerting for every tenant, which changes the goal and widens the scope, so the reply shows the rewritten brief and waits instead of building."
tags: [discipline, be-ambitious, outcome, in-progress, regression-guard]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash]
expected_outcome: "Shows a rewritten brief for tenant-wide alerting, says the goal or scope changed, and waits for the go-ahead; no Write or Edit call."
---

/discipline:be-ambitious Not good enough. What I actually need is alerting for every tenant so a spike like this never surprises us again.

Earlier in this conversation I asked: "Why did checkout errors spike yesterday? Write it up in notes/incident.md." You read logs/summary.txt and wrote notes/incident.md.
