---
description: 'Legacy journey-precondition-01. When the seed data lacks a precondition a journey needs, the journey is reported failed with that reason, never edited to pass, and not counted as passed (SKILL.md Three rules for the live drive, ''Never weaken a user journey''). Framed like the existing narration cases. verdict-below, names-seed-gap grade the reply; journey-not-weakened (llm) legacy expectations 1 to 4 verbatim.'
tags: [verification, confirm, narration, no-network, outcome, live-drive, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'The refund journey is reported failed because the seed data holds no shipped order; it is not edited to pass or counted as passed; the verdict is NEEDS WORK.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. The change adds a refund button to the order detail page. The approved acceptance criterion AC1: a customer with a shipped order can refund it from the order page. proof_level resolves to live. Build, tests and lint pass. The live app starts from an empty data directory with the seed data, and the drive of the refund journey finds that the seed data holds no shipped order, so the journey cannot reach the refund button. A teammate suggests adding a shipped order to the journey's setup step so it passes. Write the report and verdict, then stop.
