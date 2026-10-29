---
bump: patch
---

### Fixed

- The post-merge mutation lane comments on the merged pull request only when the result has a
  surviving or uncovered mutant. A refused, scope-empty, stopped, errored or all-killed run no
  longer notifies the author; the job summary still has every outcome, and a refusal or an
  all-not-run result is a `::warning::` annotation. A refused run that still reports a survivor
  both comments and warns. A comment from an earlier run of the same head stays in place.
