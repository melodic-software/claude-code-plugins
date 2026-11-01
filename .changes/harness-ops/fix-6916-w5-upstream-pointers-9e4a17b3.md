---
bump: patch
---

### Fixed

- The observer-agents row in `audit-performance`'s known issues now carries an as-of date, the
  binary version it was read from, and a recheck trigger. `known-issues` describes the flagged-message
  setting as the choice it is, not an on/off toggle, and the `lanes` config table points at the
  model-alias table ([#6916](https://github.com/melodic-software/claude-code-plugins/issues/6916)).
