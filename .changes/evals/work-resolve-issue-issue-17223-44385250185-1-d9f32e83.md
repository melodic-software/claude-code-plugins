---
bump: minor
---

### Changed

- `plugin-eval`'s validity gate no longer voids a run whose denied call a failed `max: 0` `tool_used` grader of its case forbids: the grader already scored the call as the run's failure, so the denial is a warning and the run counts as that grader's failure. A case can now measure a premature `Write` to a protected `.claude/` path ([#17223](https://github.com/melodic-software/claude-code-plugins/issues/17223)).
