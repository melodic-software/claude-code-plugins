---
bump: none
---

Changes the five `pull-request-create-*` eval cases and the eval fixture forge only. The cases now
run on the shared offline forge, which gains `--no-pr`, `pr create`, `issue view` and the create
phase's REST reads. Each must-not grader now needs a body Write to pass. No skill, hook or script
changes.
