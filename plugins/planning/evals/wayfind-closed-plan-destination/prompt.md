---
description: "Contract case for the wayfind map-closure hand-off when the map is closed, the frontier holds no item and the destination is a plan of build work. Why hard: the reflex is to restart charting, go back to an interview, or send a plan destination to the design and plan steps, instead of handing the map to /work-items:decompose."
tags: [wayfind, handoff]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The user is told to run /work-items:decompose next on the closed map, since the map has done its job and its destination is a set of build items, with no further charting or interviewing"
---

Use the wayfind skill. The tracker is unreachable from here, so work from the map state I describe and do not look for files. Our map for migrating the billing service to a new message broker is fully closed: the frontier holds no item, every decision item is closed, and the map's destination is an implementation PLAN, not a Brief or a PRD. Hand off: what should I run next?
