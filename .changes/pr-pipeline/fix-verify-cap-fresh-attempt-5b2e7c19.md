---
bump: patch
---

### Fixed

- The README's `verify:repeated-fail` rule now matches the reader. Only open, unmerged pull
  requests for the issue add their FAILs to another pull request's count, and only FAILs uploaded
  after the issue's newest capped-close record or unmerged close. A merged or closed pull
  request's FAILs never count against a fresh attempt.
