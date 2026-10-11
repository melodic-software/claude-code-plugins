---
bump: patch
---

### Fixed

- The `simple-system-prompt` lever no longer restates which models already default to the lean system prompt, which had misclassified Haiku 5.5 as full. It points at a rerunnable probe record of the binary's lean-prompt selection instead.
