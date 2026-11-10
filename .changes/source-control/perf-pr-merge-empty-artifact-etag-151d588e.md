---
bump: patch
---

### Changed

- answer empty exact-name artifact reads with a 304

  In a job that names `BABYSIT_VERIFY_LISTING`, the verdict reader makes
  one read of an artifact name nothing uploads and keeps that empty
  answer's ETag beside the listing, but only when the body is exactly
  empty. Each first page of an exact-name read then sends it as
  `If-None-Match`, and a 304 reads as the empty page, so the verdict is
  the one a 200 gives. A failed or non-empty seed sends no header, and a
  304 to a read that sent none stays unreadable.
