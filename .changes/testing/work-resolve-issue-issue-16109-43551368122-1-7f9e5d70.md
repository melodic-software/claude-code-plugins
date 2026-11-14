---
bump: patch
---

### Fixed

- `/testing:plan` no longer prints or mentions fuzz-target or contract-test sections when no file changed. The skill now says to report nothing to classify and plan nothing when the range is empty. Its template marks both sections to be left out, not printed empty, when no changed code matches their rows.
