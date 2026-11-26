---
bump: patch
---

### Changed

- The emitted file-name gate's failure summary is self-contained: it says to rename each offender to the rule or exempt it in the `file_names` configuration and re-emit the gate, instead of pointing at the script's header comment.
