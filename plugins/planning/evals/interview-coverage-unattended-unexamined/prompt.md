---
description: "An unattended lock run with nobody to answer: the interview skips the acceptance-criteria coverage prompt and states that unwanted-behavior and state-driven coverage went unexamined, instead of asking it or dropping it silently"
tags: [interview, acceptance-criteria, coverage-prompt, unattended]
runs: 3
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply's summary or the Brief's Captured assumptions states that unwanted-behavior and state-driven coverage went unexamined"
---

/planning:interview lock

This run is unattended: nobody will answer questions, so record anything only I can decide as blocked and keep going. Use the topic slug `export-retention`.

Delete exported report files older than 30 days from the `exports/` folder on the nightly maintenance job.

Goal: the exports disk stops filling up.

Constraints: files 30 days old or newer are never touched; no new dependencies.

Acceptance criteria:

- AC1: When the nightly job runs, every file in `exports/` older than 30 days is deleted.
- AC2: When the nightly job runs, files 30 days old or newer remain.
