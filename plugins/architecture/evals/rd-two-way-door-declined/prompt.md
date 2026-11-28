---
description: "A reversible skill-text decision with a weighed alternative fails the admission test as a two-way door: the reply names that part, offers to skip, and writes no record. Hard: the request asks for a record outright and carries a weighed alternative and an unstated reason, the two parts that still pass"
tags: [architecture, adr, outcome, scaffold, hard]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The final reply says the decision does not earn a record because it is a two-way door (reverting the skill text undoes it), names that as the part it fails, and offers to skip or to record it anyway. No record is written under docs/adr, by Write, Edit or a shell command."
---

/architecture:adr Record that the release skill's checklist in skills/release/SKILL.md runs lint before the test suite. Context: a release failed after a ten-minute test run on a lint error. We weighed keeping the tests first and rejected it because lint fails in seconds. Consequences: none outside that checklist.
