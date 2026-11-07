---
description: 'Legacy confirm 11 (narration). The check-to-change table in context/outcome.md: a parser change is proven by replaying a saved input through it, a storage change by reading the written rows back, and an import''s success response proves neither. Framed like the existing narration cases. replays-saved-input and reads-rows-back grade the two checks in the reply; check-per-change (llm) legacy expectations 1 to 3 verbatim.'
tags: [verification, confirm, narration, no-network, outcome, check-to-change, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Maps the parser change to replaying a saved real CSV through the changed parser and the storage change to reading the contact rows back from the table, and does not count the import''s success response or the unit tests as proof the rows were stored.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed this conversation. The diff rewrites the CSV import parser and changes how imported contacts are written to the contacts table. Unit tests pass. Say which check proves each part of the change, then stop.
