---
bump: patch
---

### Fixed

- The merge-path rollup counts a merge on its path when the pull request was ever given the path label, read from its LabeledEvents, not only when it still carries the label. A github-iac apply deleted the then-undeclared `merge-path: owner-agent` label on 2026-11-08 and stripped it from 194 merged pull requests; the timeline kept their label events, so the rollup counts them on `owner-agent` again instead of `other`.
