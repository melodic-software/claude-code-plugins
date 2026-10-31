---
bump: patch
---

### Fixed

- The README's `verify:repeated-fail` rule now matches the reader. Only open, unmerged pull
  requests for the issue add their FAILs to another pull request's count. Of those FAILs, only
  ones uploaded after the issue's newest capped-close record, or after the unmerged close of a
  lanes App pull request, count. A merged or closed pull request's FAILs never count against a
  fresh attempt.
