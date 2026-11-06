---
bump: patch
---

### Fixed

- gate the launch-scope tidy-diff pointer on code-tidying

  The agent-tell section runs /code-tidying:tidy-diff when that plugin is
  installed, otherwise reads the diff by hand.
