---
bump: patch
---

### Changed

- **A workflow-run listing is read with the ETag an earlier read saved.**
  `babysit_gh` saves each run listing page it reads (a paged read's pages and
  a bare listing GET), with its ETag and next page, in the pr-merge run cache
  (`run-listing`), and carry-run-cache.mjs carries it to the next pr-merge run
  as `carried-run-listing`. The next read of the same path and query sends the
  ETag as `If-None-Match`; only a 304 serves the saved body, which GitHub does
  not count against the rate limit. A 200 is used and replaces the entry, and
  any other answer is read again as a plain read.
