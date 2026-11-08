---
bump: patch
---

### Fixed

- The merge-path rollup counts a merge on its path when the pull request still carries the path label or still had it when the label was deleted, read from its label events in order (the newest 100 LabeledEvents and UnlabeledEvents); a label taken off on purpose stops counting. A github-iac apply deleted the then-undeclared `merge-path: owner-agent` label on 2026-11-08 and stripped it from 194 merged pull requests; the timeline kept their label events, so the rollup counts them on `owner-agent` again instead of `other`.
