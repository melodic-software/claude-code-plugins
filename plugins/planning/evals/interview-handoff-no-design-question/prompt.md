---
description: "Contract case for the interview hand-off when the Brief is locked, the codebase and externals are understood, and the change has no design question (no new types, contracts, modules or data model) but is not trivially small. Why hard: the usual reflex is to route into design rounds or straight into code."
tags: [interview, handoff]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The plan comes next, before any code, either directly or through the design step's one-line early exit, and the user is not sent into open-ended design rounds for a change that has no design question"
---

/planning:interview We just finished the interview for adding a per-customer rate limit to our existing report-download endpoint, and the Brief is locked. It touches three existing handlers and one config file, adds no new types, contracts or modules, and changes no data model. We already know this codebase and the libraries involved well. It is more than a one-line change, though. Hand off: what should I run next?
