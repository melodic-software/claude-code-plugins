---
bump: patch
---

### Fixed

- **`continue-in-background` drafts a completion condition without the `planning` plugin.** It calls `/planning:draft-goal-condition` only when `planning` is installed; otherwise it drafts the condition inline and says once what `planning` would add.
