---
description: 'Legacy measure 2. The metrics family measures a before-and-after delta against the planning-time baseline, which a review gate does not; with no baseline in an empty workspace it says it cannot quantify and does not route the measurement into a review skill (SKILL.md Purpose; What this skill does NOT do). looks-for-baseline grades a search naming baselines in the trace, cannot-quantify the honest line; delta-not-review (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, measure, metrics, no-network, routine]
max_turns: 12
timeout_seconds: 480
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Treats the request as a metrics delta against a planning-time baseline, finds none, says it cannot quantify, and does not substitute a ship-readiness review.'
---

/verification:measure metrics
