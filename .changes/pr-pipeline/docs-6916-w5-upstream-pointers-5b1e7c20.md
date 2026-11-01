---
bump: patch
---

### Fixed

- The `models` profile notes in the README no longer say an unset `effort` always lands on the
  model's default: the run takes the next level in the effort resolution order. They point at
  that order and at the subagent model order for `subagent-model`, with an as-of date and recheck
  trigger ([#6916](https://github.com/melodic-software/claude-code-plugins/issues/6916)).
