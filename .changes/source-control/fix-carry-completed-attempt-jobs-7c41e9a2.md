---
bump: patch
---

### Fixed

- **`babysit-prs` post-merge check, a completed attempt's jobs.** The check keeps its answer for a
  completed full-run attempt in the attempts file pr-merge.yml already hands from run to run, so a
  repeated HTTP 502 on that read no longer stops the merge lane once the answer is kept. An
  in-progress attempt, an answer with unknown steps or unread annotations, and an answer from other
  code are always read live, and a failed read with no usable answer still refuses.
