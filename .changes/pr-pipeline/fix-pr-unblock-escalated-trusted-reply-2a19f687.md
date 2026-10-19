---
bump: patch
---

### Fixed

- `address-feedback` now works a thread a trusted person answered after the lane escalated it even
  when the reviewer bot left the finding in a review of an earlier head than the one the
  reviewed-head markers name, as it already did for a fix request with no escalation. Threads left
  by the reviewer bot alone still need a review on a marker-confirmed head
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
