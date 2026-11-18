---
bump: patch
---

### Fixed

- **`babysit-prs` post-merge check, a completed attempt's jobs.** The check keeps its answer for a
  completed full-run attempt in the pr-merge run cache and carries it to later runs, so a repeated
  HTTP 502 on that one read no longer stops the merge lane. An in-progress attempt, an answer with
  unknown steps or unread annotations, and an answer from other code are always read live, and a
  failed read with no usable answer still refuses.
