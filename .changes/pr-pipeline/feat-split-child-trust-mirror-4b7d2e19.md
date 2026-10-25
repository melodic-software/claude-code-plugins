---
bump: patch
---

### Changed

- The pr-pipeline README describes how pr-merge's gate counts a size-split sub-issue the lanes App filed as trusted spec. It does so on the same rule pr-verify applies: every line after the header must be a trusted task-list line of its native parent, or on the edited path that line with its box ticked. A failed read is `verify:unreadable`, and a cut comment page counts nothing.
