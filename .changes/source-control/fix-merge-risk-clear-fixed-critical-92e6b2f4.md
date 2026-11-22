---
bump: patch
---

### Fixed

- The babysit merge-risk rater no longer holds a pull request on a CRITICAL
  security finding an earlier head's main-run review recorded once the current
  head's own main-run security review binds with no CRITICAL finding. A head no
  main-run review has covered, a whitespace push included, still holds it, and a
  pull_request-lane CRITICAL whose thread is still open still holds.
