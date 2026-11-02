---
bump: patch
---

### Changed

- The rewrite runbook's negative control says to merge each version's per-case result files into one file before the compare, since the noise report calls no `case drop` on fewer than 3 cases. It also says that a guard that denies the degraded copy's commands leaves those cases INVALID and unread, so the degradation should invite no denied command, or the part counts as unmeasurable.
