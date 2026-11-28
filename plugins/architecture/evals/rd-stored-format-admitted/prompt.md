---
description: "A change to a stored format other skills read, with a weighed alternative, passes the admission test as a one-way door and is recorded as the next record in the repository's convention. Regression guard against a test so strict it declines one-way doors; a run without the plugin is expected to write the record too. Paired with rd-two-way-door-declined"
tags: [architecture, adr, outcome, scaffold, regression-guard]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The run writes one new record, docs/adr/0002-<title>.md, numbered after the existing record, and the final reply names its path. The decision passes the test: a weighed alternative, a stored format the report and triage skills read and files already written in the old shape, and a reason the code does not show."
---

/architecture:adr The findings file the review skill writes moves from a Markdown table to JSON Lines, one finding per line; the report and triage skills read it. Context: findings with a pipe in their text broke the table, and the triage skill misread split rows. We weighed keeping the Markdown table with escaped pipes and rejected it because every reader would have to unescape the same way. Consequences: the findings files already written must be converted, and the report and triage skills change in the same release.
