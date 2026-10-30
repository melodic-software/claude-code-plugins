---
bump: minor
---

### Changed

- pr-review-main reviews a diff over its 300000-byte cap in chunks instead of stopping. The diff
  splits into at most 4 chunks of at most 300000 bytes, cut at file boundaries and a larger
  file's hunks (each piece under the file's header lines), and each chunk is reviewed by its own
  run. The lane's one verdict sums the chunks' findings and CRITICAL ones and binds as a
  single-pass verdict does. A `pr-review-main chunks` notice gives the chunk count and each
  chunk's bytes, and a `pr-review-main chunk` notice per chunk its bytes, findings and CRITICAL
  ones. A diff that needs more than 4 chunks, or holds a hunk larger than one, still stops as
  `too-large`. A chunk that fails, leaves no result or skips a part writes no verdict: the record
  job posts `verdict=none reason=chunk-failed` on the head and the leg fails.
