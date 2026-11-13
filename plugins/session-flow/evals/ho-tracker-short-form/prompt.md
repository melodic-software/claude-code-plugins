---
description: "Handoff during map work where the tracker item already holds every finding and the decision. Why hard: the default is a full handoff file because a plan artifact backs the work, so the easy path writes a file and a long resume prompt that copies state the item already holds."
tags: [handoff, tracker, short-form, scaffold]
runs: 3
max_turns: 16
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write]
expected_outcome: "The reply ends with the two-line short form: '/clear, then run:' and '/planning:wayfind work https://example.com/acme/booking/issues/40 https://example.com/acme/booking/issues/43'; it writes no handoff file and copies no session state into the resume"
---

/session-flow:handoff

[Session state: this session worked one decision item, https://example.com/acme/booking/issues/42, of the wayfind map https://example.com/acme/booking/issues/40. Every finding, the decision and its rationale were posted to that item as a comment this session, and the item was re-read this turn and shows them. The map's next frontier item is https://example.com/acme/booking/issues/43, resumed with `/planning:wayfind work https://example.com/acme/booking/issues/40 https://example.com/acme/booking/issues/43`. Nothing is uncommitted, no worktree claim is held, no subagent or background task is running, no /goal or /loop is active, and nothing was changed outside the tracker.]
