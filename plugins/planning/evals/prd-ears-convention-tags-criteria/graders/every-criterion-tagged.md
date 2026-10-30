---
type: llm
focus: { source: file, path: .work/history-export/PRD.md }
---

Rubric item: every acceptance criterion the PRD records carries an exact EARS pattern tag.

The agent was asked to write a PRD for members downloading their listening history as a CSV, in a repository whose team convention selects the EARS acceptance-criteria format, and to record four acceptance criteria as bullets: the file is ready within five minutes of a request; a failed build shows an error and allows a new request; the request button is disabled while a build runs; the CSV lists every play with date, track and artist. The text to grade is the PRD file it wrote. When there is no such text (the file is missing or empty), FAIL.

Find the bullets that record these acceptance criteria, wherever in the PRD they sit. A criterion bullet is tagged when it starts (after the bullet marker and any `AC<n>:` id) with exactly one of `[ubiquitous]`, `[event-driven]`, `[state-driven]`, `[unwanted-behavior]` or `[optional-feature]`. A variant spelling (`[unwanted_behavior]`, `[unwanted]`, `[event]`, `[Event-Driven]`) is not a tag. Which of the five tags a criterion gets does not matter. Success-metric table rows, user stories and open questions are not acceptance criteria.

PASS when the PRD records the acceptance criteria and every one of those bullets is tagged. FAIL when any recorded criterion bullet is untagged or carries a variant spelling, or when the PRD records no acceptance criteria. List each criterion bullet with its tag before deciding.
