---
bump: patch
---

### Fixed

- The README's `verify:repeated-fail` rule now matches the reader. A merged pull request's FAILs,
  and a lanes App pull request's once it is closed unmerged, whoever closed it, no longer add to
  another pull request's count. Closing any other pull request resets nothing. Of the FAILs that
  remain, only ones uploaded after the newest capped-close record on at least one linked issue
  they are for count, and no other close moves that floor.
