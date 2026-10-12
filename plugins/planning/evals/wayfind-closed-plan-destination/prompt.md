---
description: "Contract case for the wayfind map-closure hand-off when the decision map is closed, the frontier is empty and the destination is a PLAN. Why hard: the reflex is to restart charting, or to go back to an interview, instead of handing the destination to the planning step."
tags: [wayfind, handoff]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The user is told to produce the implementation plan next, since the map has done its job and its destination is a plan, with no further charting or interviewing"
---

Use the wayfind skill. The tracker is unreachable from here, so work from the map state I describe and do not look for files. Our decision map for migrating the billing service to a new message broker is fully closed: the frontier is empty, every decision item is closed, and the map's destination is an implementation PLAN, not a Brief or a PRD. Hand off: what should I run next?
