---
bump: patch
---

### Fixed

- `address-feedback` now works a thread a trusted person's fix request started even when the
  reviewer bot left the finding in a review of an earlier head than the one the reviewed-head
  markers name. Threads left by the reviewer bot alone, and threads the lane escalated, still need
  a review on a marker-confirmed head
  ([README.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
