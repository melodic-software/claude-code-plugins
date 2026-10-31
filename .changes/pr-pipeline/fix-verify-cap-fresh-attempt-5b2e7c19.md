---
bump: patch
---

### Fixed

- The README's `verify:repeated-fail` rule now matches the reader. Only open, unmerged pull
  requests for the issue add their FAILs to another pull request's count. Of those FAILs, only
  ones uploaded after the newest capped-close record on at least one linked issue they are for
  count, and no other close moves that floor. A merged or closed pull request's FAILs never count
  against a fresh attempt.
