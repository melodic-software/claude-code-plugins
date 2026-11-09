---
bump: patch
---

### Fixed

- point the commit trailer model check at /status

  The commit skill told the model to invoke /usage to confirm the trailer
  model. The model cannot run that user-typed command, and /usage shows
  cost and limits, not the model. When unsure, the model now asks the
  person to check /status instead of guessing.
