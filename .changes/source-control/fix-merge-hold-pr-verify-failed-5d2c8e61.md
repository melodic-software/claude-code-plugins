---
bump: patch
---

### Fixed

- The merge gate holds a pull request labeled `pr-verify-failed` as it holds `do-not-merge` (`MERGE_HOLD_LABELS`): pr-merge's prefilter sets it aside, the gate does not merge or enqueue it, adoption refuses it, and a queued entry that gains the label leaves the queue. pr-merge's enable-auto-merge job neither arms it nor leaves it armed.
