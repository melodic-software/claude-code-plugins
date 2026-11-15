---
bump: patch
---

### Fixed

- The comment lint, and the `remove-comments` audit's upstream note, count `do not edit` as a
  generated-file marker only as a whole-file notice: at the end of the line, before punctuation or
  `this file`, `this copy`, `by hand`, `manually` or `directly`, or on a line that also says
  `generated`. A hand-written `# do not edit the order below` no longer skips the whole file.
  `sync-managed` and `@generated` match as before. Both read one definition,
  `scripts/generated-marker.ere`.
