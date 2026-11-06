---
bump: patch
---

### Fixed

- gate the phase-boundary review on the review plugin being installed

  /implementation:implement and /implementation:implement-dispatch now
  run /review:quality-gate for a `Review:`-tagged phase only when the
  review plugin is installed. Without it, a fresh-context subagent
  handed only the phase diff and the tag reviews the phase, and the
  report says the review plugin would run that review.
